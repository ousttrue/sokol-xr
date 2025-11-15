const c = @import("c");
const xr_result = @import("xr_result.zig");

actionSet: c.XrActionSet = null,
// XrAction grabAction{XR_NULL_HANDLE};
// XrAction poseAction{XR_NULL_HANDLE};
// XrAction vibrateAction{XR_NULL_HANDLE};
// XrAction quitAction{XR_NULL_HANDLE};
// std::array<XrPath, Side::COUNT> handSubactionPath;
handSpace: [2]c.XrSpace = .{ null, null },
handScale: [2]f32 = .{ 1.0, 1.0 },
handActive: [2]c.XrBool32 = .{ c.XR_FALSE, c.XR_FALSE },

pub fn initializeActions(self: *@This()) !void {
    // Create an action set.
    {
        var actionSetInfo = c.XrActionSetCreateInfo{
            .type = c.XR_TYPE_ACTION_SET_CREATE_INFO,
            .priority = 0,
        };
        //     strcpy_s(actionSetInfo.actionSetName, "gameplay");
        //     strcpy_s(actionSetInfo.localizedActionSetName, "Gameplay");
        try xr_result.check(c.xrCreateActionSet(self.instance, &actionSetInfo, &self.input.actionSet));
    }

    // // Get the XrPath for the left and right hands - we will use them as subaction paths.
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left", &m_input.handSubactionPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right", &m_input.handSubactionPath[Side::RIGHT]));
    //
    // // Create actions.
    // {
    //     // Create an input action for grabbing objects with the left and right hands.
    //     XrActionCreateInfo actionInfo{XR_TYPE_ACTION_CREATE_INFO};
    //     actionInfo.actionType = XR_ACTION_TYPE_FLOAT_INPUT;
    //     strcpy_s(actionInfo.actionName, "grab_object");
    //     strcpy_s(actionInfo.localizedActionName, "Grab Object");
    //     actionInfo.countSubactionPaths = uint32_t(m_input.handSubactionPath.size());
    //     actionInfo.subactionPaths = m_input.handSubactionPath.data();
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.grabAction));
    //
    //     // Create an input action getting the left and right hand poses.
    //     actionInfo.actionType = XR_ACTION_TYPE_POSE_INPUT;
    //     strcpy_s(actionInfo.actionName, "hand_pose");
    //     strcpy_s(actionInfo.localizedActionName, "Hand Pose");
    //     actionInfo.countSubactionPaths = uint32_t(m_input.handSubactionPath.size());
    //     actionInfo.subactionPaths = m_input.handSubactionPath.data();
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.poseAction));
    //
    //     // Create output actions for vibrating the left and right controller.
    //     actionInfo.actionType = XR_ACTION_TYPE_VIBRATION_OUTPUT;
    //     strcpy_s(actionInfo.actionName, "vibrate_hand");
    //     strcpy_s(actionInfo.localizedActionName, "Vibrate Hand");
    //     actionInfo.countSubactionPaths = uint32_t(m_input.handSubactionPath.size());
    //     actionInfo.subactionPaths = m_input.handSubactionPath.data();
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.vibrateAction));
    //
    //     // Create input actions for quitting the session using the left and right controller.
    //     // Since it doesn't matter which hand did this, we do not specify subaction paths for it.
    //     // We will just suggest bindings for both hands, where possible.
    //     actionInfo.actionType = XR_ACTION_TYPE_BOOLEAN_INPUT;
    //     strcpy_s(actionInfo.actionName, "quit_session");
    //     strcpy_s(actionInfo.localizedActionName, "Quit Session");
    //     actionInfo.countSubactionPaths = 0;
    //     actionInfo.subactionPaths = nullptr;
    //     xr_result.check(xrCreateAction(m_input.actionSet, &actionInfo, &m_input.quitAction));
    // }
    //
    // std::array<XrPath, Side::COUNT> selectPath;
    // std::array<XrPath, Side::COUNT> squeezeValuePath;
    // std::array<XrPath, Side::COUNT> squeezeForcePath;
    // std::array<XrPath, Side::COUNT> squeezeClickPath;
    // std::array<XrPath, Side::COUNT> posePath;
    // std::array<XrPath, Side::COUNT> hapticPath;
    // std::array<XrPath, Side::COUNT> menuClickPath;
    // std::array<XrPath, Side::COUNT> bClickPath;
    // std::array<XrPath, Side::COUNT> triggerValuePath;
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/select/click", &selectPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/select/click", &selectPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/squeeze/value", &squeezeValuePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/squeeze/value", &squeezeValuePath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/squeeze/force", &squeezeForcePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/squeeze/force", &squeezeForcePath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/squeeze/click", &squeezeClickPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/squeeze/click", &squeezeClickPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/grip/pose", &posePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/grip/pose", &posePath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/output/haptic", &hapticPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/output/haptic", &hapticPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/menu/click", &menuClickPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/menu/click", &menuClickPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/b/click", &bClickPath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/b/click", &bClickPath[Side::RIGHT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/left/input/trigger/value", &triggerValuePath[Side::LEFT]));
    // xr_result.check(xrStringToPath(m_instance, "/user/hand/right/input/trigger/value", &triggerValuePath[Side::RIGHT]));
    // // Suggest bindings for KHR Simple.
    // {
    //     XrPath khrSimpleInteractionProfilePath;
    //     xr_result.check(xrStringToPath(m_instance, "/interaction_profiles/khr/simple_controller", &khrSimpleInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{// Fall back to a click input for the grab action.
    //                                                     {m_input.grabAction, selectPath[Side::LEFT]},
    //                                                     {m_input.grabAction, selectPath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = khrSimpleInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    // // Suggest bindings for the Oculus Touch.
    // {
    //     XrPath oculusTouchInteractionProfilePath;
    //     xr_result.check(
    //         xrStringToPath(m_instance, "/interaction_profiles/oculus/touch_controller", &oculusTouchInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, squeezeValuePath[Side::LEFT]},
    //                                                     {m_input.grabAction, squeezeValuePath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = oculusTouchInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    // // Suggest bindings for the Vive Controller.
    // {
    //     XrPath viveControllerInteractionProfilePath;
    //     xr_result.check(xrStringToPath(m_instance, "/interaction_profiles/htc/vive_controller", &viveControllerInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, triggerValuePath[Side::LEFT]},
    //                                                     {m_input.grabAction, triggerValuePath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = viveControllerInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    //
    // // Suggest bindings for the Valve Index Controller.
    // {
    //     XrPath indexControllerInteractionProfilePath;
    //     xr_result.check(
    //         xrStringToPath(m_instance, "/interaction_profiles/valve/index_controller", &indexControllerInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, squeezeForcePath[Side::LEFT]},
    //                                                     {m_input.grabAction, squeezeForcePath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, bClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, bClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = indexControllerInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    //
    // // Suggest bindings for the Microsoft Mixed Reality Motion Controller.
    // {
    //     XrPath microsoftMixedRealityInteractionProfilePath;
    //     xr_result.check(xrStringToPath(m_instance, "/interaction_profiles/microsoft/motion_controller",
    //                                &microsoftMixedRealityInteractionProfilePath));
    //     std::vector<XrActionSuggestedBinding> bindings{{{m_input.grabAction, squeezeClickPath[Side::LEFT]},
    //                                                     {m_input.grabAction, squeezeClickPath[Side::RIGHT]},
    //                                                     {m_input.poseAction, posePath[Side::LEFT]},
    //                                                     {m_input.poseAction, posePath[Side::RIGHT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::LEFT]},
    //                                                     {m_input.quitAction, menuClickPath[Side::RIGHT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::LEFT]},
    //                                                     {m_input.vibrateAction, hapticPath[Side::RIGHT]}}};
    //     XrInteractionProfileSuggestedBinding suggestedBindings{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    //     suggestedBindings.interactionProfile = microsoftMixedRealityInteractionProfilePath;
    //     suggestedBindings.suggestedBindings = bindings.data();
    //     suggestedBindings.countSuggestedBindings = (uint32_t)bindings.size();
    //     xr_result.check(xrSuggestInteractionProfileBindings(m_instance, &suggestedBindings));
    // }
    // XrActionSpaceCreateInfo actionSpaceInfo{XR_TYPE_ACTION_SPACE_CREATE_INFO};
    // actionSpaceInfo.action = m_input.poseAction;
    // actionSpaceInfo.poseInActionSpace.orientation.w = 1.f;
    // actionSpaceInfo.subactionPath = m_input.handSubactionPath[Side::LEFT];
    // xr_result.check(xrCreateActionSpace(m_session, &actionSpaceInfo, &m_input.handSpace[Side::LEFT]));
    // actionSpaceInfo.subactionPath = m_input.handSubactionPath[Side::RIGHT];
    // xr_result.check(xrCreateActionSpace(m_session, &actionSpaceInfo, &m_input.handSpace[Side::RIGHT]));
    //
    // XrSessionActionSetsAttachInfo attachInfo{XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};
    // attachInfo.countActionSets = 1;
    // attachInfo.actionSets = &m_input.actionSet;
    // xr_result.check(xrAttachSessionActionSets(m_session, &attachInfo));
}

