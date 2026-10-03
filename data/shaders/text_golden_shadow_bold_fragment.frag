// Fragment Shader (GLSL 1.20)
uniform sampler2D u_Tex0;      // Textura contendo as letras ou objetos
uniform vec4 u_Color;          // Cor personalizada para o conteúdo das letras
varying vec2 v_TexCoord;       // Coordenadas de textura

void main() {
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec2 texelSize = vec2(1.0 / 512.0, 1.0 / 512.0);  // Ajuste para a resolução da sua textura

    float alphaLeft = texture2D(u_Tex0, v_TexCoord + vec2(-texelSize.x * 2.0, 0.0)).a;
    float alphaRight = texture2D(u_Tex0, v_TexCoord + vec2(texelSize.x * 2.0, 0.0)).a;
    float alphaUp = texture2D(u_Tex0, v_TexCoord + vec2(0.0, texelSize.y * 2.0)).a;
    float alphaDown = texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texelSize.y * 2.0)).a;

    float alphaLeftFar = texture2D(u_Tex0, v_TexCoord + vec2(-texelSize.x * 4.0, 0.0)).a;
    float alphaRightFar = texture2D(u_Tex0, v_TexCoord + vec2(texelSize.x * 4.0, 0.0)).a;
    float alphaUpFar = texture2D(u_Tex0, v_TexCoord + vec2(0.0, texelSize.y * 4.0)).a;
    float alphaDownFar = texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texelSize.y * 4.0)).a;

    if (baseColor.a > 0.1) {
        // Aplica a cor da textura multiplicada por u_Color (somente no RGB)
        // Preserva o alpha da textura original (baseColor.a)
        gl_FragColor = vec4(baseColor.rgb * u_Color.rgb, baseColor.a);
    } else {
        bool isBorder = (alphaLeft > 0.1 || alphaRight > 0.1 || alphaUp > 0.1 || alphaDown > 0.1);
        bool isSmoothBorder = (alphaLeftFar > 0.1 || alphaRightFar > 0.1 || alphaUpFar > 0.1 || alphaDownFar > 0.1);

        if (isBorder) {
            gl_FragColor = vec4(0.933, 0.518, 0.075, 1.0);  // Cor #ee8413 (bordas próximas)
        } else if (isSmoothBorder) {
            gl_FragColor = vec4(0.933, 0.518, 0.075, 0.5);  // Cor #ee8413 com opacidade reduzida (bordas suaves)
        } else {
            discard;
        }
    }
}