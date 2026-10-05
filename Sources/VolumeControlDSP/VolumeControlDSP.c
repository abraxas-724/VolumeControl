#include "VolumeControlDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct VCGainState {
    uint32_t channels;
    _Atomic float target;
    _Atomic bool armed;
    _Atomic bool signal;
    _Atomic bool invalid;
    _Atomic uint64_t outputFrames;
    _Atomic float inputLevel;
    _Atomic float outputLevel;
    _Atomic uint32_t inputChannels;
    _Atomic uint32_t outputChannels;
    float current; // Owned exclusively by the render callback.
    uint32_t inputStart, inputCount, outputStart, outputCount;
};

VCGainState *VCGainCreate(uint32_t channels) {
    if (channels == 0 || channels > 2) return NULL;
    VCGainState *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->channels = channels;
    atomic_init(&s->target, 1);
    atomic_init(&s->armed, false);
    atomic_init(&s->signal, false);
    atomic_init(&s->invalid, false);
    atomic_init(&s->outputFrames, 0);
    atomic_init(&s->inputLevel, 0);
    atomic_init(&s->outputLevel, 0);
    atomic_init(&s->inputChannels, 0);
    atomic_init(&s->outputChannels, 0);
    s->current = 1;
    s->inputCount = s->outputCount = UINT32_MAX;
    return s;
}
void VCGainDestroy(VCGainState *s) { free(s); }
void VCGainSet(VCGainState *s, float gain) {
    atomic_store_explicit(&s->target, isfinite(gain) ? fminf(1, fmaxf(0, gain)) : 0, memory_order_relaxed);
}
bool VCGainSetBufferRanges(VCGainState *s, uint32_t inputStart, uint32_t inputCount, uint32_t outputStart, uint32_t outputCount) {
    if (!s || inputCount == 0 || outputCount == 0 || (uint64_t)inputStart + inputCount > 32 || (uint64_t)outputStart + outputCount > 32) return false;
    s->inputStart = inputStart; s->inputCount = inputCount;
    s->outputStart = outputStart; s->outputCount = outputCount;
    return true;
}
void VCGainArm(VCGainState *s, bool armed) { atomic_store(&s->armed, armed); }
bool VCGainHasSignal(const VCGainState *s) { return atomic_load(&s->signal); }
bool VCGainHasInvalidLayout(const VCGainState *s) { return atomic_load(&s->invalid); }
uint32_t VCGainActiveInputChannels(const VCGainState *s) { return atomic_load(&s->inputChannels); }
uint32_t VCGainActiveOutputChannels(const VCGainState *s) { return atomic_load(&s->outputChannels); }
float VCGainInputLevel(const VCGainState *s) { return atomic_load(&s->inputLevel); }
float VCGainOutputLevel(const VCGainState *s) { return atomic_load(&s->outputLevel); }
uint64_t VCGainOutputFrames(const VCGainState *s) { return atomic_load(&s->outputFrames); }

