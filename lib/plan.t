-- lib/plan.t
-- Public API for Bound → Plan phase.

local TerraUI = require("lib/terraui_schema")
local M = require("src/plan")(TerraUI.types)
return M
