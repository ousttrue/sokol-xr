#define XR_USE_PLATFORM_WIN32 1
#define XR_USE_GRAPHICS_API_OPENGL 1
#define XR_USE_GRAPHICS_API_D3D11 1
#include <openxr/openxr.h>
#include <Windows.h>
#include <d3d11.h>
#include <openxr/openxr_platform.h>

#include "graphicsplugin_d3d11.h"
#include "dxgi.h"
#include "common/gfxwrapper_opengl.h"
