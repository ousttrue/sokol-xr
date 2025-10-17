const std = @import("std");
const xr_gen = @import("openxr");
const xr = xr_gen.c;
const xr_result = @import("xr_result.zig");
const get_proc = @import("get_proc.zig");

ext_passthrough: xr_gen.extensions.XR_FB_passthrough = .{},
passthrough_feature: xr.XrPassthroughFB = null,
passthrough_layer: xr.XrPassthroughLayerFB = null,

pub fn init(instance: xr.XrInstance, session: xr.XrSession) !@This() {
    var this = @This(){};

    get_proc.getProcs(@ptrCast(instance), &this.ext_passthrough);

    //
    // XR_FB_passthrough
    // https://developers.meta.com/horizon/documentation/native/android/mobile-passthrough/?locale=ja_JP
    //
    var create_info = xr.XrPassthroughCreateInfoFB{
        .type = xr.XR_TYPE_PASSTHROUGH_CREATE_INFO_FB,
        .flags = xr.XR_PASSTHROUGH_IS_RUNNING_AT_CREATION_BIT_FB,
    };
    try xr_result.check(this.ext_passthrough.xrCreatePassthroughFB.?(
        session,
        &create_info,
        &this.passthrough_feature,
    ));

    var layer_create_info = xr.XrPassthroughLayerCreateInfoFB{
        .type = xr.XR_TYPE_PASSTHROUGH_LAYER_CREATE_INFO_FB,
        .passthrough = this.passthrough_feature,
        .purpose = xr.XR_PASSTHROUGH_LAYER_PURPOSE_RECONSTRUCTION_FB,
        .flags = xr.XR_PASSTHROUGH_IS_RUNNING_AT_CREATION_BIT_FB,
    };
    try xr_result.check(this.ext_passthrough.xrCreatePassthroughLayerFB.?(
        session,
        &layer_create_info,
        &this.passthrough_layer,
    ));

    return this;
}

pub fn deinit(this: *@This()) void {
    _ = this;
}


// https://developers.meta.com/horizon/documentation/native/android/mobile-passthrough
// TODO: XR_PASSTHROUGH_CAPABILITY_COLOR_BIT_FB
pub fn systemSupportsPassthrough(instance: xr.XrInstance, systemId: xr.XrSystemId) !bool {
    var passthroughSystemProperties = xr.XrSystemPassthroughProperties2FB{
        .type = xr.XR_TYPE_SYSTEM_PASSTHROUGH_PROPERTIES2_FB,
    };
    var systemProperties = xr.XrSystemProperties{
        .type = xr.XR_TYPE_SYSTEM_PROPERTIES,
        .next = &passthroughSystemProperties,
    };
    try xr_result.check(xr.xrGetSystemProperties(instance, systemId, &systemProperties));
    return (passthroughSystemProperties.capabilities & xr.XR_PASSTHROUGH_CAPABILITY_BIT_FB) == xr.XR_PASSTHROUGH_CAPABILITY_BIT_FB;
}
