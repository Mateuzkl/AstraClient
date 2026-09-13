// Echo Warden: vivid red glyph with a dark red outline and soft outer glow.
uniform sampler2D u_Tex0;
uniform vec4 u_Color;

varying vec2 v_TexCoord;
varying vec2 v_TexelX;
varying vec2 v_TexelY;

float alphaAt(vec2 offset)
{
    return texture2D(u_Tex0, v_TexCoord + offset).a;
}

void main()
{
    vec4 base = texture2D(u_Tex0, v_TexCoord);
    float nearAlpha = max(max(alphaAt(v_TexelX), alphaAt(-v_TexelX)),
                          max(alphaAt(v_TexelY), alphaAt(-v_TexelY)));
    nearAlpha = max(nearAlpha, max(max(alphaAt(v_TexelX + v_TexelY), alphaAt(v_TexelX - v_TexelY)),
                                   max(alphaAt(-v_TexelX + v_TexelY), alphaAt(-v_TexelX - v_TexelY))));
    float farAlpha = max(max(alphaAt(v_TexelX * 2.0), alphaAt(-v_TexelX * 2.0)),
                         max(alphaAt(v_TexelY * 2.0), alphaAt(-v_TexelY * 2.0)));

    if (base.a > 0.05) {
        float glyphLight = dot(base.rgb, vec3(0.299, 0.587, 0.114));
        vec3 color = mix(vec3(0.48, 0.01, 0.01), vec3(1.0, 0.32, 0.18), smoothstep(0.08, 0.45, glyphLight));
        gl_FragColor = vec4(color, base.a * u_Color.a);
    } else if (nearAlpha > 0.05) {
        gl_FragColor = vec4(0.82, 0.01, 0.01, nearAlpha * u_Color.a);
    } else if (farAlpha > 0.05) {
        gl_FragColor = vec4(0.45, 0.0, 0.0, farAlpha * 0.55 * u_Color.a);
    } else {
        discard;
    }
}
