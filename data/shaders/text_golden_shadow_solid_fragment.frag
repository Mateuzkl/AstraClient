// Fragment Shader (GLSL 1.20)
uniform sampler2D u_Tex0;      // Textura contendo as letras ou objetos
uniform vec4 u_Color;          // Cor personalizada para o conteúdo das letras
varying vec2 v_TexCoord;       // Coordenadas de textura

void main() {
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec2 texelSize = vec2(1.0 / 512.0, 1.0 / 512.0);  // Ajuste para a resolução da sua textura

    // Verifica os pixels vizinhos imediatos (1 pixel de distância)
    float alphaLeft = texture2D(u_Tex0, v_TexCoord + vec2(-texelSize.x, 0.0)).a;
    float alphaRight = texture2D(u_Tex0, v_TexCoord + vec2(texelSize.x, 0.0)).a;
    float alphaUp = texture2D(u_Tex0, v_TexCoord + vec2(0.0, texelSize.y)).a;
    float alphaDown = texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texelSize.y)).a;

    // Se o pixel faz parte do texto, usa a cor do texto
    if (baseColor.a > 0.1) {
        gl_FragColor = vec4(baseColor.rgb * u_Color.rgb, baseColor.a);
    } else {
        // Verifica se o pixel é uma borda (vizinho imediato tem alpha > 0.1)
        bool isBorder = (alphaLeft > 0.1 || alphaRight > 0.1 || alphaUp > 0.1 || alphaDown > 0.1);

        // Se for uma borda, aplica uma cor de sombra com opacidade total
        if (isBorder) {
            gl_FragColor = vec4(0.933, 0.518, 0.075, 1.0);  // Cor #ee8413 para bordas
        } else {
            discard;  // Descartar se não for parte do texto ou borda
        }
    }
}