// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

#include "pch.h"
#include "common.h"
#include "platformplugin.h"

#ifdef XR_USE_PLATFORM_WIN32
namespace {
struct Win32PlatformPlugin : public IPlatformPlugin {
    Win32PlatformPlugin(const Options*) { CHECK_HRCMD(CoInitializeEx(nullptr, COINIT_MULTITHREADED)); }

    virtual ~Win32PlatformPlugin() override { CoUninitialize(); }

    std::vector<std::string> GetInstanceExtensions() const override { return {}; }

    XrBaseInStructure* GetInstanceCreateExtension() const override { return nullptr; }

    void UpdateOptions(const Options* /*unused*/) override {}
};
}  // namespace

IPlatformPlugin* CreatePlatformPlugin_Win32(const Options* options) {
    return new Win32PlatformPlugin(options);
}
#endif
