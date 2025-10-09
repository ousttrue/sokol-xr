// Copyright (c) 2017-2025 The Khronos Group Inc.
//
// SPDX-License-Identifier: Apache-2.0

#include "graphicsplugin_d3d11.h"
#include "pch.h"
#include "common.h"
#include "geometry.h"
#include "graphicsplugin.h"
#include "options.h"

#include <common/xr_linear.h>
#include <DirectXColors.h>
#include <D3Dcompiler.h>

#include "d3d_common.h"
#include <list>
#include <map>

using namespace Microsoft::WRL;
using namespace DirectX;

namespace {
void InitializeD3D11DeviceForAdapter(IDXGIAdapter1* adapter, const std::vector<D3D_FEATURE_LEVEL>& featureLevels,
                                     ID3D11Device** device, ID3D11DeviceContext** deviceContext) {
    UINT creationFlags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;

#if !defined(NDEBUG)
    creationFlags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

    // Create the Direct3D 11 API device object and a corresponding context.
    D3D_DRIVER_TYPE driverType = ((adapter == nullptr) ? D3D_DRIVER_TYPE_HARDWARE : D3D_DRIVER_TYPE_UNKNOWN);

TryAgain:
    HRESULT hr = D3D11CreateDevice(adapter, driverType, 0, creationFlags, featureLevels.data(), (UINT)featureLevels.size(),
                                   D3D11_SDK_VERSION, device, nullptr, deviceContext);
    if (FAILED(hr)) {
        // If initialization failed, it may be because device debugging isn't supported, so retry without that.
        if ((creationFlags & D3D11_CREATE_DEVICE_DEBUG) && (hr == DXGI_ERROR_SDK_COMPONENT_MISSING)) {
            creationFlags &= ~D3D11_CREATE_DEVICE_DEBUG;
            goto TryAgain;
        }

        // If the initialization still fails, fall back to the WARP device.
        // For more information on WARP, see: http://go.microsoft.com/fwlink/?LinkId=286690
        if (driverType != D3D_DRIVER_TYPE_WARP) {
            driverType = D3D_DRIVER_TYPE_WARP;
            goto TryAgain;
        }
    }
}

#define RETURN_IF_FAIL(xr)       \
    {                            \
        if (xr < 0) return (xr); \
    }

struct D3D11GraphicsPlugin {
    // D3D11GraphicsPlugin(const Options* options) : m_clearColor(GetBackgroundClearColor(options)) {}

    std::vector<std::string> GetInstanceExtensions() const { return {XR_KHR_D3D11_ENABLE_EXTENSION_NAME}; }

