package main

import "base:runtime"
import "base:builtin"

import "core:fmt"
import "core:math/rand"
import "core:os"

import slog "sokol/log"
import sg "sokol/gfx"
import sapp "sokol/app"
import sglue "sokol/glue"

import stbi "vendor:stb/image"

window_width: i32 : 1280 
window_height: i32 : 960 
foreground_color := make_color_rgba8(0x181818ff)
background_color := make_color_rgba8(0x96a6c8ff)
cell_alive_color := foreground_color
cell_dead_color := background_color

cell_size: i32 : 3
num_cells_x :: window_width / cell_size
num_cells_y :: window_height / cell_size
num_cells :: num_cells_x * num_cells_y

GameState :: enum {
    DRAWING,
    RUNNING
}

CellState :: enum {
    DEAD,
    ALIVE
}

state: struct {
    pass_action: sg.Pass_Action,
    pip: sg.Pipeline,
    bind: sg.Bindings,
    pixel_buffer: [window_width*window_height]u32,
    cell_states: [num_cells]CellState,
    game_state: GameState,
    drawing_index: i32,
    event_type: sapp.Event_Type,
    key_code: sapp.Keycode
}

init :: proc "c" () {
    context = runtime.default_context()
    fmt.println(num_cells_x, num_cells_y)

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

    state.cell_states = init_cell_states_from_image()
    // state.cell_states = init_cell_states()
    state.game_state = .DRAWING
}

event :: proc "c" (event: ^sapp.Event) {
    context = runtime.default_context()
    // Switch between running and drawing
    state.event_type = event.type
    if event.type == .KEY_UP && event.key_code == .D {
        if state.game_state == .RUNNING {
            // Before switching to drawing clear all cells
            state.cell_states = clear_cell_states()
            state.game_state = .DRAWING
        }
        else {
            state.game_state = .RUNNING
        }
    }
    cell_x := i32(event.mouse_x) / cell_size
    cell_y := i32(event.mouse_y) / cell_size

    // Ignore when out of bounds
    if cell_x < 0 || cell_x >= num_cells_x || cell_y < 0 || cell_y >= num_cells_y {
        state.drawing_index = -1
    }
    else {
        state.drawing_index = (cell_y * num_cells_x) + cell_x
    }
}


