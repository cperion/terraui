-- lib/presenter.t
-- CPU-side presenter helpers for Kernel frame streams.

local ffi = require("ffi")

local M = {}

local function maybe_string(ptr)
    if ptr == nil then return nil end
    return ffi.string(ptr)
end

local function color_to_table(c)
    return { r = tonumber(c.r), g = tonumber(c.g), b = tonumber(c.b), a = tonumber(c.a) }
end

local function rect_cmd_to_table(c)
    return {
        x = tonumber(c.x), y = tonumber(c.y),
        w = tonumber(c.w), h = tonumber(c.h),
        color = color_to_table(c.color),
        opacity = tonumber(c.opacity),
        z = tonumber(c.z),
        seq = tonumber(c.seq),
    }
end

local function border_cmd_to_table(c)
    return {
        x = tonumber(c.x), y = tonumber(c.y),
        w = tonumber(c.w), h = tonumber(c.h),
        left = tonumber(c.left), top = tonumber(c.top),
        right = tonumber(c.right), bottom = tonumber(c.bottom),
        color = color_to_table(c.color),
        opacity = tonumber(c.opacity),
        z = tonumber(c.z),
        seq = tonumber(c.seq),
    }
end

local function text_cmd_to_table(c)
    return {
        x = tonumber(c.x), y = tonumber(c.y),
        w = tonumber(c.w), h = tonumber(c.h),
        text = maybe_string(c.text),
        font_id = maybe_string(c.font_id),
        font_size = tonumber(c.font_size),
        letter_spacing = tonumber(c.letter_spacing),
        line_height = tonumber(c.line_height),
        color = color_to_table(c.color),
        z = tonumber(c.z),
        seq = tonumber(c.seq),
    }
end

local function image_cmd_to_table(c)
    return {
        x = tonumber(c.x), y = tonumber(c.y),
        w = tonumber(c.w), h = tonumber(c.h),
        image_id = maybe_string(c.image_id),
        tint = color_to_table(c.tint),
        z = tonumber(c.z),
        seq = tonumber(c.seq),
    }
end

local function scissor_cmd_to_table(c)
    return {
        is_begin = c.is_begin,
        x0 = tonumber(c.x0), y0 = tonumber(c.y0),
        x1 = tonumber(c.x1), y1 = tonumber(c.y1),
        z = tonumber(c.z),
        seq = tonumber(c.seq),
    }
end

local function custom_cmd_to_table(c)
    return {
        x = tonumber(c.x), y = tonumber(c.y),
        w = tonumber(c.w), h = tonumber(c.h),
        kind = maybe_string(c.kind),
        z = tonumber(c.z),
        seq = tonumber(c.seq),
    }
end

local function push_packets(out, frame, count_field, array_field, kind, conv)
    local n = tonumber(frame[count_field])
    for i = 0, n - 1 do
        local cmd = conv(frame[array_field][i])
        out[#out + 1] = {
            kind = kind,
            stream_index = i,
            z = cmd.z,
            seq = cmd.seq,
            cmd = cmd,
        }
    end
end

function M.collect_packets(frame)
    local packets = {}
    push_packets(packets, frame, "rect_count", "rects", "rect", rect_cmd_to_table)
    push_packets(packets, frame, "border_count", "borders", "border", border_cmd_to_table)
    push_packets(packets, frame, "text_count", "texts", "text", text_cmd_to_table)
    push_packets(packets, frame, "image_count", "images", "image", image_cmd_to_table)
    push_packets(packets, frame, "scissor_count", "scissors", "scissor", scissor_cmd_to_table)
    push_packets(packets, frame, "custom_count", "customs", "custom", custom_cmd_to_table)

    table.sort(packets, function(a, b)
        if a.z == b.z then return a.seq < b.seq end
        return a.z < b.z
    end)
    return packets
end

function M.replay(frame, handlers)
    handlers = handlers or {}
    local packets = M.collect_packets(frame)
    local scissor_stack = {}

    local function current_scissor()
        return scissor_stack[#scissor_stack]
    end

    for _, p in ipairs(packets) do
        if p.kind == "scissor" then
            if p.cmd.is_begin then
                scissor_stack[#scissor_stack + 1] = p.cmd
            else
                scissor_stack[#scissor_stack] = nil
            end
            if handlers.scissor then handlers.scissor(p.cmd, p) end
        else
            local h = handlers[p.kind]
            if h then h(p.cmd, current_scissor(), p) end
        end
    end

    return packets
end

return M
