#pragma once

// Include after the GL declarations. The painter caches these bindings; capture
// them before backend construction too, and restore even on initialization failure.
class RmlGlStateScope
{
public:
    RmlGlStateScope()
    {
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &m_fbo);
        glGetIntegerv(GL_CURRENT_PROGRAM, &m_program);
        glGetIntegerv(GL_ACTIVE_TEXTURE, &m_activeTexture);
        glActiveTexture(GL_TEXTURE0);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &m_texture);
        glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &m_arrayBuffer);
        glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &m_vao);
    }
    ~RmlGlStateScope()
    {
        glBindFramebuffer(GL_FRAMEBUFFER, m_fbo);
        glUseProgram(m_program);
        glBindVertexArray(m_vao);
        glBindBuffer(GL_ARRAY_BUFFER, m_arrayBuffer);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, m_texture);
        glActiveTexture(m_activeTexture);
    }
    RmlGlStateScope(const RmlGlStateScope&) = delete;
    RmlGlStateScope& operator=(const RmlGlStateScope&) = delete;

private:
    GLint m_fbo{}, m_program{}, m_activeTexture{}, m_texture{}, m_arrayBuffer{}, m_vao{};
};
