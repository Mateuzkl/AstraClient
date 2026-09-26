varying vec2 v_TexCoord;       // Coordenadas de textura recebidas do vertex shader
uniform vec4 u_Color;          // Cor uniforme (opcional, para tingimento)
uniform sampler2D u_Tex0;      // Textura do ícone

void main()
{
    float grayFactor = 0.8;
    vec2 texCoord;
    texCoord = vec2(1.0 - v_TexCoord.x, v_TexCoord.y);
    // Amostrar a cor da textura
    vec4 texColor = texture2D(u_Tex0, texCoord);
    
    // Converter para escala de cinza usando a fórmula de luminosidade
    float gray = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 grayColor = vec3(gray, gray, gray);
    
    // Misturar a cor original com a escala de cinza
    vec3 finalColor = mix(texColor.rgb, grayColor, grayFactor);
    texColor = vec4(finalColor, texColor.a);
    
    // Aplicar a cor uniforme (se necessário) e definir a cor final
    gl_FragColor = texColor * u_Color;
    
    // Descartar fragmentos com alpha muito baixo (opcional)
    if (gl_FragColor.a < 0.01)
        discard;
}