    XrResult InitializeDevice(XrInstance instance, XrSystemId systemId) {
        PFN_xrGetD3D11GraphicsRequirementsKHR pfnGetD3D11GraphicsRequirementsKHR = nullptr;
        RETURN_IF_FAIL(xrGetInstanceProcAddr(instance, "xrGetD3D11GraphicsRequirementsKHR",
                                             reinterpret_cast<PFN_xrVoidFunction*>(&pfnGetD3D11GraphicsRequirementsKHR)));

        // Create the D3D11 device for the adapter associated with the system.
        XrGraphicsRequirementsD3D11KHR graphicsRequirements{XR_TYPE_GRAPHICS_REQUIREMENTS_D3D11_KHR};
        RETURN_IF_FAIL(pfnGetD3D11GraphicsRequirementsKHR(instance, systemId, &graphicsRequirements));
        const ComPtr<IDXGIAdapter1> adapter = GetAdapter(graphicsRequirements.adapterLuid);

        // Create a list of feature levels which are both supported by the OpenXR runtime and this application.
        std::vector<D3D_FEATURE_LEVEL> featureLevels = {D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_11_1,
                                                        D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
        featureLevels.erase(std::remove_if(featureLevels.begin(), featureLevels.end(),
                                           [&](D3D_FEATURE_LEVEL fl) { return fl < graphicsRequirements.minFeatureLevel; }),
                            featureLevels.end());
        CHECK_MSG(featureLevels.size() != 0, "Unsupported minimum feature level!");

        InitializeD3D11DeviceForAdapter(adapter.Get(), featureLevels, m_device.ReleaseAndGetAddressOf(),
                                        m_deviceContext.ReleaseAndGetAddressOf());

        InitializeResources();

        m_graphicsBinding.device = m_device.Get();

        return XR_SUCCESS;
    }

    void InitializeResources() {
        const ComPtr<ID3DBlob> vertexShaderBytes = CompileShader(ShaderHlsl, "MainVS", "vs_5_0");
        CHECK_HRCMD(m_device->CreateVertexShader(vertexShaderBytes->GetBufferPointer(), vertexShaderBytes->GetBufferSize(), nullptr,
                                                 m_vertexShader.ReleaseAndGetAddressOf()));

        const ComPtr<ID3DBlob> pixelShaderBytes = CompileShader(ShaderHlsl, "MainPS", "ps_5_0");
        CHECK_HRCMD(m_device->CreatePixelShader(pixelShaderBytes->GetBufferPointer(), pixelShaderBytes->GetBufferSize(), nullptr,
                                                m_pixelShader.ReleaseAndGetAddressOf()));

        const D3D11_INPUT_ELEMENT_DESC vertexDesc[] = {
            {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D11_APPEND_ALIGNED_ELEMENT, D3D11_INPUT_PER_VERTEX_DATA, 0},
            {"COLOR", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D11_APPEND_ALIGNED_ELEMENT, D3D11_INPUT_PER_VERTEX_DATA, 0},
        };

        CHECK_HRCMD(m_device->CreateInputLayout(vertexDesc, (UINT)ArraySize(vertexDesc), vertexShaderBytes->GetBufferPointer(),
                                                vertexShaderBytes->GetBufferSize(), &m_inputLayout));

        const CD3D11_BUFFER_DESC modelConstantBufferDesc(sizeof(ModelConstantBuffer), D3D11_BIND_CONSTANT_BUFFER);
        CHECK_HRCMD(m_device->CreateBuffer(&modelConstantBufferDesc, nullptr, m_modelCBuffer.ReleaseAndGetAddressOf()));

        const CD3D11_BUFFER_DESC viewProjectionConstantBufferDesc(sizeof(ViewProjectionConstantBuffer), D3D11_BIND_CONSTANT_BUFFER);
        CHECK_HRCMD(
            m_device->CreateBuffer(&viewProjectionConstantBufferDesc, nullptr, m_viewProjectionCBuffer.ReleaseAndGetAddressOf()));

        const D3D11_SUBRESOURCE_DATA vertexBufferData{Geometry::c_cubeVertices};
        const CD3D11_BUFFER_DESC vertexBufferDesc(sizeof(Geometry::c_cubeVertices), D3D11_BIND_VERTEX_BUFFER);
        CHECK_HRCMD(m_device->CreateBuffer(&vertexBufferDesc, &vertexBufferData, m_cubeVertexBuffer.ReleaseAndGetAddressOf()));

        const D3D11_SUBRESOURCE_DATA indexBufferData{Geometry::c_cubeIndices};
        const CD3D11_BUFFER_DESC indexBufferDesc(sizeof(Geometry::c_cubeIndices), D3D11_BIND_INDEX_BUFFER);
        CHECK_HRCMD(m_device->CreateBuffer(&indexBufferDesc, &indexBufferData, m_cubeIndexBuffer.ReleaseAndGetAddressOf()));
    }

    int64_t SelectColorSwapchainFormat(const int64_t* runtimeFormats, size_t len) const {
        // List of supported color swapchain formats.
        constexpr DXGI_FORMAT SupportedColorSwapchainFormats[] = {
            DXGI_FORMAT_R8G8B8A8_UNORM,
            DXGI_FORMAT_B8G8R8A8_UNORM,
            DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
            DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,
        };

        auto swapchainFormatIt =
            std::find_first_of(runtimeFormats, runtimeFormats + len, std::begin(SupportedColorSwapchainFormats),
                               std::end(SupportedColorSwapchainFormats));
        if (swapchainFormatIt == runtimeFormats + len) {
            THROW("No runtime swapchain format supported for color swapchain");
        }

        return *swapchainFormatIt;
    }

    const XrBaseInStructure* GetGraphicsBinding() const { return reinterpret_cast<const XrBaseInStructure*>(&m_graphicsBinding); }

    void AllocateSwapchainImageStructs(XrSwapchainImageBaseHeader** headers, uint32_t capacity) {
        // Allocate and initialize the buffer of image structs (must be sequential in memory for xrEnumerateSwapchainImages).
        // Return back an array of pointers to each swapchain image struct so the consumer doesn't need to know the type/size.
        std::vector<XrSwapchainImageD3D11KHR> swapchainImageBuffer(capacity, {XR_TYPE_SWAPCHAIN_IMAGE_D3D11_KHR});
        for (size_t i = 0; i < capacity; ++i) {
            headers[i] = reinterpret_cast<XrSwapchainImageBaseHeader*>(&swapchainImageBuffer[i]);
        }

        // Keep the buffer alive by moving it into the list of buffers.
        m_swapchainImageBuffers.push_back(std::move(swapchainImageBuffer));
    }

    ComPtr<ID3D11DepthStencilView> GetDepthStencilView(ID3D11Texture2D* colorTexture) {
        // If a depth-stencil view has already been created for this back-buffer, use it.
        auto depthBufferIt = m_colorToDepthMap.find(colorTexture);
        if (depthBufferIt != m_colorToDepthMap.end()) {
            return depthBufferIt->second;
        }

        // This back-buffer has no corresponding depth-stencil texture, so create one with matching dimensions.
        D3D11_TEXTURE2D_DESC colorDesc;
        colorTexture->GetDesc(&colorDesc);

        D3D11_TEXTURE2D_DESC depthDesc{};
        depthDesc.Width = colorDesc.Width;
        depthDesc.Height = colorDesc.Height;
        depthDesc.ArraySize = colorDesc.ArraySize;
        depthDesc.MipLevels = 1;
        depthDesc.Format = DXGI_FORMAT_R32_TYPELESS;
        depthDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_DEPTH_STENCIL;
        depthDesc.SampleDesc.Count = 1;
        ComPtr<ID3D11Texture2D> depthTexture;
        CHECK_HRCMD(m_device->CreateTexture2D(&depthDesc, nullptr, depthTexture.ReleaseAndGetAddressOf()));

        // Create and cache the depth stencil view.
        ComPtr<ID3D11DepthStencilView> depthStencilView;
        D3D11_DEPTH_STENCIL_VIEW_DESC depthStencilViewDesc = {
            .Format = DXGI_FORMAT_D32_FLOAT,
            .ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D,
            .Flags = 0,
            .Texture2D = {.MipSlice = 0},
        };
        CHECK_HRCMD(m_device->CreateDepthStencilView(depthTexture.Get(), &depthStencilViewDesc, depthStencilView.GetAddressOf()));
        depthBufferIt = m_colorToDepthMap.insert(std::make_pair(colorTexture, depthStencilView)).first;

        return depthStencilView;
    }

    void RenderView(const XrCompositionLayerProjectionView* layerView, const XrSwapchainImageBaseHeader* swapchainImage,
                    int64_t swapchainFormat, const Cube* cubes, size_t len) {
        if (layerView->subImage.imageArrayIndex != 0) {  // Texture arrays not supported.
            return;
        }

        ID3D11Texture2D* const colorTexture = reinterpret_cast<const XrSwapchainImageD3D11KHR*>(swapchainImage)->texture;

        D3D11_VIEWPORT viewport = {
            .TopLeftX = (float)layerView->subImage.imageRect.offset.x,
            .TopLeftY = (float)layerView->subImage.imageRect.offset.y,
            .Width = (float)layerView->subImage.imageRect.extent.width,
            .Height = (float)layerView->subImage.imageRect.extent.height,
            .MinDepth = 0,  // D3D11_MIN_DEPTH,
            .MaxDepth = 1,  // D3D11_MAX_DEPTH,
        };
        m_deviceContext->RSSetViewports(1, &viewport);

        // Create RenderTargetView with original swapchain format (swapchain is typeless).
        ComPtr<ID3D11RenderTargetView> renderTargetView;
        const CD3D11_RENDER_TARGET_VIEW_DESC renderTargetViewDesc(D3D11_RTV_DIMENSION_TEXTURE2D, (DXGI_FORMAT)swapchainFormat);
        CHECK_HRCMD(
            m_device->CreateRenderTargetView(colorTexture, &renderTargetViewDesc, renderTargetView.ReleaseAndGetAddressOf()));

        const ComPtr<ID3D11DepthStencilView> depthStencilView = GetDepthStencilView(colorTexture);

        // Clear swapchain and depth buffer. NOTE: This will clear the entire render target view, not just the specified view.
        float clearColor[4] = {
            0,
            0,
            0,
            0,
        };
        m_deviceContext->ClearRenderTargetView(renderTargetView.Get(), clearColor);
        m_deviceContext->ClearDepthStencilView(depthStencilView.Get(), D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 1.0f, 0);

        ID3D11RenderTargetView* renderTargets[] = {renderTargetView.Get()};
        m_deviceContext->OMSetRenderTargets((UINT)ArraySize(renderTargets), renderTargets, depthStencilView.Get());

        const XMMATRIX spaceToView = XMMatrixInverse(nullptr, LoadXrPose(layerView->pose));
        XrMatrix4x4f projectionMatrix;
        XrMatrix4x4f_CreateProjectionFov(&projectionMatrix, GRAPHICS_D3D, layerView->fov, 0.05f, 100.0f);

        // Set shaders and constant buffers.
        ViewProjectionConstantBuffer viewProjection;
        XMStoreFloat4x4(&viewProjection.ViewProjection, XMMatrixTranspose(spaceToView * LoadXrMatrix(projectionMatrix)));
        m_deviceContext->UpdateSubresource(m_viewProjectionCBuffer.Get(), 0, nullptr, &viewProjection, 0, 0);

        ID3D11Buffer* const constantBuffers[] = {m_modelCBuffer.Get(), m_viewProjectionCBuffer.Get()};
        m_deviceContext->VSSetConstantBuffers(0, (UINT)ArraySize(constantBuffers), constantBuffers);
        m_deviceContext->VSSetShader(m_vertexShader.Get(), nullptr, 0);
        m_deviceContext->PSSetShader(m_pixelShader.Get(), nullptr, 0);

        // Set cube primitive data.
        const UINT strides[] = {sizeof(Geometry::Vertex)};
        const UINT offsets[] = {0};
        ID3D11Buffer* vertexBuffers[] = {m_cubeVertexBuffer.Get()};
        m_deviceContext->IASetVertexBuffers(0, (UINT)ArraySize(vertexBuffers), vertexBuffers, strides, offsets);
        m_deviceContext->IASetIndexBuffer(m_cubeIndexBuffer.Get(), DXGI_FORMAT_R16_UINT, 0);
        m_deviceContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        m_deviceContext->IASetInputLayout(m_inputLayout.Get());

        // Render each cube
        for (size_t i = 0; i < len; ++i) {
            auto cube = cubes[i];
            // Compute and update the model transform.
            ModelConstantBuffer model;
            XMStoreFloat4x4(&model.Model,
                            XMMatrixTranspose(XMMatrixScaling(cube.Scale.x, cube.Scale.y, cube.Scale.z) * LoadXrPose(cube.Pose)));
            m_deviceContext->UpdateSubresource(m_modelCBuffer.Get(), 0, nullptr, &model, 0, 0);

            // Draw the cube.
            m_deviceContext->DrawIndexed((UINT)ArraySize(Geometry::c_cubeIndices), 0, 0);
        }
    }

    uint32_t GetSupportedSwapchainSampleCount(const XrViewConfigurationView&) { return 1; }

    // void UpdateOptions(const Options* options) { m_clearColor = GetBackgroundClearColor(options); }

   private:
    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_deviceContext;
    XrGraphicsBindingD3D11KHR m_graphicsBinding{XR_TYPE_GRAPHICS_BINDING_D3D11_KHR};
    std::list<std::vector<XrSwapchainImageD3D11KHR>> m_swapchainImageBuffers;
    ComPtr<ID3D11VertexShader> m_vertexShader;
    ComPtr<ID3D11PixelShader> m_pixelShader;
    ComPtr<ID3D11InputLayout> m_inputLayout;
    ComPtr<ID3D11Buffer> m_modelCBuffer;
    ComPtr<ID3D11Buffer> m_viewProjectionCBuffer;
    ComPtr<ID3D11Buffer> m_cubeVertexBuffer;
    ComPtr<ID3D11Buffer> m_cubeIndexBuffer;

    // Map color buffer to associated depth buffer. This map is populated on demand.
    std::map<ID3D11Texture2D*, ComPtr<ID3D11DepthStencilView>> m_colorToDepthMap;
    // std::array<float, 4> m_clearColor;
};
}  // namespace

void* create() { return new D3D11GraphicsPlugin(); }
void destroy(void* p) { delete reinterpret_cast<D3D11GraphicsPlugin*>(p); }
int initializeDevice(void* p, void* instance, uint64_t systemId) {
    return reinterpret_cast<D3D11GraphicsPlugin*>(p)->InitializeDevice(reinterpret_cast<XrInstance>(instance), systemId);
}
int64_t selectColorSwapchainFormat(void* p, int64_t* formats, size_t len) {
    return reinterpret_cast<D3D11GraphicsPlugin*>(p)->SelectColorSwapchainFormat(formats, len);
}
const void* getGraphicsBinding(void* p) { return reinterpret_cast<D3D11GraphicsPlugin*>(p)->GetGraphicsBinding(); }
void allocateSwapchainImageStructs(void* p, void* pImage, size_t len) {
    reinterpret_cast<D3D11GraphicsPlugin*>(p)->AllocateSwapchainImageStructs(reinterpret_cast<XrSwapchainImageBaseHeader**>(pImage),
                                                                             len);
}
void renderView(void* p, const void* view, const void* image, int64_t format, const void* pCube, size_t len) {
    reinterpret_cast<D3D11GraphicsPlugin*>(p)->RenderView(reinterpret_cast<const XrCompositionLayerProjectionView*>(view),
                                                          reinterpret_cast<const XrSwapchainImageBaseHeader*>(image), format,
                                                          reinterpret_cast<const Cube*>(pCube), len);
}
