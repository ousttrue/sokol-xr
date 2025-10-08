#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

struct OpenXrProgram* program_create(const struct Options* options, struct IPlatformPlugin* platformPlugin,
                                     struct IGraphicsPlugin* graphicsPlugin);
void program_CreateInstance(struct OpenXrProgram* self);
void program_InitializeSystem(struct OpenXrProgram* self);
void SetEnvironmentBlendMode(struct Options* opts, struct OpenXrProgram* self);
void program_InitializeDevice(struct OpenXrProgram* self);
void program_InitializeSession(struct OpenXrProgram* self);
void program_CreateSwapchains(struct OpenXrProgram* self);
void program_PollEvents(struct OpenXrProgram* self, bool* exitRenderLoop, bool* requestRestart);
bool program_IsSessionRunning(struct OpenXrProgram* self);
void program_PollActions(struct OpenXrProgram* self);
void program_RenderFrame(struct OpenXrProgram* self);

#ifdef __cplusplus
}
#endif
