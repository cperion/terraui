import "lib/schema"

local function is_bind_ctx(v)
    return type(v) == "table" and v.__bind_ctx == true
end

local schema Demo
    extern BindCtx = is_bind_ctx

    phase Decl
        flags Axis
            Row
            Column
        end

        record Node
            id: string
            axis: Axis
            children: Node*
        unique
        end

        enum Size
            Fit { min: number?, max: number? }
            Fixed { value: number }
        end

        methods
            Node:bind(ctx: BindCtx) -> Bound.Node
            Size:bind(ctx: BindCtx) -> Bound.Size
        end
    end

    phase Bound
        record Node
            id: string
        end

        record Size
            value: number
        end
    end
end

assert(Demo.name == "Demo")
assert(#Demo.phases == 2)
assert(Demo.phases[1] == "Decl")
assert(Demo.phases[2] == "Bound")
assert(#Demo.methods == 2)
assert(Demo.methods[1].receiver == "Decl.Node")
assert(Demo.methods[1].return_type == "Bound.Node")
assert(Demo.methods[2].receiver == "Decl.Size")
assert(Demo.methods[2].return_type == "Bound.Size")

assert(Demo.asdl:find("module Decl", 1, true) ~= nil)
assert(Demo.asdl:find("Node = %(string id, Axis axis, Node%* children%) unique") ~= nil)
assert(Demo.asdl:find("Size = Fit%(number%? min, number%? max%)") ~= nil)

local empty_children = terralib.newlist()
local node1 = Demo.types.Decl.Node("root", Demo.types.Decl.Row, empty_children)
local node2 = Demo.types.Decl.Node("root", Demo.types.Decl.Row, terralib.newlist())
assert(node1 == node2)
assert(Demo.types.Decl.Node:isclassof(node1))
assert(Demo.types.Decl.Axis:isclassof(Demo.types.Decl.Row))

local size = Demo.types.Decl.Fixed(42)
assert(Demo.types.Decl.Size:isclassof(size))
assert(size.value == 42)

print("schema smoke test passed")
