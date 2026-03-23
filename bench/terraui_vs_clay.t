local terraui = require("lib/terraui")
local bind = require("lib/bind")
local plan = require("lib/plan")
local compile = require("lib/compile")

local so_path = "/tmp/libterraui_clay_bench.so"
assert(os.execute("cc -O3 -fPIC -shared -Ithird_party/clay -I. bench/clay_bench.c -o " .. so_path) == 0)
terralib.linklibrary(so_path)

local C = terralib.includecstring [[
#include "bench/clay_bench.h"
#include <time.h>
]]

local ui = terraui.dsl()

local function rgba(r,g,b,a) return ui.rgba(r,g,b,a) end
local function label(text, props)
    props = props or {}
    props.text = text
    props.text_color = props.text_color or rgba(0.92, 0.93, 0.95, 1)
    props.font_size = props.font_size or 15
    return ui.label(props)
end

local function compile_ms(f)
    local t0 = os.clock()
    local v = f()
    local dt = (os.clock() - t0) * 1000.0
    return v, dt
end

local function make_flat_list_decl(name, item_count)
    local children = {}
    for i = 0, item_count - 1 do
        children[#children + 1] = ui.row {
            key = ui.indexed("row", i),
            width = ui.grow(),
            height = ui.fit(),
            padding = 6,
            gap = 8,
            align_y = ui.align_y.center,
            background = (i % 2 == 0) and rgba(0.14, 0.15, 0.18, 1) or rgba(0.12, 0.13, 0.16, 1),
            border = ui.border { bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
        } {
            label("Row " .. tostring(i)),
            ui.spacer { width = ui.grow(), height = ui.fixed(0) },
            ui.column {
                padding = 4,
                width = ui.fit(),
                height = ui.fit(),
                background = rgba(0.17, 0.24, 0.34, 1),
                border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.28, 0.38, 0.56, 1) },
            } {
                label("Tag " .. tostring(i % 16), { font_size = 13, text_color = rgba(0.86, 0.92, 1.0, 1) }),
            },
        }
    end

    return ui.component(name) {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.grow(),
            height = ui.grow(),
            padding = 8,
            gap = 2,
            background = rgba(0.08, 0.09, 0.11, 1),
        } (children),
    }
end

local function make_text_heavy_decl(name, item_count)
    local children = {}
    for i = 0, item_count - 1 do
        children[#children + 1] = ui.row {
            key = ui.indexed("textrow", i),
            width = ui.grow(),
            height = ui.fit(),
            padding = 4,
        } {
            label("Text row " .. tostring(i) .. " with a modest amount of content for measurement."),
        }
    end
    return ui.component(name) {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.grow(),
            height = ui.grow(),
            padding = 10,
            gap = 4,
            background = rgba(0.10, 0.11, 0.14, 1),
        } (children),
    }
end

local function make_nested_panels_decl(name, group_count)
    local groups = {}
    for g = 0, group_count - 1 do
        local cards = {}
        for i = 0, 5 do
            cards[#cards + 1] = ui.column {
                key = ui.indexed("card", g * 16 + i),
                width = ui.grow(),
                height = ui.fit(),
                padding = 6,
                gap = 4,
                background = rgba(0.16, 0.18, 0.23, 1),
                border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.28, 0.30, 0.36, 1) },
            } {
                label("Card " .. tostring(g) .. "." .. tostring(i), { font_size = 15, text_color = rgba(0.96, 0.97, 0.98, 1) }),
                label("Nested panel content", { font_size = 13, text_color = rgba(0.70, 0.74, 0.80, 1) }),
            }
        end
        groups[#groups + 1] = ui.column {
            key = ui.indexed("group", g),
            width = ui.grow(),
            height = ui.grow(),
            padding = 8,
            gap = 6,
            background = rgba(0.12, 0.13, 0.15, 1),
            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
        } (cards)
    end
    return ui.component(name) {
        root = ui.row {
            key = ui.stable("root"),
            width = ui.grow(),
            height = ui.grow(),
            padding = 8,
            gap = 8,
            background = rgba(0.08, 0.09, 0.11, 1),
        } (groups),
    }
end

