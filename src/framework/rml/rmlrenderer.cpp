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

#include "rmlrenderer.h"
#include "rmlmanager.h"
#include "RmlUi_Renderer_GL3.h"

#include <framework/graphics/glutil.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/image.h>
#include "rmlglstate.h"

RmlTargetTexture::RmlTargetTexture(const Size& size) : Texture(size, false, false, true)
{
    setCanCache(false);
}

void RmlTargetTexture::realize()
{
    update(); // GL allocation only on the graphics thread, using Astra's texture lifecycle
}

RmlRenderer::RmlRenderer() = default;
RmlRenderer::~RmlRenderer() = default;

RmlRenderer::Command& RmlRenderer::record(const Op op)
{
    if (m_inFrame)
        return m_frame.emplace_back(Command{ op });

    // Never expose a reference to a vector concurrently swapped by replay().
    return m_resources.emplace_back(Command{ op });
}

bool RmlRenderer::beginFrame(const RmlTargetTexturePtr& target)
{
    if (m_retired || hasPendingFrame())
        return false;
    m_frame.clear();
    m_inFrame = !m_retired;
    if (m_inFrame)
        record(Op::BeginFrame).target = target;
    return m_inFrame;
}

void RmlRenderer::endFrame()
{
    if (!m_inFrame)
        return;

    record(Op::EndFrame);
    m_inFrame = false;

    std::scoped_lock lock(m_queueMutex);
    std::move(m_resources.begin(), m_resources.end(), std::back_inserter(m_queue));
    m_resources.clear();
    std::move(m_frame.begin(), m_frame.end(), std::back_inserter(m_queue));
    m_frame.clear();
    m_pendingFrame = true;
}

void RmlRenderer::retire()
{
    endFrame();
    m_retired = true;
    std::scoped_lock lock(m_queueMutex);
    std::move(m_resources.begin(), m_resources.end(), std::back_inserter(m_queue));
    m_resources.clear();
}

Rml::CompiledGeometryHandle RmlRenderer::CompileGeometry(const Rml::Span<const Rml::Vertex> vertices, const Rml::Span<const int> indices)
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    auto& cmd = record(Op::CompileGeometry);
    cmd.a = handle;
    cmd.vertices.assign(vertices.begin(), vertices.end());
    cmd.indices.assign(indices.begin(), indices.end());
    return handle;
}

void RmlRenderer::RenderGeometry(const Rml::CompiledGeometryHandle geometry, const Rml::Vector2f translation, const Rml::TextureHandle texture)
{
    if (m_retired) return;
    auto& cmd = record(Op::RenderGeometry);
    cmd.a = geometry;
    cmd.c = texture;
    cmd.translation = translation;
}

void RmlRenderer::ReleaseGeometry(const Rml::CompiledGeometryHandle geometry)
{
    if (!geometry) return;
    record(Op::ReleaseGeometry).a = geometry;
}

Rml::TextureHandle RmlRenderer::LoadTexture(Rml::Vector2i& textureDimensions, const Rml::String& source)
{
    if (m_retired) return 0;

    const auto image = g_rml.loadImage(source);
    if (!image || image->getWidth() <= 0 || image->getHeight() <= 0 ||
        image->getWidth() > 4096 || image->getHeight() > 4096)
        return 0;

    const auto& size = image->getSize();
    const int bpp = image->getBpp();
    const auto& pixels = image->getPixels();
    const size_t count = static_cast<size_t>(size.width()) * size.height();
    if (bpp < 1 || bpp > 4 || pixels.size() < count * bpp)
        return 0;

    std::vector<Rml::byte> rgba(count * 4);
    for (size_t i = 0; i < count; ++i) {
        const uint8_t r = pixels[i * bpp + 0];
        const uint8_t g = bpp >= 3 ? pixels[i * bpp + 1] : r;
        const uint8_t b = bpp >= 3 ? pixels[i * bpp + 2] : r;
        const uint8_t a = bpp == 4 ? pixels[i * bpp + 3] : bpp == 2 ? pixels[i * bpp + 1] : 255;
        // RmlUi 6 expects premultiplied alpha
        rgba[i * 4 + 0] = static_cast<Rml::byte>(r * a / 255);
        rgba[i * 4 + 1] = static_cast<Rml::byte>(g * a / 255);
        rgba[i * 4 + 2] = static_cast<Rml::byte>(b * a / 255);
        rgba[i * 4 + 3] = a;
    }

    textureDimensions = { size.width(), size.height() };

    const auto handle = newHandle();
    auto& cmd = record(Op::GenerateTexture);
    cmd.a = handle;
    cmd.dimensions = textureDimensions;
    cmd.bytes = std::move(rgba);
    return handle;
}

Rml::TextureHandle RmlRenderer::GenerateTexture(const Rml::Span<const Rml::byte> source, const Rml::Vector2i sourceDimensions)
{
    if (m_retired) return 0;
    if (sourceDimensions.x <= 0 || sourceDimensions.y <= 0 ||
        sourceDimensions.x > 4096 || sourceDimensions.y > 4096 ||
        source.size() != static_cast<size_t>(sourceDimensions.x) * sourceDimensions.y * 4)
        return 0;
    const auto handle = newHandle();
    auto& cmd = record(Op::GenerateTexture);
    cmd.a = handle;
    cmd.dimensions = sourceDimensions;
    cmd.bytes.assign(source.begin(), source.end());
    return handle;
}

