-- lib/bind.t
-- Public API for Decl → Bound phase.

local TerraUI = require("lib/terraui_schema")
local M = require("src/bind")(TerraUI.types)
return M
