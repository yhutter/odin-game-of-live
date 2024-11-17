@header package main
@header import sg "sokol/gfx"

@vs vs
in vec4 position;
in vec2 texcoord0;

layout(location=0) out vec2 uv;


void main() {
    gl_Position = position;
    uv = texcoord0;
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;
layout(location=0) in vec2 uv;
out vec4 frag_color;

void main() {
    frag_color = texture(sampler2D(tex, smp), uv);
}
@end

@program quad vs fs