local function make_inspector_decl(name, item_count)
    local toolbar = {}
    for i = 0, 2 do
        toolbar[#toolbar + 1] = ui.column {
            key = ui.indexed("tab", i),
            padding = 6,
            width = ui.fit(),
            height = ui.fit(),
            background = rgba(0.18, 0.24, 0.36, 1),
            border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.28, 0.38, 0.56, 1) },
        } {
            label("Tab " .. tostring(i), { font_size = 14, text_color = rgba(1,1,1,1) }),
        }
    end

    local assets = { label("Assets", { font_size = 18, text_color = rgba(0.96, 0.97, 0.98, 1) }) }
    for i = 0, item_count - 1 do
        assets[#assets + 1] = ui.column {
            key = ui.indexed("asset", i),
            width = ui.grow(),
            height = ui.fit(),
            padding = 5,
            background = (i % 2 == 0) and rgba(0.14, 0.15, 0.18, 1) or rgba(0.12, 0.13, 0.16, 1),
        } {
            label("Asset " .. tostring(i), { font_size = 14 }),
        }
    end

    local stats = {}
    for i = 0, 7 do
        stats[#stats + 1] = ui.row { width = ui.grow(), height = ui.fit(), gap = 6 } {
            label("Metric " .. tostring(i), { font_size = 14 }),
            ui.spacer { width = ui.grow(), height = ui.fixed(0) },
            label(tostring(100 + i * 7), { font_size = 14, text_color = rgba(0.72, 0.80, 0.96, 1) }),
        }
    end

    local fields = { label("Inspector", { font_size = 18, text_color = rgba(0.96, 0.97, 0.98, 1) }) }
    for i = 0, 11 do
        fields[#fields + 1] = ui.row { width = ui.grow(), height = ui.fit(), gap = 6 } {
            label("Field " .. tostring(i), { font_size = 14 }),
            ui.spacer { width = ui.grow(), height = ui.fixed(0) },
            label("Value " .. tostring(i * 3), { font_size = 14, text_color = rgba(0.72, 0.80, 0.96, 1) }),
        }
    end

    return ui.component(name) {
        root = ui.column {
            key = ui.stable("root"),
            width = ui.grow(),
            height = ui.grow(),
            padding = 10,
            gap = 10,
            background = rgba(0.08, 0.09, 0.11, 1),
        } {
            ui.row {
                key = ui.stable("toolbar"),
                width = ui.grow(),
                height = ui.fixed(40),
                padding = 6,
                gap = 6,
                align_y = ui.align_y.center,
                background = rgba(0.10, 0.11, 0.14, 1),
                border = ui.border { bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
            } (toolbar),
            ui.row {
                key = ui.stable("main"),
                width = ui.grow(),
                height = ui.grow(),
                gap = 10,
            } {
                ui.column {
                    key = ui.stable("assets"),
                    width = ui.fixed(260),
                    height = ui.grow(),
                    padding = 8,
                    gap = 4,
                    background = rgba(0.12, 0.13, 0.15, 1),
                    border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
                } (assets),
                ui.column {
                    key = ui.stable("center"),
                    width = ui.grow(),
                    height = ui.grow(),
                    gap = 8,
                } {
                    label("Preview", { font_size = 20, text_color = rgba(0.96, 0.97, 0.98, 1) }),
                    ui.image_view {
                        key = ui.stable("image"),
                        image = "bench_image",
                        width = ui.fixed(320),
                        height = ui.fixed(180),
                        border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.26, 0.28, 0.33, 1) },
                    },
                    ui.column {
                        key = ui.stable("stats"),
                        width = ui.grow(),
                        height = ui.fit(),
                        padding = 8,
                        gap = 4,
                        background = rgba(0.12, 0.13, 0.15, 1),
                        border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
                    } (stats),
                },
                ui.column {
                    key = ui.stable("inspector"),
                    width = ui.fixed(240),
                    height = ui.grow(),
                    padding = 8,
                    gap = 4,
                    background = rgba(0.12, 0.13, 0.15, 1),
                    border = ui.border { left = 1, top = 1, right = 1, bottom = 1, color = rgba(0.22, 0.24, 0.28, 1) },
                } (fields),
            },
        },
    }
end

struct BenchResult {
    total_ns: uint64
    avg_us: double
    element_count: int32
    command_count: int32
    rect_count: int32
    border_count: int32
    text_count: int32
    image_count: int32
    scissor_count: int32
    custom_count: int32
    had_error: int32
}

terra now_ns() : uint64
    var ts: C.timespec
    C.clock_gettime(C.CLOCK_MONOTONIC_RAW, &ts)
    return [uint64](ts.tv_sec) * 1000000000ULL + [uint64](ts.tv_nsec)
