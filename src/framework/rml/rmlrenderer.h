/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#pragma once

#include <framework/graphics/texture.h>

#include <RmlUi/Core/RenderInterface.h>
#include <RmlUi/Core/Variant.h>

#include <mutex>
#include <atomic>
#include <unordered_map>

class RenderInterface_GL3;

// Texture that receives the composited RmlUi frame of one UIRmlWidget.
// It is created on the UI thread (so the draw pool can reference it while recording) and
// gets its OpenGL storage on the graphics thread, right before the first frame is replayed.
class RmlTargetTexture final : public Texture
{
public:
    explicit RmlTargetTexture(const Size& size);
    void realize();
};

using RmlTargetTexturePtr = std::shared_ptr<RmlTargetTexture>;

// Rml::RenderInterface used by one Rml::Context.
//
// The UI is updated and rendered by OTClient's UI thread, but OpenGL lives on the graphics
// thread. Every call made by RmlUi is therefore recorded with proxy handles (returned
// immediately to RmlUi) and replayed later on the graphics thread through the official
// RenderInterface_GL3 backend, which maps each proxy handle to the real GL object.
class RmlRenderer final : public Rml::RenderInterface
{
public:
    RmlRenderer();
    ~RmlRenderer() override;

    // UI thread
    bool beginFrame(const RmlTargetTexturePtr& target);
    bool hasPendingFrame() const { return m_pendingFrame.load(); }
    void endFrame();
    void retire(); // stop recording; the GL objects are freed on the graphics thread

    // graphics thread
    void replay();
    void releaseGl();
    bool hasAdvancedEffects() const { return m_advancedEffects; }

    Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex> vertices, Rml::Span<const int> indices) override;
    void RenderGeometry(Rml::CompiledGeometryHandle geometry, Rml::Vector2f translation, Rml::TextureHandle texture) override;
    void ReleaseGeometry(Rml::CompiledGeometryHandle geometry) override;

    Rml::TextureHandle LoadTexture(Rml::Vector2i& textureDimensions, const Rml::String& source) override;
    Rml::TextureHandle GenerateTexture(Rml::Span<const Rml::byte> source, Rml::Vector2i sourceDimensions) override;
    void ReleaseTexture(Rml::TextureHandle texture) override;

    void EnableScissorRegion(bool enable) override;
    void SetScissorRegion(Rml::Rectanglei region) override;

    void EnableClipMask(bool enable) override;
    void RenderToClipMask(Rml::ClipMaskOperation operation, Rml::CompiledGeometryHandle geometry, Rml::Vector2f translation) override;

    void SetTransform(const Rml::Matrix4f* transform) override;

    Rml::LayerHandle PushLayer() override;
    void CompositeLayers(Rml::LayerHandle source, Rml::LayerHandle destination, Rml::BlendMode blendMode,
                         Rml::Span<const Rml::CompiledFilterHandle> filters) override;
    void PopLayer() override;

    Rml::TextureHandle SaveLayerAsTexture() override;
    Rml::CompiledFilterHandle SaveLayerAsMaskImage() override;

    Rml::CompiledFilterHandle CompileFilter(const Rml::String& name, const Rml::Dictionary& parameters) override;
    void ReleaseFilter(Rml::CompiledFilterHandle filter) override;

    Rml::CompiledShaderHandle CompileShader(const Rml::String& name, const Rml::Dictionary& parameters) override;
    void RenderShader(Rml::CompiledShaderHandle shader, Rml::CompiledGeometryHandle geometry, Rml::Vector2f translation,
                      Rml::TextureHandle texture) override;
    void ReleaseShader(Rml::CompiledShaderHandle shader) override;

private:
    enum class Op : uint8_t
    {
        BeginFrame, EndFrame,
        CompileGeometry, RenderGeometry, ReleaseGeometry,
        GenerateTexture, ReleaseTexture,
        EnableScissor, SetScissor,
        EnableClipMask, RenderToClipMask,
        SetTransform, ResetTransform,
        PushLayer, CompositeLayers, PopLayer,
        SaveLayerAsTexture, SaveLayerAsMaskImage,
        CompileFilter, ReleaseFilter,
        CompileShader, RenderShader, ReleaseShader
    };

    struct Command
    {
        Op op;
        uintptr_t a{ 0 };
        uintptr_t b{ 0 };
        uintptr_t c{ 0 };
        bool flag{ false };
        int mode{ 0 };
        Rml::Vector2f translation;
        Rml::Vector2i dimensions;
        Rml::Rectanglei rect;
        Rml::Matrix4f matrix;
        std::vector<Rml::Vertex> vertices;
        std::vector<int> indices;
        std::vector<Rml::byte> bytes;
        std::vector<uintptr_t> handles;
        Rml::String name;
        Rml::Dictionary parameters;
        RmlTargetTexturePtr target;
    };

    Command& record(Op op);
    uintptr_t newHandle() { return ++m_lastHandle; }
    uintptr_t resolve(uintptr_t proxy) const;
    void execute(Command& cmd);

    uintptr_t m_lastHandle{ 0 };
    bool m_inFrame{ false };
    bool m_retired{ false };
    std::vector<Command> m_frame;
    std::vector<Command> m_resources; // UI-thread-only commands outside a frame
    std::atomic_bool m_pendingFrame{false}; // at most one unreplayed frame

    std::mutex m_queueMutex;
    std::vector<Command> m_queue;

    std::unique_ptr<RenderInterface_GL3> m_gl;
    bool m_glFailed{ false };
    bool m_advancedEffects{ false };
    std::unordered_map<uintptr_t, uintptr_t> m_handles;
    std::vector<uintptr_t> m_frameLayers; // layer handles are only valid inside one frame
    uint32_t m_fbo{ 0 };
    RmlTargetTexture* m_attachedTarget{ nullptr };
    RmlTargetTexturePtr m_target;
};

using RmlRendererPtr = std::shared_ptr<RmlRenderer>;
