#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uExposure;
uniform sampler2D uDye;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 dye = max(texture(uDye, uv).rgb, vec3(0.0));
  // A smooth exposure curve, without artificial normals, specular edges or bloom.
  vec3 color = pow(vec3(1.0)-exp(-dye*uExposure),vec3(0.75));
  fragColor = vec4(color,1.0);
}