void RmlRenderer::ReleaseTexture(const Rml::TextureHandle texture)
{
    if (!texture) return;
    record(Op::ReleaseTexture).a = texture;
}

void RmlRenderer::EnableScissorRegion(const bool enable)
{
    if (m_retired) return;
    record(Op::EnableScissor).flag = enable;
}

void RmlRenderer::SetScissorRegion(const Rml::Rectanglei region)
{
    if (m_retired) return;
    record(Op::SetScissor).rect = region;
}

void RmlRenderer::EnableClipMask(const bool enable)
{
    if (m_retired) return;
    record(Op::EnableClipMask).flag = enable;
}

void RmlRenderer::RenderToClipMask(const Rml::ClipMaskOperation operation, const Rml::CompiledGeometryHandle geometry, const Rml::Vector2f translation)
{
    if (m_retired) return;
    auto& cmd = record(Op::RenderToClipMask);
    cmd.mode = static_cast<int>(operation);
    cmd.a = geometry;
    cmd.translation = translation;
}

void RmlRenderer::SetTransform(const Rml::Matrix4f* transform)
{
    if (m_retired) return;
    if (transform)
        record(Op::SetTransform).matrix = *transform;
    else
        record(Op::ResetTransform);
}

Rml::LayerHandle RmlRenderer::PushLayer()
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    record(Op::PushLayer).a = handle;
    return handle;
}

void RmlRenderer::CompositeLayers(const Rml::LayerHandle source, const Rml::LayerHandle destination, const Rml::BlendMode blendMode,
                                  const Rml::Span<const Rml::CompiledFilterHandle> filters)
{
    if (m_retired) return;
    auto& cmd = record(Op::CompositeLayers);
    cmd.a = source;
    cmd.b = destination;
    cmd.mode = static_cast<int>(blendMode);
    cmd.handles.assign(filters.begin(), filters.end());
}

void RmlRenderer::PopLayer()
{
    if (m_retired) return;
    record(Op::PopLayer);
}

Rml::TextureHandle RmlRenderer::SaveLayerAsTexture()
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    record(Op::SaveLayerAsTexture).a = handle;
    return handle;
}

Rml::CompiledFilterHandle RmlRenderer::SaveLayerAsMaskImage()
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    record(Op::SaveLayerAsMaskImage).a = handle;
    return handle;
}

Rml::CompiledFilterHandle RmlRenderer::CompileFilter(const Rml::String& name, const Rml::Dictionary& parameters)
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    auto& cmd = record(Op::CompileFilter);
    cmd.a = handle;
    cmd.name = name;
    cmd.parameters = parameters;
    return handle;
}

void RmlRenderer::ReleaseFilter(const Rml::CompiledFilterHandle filter)
{
    if (!filter) return;
    record(Op::ReleaseFilter).a = filter;
}

Rml::CompiledShaderHandle RmlRenderer::CompileShader(const Rml::String& name, const Rml::Dictionary& parameters)
{
    if (m_retired) return 0;
    const auto handle = newHandle();
    auto& cmd = record(Op::CompileShader);
    cmd.a = handle;
    cmd.name = name;
    cmd.parameters = parameters;
    return handle;
}

void RmlRenderer::RenderShader(const Rml::CompiledShaderHandle shader, const Rml::CompiledGeometryHandle geometry, const Rml::Vector2f translation,
                               const Rml::TextureHandle texture)
{
    if (m_retired) return;
    auto& cmd = record(Op::RenderShader);
    cmd.a = shader;
    cmd.b = geometry;
    cmd.c = texture;
    cmd.translation = translation;
}

void RmlRenderer::ReleaseShader(const Rml::CompiledShaderHandle shader)
{
    if (!shader) return;
    record(Op::ReleaseShader).a = shader;
}

uintptr_t RmlRenderer::resolve(const uintptr_t proxy) const
{
    if (proxy == 0)
        return 0;
    const auto it = m_handles.find(proxy);
    return it != m_handles.end() ? it->second : 0;
}

void RmlRenderer::replay()
{
    std::vector<Command> commands;
    {
        std::scoped_lock lock(m_queueMutex);
        commands.swap(m_queue);
    }

    if (commands.empty() || m_glFailed)
    {
        m_pendingFrame = false;
        return;
    }

    const RmlGlStateScope restorePainterBindings;
    if (!m_gl) {
        m_gl = std::make_unique<RenderInterface_GL3>();
        if (!*m_gl) {
            g_logger.error("[rmlui] could not create the GL / ANGLE renderer; RmlUi widgets will stay empty");
            m_gl.reset();
            m_glFailed = true;
            g_rml.onBackendResult(false);
            m_pendingFrame = false;
            return;
        }
        m_advancedEffects = true;
        g_rml.onBackendResult(true);
    }

    for (auto& cmd : commands)
        execute(cmd);

    m_pendingFrame = false;
}