end

local cases = {
    { name = "flat_list_96", kind = "flat_list", arg = 96, frames = 500 },
    { name = "text_heavy_160", kind = "text_heavy", arg = 160, frames = 300 },
    { name = "nested_panels_4", kind = "nested_panels", arg = 4, frames = 500 },
    { name = "inspector_mini", kind = "inspector", arg = 18, frames = 220 },
}

local bench_entries = {}

for _, bench_case in ipairs(cases) do
    local decl, compile_ms_decl
    if bench_case.kind == "flat_list" then
        decl, compile_ms_decl = compile_ms(function() return make_flat_list_decl(bench_case.name, bench_case.arg) end)
    elseif bench_case.kind == "text_heavy" then
        decl, compile_ms_decl = compile_ms(function() return make_text_heavy_decl(bench_case.name, bench_case.arg) end)
    elseif bench_case.kind == "nested_panels" then
        decl, compile_ms_decl = compile_ms(function() return make_nested_panels_decl(bench_case.name, bench_case.arg) end)
    elseif bench_case.kind == "inspector" then
        decl, compile_ms_decl = compile_ms(function() return make_inspector_decl(bench_case.name, bench_case.arg) end)
    else
        error("unknown case kind")
    end

    local bound, bind_ms = compile_ms(function() return bind.bind_component(decl) end)
    local planned, plan_ms = compile_ms(function() return plan.plan_component(bound) end)
    local kernel, kernel_ms = compile_ms(function() return compile.compile_component(planned) end)
    local total_compile_ms = compile_ms_decl + bind_ms + plan_ms + kernel_ms

    local Frame = kernel:frame_type()
    local init_q = kernel.kernels.init_fn
    local run_q = kernel.kernels.run_fn
    local node_count = #planned.nodes

    local terraui_bench = terra(frames: int32) : BenchResult
        var frame: Frame
        [init_q](&frame)
        frame.viewport_w = 1440
        frame.viewport_h = 900

        for _ = 0, 5 do
            [run_q](&frame)
        end

        var t0 = now_ns()
        for _ = 0, frames - 1 do
            [run_q](&frame)
        end
        var total = now_ns() - t0
        var cmds = frame.rect_count + frame.border_count + frame.text_count + frame.image_count + frame.scissor_count + frame.custom_count
        return BenchResult {
            total_ns = total,
            avg_us = [double](total) / [double](frames) / 1000.0,
            element_count = node_count,
            command_count = cmds,
            rect_count = frame.rect_count,
            border_count = frame.border_count,
            text_count = frame.text_count,
            image_count = frame.image_count,
            scissor_count = frame.scissor_count,
            custom_count = frame.custom_count,
            had_error = 0,
        }
    end

    local clay_bench
    if bench_case.kind == "flat_list" then
        clay_bench = terra(frames: int32) : BenchResult
            var stats: C.ClayBenchStats
            for _ = 0, 5 do C.ClayBench_BuildFlatList(bench_case.arg, 1440, 900, &stats) end
            var t0 = now_ns()
            for _ = 0, frames - 1 do C.ClayBench_BuildFlatList(bench_case.arg, 1440, 900, &stats) end
            var total = now_ns() - t0
            return BenchResult { total_ns = total, avg_us = [double](total) / [double](frames) / 1000.0,
                element_count = stats.element_count, command_count = stats.command_count,
                rect_count = stats.rect_count, border_count = stats.border_count, text_count = stats.text_count,
                image_count = stats.image_count, scissor_count = stats.scissor_count, custom_count = stats.custom_count,
                had_error = stats.had_error }
        end
    elseif bench_case.kind == "text_heavy" then
        clay_bench = terra(frames: int32) : BenchResult
            var stats: C.ClayBenchStats
            for _ = 0, 5 do C.ClayBench_BuildTextHeavy(bench_case.arg, 1440, 900, &stats) end
            var t0 = now_ns()
            for _ = 0, frames - 1 do C.ClayBench_BuildTextHeavy(bench_case.arg, 1440, 900, &stats) end
            var total = now_ns() - t0
            return BenchResult { total_ns = total, avg_us = [double](total) / [double](frames) / 1000.0,
                element_count = stats.element_count, command_count = stats.command_count,
                rect_count = stats.rect_count, border_count = stats.border_count, text_count = stats.text_count,
                image_count = stats.image_count, scissor_count = stats.scissor_count, custom_count = stats.custom_count,
                had_error = stats.had_error }
        end
    elseif bench_case.kind == "nested_panels" then
        clay_bench = terra(frames: int32) : BenchResult
            var stats: C.ClayBenchStats
            for _ = 0, 5 do C.ClayBench_BuildNestedPanels(bench_case.arg, 1440, 900, &stats) end
            var t0 = now_ns()
            for _ = 0, frames - 1 do C.ClayBench_BuildNestedPanels(bench_case.arg, 1440, 900, &stats) end
            var total = now_ns() - t0
            return BenchResult { total_ns = total, avg_us = [double](total) / [double](frames) / 1000.0,
                element_count = stats.element_count, command_count = stats.command_count,
                rect_count = stats.rect_count, border_count = stats.border_count, text_count = stats.text_count,
                image_count = stats.image_count, scissor_count = stats.scissor_count, custom_count = stats.custom_count,
                had_error = stats.had_error }
        end
    elseif bench_case.kind == "inspector" then
        clay_bench = terra(frames: int32) : BenchResult
            var stats: C.ClayBenchStats
            for _ = 0, 5 do C.ClayBench_BuildInspectorMini(bench_case.arg, 1440, 900, &stats) end
            var t0 = now_ns()
            for _ = 0, frames - 1 do C.ClayBench_BuildInspectorMini(bench_case.arg, 1440, 900, &stats) end
            var total = now_ns() - t0
            return BenchResult { total_ns = total, avg_us = [double](total) / [double](frames) / 1000.0,
                element_count = stats.element_count, command_count = stats.command_count,
                rect_count = stats.rect_count, border_count = stats.border_count, text_count = stats.text_count,
                image_count = stats.image_count, scissor_count = stats.scissor_count, custom_count = stats.custom_count,
                had_error = stats.had_error }
        end
    end

    bench_entries[#bench_entries + 1] = {
        name = bench_case.name,
        kind = bench_case.kind,
        arg = bench_case.arg,
        frames = bench_case.frames,
        compile_ms = total_compile_ms,
        terraui = terraui_bench,
        clay = clay_bench,
    }
