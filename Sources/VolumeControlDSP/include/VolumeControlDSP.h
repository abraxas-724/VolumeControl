#ifndef VOLUME_CONTROL_DSP_H
#define VOLUME_CONTROL_DSP_H
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct VCGainState VCGainState;
VCGainState *VCGainCreate(uint32_t channels);
void VCGainDestroy(VCGainState *state);
void VCGainSet(VCGainState *state, float gain);
// Configure verified buffer ranges before starting the IOProc; unrelated buffers are never read.
bool VCGainSetBufferRanges(VCGainState *state, uint32_t inputStart, uint32_t inputCount, uint32_t outputStart, uint32_t outputCount);
void VCGainArm(VCGainState *state, bool armed);
bool VCGainHasSignal(const VCGainState *state);
bool VCGainHasInvalidLayout(const VCGainState *state);
uint32_t VCGainActiveInputChannels(const VCGainState *state);
uint32_t VCGainActiveOutputChannels(const VCGainState *state);
float VCGainInputLevel(const VCGainState *state);
float VCGainOutputLevel(const VCGainState *state);
uint64_t VCGainOutputFrames(const VCGainState *state);
// Called only by one HAL IOProc; no allocation, locks, Swift objects or UI work.
void VCGainRender(VCGainState *state, const AudioBufferList *input, AudioBufferList *output);
#endif
