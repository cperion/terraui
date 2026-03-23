-- tests/opengl_backend_test.t
-- Tests: OpenGL-style backend skeleton over presenter packets.

local terraui = require("lib/terraui")
local ui = terraui.dsl()
local glb = terraui.opengl_backend

local function run_frame(kernel, vw, vh)
    local Frame = kernel:frame_type()
    local init_q = kernel.kernels.init_fn
    local run_q = kernel.kernels.run_fn
    local mk = terra(vw: float, vh: float)
        var f : Frame
        [init_q](&f)
        f.viewport_w = vw
        f.viewport_h = vh
        [run_q](&f)
        return f
    end
    return mk(vw, vh)
end

---------------------------------------------------------------------------
-- Test 1: scissor_to_gl flips Y correctly
---------------------------------------------------------------------------

do
    local r = glb.scissor_to_gl({ x0 = 10, y0 = 20, x1 = 60, y1 = 70 }, 200)
    assert(r.x == 10)
    assert(r.y == 130)
    assert(r.w == 50)
    assert(r.h == 50)
    print("  test 1 (scissor y-flip): ok")
end

---------------------------------------------------------------------------
-- Test 2: batching groups contiguous packets of same kind/scissor
---------------------------------------------------------------------------

do
    local decl = ui.component("batching") {
        root = ui.scroll_region {
            key = ui.stable("root"),
            width = ui.fixed(120),
            height = ui.fixed(80),
            horizontal = true,
            vertical = true,
            background = ui.rgba(0.1, 0.1, 0.1, 1),
        } {
            ui.label { text = "A" },
            ui.label { text = "B" },
            ui.image_view { image = "tex" },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 200, 200)

    local seen = {}
    glb.present(f, {
        callbacks = {
            draw_rect_batch = function(cmds, scissor)
                seen[#seen + 1] = { kind = "rect", n = #cmds, scissor = scissor ~= nil }
            end,
            draw_text_batch = function(cmds, scissor)
                seen[#seen + 1] = { kind = "text", n = #cmds, scissor = scissor ~= nil }
            end,
            draw_image_batch = function(cmds, scissor)
                seen[#seen + 1] = { kind = "image", n = #cmds, scissor = scissor ~= nil }
            end,
        },
    })

    -- one rect batch, one text batch (2 labels), one image batch
    assert(#seen == 3)
    assert(seen[1].kind == "rect")
    assert(seen[2].kind == "text")
    assert(seen[2].n == 2)
    assert(seen[3].kind == "image")
    assert(seen[1].scissor == true)
    assert(seen[2].scissor == true)
    print("  test 2 (batching): ok")
end

---------------------------------------------------------------------------
-- Test 3: text shaping hook is called for text batches
---------------------------------------------------------------------------

do
    local decl = ui.component("shape_hook") {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.fixed(120),
            height = ui.fixed(80),
        } {
            ui.label { text = "Hello" },
            ui.label { text = "World" },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 200, 200)

    local shaped_count = 0
    local shaped_payload = nil
    glb.present(f, {
        font_backend = {
            shape_text_cmds = function(cmds)
                shaped_count = shaped_count + 1
                shaped_payload = { count = #cmds, first = cmds[1].text }
                return { glyphs = 42 }
            end,
        },
        callbacks = {
            draw_text_batch = function(cmds, scissor, batch)
                assert(batch.shaped.glyphs == 42)
            end,
        },
    })

    assert(shaped_count == 1)
    assert(shaped_payload.count == 2)
    assert(shaped_payload.first == "Hello")
    print("  test 3 (shape hook): ok")
end

---------------------------------------------------------------------------
-- Test 4: custom commands are dispatched individually
---------------------------------------------------------------------------

do
    local decl = ui.component("custom_dispatch") {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.fixed(50),
            height = ui.fixed(50),
        } {
            ui.custom { kind = "a" },
            ui.custom { kind = "b" },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 100, 100)

    local kinds = {}
    glb.present(f, {
        callbacks = {
            draw_custom = function(cmd)
                kinds[#kinds + 1] = cmd.kind
            end,
        },
    })

    assert(#kinds == 2)
    assert(kinds[1] == "a")
    assert(kinds[2] == "b")
    print("  test 4 (custom dispatch): ok")
end

---------------------------------------------------------------------------
print("opengl backend test passed")
