const std = @import("std");
const xr_gen = @import("openxr");
const xr = xr_gen.c;
const xr_result = @import("xr_result.zig");

tracker: xr.XrHandTrackerEXT = null,
joints: [xr.XR_HAND_JOINT_COUNT_EXT]xr.XrHandJointLocationEXT = undefined,

pub fn init(
    this: *@This(),
    extension: xr_gen.extensions.XR_EXT_hand_tracking,
    session: xr.XrSession,
    lr: enum { left, right },
) !void {
    var create_info = xr.XrHandTrackerCreateInfoEXT{
        .type = xr.XR_TYPE_HAND_TRACKER_CREATE_INFO_EXT,
        .next = null,
        .handJointSet = xr.XR_HAND_JOINT_SET_DEFAULT_EXT,
        .hand = switch (lr) {
            .left => xr.XR_HAND_LEFT_EXT,
            .right => xr.XR_HAND_RIGHT_EXT,
        },
    };
    try xr_result.check(extension.xrCreateHandTrackerEXT.?(
        session,
        &create_info,
        &this.tracker,
    ));
}

pub fn deinit(this: *@This()) void {
    _ = this;
}

pub fn locate(
    this: *@This(),
    extension: xr_gen.extensions.XR_EXT_hand_tracking,
    space: xr.XrSpace,
    predictedDisplayTime: xr.XrTime,
) !?[]xr.XrHandJointLocationEXT {
    var locate_info = xr.XrHandJointsLocateInfoEXT{
        .type = xr.XR_TYPE_HAND_JOINTS_LOCATE_INFO_EXT,
        .next = null,
        .baseSpace = space,
        .time = predictedDisplayTime,
    };
    var locations = xr.XrHandJointLocationsEXT{
        .type = xr.XR_TYPE_HAND_JOINT_LOCATIONS_EXT,
        .next = null,
        .jointCount = @intCast(this.joints.len),
        .jointLocations = &this.joints[0],
    };

    if (0 == extension.xrLocateHandJointsEXT.?(
        this.tracker,
        &locate_info,
        &locations,
    )) {
        if (locations.isActive != 0) {
            return this.joints[0..locations.jointCount];
        }
    }
    return null;
}
