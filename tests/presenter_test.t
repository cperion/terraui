-- tests/presenter_test.t
-- Tests: CPU presenter packet collection / replay.

local terraui = require("lib/terraui")
local ui = terraui.dsl()
local presenter = terraui.presenter
local Decl = terraui.types.Decl

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
-- Test 1: packets merge by (z, seq)
---------------------------------------------------------------------------

do
    local decl = ui.component("packets") {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.fixed(100),
            height = ui.fixed(100),
            background = ui.rgba(0.2, 0.2, 0.2, 1),
        } {
            ui.label { key = ui.stable("label"), text = "Hello" },
            ui.tooltip {
                key = ui.stable("tip"),
                target = ui.float.parent,
                parent_point = ui.attach.left_top,
                element_point = ui.attach.left_top,
                z_index = 10,
            } {
                ui.label { text = "Top" },
            },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 200, 200)
    local packets = presenter.collect_packets(f)

    assert(#packets >= 3)
    assert(packets[1].kind == "rect")
    -- last packet should come from the floating subtree because z=10
    assert(packets[#packets].z == 10)

    for i = 2, #packets do
        local a = packets[i - 1]
        local b = packets[i]
        assert(a.z < b.z or (a.z == b.z and a.seq < b.seq))
    end

    print("  test 1 (packet merge): ok")
end

---------------------------------------------------------------------------
-- Test 2: scissor stack is maintained during replay
---------------------------------------------------------------------------

do
    local decl = ui.component("scissor_replay") {
        root = ui.scroll_region {
            key = ui.stable("scroll"),
            width = ui.fixed(100),
            height = ui.fixed(50),
            horizontal = true,
            vertical = true,
            background = ui.rgba(0.1, 0.1, 0.1, 1),
        } {
            ui.label { text = "Inside" },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 200, 200)

    local saw_begin, saw_end, saw_text_with_scissor = false, false, false
    local packets = presenter.replay(f, {
        scissor = function(cmd)
            if cmd.is_begin then saw_begin = true else saw_end = true end
        end,
        text = function(cmd, current_scissor)
            if current_scissor ~= nil then saw_text_with_scissor = true end
        end,
    })

    assert(#packets >= 3)
    assert(saw_begin)
    assert(saw_end)
    assert(saw_text_with_scissor)

    print("  test 2 (scissor stack replay): ok")
end

---------------------------------------------------------------------------
-- Test 3: emitted command payloads are converted to Lua tables
---------------------------------------------------------------------------

do
    local decl = ui.component("payloads") {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.fixed(120),
            height = ui.fixed(90),
            background = ui.rgba(0.3, 0.4, 0.5, 1),
            border = ui.border {
                left = 1, top = 2, right = 3, bottom = 4,
                color = ui.rgba(1,1,1,1),
            },
        } {
            ui.label { text = "Hello" },
            ui.image_view { image = "tex" },
            ui.custom { kind = "widget" },
        },
    }

    local k = terraui.compile(decl)
    local f = run_frame(k, 200, 200)
    local packets = presenter.collect_packets(f)

    local saw_rect, saw_border, saw_text, saw_image, saw_custom = false, false, false, false, false
    for _, p in ipairs(packets) do
        if p.kind == "rect" then
            saw_rect = true
            assert(p.cmd.color.r > 0)
        elseif p.kind == "border" then
            saw_border = true
            assert(p.cmd.left == 1)
            assert(p.cmd.bottom == 4)
        elseif p.kind == "text" then
            saw_text = true
            assert(p.cmd.text == "Hello")
            assert(p.cmd.wrap ~= nil)
            assert(p.cmd.align ~= nil)
        elseif p.kind == "image" then
            saw_image = true
            assert(p.cmd.image_id == "tex")
        elseif p.kind == "custom" then
            saw_custom = true
            assert(p.cmd.kind == "widget")
        end
    end

    assert(saw_rect and saw_border and saw_text and saw_image and saw_custom)

    print("  test 3 (packet payload tables): ok")
end

---------------------------------------------------------------------------
print("presenter test passed")
