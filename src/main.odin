package main

import "core:fmt"

import "base:runtime"
import slog "sokol/log"
import sg "sokol/gfx"
import sapp "sokol/app"
import sglue "sokol/glue"
import "base:builtin"

window_width: i32 : 1280 
window_height: i32 : 960 

background_color := make_color_rgba8(0x282726ff)

state: struct {
    pass_action: sg.Pass_Action,
    pip: sg.Pipeline,
    bind: sg.Bindings,
    pixel_buffer: [window_width*window_height]u32
}

init :: proc "c" () {
    context = runtime.default_context()

    sg.setup({
        environment = sglue.environment(),
        logger = { func = slog.func },
    })

    vertices := [?]f32 {
        // positions     uvs
        -1.0,  1.0, 0.0, 0.0, 0.0,
         1.0,  1.0, 0.0, 1.0, 0.0,
         1.0, -1.0, 0.0, 1.0, 1.0,
        -1.0, -1.0, 0.0, 0.0, 1.0
    }

    // vertex buffer
    state.bind.vertex_buffers[0] = sg.make_buffer({
        data = { ptr = &vertices, size = size_of(vertices) },
    })

    // index buffer
    indices := [?]u16 { 0, 1, 2,  0, 2, 3 }
    state.bind.index_buffer = sg.make_buffer({
        type = .INDEXBUFFER,
        data = { ptr = &indices, size = size_of(indices) },
    })

    // image which can be dynamically updated
    img := sg.make_image({
        width = window_width,
        height = window_height,
        pixel_format = .RGBA8,
    	sample_count = 1,
        usage = .STREAM,
        label = "dynamic-texture"
    });
    state.bind.images[IMG_tex] = img

    // sampler object
    sampler := sg.make_sampler({
        min_filter = .NEAREST,
        mag_filter = .NEAREST,
        wrap_u = .CLAMP_TO_EDGE,
        wrap_v = .CLAMP_TO_EDGE,
    });
    state.bind.samplers[SMP_smp] = sampler


    // shader and pipeline object
    state.pip = sg.make_pipeline({
        shader = sg.make_shader(quad_shader_desc(sg.query_backend())),
        index_type = .UINT16,
        layout = {
            attrs = {
                ATTR_quad_position = { format = .FLOAT3 },
                ATTR_quad_texcoord0 = { format = .FLOAT2 }
            },
        },
    })

    // default pass action
    state.pass_action = {
        colors = {
            0 = { load_action = .CLEAR, clear_value = { 0, 0, 0, 1 }},
        },
    }
}


frame :: proc "c" () {
    context = runtime.default_context()

    clear_color_buffer(background_color)

    // Update image
    size := u64(size_of(state.pixel_buffer))
    image_data: sg.Image_Data
    image_data.subimage[0][0] = {
        ptr = &state.pixel_buffer,
        size = size
    }
    sg.update_image(state.bind.images[IMG_tex], image_data);


    sg.begin_pass({ action = state.pass_action, swapchain = sglue.swapchain() })
    sg.apply_pipeline(state.pip)
    sg.apply_bindings(state.bind)
    sg.draw(0, 6, 1)
    sg.end_pass()
    sg.commit()
}

cleanup :: proc "c" () {
    context = runtime.default_context()
    sg.shutdown()
}

clear_color_buffer :: proc(color: u32) {
    for y in 0..<window_height {
        for x in 0..<window_width {
            state.pixel_buffer[(y * window_width) + x] = color 
        }
    }
}

draw_rectangle :: proc(x, y, w, h :i32, color: u32) {
    for i in 0..<h {
        for j in 0..<w {
            curr_x := j + x
            curr_y := i + y 
            state.pixel_buffer[(curr_y * window_width) + curr_x] = color 
        }
    }
}

make_color_rgba8 :: proc(color: u32) -> u32 {
    // Little helper function which assumes a color in the rgba8 format and corrects
    // the format depending if the computer is little or big endian.
    // See https://github.com/floooh/sokol/blob/2c6fc7470e9b9121a178e6e68c55f2f06fac4647/sokol_app.h#L898 for more information.
    when ODIN_ENDIAN == .Little {
        // RGBA -> ABGR
        red := u8((color >> 24))
        green := u8((color >> 16))
        blue := u8((color >> 8))
        alpha := u8(color)
        corrected_color := u32((u32(alpha) << 24) | (u32(blue) << 16) | (u32(green) << 8) | (u32(red) << 0))
        return corrected_color
    } 
    // In other cases just return color 
    return color
}

main :: proc () {
    sapp.run({
        init_cb = init,
        frame_cb = frame,
        cleanup_cb = cleanup,
        width = window_width,
        height = window_height,
        window_title = "quad",
        icon = { sokol_default = true },
        logger = { func = slog.func },
    })
}