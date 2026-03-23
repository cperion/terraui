-- lib/emit_header.t
-- Emit a C header + FFI cdef string for a compiled TerraUI kernel.
-- Used by the build CLI to produce .h files alongside .so exports.

local TerraUI = require("lib/terraui_schema")
local Decl = TerraUI.types.Decl
local compile = require("lib/compile")

local M = {}

local function vtype_to_c(vt)
    if     vt == Decl.TBool   then return "bool"
    elseif vt == Decl.TNumber then return "float"
    elseif vt == Decl.TString then return "const char *"
    elseif vt == Decl.TColor  then return "TerraUI_Color"
    elseif vt == Decl.TImage  then return "const char *"
    elseif vt == Decl.TVec2   then return "TerraUI_Vec2"
    elseif vt == Decl.TAny    then return "void *"
    else error("unknown ValueType for C emission") end
end

local shared_types_c = [[
#include <stdint.h>
#include <stdbool.h>

typedef struct TerraUI_Color { float r, g, b, a; } TerraUI_Color;
typedef struct TerraUI_Vec2  { float x, y; } TerraUI_Vec2;

typedef struct TerraUI_NodeState {
    float x, y, w, h;
    float content_x, content_y, content_w, content_h;
    float content_extent_w, content_extent_h;
    float scroll_x, scroll_y;
    bool scroll_need_x, scroll_need_y;
    float want_w, want_h;
    float clip_x0, clip_y0, clip_x1, clip_y1;
    bool visible;
    bool enabled;
} TerraUI_NodeState;

typedef struct TerraUI_InputState {
    float mouse_x, mouse_y;
    bool mouse_down, mouse_pressed, mouse_released;
    float wheel_dx, wheel_dy;
} TerraUI_InputState;

typedef struct TerraUI_HitState {
    int32_t hot, active, focus;
    float active_offset_x, active_offset_y;
} TerraUI_HitState;

typedef struct TerraUI_RectCmd {
    float x, y, w, h;
    TerraUI_Color color;
    float opacity;
    float z;
    uint32_t seq;
} TerraUI_RectCmd;

typedef struct TerraUI_BorderCmd {
    float x, y, w, h;
    float left, top, right, bottom;
    TerraUI_Color color;
    float opacity;
    float z;
    uint32_t seq;
} TerraUI_BorderCmd;

typedef struct TerraUI_TextCmd {
    float x, y, w, h;
    const char *text;
    const char *font_id;
    float font_size;
    float letter_spacing;
    float line_height;
    int32_t wrap;
    int32_t align;
    TerraUI_Color color;
    float z;
    uint32_t seq;
} TerraUI_TextCmd;

typedef struct TerraUI_ImageCmd {
    float x, y, w, h;
    const char *image_id;
    TerraUI_Color tint;
    float z;
    uint32_t seq;
} TerraUI_ImageCmd;

typedef struct TerraUI_ScissorCmd {
    bool is_begin;
    float x0, y0, x1, y1;
    float z;
    uint32_t seq;
} TerraUI_ScissorCmd;

typedef struct TerraUI_CustomCmd {
    float x, y, w, h;
    const char *kind;
    float z;
    uint32_t seq;
} TerraUI_CustomCmd;
]]

