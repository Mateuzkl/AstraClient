// Exercise the production binding guard without a GPU/driver dependency.
#include <array>
#include <algorithm>
#include <cstdlib>

using GLint = int;
using GLfloat = float;
enum { GL_DRAW_FRAMEBUFFER_BINDING, GL_READ_FRAMEBUFFER_BINDING, GL_RENDERBUFFER_BINDING,
    GL_CURRENT_PROGRAM, GL_ACTIVE_TEXTURE, GL_TEXTURE_BINDING_2D, GL_ARRAY_BUFFER_BINDING,
    GL_ELEMENT_ARRAY_BUFFER_BINDING, GL_VERTEX_ARRAY_BINDING, GL_FRAMEBUFFER, GL_READ_FRAMEBUFFER,
    GL_DRAW_FRAMEBUFFER, GL_RENDERBUFFER, GL_ARRAY_BUFFER, GL_ELEMENT_ARRAY_BUFFER,
    GL_TEXTURE_2D, GL_BLEND_COLOR, GL_FRAMEBUFFER_SRGB,
    GL_FRAMEBUFFER_BINDING = GL_DRAW_FRAMEBUFFER_BINDING, GL_TEXTURE0 = 100 };
struct State {
    int drawFbo = 3, readFbo = 5, renderbuffer = 6, program = 7, activeTexture = GL_TEXTURE0 + 2, buffer = 11, vao = 13;
    std::array<int, 3> textures{17, 19, 21};
    std::array<int, 64> elementBuffers{}; // Element-array binding belongs to the VAO.
    std::array<float, 4> blendColor{.1f, .2f, .3f, .4f};
    bool srgb = true;
    bool operator==(const State&) const = default;
} state;
void glGetIntegerv(int name, int* result)
{
    switch (name) {
        case GL_DRAW_FRAMEBUFFER_BINDING: *result = state.drawFbo; break;
        case GL_READ_FRAMEBUFFER_BINDING: *result = state.readFbo; break;
        case GL_RENDERBUFFER_BINDING: *result = state.renderbuffer; break;
        case GL_CURRENT_PROGRAM: *result = state.program; break;
        case GL_ACTIVE_TEXTURE: *result = state.activeTexture; break;
        case GL_TEXTURE_BINDING_2D: *result = state.textures.at(state.activeTexture - GL_TEXTURE0); break;
        case GL_ARRAY_BUFFER_BINDING: *result = state.buffer; break;
        case GL_ELEMENT_ARRAY_BUFFER_BINDING: *result = state.elementBuffers.at(state.vao); break;
        case GL_VERTEX_ARRAY_BINDING: *result = state.vao; break;
        default: std::abort();
    }
}
void glGetFloatv(int name, float* result) { if (name != GL_BLEND_COLOR) std::abort(); std::ranges::copy(state.blendColor, result); }
bool glIsEnabled(int name) { if (name != GL_FRAMEBUFFER_SRGB) std::abort(); return state.srgb; }
void glEnable(int) { state.srgb = true; }
void glDisable(int) { state.srgb = false; }
void glActiveTexture(int unit) { state.activeTexture = unit; }
void glBindFramebuffer(int target, int id) {
    if (target != GL_READ_FRAMEBUFFER) state.drawFbo = id;
    if (target != GL_DRAW_FRAMEBUFFER) state.readFbo = id;
}
void glBindRenderbuffer(int, int id) { state.renderbuffer = id; }
void glUseProgram(int id) { state.program = id; }
void glBindVertexArray(int id) { state.vao = id; }
void glBindBuffer(int target, int id) {
    if (target == GL_ELEMENT_ARRAY_BUFFER) state.elementBuffers.at(state.vao) = id;
    else state.buffer = id;
}
void glBindTexture(int, int id) { state.textures.at(state.activeTexture - GL_TEXTURE0) = id; }
void glBlendColor(float r, float g, float b, float a) { state.blendColor = {r, g, b, a}; }

#include <framework/rml/rmlglstate.h>

void replay(bool initialized)
{
    const RmlGlStateScope restore;
    // RenderInterface_GL3's constructor creates shaders/geometry and unbinds them.
    glUseProgram(0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    if (!initialized) return;
    glUseProgram(23);
    glBindFramebuffer(GL_FRAMEBUFFER, 29);
    glBindRenderbuffer(GL_RENDERBUFFER, 30);
    glBindTexture(GL_TEXTURE_2D, 31);
    glActiveTexture(GL_TEXTURE0 + 1);
    glBindTexture(GL_TEXTURE_2D, 32);
    glBlendColor(1, 1, 1, 1);
    glDisable(GL_FRAMEBUFFER_SRGB);
    glBindBuffer(GL_ARRAY_BUFFER, 41);
}
int main()
{
    state.elementBuffers[state.vao] = 15;
    for (bool enabled : {false, true}) {
        state.srgb = enabled;
        const State before = state;
        for (bool initialized : {false, true, true}) {
            replay(initialized);
            if (state != before) return EXIT_FAILURE;
        }
    }
    return EXIT_SUCCESS;
}
