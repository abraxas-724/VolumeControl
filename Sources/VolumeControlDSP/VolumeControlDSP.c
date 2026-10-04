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
    float current; // Owned exclusively by the render callback.
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
    s->current = 1;
    return s;
}
void VCGainDestroy(VCGainState *s) { free(s); }
void VCGainSet(VCGainState *s, float gain) {
    atomic_store_explicit(&s->target, isfinite(gain) ? fminf(1, fmaxf(0, gain)) : 0, memory_order_relaxed);
}
void VCGainArm(VCGainState *s, bool armed) { atomic_store(&s->armed, armed); }
bool VCGainHasSignal(const VCGainState *s) { return atomic_load(&s->signal); }
bool VCGainHasInvalidLayout(const VCGainState *s) { return atomic_load(&s->invalid); }
float VCGainInputLevel(const VCGainState *s) { return atomic_load(&s->inputLevel); }
float VCGainOutputLevel(const VCGainState *s) { return atomic_load(&s->outputLevel); }
uint64_t VCGainOutputFrames(const VCGainState *s) { return atomic_load(&s->outputFrames); }

static bool layout(const AudioBufferList *list, uint32_t channels, uint32_t *frames) {
    if (!list || list->mNumberBuffers == 0 || list->mNumberBuffers > 2) return false;
    uint32_t total = 0, count = UINT32_MAX;
    for (uint32_t i = 0; i < list->mNumberBuffers; i++) {
        const AudioBuffer *b = &list->mBuffers[i];
        if (!b->mData || b->mNumberChannels == 0 || b->mNumberChannels > 2) return false;
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
static float *sample(const AudioBufferList *list, uint32_t frame, uint32_t channel) {
    for (uint32_t i = 0; i < list->mNumberBuffers; i++) {
        const AudioBuffer *b = &list->mBuffers[i];
        if (channel < b->mNumberChannels) return (float *)b->mData + frame * b->mNumberChannels + channel;
        channel -= b->mNumberChannels;
    }
    return NULL;
}
void VCGainRender(VCGainState *s, const AudioBufferList *input, AudioBufferList *output) {
    if (!s || !output) return;
    for (uint32_t i = 0; i < output->mNumberBuffers; i++) {
        if (output->mBuffers[i].mData) memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    }
    if (!input || input->mNumberBuffers == 0) return;
    for (uint32_t i = 0; i < input->mNumberBuffers; i++) if (input->mBuffers[i].mDataByteSize == 0) return;
    uint32_t inFrames, outFrames;
    if (!layout(input, s->channels, &inFrames) || !layout(output, s->channels, &outFrames)) {
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
            float value = *sample(input, frame, channel);
            if (!isfinite(value)) value = 0;
            signal |= fabsf(value) > 0.000001f;
            inputEnergy += value * value;
            float rendered = armed ? fminf(1, fmaxf(-1, value * s->current)) : 0;
            outputEnergy += rendered * rendered;
            *sample(output, frame, channel) = rendered;
        }
    }
    if (frames > 0) {
        atomic_store(&s->inputLevel, sqrtf(inputEnergy / (frames * s->channels)));
        atomic_store(&s->outputLevel, sqrtf(outputEnergy / (frames * s->channels)));
    }
    if (signal) atomic_store(&s->signal, true);
    if (armed) atomic_fetch_add_explicit(&s->outputFrames, frames, memory_order_relaxed);
}
