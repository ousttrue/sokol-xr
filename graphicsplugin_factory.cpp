// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

#include "graphicsplugin_factory.h"
#include <utility>

#include "pch.h"
#include "common.h"
#include "options.h"
#include "platformdata.h"
#include "graphicsplugin.h"
#include <functional>
#include <map>

// Graphics API factories are forward declared here.
#ifdef XR_USE_GRAPHICS_API_OPENGL_ES
IGraphicsPlugin* CreateGraphicsPlugin_OpenGLES(const Options* options, IPlatformPlugin* platformPlugin);
#endif
#ifdef XR_USE_GRAPHICS_API_OPENGL
IGraphicsPlugin* CreateGraphicsPlugin_OpenGL(const Options* options, IPlatformPlugin* platformPlugin);
#endif
#ifdef XR_USE_GRAPHICS_API_VULKAN
IGraphicsPlugin* CreateGraphicsPlugin_VulkanLegacy(const Options* options, IPlatformPlugin* platformPlugin);

IGraphicsPlugin* CreateGraphicsPlugin_Vulkan(const Options* options, IPlatformPlugin* platformPlugin);
#endif
#ifdef XR_USE_GRAPHICS_API_D3D11
IGraphicsPlugin* CreateGraphicsPlugin_D3D11(const Options* options, IPlatformPlugin* platformPlugin);
#endif
#ifdef XR_USE_GRAPHICS_API_D3D12
IGraphicsPlugin* CreateGraphicsPlugin_D3D12(const Options* options, IPlatformPlugin* platformPlugin);
#endif
#ifdef XR_USE_GRAPHICS_API_METAL
IGraphicsPlugin* CreateGraphicsPlugin_Metal(const Options* options, IPlatformPlugin* platformPlugin);
#endif

namespace {
using GraphicsPluginFactory = std::function<IGraphicsPlugin*(const Options* options, IPlatformPlugin* platformPlugin)>;

std::map<std::string, GraphicsPluginFactory, IgnoreCaseStringLess> graphicsPluginMap = {
#ifdef XR_USE_GRAPHICS_API_OPENGL_ES
    {"OpenGLES", [](const Options* options,
                    IPlatformPlugin* platformPlugin) { return CreateGraphicsPlugin_OpenGLES(options, std::move(platformPlugin)); }},
#endif
#ifdef XR_USE_GRAPHICS_API_OPENGL
    {"OpenGL", [](const Options* options,
                  IPlatformPlugin* platformPlugin) { return CreateGraphicsPlugin_OpenGL(options, std::move(platformPlugin)); }},
#endif
#ifdef XR_USE_GRAPHICS_API_VULKAN
    {"Vulkan",
     [](const Options* options, IPlatformPlugin* platformPlugin) {
         return CreateGraphicsPlugin_VulkanLegacy(options, std::move(platformPlugin));
     }},
    {"Vulkan2", [](const Options* options,
                   IPlatformPlugin* platformPlugin) { return CreateGraphicsPlugin_Vulkan(options, std::move(platformPlugin)); }},
#endif
#ifdef XR_USE_GRAPHICS_API_D3D11
    {"D3D11", [](const Options* options,
                 IPlatformPlugin* platformPlugin) { return CreateGraphicsPlugin_D3D11(options, std::move(platformPlugin)); }},
#endif
#ifdef XR_USE_GRAPHICS_API_D3D12
    {"D3D12", [](const Options* options,
                 IPlatformPlugin* platformPlugin) { return CreateGraphicsPlugin_D3D12(options, std::move(platformPlugin)); }},
#endif
#ifdef XR_USE_GRAPHICS_API_METAL
    {"Metal", [](const Options* options,
                 IPlatformPlugin* platformPlugin) { return CreateGraphicsPlugin_Metal(options, std::move(platformPlugin)); }},
#endif
};
}  // namespace

IGraphicsPlugin* GraphicsPlugin_create(const Options* options, IPlatformPlugin* platformPlugin) {
    if (options->GraphicsPlugin == nullptr || strlen(options->GraphicsPlugin) == 0) {
        throw std::invalid_argument("No graphics API specified");
    }

    const auto apiIt = graphicsPluginMap.find(options->GraphicsPlugin);
    if (apiIt == graphicsPluginMap.end()) {
        throw std::invalid_argument(Fmt("Unsupported graphics API '%s'", options->GraphicsPlugin));
    }

    return apiIt->second(options, std::move(platformPlugin));
}

void GraphicsPlugin_updateOptions(struct IGraphicsPlugin* self, const struct Options* options) { self->UpdateOptions(options); }