-- Same types but for LuaJIT FFI cdef (no #include, no typedef prefix needed)
local shared_types_ffi = [[
typedef struct { float r, g, b, a; } TerraUI_Color;
typedef struct { float x, y; } TerraUI_Vec2;

typedef struct {
    float x, y, w, h;
    float content_x, content_y, content_w, content_h;
    float content_extent_w, content_extent_h;
    float scroll_x, scroll_y;
    bool scroll_need_x, scroll_need_y;
    float want_w, want_h;
    float clip_x0, clip_y0, clip_x1, clip_y1;
    bool visible;
    bool enabled;
} TerraUI_NodeState;

typedef struct {
    float mouse_x, mouse_y;
    bool mouse_down, mouse_pressed, mouse_released;
    float wheel_dx, wheel_dy;
} TerraUI_InputState;

typedef struct {
    int32_t hot, active, focus;
    float active_offset_x, active_offset_y;
} TerraUI_HitState;

typedef struct {
    float x, y, w, h;
    TerraUI_Color color;
    float opacity;
    float z;
    uint32_t seq;
} TerraUI_RectCmd;

typedef struct {
    float x, y, w, h;
    float left, top, right, bottom;
    TerraUI_Color color;
    float opacity;
    float z;
    uint32_t seq;
} TerraUI_BorderCmd;

typedef struct {
    float x, y, w, h;
    const char *text;
    const char *font_id;
    float font_size;
    float letter_spacing;
    float line_height;
    int32_t wrap;
    int32_t align;
    TerraUI_Color color;
    float z;
    uint32_t seq;
} TerraUI_TextCmd;

typedef struct {
    float x, y, w, h;
    const char *image_id;
    TerraUI_Color tint;
    float z;
    uint32_t seq;
} TerraUI_ImageCmd;

typedef struct {
    bool is_begin;
    float x0, y0, x1, y1;
    float z;
    uint32_t seq;
} TerraUI_ScissorCmd;

typedef struct {
    float x, y, w, h;
    const char *kind;
    float z;
    uint32_t seq;
} TerraUI_CustomCmd;
]]

local function emit_params_struct(prefix, key)
    local lines = {}
    lines[#lines + 1] = string.format("typedef struct %s_Params {", prefix)
    if #key.params == 0 then
        lines[#lines + 1] = "    uint8_t _pad;"
    else
        for _, p in ipairs(key.params) do
            lines[#lines + 1] = string.format("    %s p%d; /* %s */", vtype_to_c(p.ty), p.slot, p.name)
        end
    end
    lines[#lines + 1] = string.format("} %s_Params;", prefix)
    return table.concat(lines, "\n")
end

local function emit_state_struct(prefix, key)
    local lines = {}
    lines[#lines + 1] = string.format("typedef struct %s_State {", prefix)
    if #key.state == 0 then
        lines[#lines + 1] = "    uint8_t _pad;"
    else
        for _, s in ipairs(key.state) do
            lines[#lines + 1] = string.format("    %s s%d; /* %s */", vtype_to_c(s.ty), s.slot, s.name)
        end
    end
    lines[#lines + 1] = string.format("} %s_State;", prefix)
    return table.concat(lines, "\n")
end

local function emit_frame_struct(prefix, key, plan)
    local node_count = #plan.nodes
    local rect_cap = 0
    local border_cap = 0
    for _, p in ipairs(plan.paints) do
        if p.background then rect_cap = rect_cap + 1 end
        if p.border then border_cap = border_cap + 1 end
    end
    local text_cap = #plan.texts
    local image_cap = #plan.images
    local scissor_cap = #plan.clips * 2
    local custom_cap = #plan.customs

    local lines = {}
    lines[#lines + 1] = string.format("typedef struct %s_Frame {", prefix)
    lines[#lines + 1] = string.format("    %s_Params params;", prefix)
    lines[#lines + 1] = string.format("    %s_State state;", prefix)
    lines[#lines + 1] = string.format("    TerraUI_NodeState nodes[%d];", node_count)
    lines[#lines + 1] = "    TerraUI_InputState input;"
    lines[#lines + 1] = "    TerraUI_HitState hit;"
    lines[#lines + 1] = "    void *text_backend_state;"
    lines[#lines + 1] = "    float viewport_w;"
    lines[#lines + 1] = "    float viewport_h;"
    lines[#lines + 1] = "    uint32_t draw_seq;"
    lines[#lines + 1] = "    int32_t action_node;"
    lines[#lines + 1] = "    const char *action_name;"
    lines[#lines + 1] = "    const char *cursor_name;"
    lines[#lines + 1] = string.format("    TerraUI_RectCmd rects[%d];", math.max(rect_cap, 1))
    lines[#lines + 1] = "    int32_t rect_count;"
    lines[#lines + 1] = string.format("    TerraUI_BorderCmd borders[%d];", math.max(border_cap, 1))
    lines[#lines + 1] = "    int32_t border_count;"
    lines[#lines + 1] = string.format("    TerraUI_TextCmd texts[%d];", math.max(text_cap, 1))
    lines[#lines + 1] = "    int32_t text_count;"
    lines[#lines + 1] = string.format("    TerraUI_ImageCmd images[%d];", math.max(image_cap, 1))
    lines[#lines + 1] = "    int32_t image_count;"
    lines[#lines + 1] = string.format("    TerraUI_ScissorCmd scissors[%d];", math.max(scissor_cap, 1))
    lines[#lines + 1] = "    int32_t scissor_count;"
    lines[#lines + 1] = string.format("    TerraUI_CustomCmd customs[%d];", math.max(custom_cap, 1))
    lines[#lines + 1] = "    int32_t custom_count;"
    lines[#lines + 1] = string.format("} %s_Frame;", prefix)
    return table.concat(lines, "\n")
end

--- Emit a complete C header for a compiled component.
-- @param prefix  C symbol prefix (e.g. "MyPanel")
-- @param key     Bound.SpecializationKey
-- @param plan    Plan.Component
-- @return string  The full .h content
function M.emit_c_header(prefix, key, plan)
    local guard = string.upper(prefix) .. "_H"
    local parts = {}
    parts[#parts + 1] = string.format("#ifndef %s", guard)
    parts[#parts + 1] = string.format("#define %s", guard)
    parts[#parts + 1] = ""
    parts[#parts + 1] = "#ifdef __cplusplus"
    parts[#parts + 1] = 'extern "C" {'
    parts[#parts + 1] = "#endif"
    parts[#parts + 1] = ""
    parts[#parts + 1] = shared_types_c
    parts[#parts + 1] = emit_params_struct(prefix, key)
    parts[#parts + 1] = ""
    parts[#parts + 1] = emit_state_struct(prefix, key)
    parts[#parts + 1] = ""
    parts[#parts + 1] = emit_frame_struct(prefix, key, plan)
    parts[#parts + 1] = ""
    parts[#parts + 1] = string.format("void %s_init(%s_Frame *frame);", prefix, prefix)
    parts[#parts + 1] = string.format("void %s_run(%s_Frame *frame);", prefix, prefix)
    parts[#parts + 1] = ""
    parts[#parts + 1] = string.format("/* node_count = %d */", #plan.nodes)
    parts[#parts + 1] = ""
    -- Emit param name → slot mapping as comments
    if #key.params > 0 then
        parts[#parts + 1] = "/* Param slots:"
        for _, p in ipairs(key.params) do
            parts[#parts + 1] = string.format(" *   p%d = %s (%s)", p.slot, p.name, vtype_to_c(p.ty))
        end
        parts[#parts + 1] = " */"
        parts[#parts + 1] = ""
    end
    parts[#parts + 1] = "#ifdef __cplusplus"
    parts[#parts + 1] = "}"
    parts[#parts + 1] = "#endif"
    parts[#parts + 1] = ""
    parts[#parts + 1] = string.format("#endif /* %s */", guard)
    parts[#parts + 1] = ""
    return table.concat(parts, "\n")
end

--- Emit a LuaJIT FFI cdef string for a compiled component.
-- @param prefix  C symbol prefix (e.g. "MyPanel")
-- @param key     Bound.SpecializationKey
-- @param plan    Plan.Component
-- @return string  The FFI cdef content (pass to ffi.cdef)
function M.emit_ffi_cdef(prefix, key, plan)
    local parts = {}
    parts[#parts + 1] = shared_types_ffi
    parts[#parts + 1] = emit_params_struct(prefix, key)
    parts[#parts + 1] = ""
    parts[#parts + 1] = emit_state_struct(prefix, key)
    parts[#parts + 1] = ""
    parts[#parts + 1] = emit_frame_struct(prefix, key, plan)
    parts[#parts + 1] = ""
    parts[#parts + 1] = string.format("void %s_init(%s_Frame *frame);", prefix, prefix)
    parts[#parts + 1] = string.format("void %s_run(%s_Frame *frame);", prefix, prefix)
    parts[#parts + 1] = ""
    return table.concat(parts, "\n")
end

return M
