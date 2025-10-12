#include "openxr_factory.h"
#include "openxr_program.h"
#include "pch.h"
#include "common.h"
#include <openxr/openxr.h>

struct OpenXrProgram* program_create(const struct Options* options, struct IPlatformPlugin* platformPlugin,
                                     struct IGraphicsPlugin* graphicsPlugin) {
    return new OpenXrProgram(options, platformPlugin, graphicsPlugin);
}

void program_CreateInstance(struct OpenXrProgram* self) { self->CreateInstance(); }

void program_InitializeSystem(struct OpenXrProgram* self) { self->InitializeSystem(); }

inline const char* GetXrEnvironmentBlendModeStr(XrEnvironmentBlendMode environmentBlendMode) {
    switch (environmentBlendMode) {
        case XR_ENVIRONMENT_BLEND_MODE_OPAQUE:
            return "Opaque";
        case XR_ENVIRONMENT_BLEND_MODE_ADDITIVE:
            return "Additive";
        case XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND:
            return "AlphaBlend";
        default:
            throw std::invalid_argument(Fmt("Unknown environment blend mode '%s'", to_string(environmentBlendMode)));
    }
}

static void SetEnvironmentBlendMode(Options* opts, XrEnvironmentBlendMode environmentBlendMode) {
    opts->EnvironmentBlendMode = GetXrEnvironmentBlendModeStr(environmentBlendMode);
    opts->Parsed.EnvironmentBlendMode = environmentBlendMode;
}

void SetEnvironmentBlendMode(struct Options* opts, struct OpenXrProgram* self) {
    SetEnvironmentBlendMode(opts, self->GetPreferredBlendMode());
}

void program_InitializeDevice(struct OpenXrProgram* self) { self->InitializeDevice(); }

void program_InitializeSession(struct OpenXrProgram* self) { self->InitializeSession(); }

void program_CreateSwapchains(struct OpenXrProgram* self) { self->CreateSwapchains(); }

void program_PollEvents(struct OpenXrProgram* self, bool* exitRenderLoop, bool* requestRestart) {
    self->PollEvents(exitRenderLoop, requestRestart);
}

bool program_IsSessionRunning(struct OpenXrProgram* self) { return self->IsSessionRunning(); }

void program_PollActions(struct OpenXrProgram* self) { self->PollActions(); }

void program_RenderFrame(struct OpenXrProgram* self) { self->RenderFrame(); }
