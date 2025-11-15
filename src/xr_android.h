#define XR_USE_PLATFORM_ANDROID 1
#define XR_USE_GRAPHICS_API_OPENGL_ES 1
#include <openxr/openxr.h>

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <GLES3/gl3ext.h>

#include <android/log.h>
#include <android_native_app_glue.h>
#include <android/native_window.h>
#include <android/native_activity.h>
#include <jni.h>
#include <sys/system_properties.h>

#include <openxr/openxr_platform.h>

#include "cpp_helper.h"
