#pragma once

// Include after the GL declarations. The painter caches these bindings; capture
// them before backend construction too, and restore even on initialization failure.
class RmlGlStateScope
{
public:
    RmlGlStateScope()
    {
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &m_drawFbo);
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &m_readFbo);
        glGetIntegerv(GL_RENDERBUFFER_BINDING, &m_renderbuffer);
        glGetIntegerv(GL_CURRENT_PROGRAM, &m_program);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &m_activeTexture);
        // Mask filters use unit 1, even if Astra entered on another unit.
        for (int unit = 0; unit < 2; ++unit) {
            glActiveTexture(GL_TEXTURE0 + unit);
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &m_textures[unit]);
        }
        glActiveTexture(GL_TEXTURE0);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &m_arrayBuffer);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &m_vao);
        glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &m_elementBuffer);
        glGetFloatv(GL_BLEND_COLOR, m_blendColor);
#if !defined(RMLUI_PLATFORM_EMSCRIPTEN) && !defined(__ANDROID__) && !defined(OPENGL_ES)
        m_srgb = glIsEnabled(GL_FRAMEBUFFER_SRGB);
#endif
    }
    ~RmlGlStateScope()
    {
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_drawFbo);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, m_readFbo);
        glBindRenderbuffer(GL_RENDERBUFFER, m_renderbuffer);
        glUseProgram(m_program);
        glBindVertexArray(m_vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_elementBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, m_arrayBuffer);
        for (int unit = 0; unit < 2; ++unit) {
            glActiveTexture(GL_TEXTURE0 + unit);
            glBindTexture(GL_TEXTURE_2D, m_textures[unit]);
        }
        glActiveTexture(m_activeTexture);
        glBlendColor(m_blendColor[0], m_blendColor[1], m_blendColor[2], m_blendColor[3]);
#if !defined(RMLUI_PLATFORM_EMSCRIPTEN) && !defined(__ANDROID__) && !defined(OPENGL_ES)
        if (m_srgb) glEnable(GL_FRAMEBUFFER_SRGB);
        else glDisable(GL_FRAMEBUFFER_SRGB);
#endif
    }
    RmlGlStateScope(const RmlGlStateScope&) = delete;
    RmlGlStateScope& operator=(const RmlGlStateScope&) = delete;

private:
    GLint m_drawFbo{}, m_readFbo{}, m_renderbuffer{}, m_program{}, m_activeTexture{};
    GLint m_textures[2]{}, m_arrayBuffer{}, m_vao{}, m_elementBuffer{};
    GLfloat m_blendColor[4]{};
#if !defined(RMLUI_PLATFORM_EMSCRIPTEN) && !defined(__ANDROID__) && !defined(OPENGL_ES)
    bool m_srgb{};
#endif
};
