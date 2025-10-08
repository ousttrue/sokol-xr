// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <openxr/openxr.h>

#ifdef __cplusplus
extern "C" {
#endif

struct Options {
    const char* GraphicsPlugin
#ifdef __cplusplus
        = ""
#endif
        ;
    const char* FormFactor
#ifdef __cplusplus
        = "Hmd"
#endif
        ;

    const char* ViewConfiguration
#ifdef __cplusplus
        = "Stereo"
#endif
        ;

    const char* EnvironmentBlendMode
#ifdef __cplusplus
        = "Opaque"
#endif
        ;

    const char* AppSpace
#ifdef __cplusplus
        = "Local"
#endif
        ;

    struct {
        XrFormFactor FormFactor
#ifdef __cplusplus
            = {XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY}
#endif
        ;

        XrViewConfigurationType ViewConfigType
#ifdef __cplusplus
            = {XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO}
#endif
        ;

        XrEnvironmentBlendMode EnvironmentBlendMode
#ifdef __cplusplus
            = {XR_ENVIRONMENT_BLEND_MODE_OPAQUE}
#endif
        ;
    } Parsed;
};

#ifdef __cplusplus
}

#include <array>
// #include <string>

inline std::array<float, 4> GetBackgroundClearColor(const Options* self) {
    static const std::array<float, 4> SlateGrey{0.184313729f, 0.309803933f, 0.309803933f, 1.0f};
    static const std::array<float, 4> TransparentBlack{0.0f, 0.0f, 0.0f, 0.0f};
    static const std::array<float, 4> Black{0.0f, 0.0f, 0.0f, 1.0f};

    switch (self->Parsed.EnvironmentBlendMode) {
        case XR_ENVIRONMENT_BLEND_MODE_OPAQUE:
            return SlateGrey;
        case XR_ENVIRONMENT_BLEND_MODE_ADDITIVE:
            return Black;
        case XR_ENVIRONMENT_BLEND_MODE_ALPHA_BLEND:
            return TransparentBlack;
        default:
            return SlateGrey;
    }
}
#endif
