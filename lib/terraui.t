-- lib/terraui.t
-- Public TerraUI entrypoint.

local schema = require("lib/terraui_schema")
local bind = require("lib/bind")
local plan = require("lib/plan")
local compile = require("lib/compile")
local dsl = require("lib/dsl")
local presenter = require("lib/presenter")
local opengl_backend = require("lib/opengl_backend")
local direct_c_backend = require("lib/direct_c_backend")

local plan_registry = {}

local compile_plan_memo = terralib.memoize(function(sig)
    local entry = assert(plan_registry[sig], "missing plan for specialization key")
    return compile.compile_component(entry.plan_component, entry.compile_opts)
end)

local M = {}

M.schema = schema
M.types = schema.types
M.dsl = dsl.dsl
M.presenter = presenter
M.opengl_backend = opengl_backend
M.direct_c_backend = direct_c_backend

function M.bind(decl_component, opts)
    return bind.bind_component(decl_component, opts)
end

function M.plan(bound_component)
    return plan.plan_component(bound_component)
end

local function compile_sig(plan_component, opts)
    return tostring(plan_component.key) .. "|text=" .. compile.text_measurer_key(opts and opts.text_measurer)
end

function M.compile_plan(plan_component, opts)
    local sig = compile_sig(plan_component, opts)
    plan_registry[sig] = { plan_component = plan_component, compile_opts = opts }
    return compile_plan_memo(sig)
end

function M.compile(decl_component, opts)
    local bound_component = bind.bind_component(decl_component, opts)
    local plan_component = plan.plan_component(bound_component)
    local sig = compile_sig(plan_component, opts)
    plan_registry[sig] = { plan_component = plan_component, compile_opts = opts }
    return compile_plan_memo(sig)
end

return M
