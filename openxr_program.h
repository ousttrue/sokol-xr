// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

#pragma once
#include "options.h"
#include <map>
#include <set>

struct Swapchain {
    XrSwapchain handle;
    int32_t width;
    int32_t height;
};

namespace Side {
const int LEFT = 0;
const int RIGHT = 1;
const int COUNT = 2;
}  // namespace Side

struct InputState {
    XrActionSet actionSet{XR_NULL_HANDLE};
    XrAction grabAction{XR_NULL_HANDLE};
    XrAction poseAction{XR_NULL_HANDLE};
    XrAction vibrateAction{XR_NULL_HANDLE};
    XrAction quitAction{XR_NULL_HANDLE};
    std::array<XrPath, Side::COUNT> handSubactionPath;
    std::array<XrSpace, Side::COUNT> handSpace;
    std::array<float, Side::COUNT> handScale = {{1.0f, 1.0f}};
    std::array<XrBool32, Side::COUNT> handActive;
};

struct OpenXrProgram {
   private:
    const struct Options *m_options;
    struct IPlatformPlugin* m_platformPlugin;
    struct IGraphicsPlugin* m_graphicsPlugin;
    XrInstance m_instance{XR_NULL_HANDLE};
    XrSession m_session{XR_NULL_HANDLE};
    XrSpace m_appSpace{XR_NULL_HANDLE};
    XrSystemId m_systemId{XR_NULL_SYSTEM_ID};

    std::vector<XrViewConfigurationView> m_configViews;
    std::vector<Swapchain> m_swapchains;
    std::map<XrSwapchain, std::vector<XrSwapchainImageBaseHeader*>> m_swapchainImages;
    std::vector<XrView> m_views;
    int64_t m_colorSwapchainFormat{-1};

    std::vector<XrSpace> m_visualizedSpaces;

    // Application's current lifecycle state according to the runtime
    XrSessionState m_sessionState{XR_SESSION_STATE_UNKNOWN};
    bool m_sessionRunning{false};

    XrEventDataBuffer m_eventDataBuffer;
    InputState m_input;

    const std::set<XrEnvironmentBlendMode> m_acceptableBlendModes;

   public:
    OpenXrProgram(const Options* options, IPlatformPlugin* platformPlugin,
                  IGraphicsPlugin* graphicsPlugin);
    ~OpenXrProgram();
    OpenXrProgram(const OpenXrProgram&) = delete;
    OpenXrProgram& operator=(const OpenXrProgram&) = delete;

    static void LogLayersAndExtensions();
    void LogInstanceInfo();
    void CreateInstanceInternal();
    void CreateInstance();
    void LogViewConfigurations();
    void LogEnvironmentBlendMode(XrViewConfigurationType type);
    XrEnvironmentBlendMode GetPreferredBlendMode() const;
    void InitializeSystem();
    void InitializeDevice();
    void LogReferenceSpaces();
    void InitializeActions();
    void CreateVisualizedSpaces();
    void InitializeSession();
    void CreateSwapchains();
    // Return event if one is available, otherwise return null.
    const XrEventDataBaseHeader* TryReadNextEvent();
    void PollEvents(bool* exitRenderLoop, bool* requestRestart);
    void HandleSessionStateChangedEvent(const XrEventDataSessionStateChanged& stateChangedEvent, bool* exitRenderLoop,
                                        bool* requestRestart);
    void LogActionSourceName(XrAction action, const std::string& actionName) const;
    bool IsSessionRunning() const { return m_sessionRunning; }
    bool IsSessionFocused() const { return m_sessionState == XR_SESSION_STATE_FOCUSED; }
    void PollActions();
    void RenderFrame();
    bool RenderLayer(XrTime predictedDisplayTime, std::vector<XrCompositionLayerProjectionView>& projectionLayerViews,
                     XrCompositionLayerProjection& layer);
};