static bool layout(const AudioBufferList *list, uint32_t channels, uint32_t *frames, uint32_t first, uint32_t end) {
    if (!list || list->mNumberBuffers == 0 || list->mNumberBuffers > 32) return false;
    uint32_t total = 0, count = UINT32_MAX;
    for (uint32_t i = first; i < end; i++) {
        const AudioBuffer *b = &list->mBuffers[i];
        // Disabled HAL streams retain channel/byte metadata but have a NULL data pointer.
        if (!b->mData) continue;
        if (b->mNumberChannels == 0 || b->mNumberChannels > 2) return false;
        uint32_t stride = sizeof(float) * b->mNumberChannels;
        if (b->mDataByteSize % stride) return false;
        uint32_t n = b->mDataByteSize / stride;
        if (count != UINT32_MAX && count != n) return false;
        count = n;
        total += b->mNumberChannels;
    }
    if (total != channels || count > 65536) return false;
    *frames = count;
    return true;
}
static float *sample(const AudioBufferList *list, uint32_t frame, uint32_t channel, uint32_t first, uint32_t end) {
    for (uint32_t i = first; i < end; i++) {
        const AudioBuffer *b = &list->mBuffers[i];
        if (!b->mData) continue;
        if (channel < b->mNumberChannels) return (float *)b->mData + frame * b->mNumberChannels + channel;
        channel -= b->mNumberChannels;
    }
    return NULL;
}
void VCGainRender(VCGainState *s, const AudioBufferList *input, AudioBufferList *output) {
    if (!s || !output) return;
    uint32_t outputEnd = s->outputCount == UINT32_MAX ? output->mNumberBuffers : s->outputStart + s->outputCount;
    if (outputEnd > output->mNumberBuffers || outputEnd > 32) {
        atomic_store(&s->invalid, true); return;
    }
    for (uint32_t i = s->outputStart; i < outputEnd; i++) {
        if (output->mBuffers[i].mData) memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    }
    if (!input || input->mNumberBuffers == 0) return;
    uint32_t inputEnd = s->inputCount == UINT32_MAX ? input->mNumberBuffers : s->inputStart + s->inputCount;
    if (inputEnd > input->mNumberBuffers || inputEnd > 32) {
        atomic_store(&s->invalid, true); return;
    }
    uint32_t inputChannels = 0, outputChannels = 0;
    for (uint32_t i = s->inputStart; i < inputEnd; i++) if (input->mBuffers[i].mData) inputChannels += input->mBuffers[i].mNumberChannels;
    for (uint32_t i = s->outputStart; i < outputEnd; i++) if (output->mBuffers[i].mData) outputChannels += output->mBuffers[i].mNumberChannels;
    atomic_store(&s->inputChannels, inputChannels);
    atomic_store(&s->outputChannels, outputChannels);
    bool hasInput = false;
    for (uint32_t i = s->inputStart; i < inputEnd; i++) {
        if (!input->mBuffers[i].mData) continue;
        if (input->mBuffers[i].mDataByteSize == 0) return;
        hasInput = true;
    }
    if (!hasInput) return;
    uint32_t inFrames, outFrames;
    if (!layout(input, s->channels, &inFrames, s->inputStart, inputEnd) || !layout(output, s->channels, &outFrames, s->outputStart, outputEnd)) {
        atomic_store(&s->invalid, true);
        return;
    }
    uint32_t frames = inFrames < outFrames ? inFrames : outFrames;
    bool armed = atomic_load_explicit(&s->armed, memory_order_relaxed), signal = false;
    float inputEnergy = 0, outputEnergy = 0;
    float target = atomic_load_explicit(&s->target, memory_order_relaxed);
    for (uint32_t frame = 0; frame < frames; frame++) {
        // A short ramp avoids clicks without sharing mutable DSP state with the UI.
        float difference = target - s->current;
        s->current += fminf(1.0f / 128, fmaxf(-1.0f / 128, difference));
        for (uint32_t channel = 0; channel < s->channels; channel++) {
            float value = *sample(input, frame, channel, s->inputStart, inputEnd);
            if (!isfinite(value)) value = 0;
            signal |= fabsf(value) > 0.000001f;
            inputEnergy += value * value;
            float rendered = armed ? fminf(1, fmaxf(-1, value * s->current)) : 0;
            outputEnergy += rendered * rendered;
            *sample(output, frame, channel, s->outputStart, outputEnd) = rendered;
        }
    }
    if (frames > 0) {
        atomic_store(&s->inputLevel, sqrtf(inputEnergy / (frames * s->channels)));
        atomic_store(&s->outputLevel, sqrtf(outputEnergy / (frames * s->channels)));
    }
    if (signal) atomic_store(&s->signal, true);
    if (armed) atomic_fetch_add_explicit(&s->outputFrames, frames, memory_order_relaxed);
}