frame :: proc "c" () {
    context = runtime.default_context()
    clear_color_buffer(background_color)

    // Drawing
    if state.game_state == .DRAWING {
        if state.event_type == .MOUSE_DOWN && state.drawing_index != -1 {
            state.cell_states[state.drawing_index] = .ALIVE
        }
    } else {
        // Running
        state.cell_states = apply_cell_state_rules(state.cell_states)
    }
    draw_cell_states(state.cell_states[:])

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

draw_pixel :: proc(x, y: i32, color: u32) {
    if x < 0 || x > window_width || y < 0 || y > window_height {
        return
    }
    state.pixel_buffer[(y * window_width) + x] = color 
}

clear_color_buffer :: proc(color: u32) {
    for y in 0..<window_height {
        for x in 0..<window_width {
            draw_pixel(x, y, color)
        }
    }
}

draw_rectangle :: proc(x, y, w, h :i32, color: u32) {
    for i in 0..<h {
        for j in 0..<w {
            curr_x := j + x
            curr_y := i + y 
            draw_pixel(curr_x, curr_y, color)
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


draw_grid :: proc(cell_size: i32, color: u32) {
    for y in 0..<window_height {
        for x in 0..<window_width {
            if x % cell_size == 0 || y % cell_size == 0 {
                draw_pixel(x, y, color)
            }
        }
    }
}

draw_cell_states :: proc(cell_states:[]CellState) {
    for cell_state, index in cell_states {
        // Convert index to x and y position
        x := i32(index) % num_cells_x
        y := i32(index) / num_cells_x 
        color := cell_state == .DEAD ? cell_dead_color : cell_alive_color
        draw_rectangle(x * cell_size, y * cell_size, cell_size, cell_size, color)
    }
    // draw_grid(cell_size, foreground_color)
}

apply_cell_state_rules :: proc(cell_states:[num_cells]CellState) -> [num_cells]CellState {
    new_cell_states: [num_cells]CellState
    for cell_state, index in cell_states {
        new_cell_state := cell_state
        // Get living neighbours and apply rule for Convways Game of Live
        num_living_neighbours := get_living_neighbours(cell_states, i32(index))
        if cell_state == .ALIVE {
            // 1: Any live cell with fewer than two live neighbours dies
            if num_living_neighbours < 2 {
                new_cell_state = .DEAD
            } else if num_living_neighbours == 2 || num_living_neighbours == 3 {
                // 2: Any live cell with two or three live neighbours lives
                new_cell_state = .ALIVE
            } else {
                // 3: Any live cell with more then three live neibhours dies
                new_cell_state = .DEAD
            }
        }
        else {
            // 4: Any dead cell with exactly three live neighbours becomes alive again 
            if num_living_neighbours == 3 {
                new_cell_state = .ALIVE
            }
        }
        new_cell_states[index] = new_cell_state
    }

    return new_cell_states
}

get_living_neighbours :: proc(cell_states:[num_cells]CellState, x: i32) -> u32 {
    /*
        [ ][ ][ ]
        ^
        top_row
        [ ][x][ ]
        ^
        middle_row
        [ ][ ][ ]
        ^
        bottom_row
    */
    // Check top row
    top_row_start := x - num_cells_x - 1
    middle_row_start := x - 1
    bottom_row_start:= x + num_cells_x - 1 
    num_living_neighbours: u32 = 0

    // Check top row
    for i in 0..<3 {
        index := top_row_start + i32(i)
        if index < 0 || index >= num_cells || index == x {
            // Skip invalid index
            continue
        }
        cell_state := cell_states[index]
        if cell_state == .ALIVE {
            num_living_neighbours += 1
        }
    }

    // Check middle row
    for i in 0..<3 {
        index := middle_row_start + i32(i)
        if index < 0 || index >= num_cells || index == x {
            // Skip invalid index
            continue
        }
        cell_state := cell_states[index]
        if cell_state == .ALIVE {
            num_living_neighbours += 1
        }
    }

    // Check bottom row
    for i in 0..<3 {
        index := bottom_row_start + i32(i)
        if index < 0 || index >= num_cells || index == x {
            // Skip invalid index
            continue
        }
        cell_state := cell_states[index]
        if cell_state == .ALIVE {
            num_living_neighbours += 1
        }
    }
    return num_living_neighbours
}

init_cell_states :: proc() -> [num_cells]CellState {
    cell_states: [num_cells]CellState
    for i in 0..<num_cells {
        cell_states[i] = rand.choice_enum(CellState)
    }
    return cell_states
}

init_cell_states_from_image :: proc() -> [num_cells]CellState {
    cell_states: [num_cells]CellState

    path :cstring = "./src/sako.png"
    width: i32
    height: i32
    components: i32
    
    data := stbi.load(path, &width, &height, &components, 1)
    size := width * height
    
    // TODO: Safety check of size
    for y in 0..<height {
        for x in 0..<width {
            index := (y * width) + x
            // Note: The pixel index and cell index are not mapped 1:1 to get the correct cell index
            // we need to consider the number of cells available on the x axis
            cell_index := (y * num_cells_x) + x
            pixel := data[index]
            cell_state: CellState = pixel == 0 ? .ALIVE : .DEAD
            cell_states[cell_index] = cell_state
        }
    }
    return cell_states
}

clear_cell_states :: proc() -> [num_cells]CellState {
    cell_states: [num_cells]CellState
    for i in 0..<num_cells {
        cell_states[i] = .DEAD 
    }
    return cell_states
}

main :: proc () {
    sapp.run({
        init_cb = init,
        frame_cb = frame,
        event_cb = event,
        cleanup_cb = cleanup,
        width = window_width,
        height = window_height,
        window_title = "Odin Game of Live",
        icon = { sokol_default = true },
        logger = { func = slog.func },
    })
}
