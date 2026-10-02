#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uDt;
uniform float uDecay;
uniform float uTime;
uniform float uEnergy;
uniform float uBass;
uniform float uTreble;
uniform float uGain;
uniform float uOnset;
uniform vec4 uTouch0;
uniform vec4 uTouch1;
uniform vec4 uTouch2;
uniform vec4 uTouch3;
uniform sampler2D uDye;
uniform sampler2D uVelocity;
out vec4 fragColor;
vec3 touchDye(vec2 uv, vec4 touch) {
  vec2 d = uv - touch.xy;
  d.x *= uSize.x / uSize.y;
  return vec3(0.15, 0.65, 1.0) * exp(-dot(d,d) / 0.00016) * touch.z * touch.w;
}
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 velocity = (texture(uVelocity, uv).rg - 0.5) * 4.0;
  vec2 back = clamp(uv - velocity * uDt, vec2(0.0), vec2(1.0));
  vec3 dye = texture(uDye, back).rgb * uDecay;
  for (int k = 0; k < 3; k++) {
    float a = uTime + float(k) * 2.094395;
    vec2 center = vec2(0.28 + float(k)*0.22 + 0.045*sin(a), 0.82 + 0.018*cos(a*0.7));
    vec2 d = uv - center;
    d.x *= uSize.x / uSize.y;
    float radius = 0.015 + uBass * 0.008 + uTreble * 0.001;
    float source = exp(-dot(d,d)/(radius*radius));
    vec3 color = 0.5 + 0.5*sin(vec3(a*0.69813 + uTime*0.24435) + vec3(0.0,2.094395,4.18879));
    dye += color * source * (uEnergy*uGain*0.28 + uOnset*0.06) * uDt*30.0;
  }
  dye += touchDye(uv,uTouch0) + touchDye(uv,uTouch1) + touchDye(uv,uTouch2) + touchDye(uv,uTouch3);
  fragColor = vec4(min(dye, vec3(8.0)), 1.0);
}
