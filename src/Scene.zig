const std = @import("std");
const xr = @import("openxr");
const xr_util = @import("xr_util.zig");
const geometry = @import("geometry.zig");
const InputState = @import("InputState.zig");

allocator: std.mem.Allocator,
cubes: std.array_list.Managed(geometry.Cube),
visualizedSpaces: std.array_list.Managed(xr.XrSpace),

pub fn init(allocator: std.mem.Allocator, session: xr.XrSession) !@This() {
    // fn createVisualizedSpaces(self: *@This()) !void {
    // try xr_util.assert(self.session != null);
    var self = @This(){
        .allocator = allocator,
        .cubes = .init(allocator),
        .visualizedSpaces = .init(allocator),
    };

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
        var space: xr.XrSpace = undefined;
        const res = xr.xrCreateReferenceSpace(session, &referenceSpaceCreateInfo, &space);
        if (res == 0) {
            try self.visualizedSpaces.append(space);
        } else {
            std.log.warn("Failed to create reference space {s} with error {}", .{
                visualizedSpace,
                res,
            });
        }
    }

    return self;
}

pub fn deinit(self: *@This()) void {
    self.cubes.deinit();
    self.visualizedSpaces.deinit();
}

pub fn update(self: *@This(), space: xr.XrSpace, input: *InputState, predictedDisplayTime: i64) ![]geometry.Cube {
    // For each locatable space that we want to visualize, render a 25cm cube.
    try self.cubes.resize(0);

    for (self.visualizedSpaces.items) |visualizedSpace| {
        var spaceLocation = xr.XrSpaceLocation{
            .type = xr.XR_TYPE_SPACE_LOCATION,
        };
        const res = xr.xrLocateSpace(
            visualizedSpace,
            space,
            predictedDisplayTime,
            &spaceLocation,
        );
        try xr_util.assert(res == 0); //, "xrLocateSpace");
        if (xr.XR_UNQUALIFIED_SUCCESS(res)) {
            if ((spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0 and
                (spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0)
            {
                try self.cubes.append(.{
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
        var spaceLocation = xr.XrSpaceLocation{
            .type = xr.XR_TYPE_SPACE_LOCATION,
        };
        const res = xr.xrLocateSpace(
            input.handSpace[hand],
            space,
            predictedDisplayTime,
            &spaceLocation,
        );
        // std.debug.assert(res == 0); //, "xrLocateSpace");
        if (xr.XR_UNQUALIFIED_SUCCESS(res)) {
            if ((spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_POSITION_VALID_BIT) != 0 and
                (spaceLocation.locationFlags & xr.XR_SPACE_LOCATION_ORIENTATION_VALID_BIT) != 0)
            {
                const scale = 0.1 * input.handScale[hand];
                try self.cubes.append(.{
                    .Pose = spaceLocation.pose,
                    .Scale = .{ .x = scale, .y = scale, .z = scale },
                });
            }
        } else {
            // Tracking loss is expected when the hand is not active so only log a message
            // if the hand is active.
            if (input.handActive[hand] == xr.XR_TRUE) {
                const handName = [_][]const u8{ "left", "right" };
                std.log.debug("Unable to locate {s} hand action space in app space: {}", .{
                    handName[hand],
                    res,
                });
            }
        }
    }

    return self.cubes.items;
}

pub fn getXrReferenceSpaceCreateInfo(referenceSpaceTypeStr: []const u8) !xr.XrReferenceSpaceCreateInfo {
    var referenceSpaceCreateInfo = xr.XrReferenceSpaceCreateInfo{
        .type = xr.XR_TYPE_REFERENCE_SPACE_CREATE_INFO,
        .poseInReferenceSpace = geometry.XrPosef_Identity(),
    };
    if (std.mem.eql(u8, referenceSpaceTypeStr, "View")) {
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_VIEW;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "ViewFront")) {
        // Render head-locked 2m in front of device.
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_Translation(.{ .x = 0, .y = 0, .z = -2 });
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_VIEW;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "Local")) {
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_LOCAL;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "Stage")) {
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageLeft")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            0,
            .{ .x = -2, .y = 0, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageRight")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            0,
            .{ .x = 2, .y = 0, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageLeftRotated")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            3.14 / 3.0,
            .{ .x = -2, .y = 0.5, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else if (std.mem.eql(u8, referenceSpaceTypeStr, "StageRightRotated")) {
        referenceSpaceCreateInfo.poseInReferenceSpace = geometry.XrPosef_RotateCCWAboutYAxis(
            -3.14 / 3.0,
            .{ .x = 2, .y = 0.5, .z = -2 },
        );
        referenceSpaceCreateInfo.referenceSpaceType = xr.XR_REFERENCE_SPACE_TYPE_STAGE;
    } else {
        std.log.err("unknown_reference_space_type: {s}", .{referenceSpaceTypeStr});
        return error.unknown_reference_space_type;
    }
    return referenceSpaceCreateInfo;
}
