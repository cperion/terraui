local function expect_parse_error(src, pattern)
    local fn, err = terralib.loadstring(src)
    assert(fn == nil, "expected parse error")
    if not err:match(pattern) then
        error(("expected error matching %q, got:\n%s"):format(pattern, err))
    end
end

expect_parse_error([[
import "lib/schema"
local schema Bad
    phase Decl
        record Node
            child: Missing
        end
    end
end
]], "unknown type 'Decl%.Missing'")

expect_parse_error([[
import "lib/schema"
local schema Bad
    phase Decl
        enum Only
            One {}
        end
    end
end
]], "must have at least 2 variants")

expect_parse_error([[
import "lib/schema"
local schema Bad
    phase Decl
        record R
            a: number where 0 <= missing <= 1
        end
    end
end
]], "constraint for 'Decl%.R%.a' references unknown field 'missing'")

expect_parse_error([[
import "lib/schema"
local schema Bad
    doc = "schema doc"
    phase Decl
        doc = "phase doc"
        record R
            a: number
        end
    end
end
]], "record 'Decl%.R' must declare non%-empty doc")

expect_parse_error([[
import "lib/schema"
local schema Bad
    note = "legacy"
    phase Decl
        record R
            a: number
        end
    end
end
]], "expected doc, extern, phase, hooks, or end inside schema")

expect_parse_error([[
import "lib/schema"
local schema Bad
    doc = "schema doc"
    hooks X
        doc = "hooks doc"
        methodmissing
            doc = "bad"
            impl = function() end
        end
    end
end
]], "hook 'methodmissing' in hooks 'X' must declare macro")

expect_parse_error([[
import "lib/schema"
local schema Bad
    phase Source
        record Node
            id: string
        end
        methods
            Node:lower() -> Lowered.Node
        end
    end
    phase Lowered
        record Node
            id: string
        end
        methods
            Node:raise() -> Source.Node
        end
    end
end
]], "returns earlier%-phase type 'Source%.Node'")

print("schema validation test passed")
