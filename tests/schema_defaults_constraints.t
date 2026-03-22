import "lib/schema"

local seed = 7

local schema DefaultsDemo
    phase Decl
        record Config
            a: number = seed
            b: number = 2 where 0 <= b <= 10
            c: string = "ok"
        end

        enum Boxed
            Box { amount: number = 5 where 0 <= amount <= 10, label: string = "box" }
            Empty
        end
    end
end

local Config = DefaultsDemo.types.Decl.Config
local Box = DefaultsDemo.types.Decl.Box

local cfg1 = Config()
assert(cfg1.a == 7)
assert(cfg1.b == 2)
assert(cfg1.c == "ok")

local cfg2 = Config(nil, 9, nil)
assert(cfg2.a == 7)
assert(cfg2.b == 9)
assert(cfg2.c == "ok")

local box1 = Box()
assert(box1.amount == 5)
assert(box1.label == "box")

local box2 = Box(9, "crate")
assert(box2.amount == 9)
assert(box2.label == "crate")

local ok1, err1 = pcall(function()
    Config(1, 99, "bad")
end)
assert(not ok1)
assert(err1:match("constraint failed for Decl%.Config%.b"))

local ok2, err2 = pcall(function()
    Box(-1, "bad")
end)
assert(not ok2)
assert(err2:match("constraint failed for Decl%.Box.amount"))

print("schema defaults/constraints test passed")
