-- lib/opengl_backend.t
-- OpenGL-oriented backend skeleton built on top of the CPU presenter.
--
-- This module does not require a live GL context. Instead it translates
-- merged packets into a replay/batching protocol that a real GL layer can
-- implement. Tests can provide mock callbacks.

local presenter = require("lib/presenter")

local M = {}

local function clone_cmd(cmd)
    local out = {}
    for k, v in pairs(cmd) do out[k] = v end
    return out
end

local function scissor_to_gl(rect, viewport_h)
    if rect == nil then return nil end
    local x0 = math.floor(rect.x0)
    local x1 = math.ceil(rect.x1)
    local y0 = math.floor(viewport_h - rect.y1)
    local y1 = math.ceil(viewport_h - rect.y0)
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

M.scissor_to_gl = scissor_to_gl

local function flush_batch(batch, callbacks, font_backend, viewport_h)
    if not batch or #batch.cmds == 0 then return nil end

    local kind = batch.kind
    local current_scissor = batch.scissor and scissor_to_gl(batch.scissor, viewport_h) or nil

    if kind == "text" and font_backend and font_backend.shape_text_cmds then
        batch.shaped = font_backend.shape_text_cmds(batch.cmds)
    end

    if callbacks.apply_scissor then
        callbacks.apply_scissor(current_scissor)
    end

    local fn = callbacks["draw_" .. kind .. "_batch"]
    if fn then
        fn(batch.cmds, current_scissor, batch)
    elseif kind == "custom" and callbacks.draw_custom then
        for _, cmd in ipairs(batch.cmds) do
            callbacks.draw_custom(cmd, current_scissor, batch)
        end
    end

    return nil
end

function M.present(frame, opts)
    opts = opts or {}
    local callbacks = opts.callbacks or {}
    local font_backend = opts.font_backend
    local viewport_h = assert(opts.viewport_h or tonumber(frame.viewport_h),
        "viewport_h required for GL scissor conversion")

    if callbacks.begin_frame then callbacks.begin_frame(frame) end

    local packets = presenter.collect_packets(frame)
    local scissor_stack = {}
    local current_batch = nil

    local function current_scissor()
        return scissor_stack[#scissor_stack]
    end

    local function same_scissor(a, b)
        if a == nil and b == nil then return true end
        if a == nil or b == nil then return false end
        return a.x0 == b.x0 and a.y0 == b.y0 and a.x1 == b.x1 and a.y1 == b.y1
    end

    local function ensure_batch(kind, scissor)
        if current_batch
           and current_batch.kind == kind
           and same_scissor(current_batch.scissor, scissor)
        then
            return current_batch
        end
        current_batch = flush_batch(current_batch, callbacks, font_backend, viewport_h)
        current_batch = { kind = kind, scissor = scissor and clone_cmd(scissor) or nil, cmds = {} }
        return current_batch
    end

    for _, p in ipairs(packets) do
        if p.kind == "scissor" then
            current_batch = flush_batch(current_batch, callbacks, font_backend, viewport_h)
            if p.cmd.is_begin then
                scissor_stack[#scissor_stack + 1] = p.cmd
            else
                scissor_stack[#scissor_stack] = nil
            end
            local sc = current_scissor()
            if callbacks.apply_scissor then
                callbacks.apply_scissor(sc and scissor_to_gl(sc, viewport_h) or nil)
            end
            if callbacks.on_scissor_packet then
                callbacks.on_scissor_packet(p.cmd, sc and scissor_to_gl(sc, viewport_h) or nil, p)
            end
        elseif p.kind == "custom" then
            current_batch = flush_batch(current_batch, callbacks, font_backend, viewport_h)
            local b = ensure_batch("custom", current_scissor())
            b.cmds[#b.cmds + 1] = p.cmd
            current_batch = flush_batch(current_batch, callbacks, font_backend, viewport_h)
        else
            local b = ensure_batch(p.kind, current_scissor())
            b.cmds[#b.cmds + 1] = p.cmd
        end
    end

    current_batch = flush_batch(current_batch, callbacks, font_backend, viewport_h)

    if callbacks.end_frame then callbacks.end_frame(frame) end
    return packets
end

return M
