const std = @import("std");
const c = @import("c");
const xr_util = @import("xr_util.zig");
const geometry = @import("geometry.zig");
const InputState = @import("InputState.zig");
const get_proc = @import("get_proc.zig");
const HandTracking = @import("HandTracking.zig");
const xr = @import("openxr");

allocator: std.mem.Allocator,
cubes: std.array_list.Managed(geometry.Cube),
visualizedSpaces: std.array_list.Managed(c.XrSpace),

ext_handTracking: xr.extensions.XR_EXT_hand_tracking = .{},
handLeft: HandTracking = .{},
handRight: HandTracking = .{},

pub fn init(
    allocator: std.mem.Allocator,
    instance: c.XrInstance,
    session: c.XrSession,
) !@This() {

    // fn createVisualizedSpaces(this: *@This()) !void {
    // try xr_util.assert(this.session != null);
    var this = @This(){
        .allocator = allocator,
        .cubes = .init(allocator),
        .visualizedSpaces = .init(allocator),
    };

    get_proc.getProcs(@ptrCast(instance), &this.ext_handTracking);
    try this.handLeft.init(this.ext_handTracking, session, .left);
    try this.handRight.init(this.ext_handTracking, session, .right);

    const visualizedSpaces = [_][]const u8{
        "ViewFront",
        "Local",
        "Stage",
        "StageLeft",
        "StageRight",
        "StageLeftRotated",
        "StageRightRotated",
    };

    for (visualizedSpaces) |visualizedSpace| {
        const referenceSpaceCreateInfo = try getXrReferenceSpaceCreateInfo(visualizedSpace);
        var space: c.XrSpace = undefined;
        const res = c.xrCreateReferenceSpace(session, &referenceSpaceCreateInfo, &space);
        if (res == 0) {
            try this.visualizedSpaces.append(space);
        } else {
            std.log.warn("Failed to create reference space {s} with error {}", .{
                visualizedSpace,
                res,
            });
        }
    }

    return this;
}

pub fn deinit(this: *@This()) void {
    this.cubes.deinit();
    this.visualizedSpaces.deinit();
}

pub fn update(
    this: *@This(),
    space: c.XrSpace,
    input: *InputState,
    predictedDisplayTime: i64,
) ![]geometry.Cube {
    // For each locatable space that we want to visualize, render a 25cm cube.
    try this.cubes.resize(0);

    // left
    if (try this.handLeft.locate(
        this.ext_handTracking,
        space,
        predictedDisplayTime,
    )) |joints| {
        for (joints) |joint| {
            try this.cubes.append(.{
                .Pose = joint.pose,
                .Scale = .{ .x = 0.02, .y = 0.02, .z = 0.02 },
            });
        }
    }
    // right
    if (try this.handRight.locate(
        this.ext_handTracking,
        space,
        predictedDisplayTime,
    )) |joints| {
        for (joints) |joint| {
            try this.cubes.append(.{
                .Pose = joint.pose,
                .Scale = .{ .x = 0.02, .y = 0.02, .z = 0.02 },
            });
        }
    }

    for (this.visualizedSpaces.items) |visualizedSpace| {
        var spaceLocation = c.XrSpaceLocation{
            .type = c.XR_TYPE_SPACE_LOCATION,
        };
        const res = c.xrLocateSpace(
            visualizedSpace,
            space,
            predictedDisplayTime,
            &spaceLocation,
        );
        try xr_util.assert(res == 0); //, "xrLocateSpace");
        if (c.XR_UNQUALIFIED_SUCCESS(res)) {
            if ((spaceLocation.locationFlags & c.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0 and
                (spaceLocation.locationFlags & c.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0)
            {
                try this.cubes.append(.{
                    .Pose = spaceLocation.pose,
                    .Scale = .{ .x = 0.25, .y = 0.25, .z = 0.25 },
                });
            }
        } else {
            std.log.debug("Unable to locate a visualized reference space in app space: {}", .{res});
        }
    }

    // Render a 10cm cube scaled by grabAction for each hand. Note renderHand will only be
    // true when the application has focus.
    const Side = struct {
        const LEFT = 0;
        const RIGHT = 1;
        const COUNT = 2;
    };
    const hands = [2]u32{ Side.LEFT, Side.RIGHT };
    for (hands) |hand| {
        var spaceLocation = c.XrSpaceLocation{
            .type = c.XR_TYPE_SPACE_LOCATION,
        };
        const res = c.xrLocateSpace(
            input.handSpace[hand],
            space,
            predictedDisplayTime,
            &spaceLocation,
        );
        // std.debug.assert(res == 0); //, "xrLocateSpace");
        if (c.XR_UNQUALIFIED_SUCCESS(res)) {
            if ((spaceLocation.locationFlags & c.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0 and
                (spaceLocation.locationFlags & c.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0)
            {
                const scale = 0.1 * input.handScale[hand];
                try this.cubes.append(.{
                    .Pose = spaceLocation.pose,
                    .Scale = .{ .x = scale, .y = scale, .z = scale },
                });
            }
        } else {
            // Tracking loss is expected when the hand is not active so only log a message
            // if the hand is active.
            if (input.handActive[hand] == c.XR_TRUE) {
                const handName = [_][]const u8{ "left", "right" };
                std.log.debug("Unable to locate {s} hand action space in app space: {}", .{
                    handName[hand],
                    res,
                });
            }
        }
    }

    return this.cubes.items;
}

pub fn getXrReferenceSpaceCreateInfo(referenceSpaceTypeStr: []const u8) !c.XrReferenceSpaceCreateInfo {
    var referenceSpaceCreateInfo = c.XrReferenceSpaceCreateInfo{
        .type = c.XR_TYPE_REFERENCE_SPACE_CREATE_INFO,
        .poseInReferenceSpace = geometry.XrPosef_Identity(),
    };
    if (std.mem.eql(u8, referenceSpaceTypeStr, "View")) {
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_VIEW;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "ViewFront")) {
        // Render head-locked 2m in front of device.
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_Translation(.{ .x = 0, .y = 0, .z = -2 });
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_VIEW;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "Local")) {
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_LOCAL;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "Stage")) {
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageLeft")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            0,
            .{ .x = -2, .y = 0, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageRight")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            0,
            .{ .x = 2, .y = 0, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageLeftRotated")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            3.14 / 3.0,
            .{ .x = -2, .y = 0.5, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageRightRotated")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            -3.14 / 3.0,
            .{ .x = 2, .y = 0.5, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = c.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else {
        std.log.err("unknown_reference_space_type: {s}", .{referenceSpaceTypeStr});
        return error.unknown_reference_space_type;
    }
    return referenceSpaceCreateInfo;
}
