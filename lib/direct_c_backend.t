-- lib/direct_c_backend.t
-- Direct C-callback backend surface using Terra/C function pointers.

local compile = require("lib/compile")
local presenter = require("lib/presenter")
local ffi = require("ffi")

struct BackendAPI {
    userdata: &opaque
    begin_frame: {&opaque, float, float} -> {}
    end_frame: {&opaque} -> {}
    apply_scissor: {&opaque, bool, int32, int32, int32, int32} -> {}
    draw_rect_batch: {&opaque, &compile.RectCmd, int32} -> {}
    draw_border_batch: {&opaque, &compile.BorderCmd, int32} -> {}
    draw_text_batch: {&opaque, &compile.TextCmd, int32} -> {}
    draw_image_batch: {&opaque, &compile.ImageCmd, int32} -> {}
    draw_custom_batch: {&opaque, &compile.CustomCmd, int32} -> {}
}

local M = {}
M.BackendAPI = BackendAPI

local function current_scissor_gl(scissor_stack, viewport_h)
    local top = scissor_stack[#scissor_stack]
    if not top then return nil end
    local x0 = math.floor(top.x0)
    local x1 = math.ceil(top.x1)
    local y0 = math.floor(viewport_h - top.y1)
    local y1 = math.ceil(viewport_h - top.y0)
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

local function scissor_equal(a, b)
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function flush_batch(frame, api, batch)
    if not batch then return nil end
    if batch.count <= 0 then return nil end

    local ud = api.userdata
    if batch.kind == "rect" then
        api.draw_rect_batch(ud, frame.rects + batch.first, batch.count)
    elseif batch.kind == "border" then
        api.draw_border_batch(ud, frame.borders + batch.first, batch.count)
    elseif batch.kind == "text" then
        api.draw_text_batch(ud, frame.texts + batch.first, batch.count)
    elseif batch.kind == "image" then
        api.draw_image_batch(ud, frame.images + batch.first, batch.count)
    elseif batch.kind == "custom" then
        api.draw_custom_batch(ud, frame.customs + batch.first, batch.count)
    end
    return nil
end

function M.present(frame, api)
    local packets = presenter.collect_packets(frame)
    local viewport_h = tonumber(frame.viewport_h)
    local scissor_stack = {}
    local batch = nil

    api.begin_frame(api.userdata, frame.viewport_w, frame.viewport_h)

    local function apply_current_scissor()
        local sc = current_scissor_gl(scissor_stack, viewport_h)
        if sc then
            api.apply_scissor(api.userdata, true, sc.x, sc.y, sc.w, sc.h)
        else
            api.apply_scissor(api.userdata, false, 0, 0, 0, 0)
        end
        return sc
    end

    for _, p in ipairs(packets) do
        if p.kind == "scissor" then
            batch = flush_batch(frame, api, batch)
            if p.cmd.is_begin then
                scissor_stack[#scissor_stack + 1] = p.cmd
            else
                scissor_stack[#scissor_stack] = nil
            end
            apply_current_scissor()
        else
            local cur_sc = current_scissor_gl(scissor_stack, viewport_h)
            local contiguous = batch
                and batch.kind == p.kind
                and batch.first + batch.count == p.stream_index
                and scissor_equal(batch.scissor, cur_sc)
            if contiguous then
                batch.count = batch.count + 1
            else
                batch = flush_batch(frame, api, batch)
                batch = {
                    kind = p.kind,
                    first = p.stream_index,
                    count = 1,
                    scissor = cur_sc,
                }
            end
        end
    end

    batch = flush_batch(frame, api, batch)
    api.end_frame(api.userdata)
    return packets
end

return M
