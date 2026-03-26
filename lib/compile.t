-- lib/compile.t
-- Public API for Plan → Kernel phase + runtime type exports.

local TerraUI = require("lib/terraui_schema")
local M = require("src/compile")(TerraUI.types)
return M