end

local function fmt_ms(x)
    return string.format("%.3f ms", x)
end

local function fmt_us(x)
    return string.format("%.3f us", x)
end

local function fmt_speedup(clay_us, terra_us)
    if terra_us == 0 then return "inf x" end
    return string.format("%.2f x", clay_us / terra_us)
end

print("TerraUI vs Clay benchmark")
print(string.rep("=", 72))
print("All timings are hot runtime per frame unless noted otherwise.")
print()

for _, entry in ipairs(bench_entries) do
    local tr = entry.terraui(entry.frames)
    local cr = entry.clay(entry.frames)

    print(string.format("[%s] arg=%d frames=%d", entry.name, entry.arg, entry.frames))
    print(string.format("  TerraUI  compile: %-12s runtime: %-12s", fmt_ms(entry.compile_ms), fmt_us(tonumber(tr.avg_us))))
    print(string.format("  Clay     compile: %-12s runtime: %-12s", "n/a", fmt_us(tonumber(cr.avg_us))))
    print(string.format("  Speedup  runtime: %s (Clay / TerraUI)", fmt_speedup(tonumber(cr.avg_us), tonumber(tr.avg_us))))
    print(string.format("  Shape    elements: %d vs %d   commands: %d vs %d",
        tonumber(tr.element_count), tonumber(cr.element_count),
        tonumber(tr.command_count), tonumber(cr.command_count)))
    print(string.format("  Streams  rect=%d/%d border=%d/%d text=%d/%d image=%d/%d scissor=%d/%d custom=%d/%d",
        tonumber(tr.rect_count), tonumber(cr.rect_count),
        tonumber(tr.border_count), tonumber(cr.border_count),
        tonumber(tr.text_count), tonumber(cr.text_count),
        tonumber(tr.image_count), tonumber(cr.image_count),
        tonumber(tr.scissor_count), tonumber(cr.scissor_count),
        tonumber(tr.custom_count), tonumber(cr.custom_count)))
    if tonumber(tr.had_error) ~= 0 or tonumber(cr.had_error) ~= 0 then
        print(string.format("  Errors   terraui=%d clay=%d", tonumber(tr.had_error), tonumber(cr.had_error)))
    end
    print()
end