void RmlRenderer::execute(Command& cmd)
{
    auto& gl = *m_gl;

    switch (cmd.op) {
        case Op::BeginFrame: {
            auto* target = cmd.target.get();
            target->realize();

            if (!m_fbo)
                glGenFramebuffers(1, &m_fbo);

            if (m_attachedTarget != target) {
                glBindFramebuffer(GL_FRAMEBUFFER, m_fbo);
                glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, target->getId(), 0);
                if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
                    g_logger.warning("[rmlui] widget framebuffer is incomplete");
                m_attachedTarget = target;
                m_target = cmd.target;
            }

            gl.SetViewport(target->getWidth(), target->getHeight());
            gl.SetTargetFramebuffer(m_fbo);
            gl.BeginFrame();

            // BeginFrame() bound its first layer; clear our target (blending happens onto it at EndFrame).
            GLint layerFbo = 0;
            glGetIntegerv(GL_FRAMEBUFFER_BINDING, &layerFbo);
            glBindFramebuffer(GL_FRAMEBUFFER, m_fbo);
            glClear(GL_COLOR_BUFFER_BIT);
            glBindFramebuffer(GL_FRAMEBUFFER, layerFbo);
            break;
        }
        case Op::EndFrame:
            gl.EndFrame();
            for (const auto layer : m_frameLayers)
                m_handles.erase(layer);
            m_frameLayers.clear();
            break;
        case Op::CompileGeometry:
            m_handles[cmd.a] = gl.CompileGeometry(cmd.vertices, cmd.indices);
            break;
        case Op::RenderGeometry:
            if (const auto geometry = resolve(cmd.a))
                gl.RenderGeometry(geometry, cmd.translation, resolve(cmd.c));
            break;
        case Op::ReleaseGeometry:
            if (const auto geometry = resolve(cmd.a)) {
                gl.ReleaseGeometry(geometry);
                m_handles.erase(cmd.a);
            }
            break;
        case Op::GenerateTexture:
            m_handles[cmd.a] = gl.GenerateTexture(cmd.bytes, cmd.dimensions);
            break;
        case Op::ReleaseTexture:
            if (const auto texture = resolve(cmd.a)) {
                gl.ReleaseTexture(texture);
                m_handles.erase(cmd.a);
            }
            break;
        case Op::EnableScissor:
            gl.EnableScissorRegion(cmd.flag);
            break;
        case Op::SetScissor:
            gl.SetScissorRegion(cmd.rect);
            break;
        case Op::EnableClipMask:
            gl.EnableClipMask(cmd.flag);
            break;
        case Op::RenderToClipMask:
            gl.RenderToClipMask(static_cast<Rml::ClipMaskOperation>(cmd.mode), resolve(cmd.a), cmd.translation);
            break;
        case Op::SetTransform:
            gl.SetTransform(&cmd.matrix);
            break;
        case Op::ResetTransform:
            gl.SetTransform(nullptr);
            break;
        case Op::PushLayer:
            m_handles[cmd.a] = gl.PushLayer();
            m_frameLayers.emplace_back(cmd.a);
            break;
        case Op::CompositeLayers: {
            std::vector<Rml::CompiledFilterHandle> filters;
            filters.reserve(cmd.handles.size());
            for (const auto proxy : cmd.handles)
                filters.emplace_back(resolve(proxy));
            gl.CompositeLayers(resolve(cmd.a), resolve(cmd.b), static_cast<Rml::BlendMode>(cmd.mode), filters);
            break;
        }
        case Op::PopLayer:
            gl.PopLayer();
            break;
        case Op::SaveLayerAsTexture:
            m_handles[cmd.a] = gl.SaveLayerAsTexture();
            break;
        case Op::SaveLayerAsMaskImage:
            m_handles[cmd.a] = gl.SaveLayerAsMaskImage();
            break;
        case Op::CompileFilter:
            m_handles[cmd.a] = gl.CompileFilter(cmd.name, cmd.parameters);
            break;
        case Op::ReleaseFilter:
            if (const auto filter = resolve(cmd.a)) {
                gl.ReleaseFilter(filter);
                m_handles.erase(cmd.a);
            }
            break;
        case Op::CompileShader:
            m_handles[cmd.a] = gl.CompileShader(cmd.name, cmd.parameters);
            break;
        case Op::RenderShader:
            gl.RenderShader(resolve(cmd.a), resolve(cmd.b), cmd.translation, resolve(cmd.c));
            break;
        case Op::ReleaseShader:
            if (const auto shader = resolve(cmd.a)) {
                gl.ReleaseShader(shader);
                m_handles.erase(cmd.a);
            }
            break;
    }
}

void RmlRenderer::releaseGl()
{
    // graphics thread, after retire(): apply the final releases recorded by RmlUi, then free GL.
    replay();
    m_glFailed = true;

    if (!g_graphics.ok())
        return;

    m_handles.clear();
    m_gl.reset();
    if (m_fbo) {
        glDeleteFramebuffers(1, &m_fbo);
        m_fbo = 0;
    }
    m_attachedTarget = nullptr;
    m_target = nullptr;
}
