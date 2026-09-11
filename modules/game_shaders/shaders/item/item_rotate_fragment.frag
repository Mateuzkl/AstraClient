varying vec2 v_TexCoord;
uniform vec4 u_Color;
uniform sampler2D u_Tex0;

void main()
{
    // Define the rotation angle in degrees (e.g., 90.0 for 90°)
    float rotationAngle = 90.0;
    
    // Convert the angle from degrees to radians
    float angle = radians(rotationAngle);
    
    // Calculate sine and cosine of the angle
    float cosA = cos(angle);
    float sinA = sin(angle);
    
    // Define the texture center (0.5, 0.5)
    vec2 center = vec2(0.5, 0.5);
    
    // Translate texture coordinates to the origin
    vec2 texCoord = v_TexCoord - center;
    
    // Apply rotation
    vec2 rotatedTexCoord = vec2(
        texCoord.x * cosA - texCoord.y * sinA,
        texCoord.x * sinA + texCoord.y * cosA
    );
    
    // Translate back to the original coordinate system
    rotatedTexCoord += center;
    
    // Sample the original texture color with rotated coordinates
    vec4 texColor = texture2D(u_Tex0, rotatedTexCoord);
    
    // Multiply by the uniform color
    gl_FragColor = texColor * u_Color;
    
    // Discard fragments with very low alpha
    if (gl_FragColor.a < 0.01)
        discard;
}