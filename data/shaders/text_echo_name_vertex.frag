// Text shader vertex stage. Derive one-pixel offsets through the active
// texture matrix so outlines remain correct when fonts live in the atlas.
attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;

uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;

varying vec2 v_TexCoord;
varying vec2 v_TexelX;
varying vec2 v_TexelY;

void main()
{
    vec3 adjustedVertex = vec3(a_Vertex + u_Offset, 1.0);
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * adjustedVertex).xy, 0.0, 1.0);

    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexelX = (u_TextureMatrix * vec3(1.0, 0.0, 0.0)).xy;
    v_TexelY = (u_TextureMatrix * vec3(0.0, 1.0, 0.0)).xy;
}
