// Exercise the production binding guard without a GPU/driver dependency.
#include <array>
#include <cstdlib>

using GLint = int;
enum { GL_FRAMEBUFFER_BINDING, GL_CURRENT_PROGRAM, GL_ACTIVE_TEXTURE, GL_TEXTURE_BINDING_2D,
    GL_ARRAY_BUFFER_BINDING, GL_VERTEX_ARRAY_BINDING, GL_FRAMEBUFFER, GL_TEXTURE0 = 100,
    GL_ARRAY_BUFFER, GL_TEXTURE_2D };
struct State {
    int fbo = 3, program = 7, activeTexture = GL_TEXTURE0 + 1, buffer = 11, vao = 13;
    std::array<int, 2> textures{17, 19};
    bool operator==(const State&) const = default;
} state;
void glGetIntegerv(int name, int* result)
{
    switch (name) {
        case GL_FRAMEBUFFER_BINDING: *result = state.fbo; break;
        case GL_CURRENT_PROGRAM: *result = state.program; break;
        case GL_ACTIVE_TEXTURE: *result = state.activeTexture; break;
        case GL_TEXTURE_BINDING_2D: *result = state.textures.at(state.activeTexture - GL_TEXTURE0); break;
        case GL_ARRAY_BUFFER_BINDING: *result = state.buffer; break;
        case GL_VERTEX_ARRAY_BINDING: *result = state.vao; break;
        default: std::abort();
    }
}
void glActiveTexture(int unit) { state.activeTexture = unit; }
void glBindFramebuffer(int, int id) { state.fbo = id; }
void glUseProgram(int id) { state.program = id; }
void glBindVertexArray(int id) { state.vao = id; }
void glBindBuffer(int, int id) { state.buffer = id; }
void glBindTexture(int, int id) { state.textures.at(state.activeTexture - GL_TEXTURE0) = id; }

#include <framework/rml/rmlglstate.h>

void replay(bool initialized)
{
    const RmlGlStateScope restore;
    // RenderInterface_GL3's constructor creates shaders/geometry and unbinds them.
    glUseProgram(0);
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    if (!initialized) return;
    glUseProgram(23);
    glBindFramebuffer(GL_FRAMEBUFFER, 29);
    glBindTexture(GL_TEXTURE_2D, 31);
    glBindVertexArray(37);
    glBindBuffer(GL_ARRAY_BUFFER, 41);
}
int main()
{
    const State before = state;
    replay(false);
    if (state != before) return EXIT_FAILURE;
    replay(true);
    if (state != before) return EXIT_FAILURE;
    replay(true);
    return state == before ? EXIT_SUCCESS : EXIT_FAILURE;
}
