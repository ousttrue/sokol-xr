// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

#include "platformplugin_factory.h"
#include "pch.h"
#include "platformplugin.h"

#define UNUSED_PARM(x) \
    {                  \
        (void)(x);     \
    }

// Implementation in platformplugin_win32.cpp
IPlatformPlugin* CreatePlatformPlugin_Win32(const Options* options);

// Implementation in platformplugin_posix.cpp
IPlatformPlugin* CreatePlatformPlugin_Posix(const Options* options);

// Implementation in platformplugin_android.cpp
IPlatformPlugin* CreatePlatformPlugin_Android(const Options* /*unused*/, const PlatformData* /*unused*/);

IPlatformPlugin* PlatformPlugin_create(const Options* options, const PlatformData* data) {
#if !defined(XR_USE_PLATFORM_ANDROID)
    UNUSED_PARM(data);
#endif

#if defined(XR_USE_PLATFORM_WIN32)
    return CreatePlatformPlugin_Win32(options);
#elif defined(XR_USE_PLATFORM_ANDROID)
    return CreatePlatformPlugin_Android(options, data);
#elif defined(XR_OS_APPLE) || defined(XR_OS_LINUX)
    return CreatePlatformPlugin_Posix(options);
#else
#error Unsupported platform or no XR platform defined!
#endif
}

void PlatformPlugin_updateOptions(struct IPlatformPlugin* self, const struct Options* options) { self->UpdateOptions(options); }
