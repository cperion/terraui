terralib.linklibrary("/lib64/libSDL3.so")
terralib.linklibrary("/lib64/libSDL3_ttf.so")
terralib.linklibrary("/lib64/libGL.so")

local ffi = require("ffi")

local saved_saveobj = terralib.saveobj
local saved_print = print
local captured

local runtime_args = {}
local build_font = nil
local i = 1
while arg and i <= #arg do
    if arg[i] == "--font" then
        assert(i + 1 <= #arg, "--font requires a path")
        build_font = arg[i + 1]
        i = i + 2
    else
        runtime_args[#runtime_args + 1] = arg[i]
        i = i + 1
    end
end

local build_args = { "/tmp/terraui_direct_demo_ignored" }
if build_font ~= nil then
    build_args[#build_args + 1] = build_font
end

terralib.saveobj = function(path, kind, exports, link_flags)
    captured = {
        path = path,
        kind = kind,
        exports = exports,
        link_flags = link_flags,
    }
end
print = function(...) end

local old_arg = arg
arg = build_args
package.loaded["examples.build_sdl_gl_demo"] = nil
require("examples.build_sdl_gl_demo")
arg = old_arg

terralib.saveobj = saved_saveobj
print = saved_print

assert(captured and captured.exports and captured.exports.main,
    "failed to capture demo main from examples/build_sdl_gl_demo.t")

local argv_lua = { "terraui-direct-demo" }
for _, a in ipairs(runtime_args) do
    argv_lua[#argv_lua + 1] = a
end

local argv = ffi.new("char *[?]", #argv_lua)
for j, s in ipairs(argv_lua) do
    argv[j - 1] = ffi.cast("char *", s)
end

local rc = captured.exports.main(#argv_lua, argv)
assert(rc == 0, string.format("direct demo exited with code %d", tonumber(rc)))
