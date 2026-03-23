-- tools/build_component.t
-- Build CLI: compile a TerraUI component to .so + .h + _ffi.lua
--
-- Usage:
--   terraui-build <source> [options]
--
-- Can be invoked from any directory:
--   terra /path/to/terraui/tools/build_component.t my_ui.t --output build/
--
-- The tool auto-detects the TerraUI root from its own location so
-- require("lib/...") always works regardless of cwd.
--
-- The source file must return a Decl.Component value.
--
-- Options:
--   --prefix NAME   C symbol prefix for exports (default: component name)
--   --output DIR    Output directory (default: directory of source file)
--   --so-name NAME  Override shared library filename (default: <prefix>.so)
--   -q, --quiet     Suppress progress output

---------------------------------------------------------------------------
-- Bootstrap: resolve TerraUI root from this script's location
---------------------------------------------------------------------------

local script_path = debug.getinfo(1, "S").source:match("^@(.+)$") or arg[-1] or "tools/build_component.t"

local function dirname(path)
    local dir = path:match("^(.*)/[^/]+$")
    return dir or "."
end

local function resolve(path)
    -- Collapse ., .., and // in a path
    local parts = {}
    for seg in path:gmatch("[^/]+") do
        if seg == ".." and #parts > 0 and parts[#parts] ~= ".." then
            parts[#parts] = nil
        elseif seg ~= "." then
            parts[#parts + 1] = seg
        end
    end
    local result = table.concat(parts, "/")
    if path:sub(1, 1) == "/" then result = "/" .. result end
    return result
end

local function abspath(path)
    if path:sub(1, 1) == "/" then return resolve(path) end
    local cwd = io.popen("pwd -P"):read("*l")
    return resolve(cwd .. "/" .. path)
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local tools_dir = dirname(abspath(script_path))
local terraui_root = dirname(tools_dir)

-- Inject TerraUI root into package.terrapath and package.path so
-- require("lib/...") works from any cwd.
local root_pattern = terraui_root .. "/?.t"
if not package.terrapath:find(terraui_root, 1, true) then
    package.terrapath = root_pattern .. ";" .. package.terrapath
end
local lua_pattern = terraui_root .. "/?.lua;" .. terraui_root .. "/?/init.lua"
if not package.path:find(terraui_root, 1, true) then
    package.path = lua_pattern .. ";" .. package.path
end

---------------------------------------------------------------------------
-- Now safe to require TerraUI modules
---------------------------------------------------------------------------

local terraui = require("lib/terraui")
local TerraUI = require("lib/terraui_schema")
local Decl = TerraUI.types.Decl
local bind = require("lib/bind")
local plan = require("lib/plan")
local compile = require("lib/compile")
local emit_header = require("lib/emit_header")

---------------------------------------------------------------------------
-- Argument parsing
---------------------------------------------------------------------------

local source_path = nil
local prefix = nil
local output_dir = nil
local so_name_override = nil
local quiet = false

local i = 1
while arg and arg[i] do
    local a = arg[i]
    if a == "--prefix" then
        i = i + 1; prefix = assert(arg[i], "--prefix requires a value")
    elseif a == "--output" or a == "-o" then
        i = i + 1; output_dir = assert(arg[i], "--output requires a value")
    elseif a == "--so-name" then
        i = i + 1; so_name_override = assert(arg[i], "--so-name requires a value")
    elseif a == "--quiet" or a == "-q" then
        quiet = true
    elseif a == "--help" or a == "-h" then
        io.stdout:write([[
terraui-build — compile a TerraUI component to a shared library

Usage:
  terra ]] .. script_path .. [[ <source> [options]

The source file must return a Decl.Component. It is loaded in a Terra
context with the TerraUI DSL available via require("lib/terraui").

Options:
  --prefix NAME     C symbol prefix (default: component name)
  --output DIR      Output directory (default: source file's directory)
  --so-name NAME    Override .so filename (default: <prefix>.so)
  -q, --quiet       Suppress progress output
  -h, --help        Show this help

Outputs:
  <prefix>.so       Shared library  — <prefix>_init() and <prefix>_run()
  <prefix>.h        C header        — struct definitions for C/C++ consumers
  <prefix>_ffi.lua  LuaJIT helper   — require() and go from LuaJIT / Love2D

Examples:
  # Build from project root
  terra tools/build_component.t examples/love2d/ui_def.t

  # Build from anywhere, output to a specific directory
  terra ]] .. terraui_root .. [[/tools/build_component.t \
      my_game/ui/hud.t --prefix hud --output my_game/build

  # Use in a Makefile
  TERRAUI := /path/to/terraui
  build/hud.so: ui/hud.t
  	terra $(TERRAUI)/tools/build_component.t $< --prefix hud -o build
]])
        os.exit(0)
    elseif a:sub(1, 1) == "-" then
        io.stderr:write("Unknown option: " .. a .. "\n")
        io.stderr:write("Run with --help for usage.\n")
        os.exit(1)
    elseif source_path == nil then
        source_path = a
    else
        io.stderr:write("Unexpected argument: " .. a .. "\n")
        io.stderr:write("Run with --help for usage.\n")
        os.exit(1)
    end
    i = i + 1
end

if source_path == nil then
    io.stderr:write("Error: no source file specified.\n")
    io.stderr:write("Run with --help for usage.\n")
    os.exit(1)
end

---------------------------------------------------------------------------
-- Resolve paths
---------------------------------------------------------------------------

local source_abs = abspath(source_path)
local source_dir = dirname(source_abs)

if not file_exists(source_abs) then
    io.stderr:write("Error: source file not found: " .. source_abs .. "\n")
    os.exit(1)
end

-- Default output directory = same directory as the source file
if output_dir == nil then
    output_dir = source_dir
else
    output_dir = abspath(output_dir)
end

-- Inject source file's directory into package path so the source can
-- require() sibling modules (e.g. shared widget libraries).
local source_terra_pat = source_dir .. "/?.t"
local source_lua_pat = source_dir .. "/?.lua"
if not package.terrapath:find(source_dir, 1, true) then
    package.terrapath = source_terra_pat .. ";" .. package.terrapath
end
if not package.path:find(source_dir, 1, true) then
    package.path = source_lua_pat .. ";" .. package.path
end

local function log(...)
    if not quiet then print(...) end
end

---------------------------------------------------------------------------
-- Load the component definition
---------------------------------------------------------------------------

log(string.format("Loading %s", source_abs))
local decl, load_err = dofile(source_abs)
if decl == nil then
    io.stderr:write("Error: source file returned nil.\n")
    if load_err then io.stderr:write("  " .. tostring(load_err) .. "\n") end
    io.stderr:write("  The file must return a Decl.Component value.\n")
    os.exit(1)
end

if type(decl) ~= "table" or not Decl.Component:isclassof(decl) then
    io.stderr:write("Error: source file must return a Decl.Component.\n")
    io.stderr:write("  Got: " .. tostring(decl) .. "\n")
    os.exit(1)
end

if prefix == nil then
    -- Sanitize component name for use as a C identifier
    prefix = decl.name:gsub("[^%w_]", "_"):gsub("^(%d)", "_%1")
end

log(string.format("  component: %s", decl.name))
log(string.format("  prefix:    %s", prefix))
log(string.format("  output:    %s", output_dir))

---------------------------------------------------------------------------
-- Compile
---------------------------------------------------------------------------

log("  compiling ...")

local t0 = os.clock()
local bound = bind.bind_component(decl)
local planned = plan.plan_component(bound)
local kernel = compile.compile_component(planned)
local compile_ms = (os.clock() - t0) * 1000

local Frame = kernel:frame_type()
local init_fn = kernel.kernels.init_fn
local run_fn = kernel.kernels.run_fn

local terra init_wrapper(frame: &Frame) [init_fn](frame) end
local terra run_wrapper(frame: &Frame) [run_fn](frame) end

---------------------------------------------------------------------------
-- Ensure output directory exists
---------------------------------------------------------------------------

os.execute('mkdir -p "' .. output_dir .. '"')

---------------------------------------------------------------------------
-- Export .so
---------------------------------------------------------------------------

local so_name = so_name_override or (prefix .. ".so")
local so_path = output_dir .. "/" .. so_name
local symbols = {}
symbols[prefix .. "_init"] = init_wrapper
symbols[prefix .. "_run"] = run_wrapper

log(string.format("  writing %s", so_path))
terralib.saveobj(so_path, "sharedlibrary", symbols)

---------------------------------------------------------------------------
-- Export .h
---------------------------------------------------------------------------

local h_path = output_dir .. "/" .. prefix .. ".h"
local h_content = emit_header.emit_c_header(prefix, bound.key, planned)

log(string.format("  writing %s", h_path))
local f = assert(io.open(h_path, "w"))
f:write(h_content)
f:close()

---------------------------------------------------------------------------
-- Export _ffi.lua
---------------------------------------------------------------------------

local ffi_cdef = emit_header.emit_ffi_cdef(prefix, bound.key, planned)

-- The FFI loader locates the .so relative to its own file, so it works
-- regardless of the consumer's cwd.
local ffi_lua = {}

ffi_lua[#ffi_lua + 1] = string.format("-- %s_ffi.lua  (auto-generated by terraui-build)", prefix)
ffi_lua[#ffi_lua + 1] = string.format("-- LuaJIT FFI bindings for TerraUI component %q", decl.name)
ffi_lua[#ffi_lua + 1] = "--"
ffi_lua[#ffi_lua + 1] = "-- Usage:"
ffi_lua[#ffi_lua + 1] = string.format("--   local ui = require(%q)", prefix .. "_ffi")
ffi_lua[#ffi_lua + 1] = "--   local frame = ui.new_frame()"
ffi_lua[#ffi_lua + 1] = "--   ui.init(frame)"
ffi_lua[#ffi_lua + 1] = "--   frame.viewport_w, frame.viewport_h = 1280, 720"
ffi_lua[#ffi_lua + 1] = "--   ui.run(frame)"
ffi_lua[#ffi_lua + 1] = ""
ffi_lua[#ffi_lua + 1] = 'local ffi = require("ffi")'
ffi_lua[#ffi_lua + 1] = ""
ffi_lua[#ffi_lua + 1] = "ffi.cdef [[\n" .. ffi_cdef .. "]]"
ffi_lua[#ffi_lua + 1] = ""

-- Locate the .so next to this file.  Works under plain LuaJIT (debug.getinfo
-- gives us the full filesystem path) and under Love2D (where the source is
-- just the module name, so we fall back to love.filesystem.getSource()).
ffi_lua[#ffi_lua + 1] = "local function find_lib(name)"
ffi_lua[#ffi_lua + 1] = '    local info = debug.getinfo(1, "S")'
ffi_lua[#ffi_lua + 1] = '    local src  = info and info.source:match("^@(.+)$")'
ffi_lua[#ffi_lua + 1] = '    if src then'
ffi_lua[#ffi_lua + 1] = '        local dir = src:match("^(.*)/[^/]+$")'
ffi_lua[#ffi_lua + 1] = '        if dir then return dir .. "/" .. name end'
ffi_lua[#ffi_lua + 1] = '    end'
ffi_lua[#ffi_lua + 1] = '    if love and love.filesystem then'
ffi_lua[#ffi_lua + 1] = '        local base = love.filesystem.getSource()'
ffi_lua[#ffi_lua + 1] = '        if base and base ~= "" then return base .. "/" .. name end'
ffi_lua[#ffi_lua + 1] = '    end'
ffi_lua[#ffi_lua + 1] = '    return "./" .. name'
ffi_lua[#ffi_lua + 1] = "end"
ffi_lua[#ffi_lua + 1] = ""
ffi_lua[#ffi_lua + 1] = string.format("local lib = ffi.load(find_lib(%q))", so_name)
ffi_lua[#ffi_lua + 1] = ""
ffi_lua[#ffi_lua + 1] = "local M = {}"
ffi_lua[#ffi_lua + 1] = ""
ffi_lua[#ffi_lua + 1] = string.format("M.prefix     = %q", prefix)
ffi_lua[#ffi_lua + 1] = string.format("M.name       = %q", decl.name)
ffi_lua[#ffi_lua + 1] = string.format("M.node_count = %d", #planned.nodes)
ffi_lua[#ffi_lua + 1] = string.format("M.frame_size = %d", terralib.sizeof(Frame))
ffi_lua[#ffi_lua + 1] = "M.lib        = lib"
ffi_lua[#ffi_lua + 1] = ""

-- new_frame / init / run
ffi_lua[#ffi_lua + 1] = "function M.new_frame()"
ffi_lua[#ffi_lua + 1] = string.format('    return ffi.new("%s_Frame")', prefix)
ffi_lua[#ffi_lua + 1] = "end"
ffi_lua[#ffi_lua + 1] = ""
ffi_lua[#ffi_lua + 1] = "function M.init(frame)"
ffi_lua[#ffi_lua + 1] = string.format("    lib.%s_init(frame)", prefix)
ffi_lua[#ffi_lua + 1] = "end"
ffi_lua[#ffi_lua + 1] = ""
ffi_lua[#ffi_lua + 1] = "function M.run(frame)"
ffi_lua[#ffi_lua + 1] = string.format("    lib.%s_run(frame)", prefix)
ffi_lua[#ffi_lua + 1] = "end"
ffi_lua[#ffi_lua + 1] = ""

-- Param helpers
if #bound.key.params > 0 then
    ffi_lua[#ffi_lua + 1] = "--- Param slot mapping  { name = field_name }"
    ffi_lua[#ffi_lua + 1] = "M.params = {"
    for _, p in ipairs(bound.key.params) do
        ffi_lua[#ffi_lua + 1] = string.format('    [%q] = "p%d",', p.name, p.slot)
    end
    ffi_lua[#ffi_lua + 1] = "}"
    ffi_lua[#ffi_lua + 1] = ""
    ffi_lua[#ffi_lua + 1] = "--- Set a param by name.  ui.set_param(frame, 'title', 'Hello')"
    ffi_lua[#ffi_lua + 1] = "function M.set_param(frame, name, value)"
    ffi_lua[#ffi_lua + 1] = "    local field = M.params[name]"
    ffi_lua[#ffi_lua + 1] = '    if not field then error("unknown param: " .. tostring(name)) end'
    ffi_lua[#ffi_lua + 1] = "    frame.params[field] = value"
    ffi_lua[#ffi_lua + 1] = "end"
    ffi_lua[#ffi_lua + 1] = ""
    ffi_lua[#ffi_lua + 1] = "--- Get a param by name."
    ffi_lua[#ffi_lua + 1] = "function M.get_param(frame, name)"
    ffi_lua[#ffi_lua + 1] = "    local field = M.params[name]"
    ffi_lua[#ffi_lua + 1] = '    if not field then error("unknown param: " .. tostring(name)) end'
    ffi_lua[#ffi_lua + 1] = "    return frame.params[field]"
    ffi_lua[#ffi_lua + 1] = "end"
    ffi_lua[#ffi_lua + 1] = ""
end

ffi_lua[#ffi_lua + 1] = "return M"
ffi_lua[#ffi_lua + 1] = ""

local ffi_path = output_dir .. "/" .. prefix .. "_ffi.lua"
log(string.format("  writing %s", ffi_path))
local f2 = assert(io.open(ffi_path, "w"))
f2:write(table.concat(ffi_lua, "\n"))
f2:close()

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------

local node_count = #planned.nodes
local rect_cap, border_cap = 0, 0
for _, p in ipairs(planned.paints) do
    if p.background then rect_cap = rect_cap + 1 end
    if p.border then border_cap = border_cap + 1 end
end

log("")
log(string.format("  ✓ %s  (%d nodes, %d rects, %d borders, %d texts, %d images)",
    decl.name, node_count, rect_cap, border_cap, #planned.texts, #planned.images))
log(string.format("    frame: %d bytes (%.1f KB)  compile: %.0f ms",
    terralib.sizeof(Frame), terralib.sizeof(Frame) / 1024.0, compile_ms))
log(string.format("    %s", so_path))
log(string.format("    %s", h_path))
log(string.format("    %s", ffi_path))
