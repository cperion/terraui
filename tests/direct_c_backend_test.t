-- tests/direct_c_backend_test.t
-- Tests: direct C-callback backend surface.

local ffi = require("ffi")
local terraui = require("lib/terraui")
local ui = terraui.dsl()
local direct = terraui.direct_c_backend
local compile = require("lib/compile")

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

local function make_api(log)
    local api = terralib.new(direct.BackendAPI)
    api.userdata = nil
    api.begin_frame = terralib.cast({&opaque, float, float} -> {}, function(_, w, h)
        log[#log + 1] = { kind = "begin", w = tonumber(w), h = tonumber(h) }
    end)
    api.end_frame = terralib.cast({&opaque} -> {}, function(_)
        log[#log + 1] = { kind = "end" }
    end)
    api.apply_scissor = terralib.cast({&opaque, bool, int32, int32, int32, int32} -> {}, function(_, enabled, x, y, w, h)
        log[#log + 1] = {
            kind = "scissor",
            enabled = enabled,
            x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h),
        }
    end)
    api.draw_rect_batch = terralib.cast({&opaque, &compile.RectCmd, int32} -> {}, function(_, cmds, count)
        log[#log + 1] = { kind = "rect", count = tonumber(count), w = tonumber(cmds[0].w) }
    end)
    api.draw_border_batch = terralib.cast({&opaque, &compile.BorderCmd, int32} -> {}, function(_, cmds, count)
        log[#log + 1] = { kind = "border", count = tonumber(count), left = tonumber(cmds[0].left) }
    end)
    api.draw_text_batch = terralib.cast({&opaque, &compile.TextCmd, int32} -> {}, function(_, cmds, count)
        log[#log + 1] = { kind = "text", count = tonumber(count), first = ffi.string(cmds[0].text) }
    end)
    api.draw_image_batch = terralib.cast({&opaque, &compile.ImageCmd, int32} -> {}, function(_, cmds, count)
        log[#log + 1] = { kind = "image", count = tonumber(count), first = ffi.string(cmds[0].image_id) }
    end)
    api.draw_custom_batch = terralib.cast({&opaque, &compile.CustomCmd, int32} -> {}, function(_, cmds, count)
        log[#log + 1] = { kind = "custom", count = tonumber(count), first = ffi.string(cmds[0].kind) }
    end)
    return api
end

---------------------------------------------------------------------------
-- Test 1: direct callback replay batches stream slices
---------------------------------------------------------------------------

do
    local decl = ui.component("direct_batches") {
        root = ui.scroll_region {
            id = ui.stable("root"),
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
    local log = {}
    local api = make_api(log)

    direct.present(f, api)

    assert(log[1].kind == "begin")
    assert(log[#log].kind == "end")

    local kinds = {}
    for _, e in ipairs(log) do kinds[#kinds + 1] = e.kind end
    assert(table.concat(kinds, ","):find("rect"))
    assert(table.concat(kinds, ","):find("text"))
    assert(table.concat(kinds, ","):find("image"))

    local text_batch
    for _, e in ipairs(log) do
        if e.kind == "text" then text_batch = e end
    end
    assert(text_batch and text_batch.count == 2)
    assert(text_batch.first == "A")

    print("  test 1 (direct callback batching): ok")
end

---------------------------------------------------------------------------
-- Test 2: borders and customs are delivered through typed callbacks
---------------------------------------------------------------------------

do
    local decl = ui.component("direct_payloads") {
        root = ui.column {
            id = ui.stable("root"),
            width = ui.fixed(100),
            height = ui.fixed(60),
            background = ui.rgba(0.2, 0.2, 0.2, 1),
            border = ui.border { left = 1, top = 2, right = 3, bottom = 4, color = ui.rgba(1,1,1,1) },
        } {
            ui.custom { kind = "widget" },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 120, 80)
    local log = {}
    local api = make_api(log)

    direct.present(f, api)

    local saw_border, saw_custom = false, false
    for _, e in ipairs(log) do
        if e.kind == "border" then
            saw_border = true
            assert(e.left == 1)
        elseif e.kind == "custom" then
            saw_custom = true
            assert(e.first == "widget")
        end
    end
    assert(saw_border and saw_custom)

    print("  test 2 (typed payload callbacks): ok")
end

---------------------------------------------------------------------------
-- Test 3: scissor callback receives GL-style flipped coordinates
---------------------------------------------------------------------------

do
    local decl = ui.component("direct_scissor") {
        root = ui.scroll_region {
            id = ui.stable("root"),
            width = ui.fixed(50),
            height = ui.fixed(20),
            horizontal = true,
            vertical = true,
        } {
            ui.label { text = "X" },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 100, 100)
    local log = {}
    local api = make_api(log)

    direct.present(f, api)

    local first_scissor
    for _, e in ipairs(log) do
        if e.kind == "scissor" and e.enabled then
            first_scissor = e
            break
        end
    end
    assert(first_scissor)
    assert(first_scissor.x == 0)
    assert(first_scissor.y == 80)
    assert(first_scissor.w == 50)
    assert(first_scissor.h == 20)

    print("  test 3 (direct scissor coords): ok")
end

---------------------------------------------------------------------------
print("direct c backend test passed")
