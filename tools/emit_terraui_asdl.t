local TerraUI = require("lib/terraui_schema")

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then
        return nil, err
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_all(path, data)
    local f, err = io.open(path, "wb")
    if not f then
        error(("failed to open '%s' for writing: %s"):format(path, tostring(err)))
    end
    f:write(data)
    f:close()
end

local function usage()
    io.stderr:write([[
usage:
  terra tools/emit_terraui_asdl.t              # print emitted ASDL to stdout
  terra tools/emit_terraui_asdl.t OUTFILE      # write emitted ASDL to OUTFILE
  terra tools/emit_terraui_asdl.t --check FILE # compare emitted ASDL with FILE
]])
end

local emitted = TerraUI.asdl
local argv = rawget(_G, "arg") or {}

if argv[1] == "-h" or argv[1] == "--help" then
    usage()
    os.exit(0)
elseif argv[1] == "--check" then
    local path = argv[2]
    if not path then
        usage()
        error("missing FILE after --check")
    end
    local existing, err = read_all(path)
    if not existing then
        error(("failed to read '%s': %s"):format(path, tostring(err)))
    end
    if existing == emitted then
        io.stdout:write(("OK %s matches emitted TerraUI ASDL\n"):format(path))
        os.exit(0)
    end
    io.stderr:write(("MISMATCH %s does not match emitted TerraUI ASDL\n"):format(path))
    os.exit(1)
elseif argv[1] and argv[1] ~= "-" then
    write_all(argv[1], emitted)
    io.stdout:write(("wrote %s\n"):format(argv[1]))
else
    io.stdout:write(emitted)
end
