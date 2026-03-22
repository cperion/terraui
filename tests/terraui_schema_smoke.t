local TerraUI = require("lib/terraui_schema")

assert(TerraUI.name == "TerraUI")
assert(#TerraUI.phases == 4)
assert(TerraUI.phases[1] == "Decl")
assert(TerraUI.phases[2] == "Bound")
assert(TerraUI.phases[3] == "Plan")
assert(TerraUI.phases[4] == "Kernel")

assert(TerraUI.asdl:find("module Decl", 1, true) ~= nil)
assert(TerraUI.asdl:find("module Bound", 1, true) ~= nil)
assert(TerraUI.asdl:find("module Plan", 1, true) ~= nil)
assert(TerraUI.asdl:find("module Kernel", 1, true) ~= nil)

local found_component_bind = false
local found_kernel_run = false
for _, method in ipairs(TerraUI.methods) do
    if method.receiver == "Decl.Component" and method.name == "bind" and method.return_type == "Bound.Component" then
        found_component_bind = true
    end
    if method.receiver == "Kernel.Component" and method.name == "run_quote" and method.return_type == "TerraQuote" then
        found_kernel_run = true
    end
end
assert(found_component_bind)
assert(found_kernel_run)

local Decl = TerraUI.types.Decl
local Bound = TerraUI.types.Bound
local Plan = TerraUI.types.Plan

local pad = Decl.Padding(Decl.NumLit(1), Decl.NumLit(2), Decl.NumLit(3), Decl.NumLit(4))
local visibility = Decl.Visibility(nil, nil)
local decor = Decl.Decor(nil, nil, nil, nil)
local input = Decl.Input(false, false, false, false, nil, nil)
local layout = Decl.Layout(Decl.Column, Decl.Grow(nil, nil), Decl.Grow(nil, nil), pad, Decl.NumLit(8), Decl.AlignLeft, Decl.AlignTop)
local node = Decl.Node(Decl.Stable("root"), visibility, layout, decor, nil, nil, input, nil, nil, terralib.newlist())
assert(Decl.Node:isclassof(node))
assert(Decl.Id:isclassof(node.id))

local resolved_id = Bound.ResolvedId("root", 0)
assert(Bound.ResolvedId:isclassof(resolved_id))

local binding = Plan.ConstNumber(42)
assert(Plan.Binding:isclassof(binding))
assert(binding.v == 42)

print("terraui schema smoke test passed")
