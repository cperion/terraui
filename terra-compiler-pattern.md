# The Terra Compiler Pattern

## What it is

A method for building domain-specific compilers in Terra using four facilities: ASDL for domain types, struct metamethods and macros for compile-time code generation hooks, `terralib.memoize` for caching compiled output, and an optional schema DSL that validates ASDL definitions as a Terra language extension. The pattern produces monomorphic native code from high-level domain descriptions, with zero infrastructure code written by the user.

This document describes the pattern precisely, grounded in the Terra API and the original exotypes paper (DeVito et al., PLDI 2014).


## Exotypes: the foundation

Everything in this pattern rests on one concept from the Terra paper: **exotypes** — user-defined types whose behavior and memory layout are defined *external* to Terra, using Lua property functions queried during typechecking.

Formally, an exotype is a tuple of functions:

```
(() → MemoryLayout) × (Op₀ → Quote) × ... × (Opₙ → Quote)
```

The first function computes the in-memory layout. The remaining functions describe the semantics when the type appears in a primitive operation (method invocation, binary operator, cast, field access, function application). Given an operation, the corresponding function returns a Quote — a concrete Terra expression implementing the operation. These functions are evaluated by the typechecker whenever it encounters an operation on the exotype.

This is not a dynamic dispatch mechanism. The property functions run **once during compilation**, not at runtime. The generated quotes are spliced into the compiled code. By the time the code executes, the property functions are gone. What remains is monomorphic machine code — the same code a C programmer would write by hand.

### Why exotypes matter for our pattern

The paper identifies the key insight: "Rather than define an object's behavior as a function that is evaluated at runtime, an exotype describes the behavior with a function that is evaluated once during a staged compilation step. These functions generate the code that implements the behavior of the object in the next stage rather than implementing the behavior directly."

This is exactly what we do with ASDL + metamethods. The ASDL tree describes the domain. The metamethods (which are exotype property functions) generate the implementation code. The quotes they return become the compiled output. The staging boundary is explicit: Lua decides, Terra executes.

### Lazy property evaluation and composability

The paper proves that exotype properties must be **lazily evaluated** for composability. Consider `Array(Tree)` where `Tree` contains an `Array(Tree)`. The layout of `Tree` depends on the layout of `Array(Tree)`. The methods of `Array(Tree)` depend on the methods of `Tree`. If we eagerly compute all properties of one type before the other, we create a false cycle.

Terra solves this by querying each property **only when needed** during typechecking. Properties are individual functions, evaluated independently. The compiler interleaves queries across types automatically. From the paper: "Lazily queried properties also make it possible to create types that have an unbounded number of behaviors" — which is why `__methodmissing` can respond to any method name, and why types built with `__methodmissing` compose with other exotype constructors like `Array(T)`.

This lazy evaluation is what makes `terralib.memoize` work as a type constructor. `Array = terralib.memoize(function(T) ... end)` returns a new exotype for each `T`. The exotype's properties (layout, methods) are defined as functions, not eagerly computed tables. When the compiler needs `Array(Tree).print`, it queries `Array(Tree).__getmethod("print")`, which queries `Tree.methods.print`, which is already defined. No cycle.

### Termination guarantee

The paper proves that property evaluation terminates if two conditions hold:

1. **Individual termination**: each property function, assuming its sub-queries return values, itself returns a value.
2. **Closed universe**: there are a finite number of unique properties that can be queried.

Under these conditions, the set of active property queries grows monotonically with each nested query. Since the universe is finite, either evaluation completes or a cycle is detected. Terra tracks active queries and throws an error on cycles.

In practice, `__methodmissing` can create an unbounded universe (infinite possible method names), so Terra caps the depth of property lookup and reports the query trace when the limit is reached. For our pattern, this rarely matters: ASDL types have a known set of methods, and `terralib.memoize` ensures each type constructor is called once per unique argument.

### `__methodmissing` is the central mechanism

The paper uses `__methodmissing` in every major example. It is not one metamethod among many — it is the primary mechanism through which exotypes achieve their expressiveness:

**Student2**: `__methodmissing` generates setter methods (`setname`, `setyear`) dynamically from the field list. The methods don't exist in the methods table — they are generated on first call during typechecking.

```lua
Student2.metamethods.__methodmissing = macro(function(name,self,arg)
    local field = string.match(name,"set(.*)")
    if field then return quote self.[field] = arg end end
    error("unknown method: "..name)
end)
```

**Objective-C wrapper**: `__methodmissing` forwards ANY method call to the Objective-C runtime. The type has an unbounded method set — every possible Objective-C selector is a valid method. Each is compiled on demand with the selector pre-computed at compile time.

```lua
ObjC.metamethods.__methodmissing = macro(function(sel,obj,...)
    local arguments = {...}
    local sel = C.sel_registerName(sanitizeSelector(sel,#arguments))
    return `ObjC { C.objc_msgSend([obj].handle,[sel],[arguments]) }
end)
```

**Array(T)**: `__methodmissing` implements the proxy pattern generically. For any method called on `Array(T)`, it generates a loop forwarding the call to each element. It does NOT need to know T's methods ahead of time.

```lua
ArrayImpl.metamethods.__methodmissing =
    macro(function(methodname,selfexp,...)
        local args = terralib.newlist{...}
        return quote
            var self = selfexp
            for i = 0,self.N do
                self.data[i]:[methodname]([args])
            end
        end
    end)
```

**Dynamic x86 assembler**: `__methodmissing` compiles assembly instructions on demand. `A:movlpd(RegR, addr)` triggers the generation of the encoding function for `movlpd` from the instruction table. Only instructions actually used are compiled. Furthermore, each call site gets a specialized version: constant arguments become part of a template, dynamic arguments are patched at runtime. This achieved 3–20× faster assembly than Google Chrome's hand-written assembler.

**Probabilistic programming**: `__apply` (the same concept applied to function application) wraps every function call with address stack management code. Each call site gets a unique ID at compile time — impossible without staging.

The composability proof in the paper depends on `__methodmissing` creating an unbounded method set that is resolved lazily. `Array(ObjC)` works because calling `windows:makeKeyAndOrderFront(nil)` triggers `Array.__methodmissing`, which generates a loop that calls `element:makeKeyAndOrderFront(nil)` on each element, which triggers `ObjC.__methodmissing`, which generates the Objective-C message send. Each query happens only when needed. If `Array` required all methods up front, the composition would fail because ObjC's method set is infinite.

This is the same mechanism we use throughout our pattern. In the MapLibre compiler, `__methodmissing` on `LayerRuntime` dispatches `layer:get_fill_color()` to either an inlined constant or a compiled zoom expression based on classification. In the UI library, `__methodmissing` could resolve property accessors by binding type (static vs. dynamic). In the BEM solver, `__methodmissing` on a surface struct could dispatch to the appropriate boundary condition evaluation. The mechanism is always the same: a macro that receives the method name as a string, inspects domain data (ASDL nodes, classification tables, spec metadata), and returns a quote.


### Properties should be functional

From the paper: "Since the writer of a property does not control when it is queried, it is a good idea to write property functions so that they will produce the same result regardless of when they are evaluated." Terra memoizes property queries to guarantee the same result on repeated calls. This means:

- Don't depend on mutable global state in property functions
- Don't depend on evaluation order between properties
- Don't query properties you don't need (to avoid creating false cycles)

These constraints align naturally with our pattern: ASDL methods are pure functions from ASDL nodes to Terra quotes. Metamethods are pure functions from type-checker queries to quotes. `terralib.memoize` is a pure cache. The only state is the ASDL tree itself, which is immutable once constructed.


## The four facilities

### ASDL

Ships with Terra as `require 'asdl'`. Creates Lua classes (metatables) from algebraic type definitions. Types are created inside a context via `context:Define(string)`. The string supports:

- **Product types** (records): `Point = (number x, number y)`
- **Sum types** (tagged unions): `Expr = Lit(number v) | BinOp(Expr l, string op, Expr r)`
- **Singletons**: `BinOp = Plus | Minus` — values, not classes
- **Field modifiers**: `*` for List, `?` for optional
- **Modules** (namespaces): `module Foo { Bar = (number a) }`
- **Unique types**: `Id(string name) unique` — memoized construction, same arguments yield same Lua object, enables identity comparison with `==`
- **External types**: registered via `context:Extern(name, predicate_fn)`, e.g. `Types:Extern("TerraType", terralib.types.istype)`

ASDL values are plain Lua objects. They have:
- Fields set by the constructor: `expr.v`, `expr.lhs`
- A `.kind` string on sum type instances: `expr.kind == "Lit"`
- Class identity via `Types.Lit:isclassof(expr)`
- The class as metatable: `getmetatable(expr) == Types.Lit`

**Methods** are added by assigning functions to the class table:

```lua
function Types.Lit:eval(env)
    return self.v
end
```

**Critical ordering rule** (from the docs): parent methods are copied to children at definition time, not via chained metatables. Therefore you must define parent methods BEFORE child methods, or the parent will clobber the child.

ASDL operates entirely in Lua. It knows nothing about Terra. The connection between them is explicit — through quotes, escapes, macros, and metamethods.


### Struct metamethods

Every Terra struct has a `metamethods` table. These are the **exotype property functions** from the paper — Lua functions queried by Terra's type checker when it encounters operations it cannot resolve. Each property function receives the operation context and returns either a value (for layout queries) or a quote (for behavior queries).

The metamethods are (from the docs):

**`__getentries(self) → entries`**
A Lua function. Called once when the compiler first needs the struct layout. Returns a List of `{field = name, type = terratype}` tables. Since the type is not yet complete during this call, anything requiring the type to be complete will error.

**`__staticinitialize(self)`**
A Lua function. Called after the type is complete (layout is known) but before the compiler returns to user code. Can examine offsets with `terralib.offsetof`, create vtables, install additional methods. Runs once per type.

**`__getmethod(self, methodname) → method`**
A Lua function. Called for every static invocation of `methodname` on this type. May return a Terra function, a Lua function, or a macro. Since it can be called multiple times for the same name, expensive operations should be memoized. By default returns `self.methods[methodname]`, falling through to `__methodmissing` if not found.

**`__methodmissing(methodname, obj, arg1, ..., argN)`**
A **macro**. The most important exotype property. Called when `__getmethod` fails (method not in the methods table). Receives quotes as arguments. Must return a quote to splice in place of the method call. The paper uses this in every major example: generating setters from field names, forwarding to Objective-C, implementing the proxy pattern in `Array(T)`, compiling x86 instructions on demand, wrapping probabilistic function calls. It enables unbounded method sets resolved lazily — the foundation of exotype composability.

**`__entrymissing(entryname, obj)`**
A **macro**. Called when `obj.entryname` is not a known field. Receives quotes. Must return a quote.

**`__cast(from, to, exp) → castedexp`**
A Lua function. Called when either `from` or `to` is this struct type (or pointer to it). If a valid conversion exists, returns a Terra expression (quote) converting `exp` from `from` to `to`. If not, calls `error()`. The compiler tries applicable `__cast` methods until one succeeds.

**`__for(iterable, body) → quote`**
A Lua function (marked experimental). Generates the loop body for `for x in myobj do`. `iterable` is an expression yielding a value of this type. `body` is a Lua function that, when called with the loop variable, returns one iteration's code. Both `iterable` and the body argument must be protected from multiple evaluation. Returns a quote.

**Operator metamethods**: `__add`, `__sub`, `__mul`, `__div`, `__mod`, `__lt`, `__le`, `__gt`, `__ge`, `__eq`, `__ne`, `__and`, `__or`, `__not`, `__xor`, `__lshift`, `__rshift`, `__select`, `__apply`. Can be either Terra methods or macros.

**`__typename(self) → string`**
A Lua function. Provides the display name for error messages.

The key distinction: `__methodmissing` and `__entrymissing` are **macros** — they receive quotes and return quotes. `__cast`, `__for`, `__getentries`, `__staticinitialize` are **Lua functions** — they receive types/values and return entries, quotes, or nothing. Operator metamethods can be either.

In the exotype formalism, all of these are property functions `(Opᵢ → Quote)`. The difference between macros and Lua functions is when they access their arguments: macros receive arguments as unevaluated AST fragments (quotes), while Lua functions receive evaluated values (types, expressions). Both are queried lazily by the type checker and both run at compile time — not at runtime.


### Macros

Created with `macro(function(arg0, arg1, ...) ... end)`. The function is invoked **at compile time** (during type-checking) for each call in Terra code. Each argument is a Terra quote representing the argument expression. The macro must return a value that converts to Terra via the compile-time conversion rules — typically a quote.

Macros are how Lua logic runs inside Terra code without escape blocks. When Terra code calls a macro, the macro receives the arguments as AST fragments (quotes), performs arbitrary Lua computation, and returns an AST fragment (quote) that is spliced into the call site. The compiler then type-checks the result.

From the docs: "Escapes are evaluated when the surrounding Terra code is **defined**." Macros run when the code is **compiled** (type-checked). This is a subtle but important difference for nested/deferred compilation. In practice, for our pattern both happen during `terralib.memoize`'d function generation, so the distinction rarely matters.

### `terralib.memoize`

From the docs: "Memoize the result of a function. The first time a function is called with a particular set of arguments, it calls the function to calculate the return value and caches it. Subsequent calls with the same arguments (using Lua equality) will return that value."

This is a Terra built-in. We do not write cache code. We wrap our compiler function:

```lua
local compile_thing = terralib.memoize(function(key)
    -- ... generate Terra function ...
    return fn
end)
```

Terra handles the cache, the key comparison, the lookup. Combined with ASDL's `unique` types (which memoize construction so structurally identical objects are `==`), this gives us structural caching: same domain configuration → same compiled function.


### The schema DSL: validated ASDL as a language extension

Raw ASDL is a string passed to `context:Define()`. It's unchecked beyond basic syntax. You can define a sum type with one variant, a record that recurses without indirection, a phase that widens instead of narrows. These are design errors that produce confusing failures downstream — a method that returns nil, an infinite loop at construction, generated code that branches where it shouldn't.

The schema DSL fixes this by hooking into Terra's **language extension API** — the same mechanism used to define `terra` functions and `struct` declarations. It registers the keyword `schema`, uses Terra's **Pratt parser** (shipped as `tests/lib/parsing.t`) for constraint expressions, and emits errors through Terra's own error reporting. An ASDL structural error becomes a Terra error — same format, same file, same line number.

From the API docs, a language extension is a Lua table with:

- `name`: identifier for the extension
- `entrypoints`: keywords that trigger the parser (e.g. `{"schema"}`)
- `keywords`: additional reserved words (e.g. `{"enum", "flags", "record", "phase", "methods", "extern", "unique"}`)
- `expression` / `statement` / `localstatement`: parser functions that receive the `lexer` and return constructor functions

The `lexer` provides `lexer:next()`, `lexer:expect(type)`, `lexer:matches(type)`, `lexer:luaexpr()`, `lexer:terraexpr()`, `lexer:error(msg)`. The Pratt parser library wraps these with precedence-aware expression parsing.

The schema DSL uses `statement` to parse the entire schema block, validate it, generate the ASDL definition string, and return the compiled context:

```lua
local schema_lang = {
    name = "schema",
    entrypoints = {"schema"},
    keywords = {"enum", "flags", "record", "phase",
                "methods", "extern", "unique"},

    statement = function(self, lex)
        lex:expect("schema")
        local name = lex:expect(lex.name).value

        -- Parse the body using the lexer
        local decl = parse_schema_body(lex)

        -- Validate ALL structural rules
        local errors = validate(decl)
        if #errors > 0 then
            -- Errors go through Terra's error system
            -- with correct file and line numbers
            lex:error(errors[1].message)
        end

        -- Generate the ASDL definition string
        local asdl_string = emit_asdl(decl)

        -- Return the constructor
        return function(env)
            local ctx = asdl.NewContext()
            for _, ext in ipairs(decl.externs) do
                ctx:Extern(ext.name, ext.checker)
            end
            ctx:Define(asdl_string)
            install_constraints(ctx, decl)
            install_method_traps(ctx, decl)
            return {
                types = ctx,
                phases = decl.phase_names,
                methods = decl.method_sigs,
            }
        end, {name}  -- bind to local variable `name`
    end,
}
```

#### Syntax

The user writes:

```lua
import "schema"

schema MyDomain

    extern terra_type = terralib.types.istype
    extern terra_quote = terralib.isquote

    flags Dir
        Row
        Col
    end

    enum Sizing
        Fit     { min: number, max: number }
        Grow    { weight: number, min: number, max: number }
        Fixed   { value: number }
        Percent { fraction: number, 0 <= fraction <= 1 }
    end

    record Color
        r: number
        g: number
        b: number
        a: number = 1.0
    end

    phase Source
        enum Expr
            Lit   { value: number }
            BinOp { op: string, lhs: Expr, rhs: Expr }
            Get   { property: string }
            Zoom  {}
        end

        methods
            Expr:compile(ctx: table) -> terra_quote
        end
    end

    phase Classified
        flags Dep
            Const
            Zoom
            Feature
        end
    end

    phase Compiled
        record VertexField
            name: string
            components: number, 1 <= components <= 4
        end

        record VertexFormat
            fields: VertexField*
        unique
        end
    end

end
```

This parses to an internal representation, validates, then generates:

```lua
M:Define [[
    Dir = Row | Col

    Sizing = Fit(number min, number max)
           | Grow(number weight, number min, number max)
           | Fixed(number value)
           | Percent(number fraction)

    Color = (number r, number g, number b, number a)

    module Source {
        Expr = Lit(number value)
             | BinOp(string op, Source.Expr lhs, Source.Expr rhs)
             | Get(string property)
             | Zoom()
    }

    module Classified {
        Dep = Const | Zoom | Feature
    }

    module Compiled {
        VertexField = (string name, number components)
        VertexFormat = (Compiled.VertexField* fields) unique
    }
]]
```

Plus constructor wrappers that check constraints at construction time:

```lua
-- Fraction must be 0..1
local original = M.Sizing.Percent
M.Sizing.Percent = function(fraction)
    assert(fraction >= 0 and fraction <= 1,
        "Percent.fraction must be in [0,1], got " .. fraction)
    return original(fraction)
end

-- Components must be 1..4
local original_vf = M.Compiled.VertexField
M.Compiled.VertexField = function(name, components)
    assert(components >= 1 and components <= 4,
        "components must be 1-4, got " .. components)
    return original_vf(name, components)
end
```

Plus method exhaustiveness traps via the ASDL ordering rule — the parent method is installed first as an error-reporting fallback. Any variant that doesn't override it fires a clear error at first call naming the missing variant and method.

#### What the validator checks

Every rule is checked at parse time and reported through `lex:error()` as a standard Terra error:

**Sum types (enum)**:
- At least 2 variants. One variant = use a record instead.
- No two variants have identical field sets. Identical fields = merge or differentiate.
- Every variant has at least one distinguishing field from its siblings.

**Records**:
- All referenced types exist in the schema or are registered externs.
- No direct recursion without `*` or `?` indirection (infinite struct).
- Warning if more than 3 mutually exclusive optional fields (suggests a sum type).
- Default values type-check against the field type.
- Constraint expressions are valid (bounds are numeric, min < max).

**Phases**:
- Declaration order = phase order.
- Later phases have fewer or equal sum types than earlier phases.
- Final phase has zero sum types (the monomorphic guarantee) — warning if violated.
- Types reference only types from their own phase or earlier phases.

**Methods**:
- Return type's phase ≥ receiver type's phase (no backward lowering).
- Exhaustiveness: at first call, every variant of the sum type must have an implementation.

**Unique**:
- Only on types that will benefit from identity comparison.

#### How errors look

Because `lex:error()` uses Terra's error infrastructure, errors have file names and line numbers:

```
schema.t:14: sum type 'Format' has only one variant.
    A sum type must have at least 2 variants. Use a record instead.

schema.t:28: field 'target' references type 'Waypoint'
    which is not defined in this schema.

schema.t:45: method 'decompile' on Typed.TypedExpr returns Source.Expr,
    which is an earlier phase. Methods must produce types from
    the same or later phase.

schema.t:52: record 'Tree' contains field 'left' of type 'Tree'
    which creates infinite recursion. Use Tree* or Tree?.
```

These are identical in format to any other Terra compilation error. The user's editor shows them in the same way. The schema DSL is invisible except when you get it wrong — then it tells you exactly what's wrong and where.

#### The Pratt parser for constraints

Constraint expressions like `0 <= fraction <= 1` and `1 <= components <= 4` are parsed using Terra's shipped Pratt parser library. The Pratt parser handles operator precedence naturally. We define:

- Prefix rules for identifiers (field names) and numbers
- Infix rules for `<=`, `>=`, `<`, `>`, `==` at appropriate precedence levels

The parsed constraint becomes a Lua predicate function wrapped around the ASDL constructor. The Pratt parser is also used for default value expressions (`a: number = 1.0`).

#### Relationship to the rest of the pattern

The schema DSL is **optional**. You can always write raw `context:Define()` strings. The DSL is for projects where humans author ASDL definitions — UI libraries, game engines, DSLs you're inventing. Projects where a spec JSON generates ASDL programmatically (like the MapLibre compiler) don't need it.

The schema DSL is a **separate project** — a reusable Terra language extension. It produces the same ASDL contexts and types that `context:Define()` produces. Everything downstream (ASDL methods, metamethods, `terralib.memoize`, the compilation pattern) works identically whether the ASDL came from the schema DSL or from a raw string.

The schema DSL is itself an example of the exotype pattern: it uses Terra's language extension API (a form of `__methodmissing` at the parser level — the `expression`/`statement` functions are invoked when the keyword is encountered), it generates ASDL types (domain modeling), and it installs exotype properties (constraint checkers, method traps) on the generated types. The tool is built with the same tools it validates.


## The pattern

### Step 1: Define the domain in ASDL

ASDL modules correspond to compiler phases. Types in each module represent the data at that phase. Later modules have fewer sum types — decisions are resolved as you progress through phases.

```lua
local asdl = require 'asdl'
local M = asdl.NewContext()

M:Extern("TerraType", terralib.types.istype)
M:Extern("TerraQuote", terralib.isquote)

M:Define [[
    module Source {
        Expr = Lit(number v)
             | BinOp(string op, Source.Expr lhs, Source.Expr rhs)
             | Get(string property)
             | Zoom()
             | Interpolate(Source.Expr input, Source.Stop* stops)

        Stop = (number at, number val)
    }
]]
```

This is pure Lua. No Terra yet. The types are Lua metatables with validated constructors.


### Step 2: Install methods on ASDL types

ASDL methods are Lua functions. For methods that produce Terra code, they return quotes:

```lua
-- PARENT methods FIRST (ASDL ordering rule)
function M.Source.Expr:compile(ctx)
    error("compile not implemented for " .. self.kind)
end

-- Then child methods
function M.Source.Expr.Lit:compile(ctx)
    return `[float](self.v)
end

function M.Source.Expr.BinOp:compile(ctx)
    local l = self.lhs:compile(ctx)
    local r = self.rhs:compile(ctx)
    local ops = {
        ["+"] = function(a, b) return `a + b end,
        ["-"] = function(a, b) return `a - b end,
        ["*"] = function(a, b) return `a * b end,
        ["/"] = function(a, b) return `a / b end,
    }
    return ops[self.op](l, r)
end

function M.Source.Expr.Get:compile(ctx)
    local key = self.property
    return `ctx.feature.[key]
end

function M.Source.Expr.Zoom:compile(ctx)
    return `ctx.zoom
end

function M.Source.Expr.Interpolate:compile(ctx)
    local input = self.input:compile(ctx)
    local stops = self.stops
    local result = symbol(float, "interp_result")

    local stmts = terralib.newlist()
    stmts:insert(quote var [result] = [float](stops[1].val) end)

    for i = 2, #stops do
        local lo, hi = stops[i-1].at, stops[i].at
        local lo_v, hi_v = stops[i-1].val, stops[i].val
        stmts:insert(quote
            if [input] >= [lo] and [input] < [hi] then
                var t = ([input] - [lo]) / ([hi] - [lo])
                [result] = [lo_v] + t * ([hi_v] - [lo_v])
            end
        end)
    end

    stmts:insert(quote
        if [input] >= [stops[#stops].at] then
            [result] = [float](stops[#stops].val)
        end
    end)

    return quote [stmts] in [result] end
end
```

Each method takes an ASDL node (`self`) plus a context, and returns a Terra quote. The quote is not yet inside a function — it is a code fragment waiting to be spliced.

Note: `Interpolate:compile` unrolls the stop array. The `for i = 2, #stops` is a Lua loop that runs at code-generation time. Each iteration emits a quote. The stops are compile-time constants baked into the generated code. At runtime there is no loop and no stop array — just a sequence of comparisons against constant values.


### Step 3: Install metamethods on Terra structs

Metamethods bridge from Terra's type checker to our ASDL-based code generators.

**`__getentries`** derives struct layout from ASDL data:

```lua
local make_vertex_struct = terralib.memoize(function(format)
    local S = terralib.types.newstruct("Vertex")

    S.metamethods.__getentries = function(self)
        return format.fields:map(function(f)
            return {field = f.name, type = components_to_type(f.components)}
        end)
    end

    return S
end)
```

`format` is an ASDL value describing the vertex layout. `__getentries` reads it and returns the field list. Terra calls this once when the struct is first completed. The resulting struct has exactly the fields the ASDL format specifies — no more, no less.

**`__staticinitialize`** generates derived code after layout is known:

```lua
S.metamethods.__staticinitialize = function(self)
    local stride = terralib.sizeof(self)
    self.methods.bind = terra(prog: uint32)
        escape
            local offset = 0
            for _, f in ipairs(format.fields) do
                emit quote
                    var loc = gl.GetAttribLocation(prog, [f.name])
                    gl.VertexAttribPointer(loc, [f.components],
                        gl.FLOAT, 0, [stride],
                        [&uint8](nil) + [offset])
                    gl.EnableVertexAttribArray(loc)
                end
                offset = offset + f.components * 4
            end
        end
    end
end
```

This runs once per struct type, after the layout is determined. It installs a `bind` method that knows the exact offsets (computed from the real layout) and generates one `glVertexAttribPointer` call per field. The `escape/emit` block iterates the ASDL field list at method-definition time.

**`__entrymissing`** as a macro dispatches field access:

```lua
S.metamethods.__entrymissing = macro(function(entryname, obj)
    local name = entryname:asvalue()
    if known_fields[name] then
        return `obj.[name]
    else
        return `dynamic_get(obj._extra, [hash(name)])
    end
end)
```

When Terra code accesses `feature.population`, and `population` is not a declared field, this macro fires. It checks (at compile time) whether `population` is in the known schema. If yes: direct field access. If no: hash table fallback. The decision is made once at compile time. The compiled code has one path.

**`__methodmissing`** as a macro dispatches method calls:

```lua
Layer.metamethods.__methodmissing = macro(function(name, obj, ...)
    local method_name = name:asvalue()
    local prop_name = method_to_prop(method_name)
    local dep = classifications[prop_name]
    if dep == DEP_CONST then
        return `[value_to_terra(constant_values[prop_name])]
    elseif dep == DEP_ZOOM then
        local expr = zoom_exprs[prop_name]
        return `[expr:compile({zoom = `obj.zoom})]
    end
end)
```

When Terra code calls `layer:get_fill_color()`, and the method doesn't exist in the methods table, this macro fires. It looks up the classification (a Lua value from our ASDL analysis), then returns either an inlined constant or a compiled zoom expression. The call site compiles to either a constant or an arithmetic expression — no dispatch at runtime.

**`__cast`** as a Lua function handles type conversions:

```lua
MapColor.metamethods.__cast = function(from, to, exp)
    if from == float and to == MapColor then
        return `MapColor {exp, exp, exp, 1.0f}
    elseif from == MapColor and to == float then
        return `(exp.r + exp.g + exp.b) / 3.0f
    else
        error("invalid cast")
    end
end
```

When Terra's type checker needs to convert between `float` and `MapColor`, it calls this. If conversion is valid, it returns the expression. If not, it calls `error()` and the compiler tries other `__cast` methods. This is a Lua function, not a macro — it receives type objects and a quote, not just quotes.

**`__for`** as a Lua function generates custom iteration:

```lua
TileLayer.metamethods.__for = function(iter, body)
    return quote
        var layer = iter
        var cursor = 0
        for i = 0, layer.feature_count do
            var feature : Feature
            cursor = decode_feature(layer.data, cursor, &feature)
            [body(`feature)]
        end
    end
end
```

When Terra code writes `for feature in tile_layer do`, this generates the decoding loop. `iter` is the expression producing the tile layer. `body` is a function that, given the loop variable, returns one iteration's code. The result is a quote containing the complete loop.

**Operator metamethods** for domain arithmetic:

```lua
MapColor.metamethods.__add = terra(a: MapColor, b: MapColor): MapColor
    return MapColor {a.r+b.r, a.g+b.g, a.b+b.b, a.a+b.a}
end
MapColor.metamethods.__mul = terra(a: MapColor, b: float): MapColor
    return MapColor {a.r*b, a.g*b, a.b*b, a.a*b}
end
```

These are Terra methods (not macros). They define what `+` and `*` mean for colors. The expression compiler can write `lo + t * (hi - lo)` and it works for both `float` (scalar arithmetic) and `MapColor` (component-wise), with the correct code generated for each. No type-dispatch in the expression compiler.


### Step 4: Generate Terra functions

The ASDL tree, the methods that return quotes, and the metamethods on the structs all come together when we generate a Terra function:

```lua
local compile_processor = terralib.memoize(function(plan_key)
    local plan = plan_registry[plan_key]
    local VStruct = make_vertex_struct(plan.format)
    local filter = plan.filter      -- an ASDL Expr node
    local exprs = plan.exprs        -- table: field_name → ASDL Expr node

    return terra(
        tile: TileLayer,
        vertices: &VStruct,
        vertex_cap: int,
        zoom: float
    ) : int
        var count = 0
        var ctx : CompileCtx
        ctx.zoom = zoom

        -- __for metamethod on TileLayer generates the decoding loop
        for feature in tile do
            ctx.feature = feature

            -- filter:compile(ctx) is a Lua call at definition time.
            -- It returns a quote. The [...] escape splices it in.
            if [filter:compile(ctx)] then
                var v : VStruct
                -- __getentries determined VStruct's layout from plan.format

                escape
                    for name, expr in pairs(exprs) do
                        -- Each expr:compile(ctx) returns a quote.
                        -- __cast on the result type handles conversion
                        -- to the vertex field type automatically.
                        emit quote v.[name] = [expr:compile(ctx)] end
                    end
                end

                vertices[count] = v
                count = count + 1
            end
        end
        return count
    end
end)
```

Reading this function:

1. `for feature in tile do` — Terra sees `TileLayer`, calls `__for`, gets the decoding loop inlined.

2. `[filter:compile(ctx)]` — At function definition time, `filter` is an ASDL node. `:compile(ctx)` is a Lua method call that walks the ASDL tree and returns a quote. The `[...]` escape splices that quote into the `if` condition. The compiled code has the filter as a flat boolean expression.

3. `var v : VStruct` — Terra completes the struct, calling `__getentries`, which reads the ASDL format descriptor and returns the field list. The struct has exactly the fields this specific plan requires.

4. `escape ... for name, expr in pairs(exprs) ... emit ... end` — Lua iterates the ASDL expression table at definition time. For each data-driven property, it calls `expr:compile(ctx)` to get a quote, and emits an assignment statement. If the quote's type doesn't match the field's type, `__cast` fires to generate the conversion.

5. `terralib.memoize` wraps the whole generator. Same plan key → same compiled function. We don't write cache code.

The result is a Terra function with no ASDL dispatch, no type checking, no optional field handling. The tree walk happened in Lua at definition time. The compiled function is a tight loop of arithmetic and memory writes.


### Step 5: Compile and run

```lua
-- First call: Lua generates the function, Terra JIT-compiles it via LLVM
local fn = compile_processor(plan_key)
fn:compile()

-- Subsequent calls: direct native function call
local count = fn(tile_data, vertex_buffer, capacity, zoom)
```

`:compile()` triggers LLVM JIT compilation to native machine code. After that, calling the function is a native call — no Lua, no interpretation, no LLVM. Just machine code.


## Where each thing runs

| What | When | Produces |
|---|---|---|
| `asdl.NewContext():Define(...)` | Lua execution time | Lua metatables (ASDL types) |
| ASDL constructor: `M.Lit(42)` | Lua execution time | Lua table (ASDL instance) |
| ASDL method: `expr:compile(ctx)` | Terra function definition time (inside escape) | Terra quote |
| `__getentries(self)` | Type completion time (once per struct) | List of field entries |
| `__staticinitialize(self)` | After type completion (once per struct) | Side effects (install methods) |
| `__cast(from, to, exp)` | Terra type-checking time | Terra quote (conversion) |
| `__for(iterable, body)` | Terra type-checking time | Terra quote (loop) |
| `__methodmissing(name, ...)` | Terra type-checking time (macro) | Terra quote |
| `__entrymissing(name, obj)` | Terra type-checking time (macro) | Terra quote |
| Operator metamethods | Terra type-checking time | Terra function or macro expansion |
| `escape ... emit ... end` | Terra function definition time | Spliced quotes |
| `[luaexpr]` (backtick escape) | Terra function definition time | Spliced value/quote |
| `terralib.memoize(fn)` | First call with new args | Cached return value |
| `fn:compile()` | Explicit call or first invocation | LLVM JIT → native machine code |
| `fn(args...)` | Runtime | Native execution |


## The role of escape vs. macro

Both are mechanisms for Lua code to produce Terra code. The difference:

**Escapes** (`[...]` and `escape ... emit ... end`) run when the surrounding Terra function is **defined**. They evaluate a Lua expression and splice the result into the function's AST. They're the mechanism for iterating over ASDL lists and splicing quotes.

**Macros** run when the function is **type-checked** (compiled). They receive their arguments as quotes (AST fragments) and return a quote. They're the mechanism for `__methodmissing` and `__entrymissing` — compile-time dispatch that looks like a normal method call or field access in Terra code.

In practice, for our pattern, both happen during the `terralib.memoize`'d function generation. The practical rule:

- **Use escapes** when you need to iterate an ASDL list and emit code for each element. This is Lua controlling the structure of the generated code.
- **Use macros** (via metamethods) when you want Terra code to look like normal code while hiding compile-time dispatch. `feature.population` looks like a field access but is actually `__entrymissing` dispatching to either direct access or a hash lookup.

The cleanest code minimizes escapes. Ideally there is one escape block per ASDL list traversal. Inside each emission, the code is either a direct quote or a macro call. Everything else — field access, method calls, operators, iteration, casts — is handled by metamethods, which Terra invokes automatically.


## What makes it work

The pattern works because of the exotype architecture described in DeVito et al.:

**ASDL types exist in Lua.** They are Lua tables with metatables. Lua code can walk them, analyze them, transform them, and make decisions based on their structure — all at function-generation time. They are the domain model that the exotype property functions inspect.

**Terra quotes exist in Lua.** A backtick expression `` `a + b `` is a Lua object representing a fragment of Terra code. Quotes compose: you can build larger quotes from smaller ones. They are the currency exchanged between ASDL methods and exotype property functions. In the formal model, every property function returns a Quote.

**Exotype properties run at compile time, not runtime.** From the paper: "Rather than define an object's behavior as a function that is evaluated at runtime, an exotype describes the behavior with a function that is evaluated once during a staged compilation step." The metamethods are these property functions. They inspect ASDL data, make decisions, and return quotes. The decision is made once, during typechecking. The generated code has no trace of the decision.

**Properties are lazily evaluated and composable.** From the paper: properties are queried individually, only when needed. This prevents false cycles and allows independently-defined type constructors (like `Array(T)`) to compose with arbitrary exotypes. In our pattern, `terralib.memoize` wraps type constructors, and ASDL `unique` ensures structural identity. Together they give us composable, cached type generation.

**`terralib.memoize` caches by Lua equality.** ASDL's `unique` types ensure that structurally identical values are `==`. Combined with `terralib.memoize`, this means: same domain configuration → same compiled function. The first call pays the compilation cost. Every subsequent call with the same configuration returns the cached function instantly.

The net effect: domain complexity lives in ASDL (Lua). Generated code is monomorphic (Terra). The gap between them is bridged by quotes flowing through ASDL methods and exotype property functions. LLVM optimizes the final code aggressively because it sees only concrete types, constant values, and straight-line arithmetic — no virtual dispatch, no tagged unions, no optional field checks.

The paper demonstrated this in four domains: serialization (11× faster than Kryo), dynamic x86 assembly (3–20× faster than Chrome's assembler), automatic differentiation (comparable to Stan C++ with 25% less memory), and probabilistic programming (10× faster than V8 JavaScript PPL). Our pattern generalizes their approach: ASDL replaces hand-built type hierarchies, and the metamethods + macros are the exotype property functions. The result is the same — high-level expressiveness with low-level performance — but with a structured methodology that applies to any domain.


## Examples

Seven complete examples, each demonstrating specific facilities. They build in complexity: the first uses only ASDL + quotes, the last uses everything.


### Example 1: Expression compiler

Demonstrates: ASDL sum types, method dispatch by variant, quotes composing recursively, escape to splice, `terralib.memoize`.

```lua
local asdl = require 'asdl'
local List = require 'terralist'
local C = terralib.includecstring [[
    #include <math.h>
    #include <stdio.h>
]]

local M = asdl.NewContext()
M:Define [[
    Expr = Lit(number v)
         | Var(string name)
         | BinOp(string op, Expr lhs, Expr rhs)
         | UnaryOp(string op, Expr arg)
         | Call(string fn, Expr* args)
         | Cond(Expr test, Expr yes, Expr no)
]]

-- Parent fallback FIRST (ASDL ordering rule)
function M.Expr:compile(env)
    error("compile not implemented for " .. self.kind)
end

-- Child methods
function M.Expr.Lit:compile(env)
    return `[double](self.v)
end

function M.Expr.Var:compile(env)
    local sym = env[self.name]
    if not sym then error("undefined: " .. self.name) end
    return `sym
end

function M.Expr.BinOp:compile(env)
    local l = self.lhs:compile(env)
    local r = self.rhs:compile(env)
    local ops = {
        ["+"] = function(a,b) return `a + b end,
        ["-"] = function(a,b) return `a - b end,
        ["*"] = function(a,b) return `a * b end,
        ["/"] = function(a,b) return `a / b end,
        ["%"] = function(a,b) return `a % b end,
        ["^"] = function(a,b) return `C.pow(a, b) end,
    }
    return ops[self.op](l, r)
end

function M.Expr.UnaryOp:compile(env)
    local a = self.arg:compile(env)
    if self.op == "-" then return `-a
    elseif self.op == "abs" then return `C.fabs(a)
    elseif self.op == "sqrt" then return `C.sqrt(a)
    elseif self.op == "sin" then return `C.sin(a)
    elseif self.op == "cos" then return `C.cos(a)
    elseif self.op == "log" then return `C.log(a)
    elseif self.op == "exp" then return `C.exp(a)
    end
end

function M.Expr.Call:compile(env)
    local compiled_args = self.args:map(function(a) return a:compile(env) end)
    local fn_sym = env[self.fn]
    return `fn_sym([compiled_args])
end

function M.Expr.Cond:compile(env)
    local t = self.test:compile(env)
    local y = self.yes:compile(env)
    local n = self.no:compile(env)
    return `terralib.select(t > 0.0, y, n)
end

-- Compile an expression tree into a Terra function.
-- terralib.memoize: same tree → same function.
local compile_expr = terralib.memoize(function(expr, param_names)
    local param_syms = param_names:map(function(n)
        return symbol(double, n)
    end)
    local env = {}
    for i, n in ipairs(param_names) do
        env[n] = param_syms[i]
    end
    local body = expr:compile(env)

    local fn = terra([param_syms]) : double
        return [body]
    end
    return fn
end)

-- Usage:
-- Build the AST: sin(x) * cos(y) + 0.5
local tree = M.BinOp("+",
    M.BinOp("*",
        M.UnaryOp("sin", M.Var("x")),
        M.UnaryOp("cos", M.Var("y"))),
    M.Lit(0.5))

local fn = compile_expr(tree, List {"x", "y"})
fn:compile()

-- This is now a native function. No AST walking at runtime.
print(fn(3.14, 0))  -- sin(pi)*cos(0) + 0.5 ≈ 0.5
fn:disas()           -- see the LLVM-optimized assembly
```

The generated function is pure arithmetic — `sin`, `cos`, `mul`, `add`, no branches, no dispatch. LLVM can inline the math intrinsics and vectorize if called in a loop.


### Example 2: Struct from ASDL schema

Demonstrates: `__getentries`, `__staticinitialize`, `terralib.memoize`, ASDL driving struct layout, generated methods.

```lua
local asdl = require 'asdl'
local List = require 'terralist'
local C = terralib.includecstring [[
    #include <stdio.h>
    #include <string.h>
]]

local S = asdl.NewContext()
S:Define [[
    Field = (string name, string type, number size)
    Schema = (Field* fields, string name) unique
]]

-- Map schema type names to Terra types
local type_map = {
    f32 = float, f64 = double,
    i32 = int32, i64 = int64,
    u8 = uint8, u32 = uint32,
    bool = bool,
}

-- Generate a Terra struct from an ASDL schema
local make_struct = terralib.memoize(function(schema)
    local T = terralib.types.newstruct(schema.name)

    T.metamethods.__getentries = function(self)
        return schema.fields:map(function(f)
            local terra_type = type_map[f.type]
            if f.size > 1 then
                terra_type = terra_type[f.size]
            end
            return {field = f.name, type = terra_type}
        end)
    end

    T.metamethods.__staticinitialize = function(self)
        -- Generate a print method that knows every field
        self.methods.dump = terra(self_ptr: &self)
            C.printf("[%s]\n", [schema.name])
            escape
                for _, f in ipairs(schema.fields) do
                    if f.type == "f32" or f.type == "f64" then
                        if f.size == 1 then
                            emit quote
                                C.printf("  %s = %f\n",
                                    [f.name], [double](self_ptr.[f.name]))
                            end
                        else
                            emit quote
                                C.printf("  %s = [", [f.name])
                                for i = 0, [f.size] do
                                    C.printf("%f ", [double](self_ptr.[f.name][i]))
                                end
                                C.printf("]\n")
                            end
                        end
                    elseif f.type == "i32" or f.type == "u32" or f.type == "i64" then
                        emit quote
                            C.printf("  %s = %d\n",
                                [f.name], [int](self_ptr.[f.name]))
                        end
                    elseif f.type == "bool" then
                        emit quote
                            C.printf("  %s = %s\n",
                                [f.name],
                                terralib.select(self_ptr.[f.name],
                                    "true", "false"))
                        end
                    end
                end
            end
        end

        -- Generate a zero method
        self.methods.zero = terra(self_ptr: &self)
            C.memset(self_ptr, 0, [terralib.sizeof(self)])
        end

        -- Generate a size query
        self.methods.byte_size = terra() : int
            return [terralib.sizeof(self)]
        end
    end

    return T
end)

-- Usage:
local vec3_schema = S.Schema(List {
    S.Field("x", "f32", 1),
    S.Field("y", "f32", 1),
    S.Field("z", "f32", 1),
}, "Vec3")

local particle_schema = S.Schema(List {
    S.Field("pos", "f32", 3),
    S.Field("vel", "f32", 3),
    S.Field("mass", "f32", 1),
    S.Field("alive", "bool", 1),
}, "Particle")

local Vec3 = make_struct(vec3_schema)
local Particle = make_struct(particle_schema)

terra test()
    var v : Vec3
    v.x = 1.0f; v.y = 2.0f; v.z = 3.0f
    v:dump()

    var p : Particle
    p:zero()
    p.pos = array(1.0f, 2.0f, 3.0f)
    p.mass = 0.5f
    p.alive = true
    p:dump()

    C.printf("Particle size: %d bytes\n", Particle.methods.byte_size())
end

test()
```

The struct layout, the `dump` method, the `zero` method — all generated from the ASDL schema. Change the schema, rerun, get a new struct with new methods. No hand-written serialization.


### Example 3: Custom iteration with `__for`

Demonstrates: `__for` metamethod, ASDL describing a data format, compiled decoding inlined into iteration.

```lua
local asdl = require 'asdl'
local List = require 'terralist'
local C = terralib.includecstring [[
    #include <stdio.h>
    #include <string.h>
]]

local D = asdl.NewContext()
D:Define [[
    ColumnDef = (string name, string type)
    TableDef = (string name, ColumnDef* columns) unique
]]

-- A row-store table: header + packed rows
struct TableStore {
    data: &uint8
    row_count: int32
    row_stride: int32
}

-- Generate a Row struct and iteration from a table definition
local make_table_api = terralib.memoize(function(table_def)
    local type_map = {f64 = double, i32 = int32, bool = bool}

    -- Row struct via __getentries
    local Row = terralib.types.newstruct("Row_" .. table_def.name)
    Row.metamethods.__getentries = function(self)
        return table_def.columns:map(function(c)
            return {field = c.name, type = type_map[c.type]}
        end)
    end

    -- __for on TableStore: iterate rows with compiled decoding
    -- Each column read is at a known offset (baked at compile time)
    TableStore.metamethods.__for = function(iter, body)
        return quote
            var store = iter
            for i = 0, store.row_count do
                var row : Row
                var base = store.data + i * store.row_stride
                escape
                    local offset = 0
                    for _, col in ipairs(table_def.columns) do
                        local tt = type_map[col.type]
                        local sz = terralib.sizeof(tt)
                        emit quote
                            C.memcpy(&row.[col.name], base + [offset], [sz])
                        end
                        offset = offset + sz
                    end
                end
                [body(`row)]
            end
        end
    end

    return {Row = Row, stride = terralib.sizeof(Row)}
end)

-- Usage: define a table, get compiled iteration

local people_def = D.TableDef("people", List {
    D.ColumnDef("age", "i32"),
    D.ColumnDef("salary", "f64"),
    D.ColumnDef("active", "bool"),
})

local api = make_table_api(people_def)

-- This terra function uses __for — the decoding is inlined
terra sum_salary_of_active(store: TableStore) : double
    var total = 0.0
    for row in store do
        if row.active then
            total = total + row.salary
        end
    end
    return total
end

-- The compiled function reads specific bytes at specific offsets.
-- No column name lookup. No type dispatch. Just loads.
sum_salary_of_active:disas()
```

The `for row in store do` expands to a loop where each column is read from a known byte offset. The generated code is equivalent to hand-written C with hardcoded struct offsets.


### Example 4: Type conversions with `__cast`

Demonstrates: `__cast` for automatic conversions, operator metamethods for domain arithmetic, quotes composing through operators.

```lua
local C = terralib.includecstring [[ #include <math.h> ]]

struct Color { r: float; g: float; b: float; a: float }

-- Construct from hex integer
Color.metamethods.__cast = function(from, to, exp)
    if from:isintegral() and to == Color then
        return quote
            var v = [uint32](exp)
            in Color {
                [float]((v >> 24) and 0xFF) / 255.0f,
                [float]((v >> 16) and 0xFF) / 255.0f,
                [float]((v >> 8) and 0xFF) / 255.0f,
                [float](v and 0xFF) / 255.0f
            }
        end
    elseif from == float and to == Color then
        -- Grayscale
        return `Color { exp, exp, exp, 1.0f }
    elseif from == Color and to == float then
        -- Luminance
        return `0.2126f * exp.r + 0.7152f * exp.g + 0.0722f * exp.b
    else
        error("invalid Color cast")
    end
end

-- Arithmetic: component-wise
Color.metamethods.__add = terra(a: Color, b: Color): Color
    return Color { a.r+b.r, a.g+b.g, a.b+b.b, a.a+b.a }
end
Color.metamethods.__sub = terra(a: Color, b: Color): Color
    return Color { a.r-b.r, a.g-b.g, a.b-b.b, a.a-b.a }
end
Color.metamethods.__mul = terra(a: Color, b: float): Color
    return Color { a.r*b, a.g*b, a.b*b, a.a*b }
end

-- Now lerp is generic — works for float AND Color
-- with no type dispatch
local function make_lerp(T)
    return terra(a: T, b: T, t: float): T
        return a + (b - a) * t
    end
end

local lerp_float = make_lerp(float)
local lerp_color = make_lerp(Color)

terra demo()
    -- __cast from int: hex color literal
    var bg : Color = [Color](0xFF8800FF)

    -- __cast from float: grayscale
    var gray : Color = [Color](0.5f)

    -- __cast to float: luminance
    var lum : float = [float](bg)

    -- Operator metamethods: lerp works on Color
    var sunrise = lerp_color(
        [Color](0x1a0533FF),   -- deep purple
        [Color](0xFF6B35FF),   -- orange
        0.5f)

    -- And on float
    var mid = lerp_float(10.0f, 20.0f, 0.5f)
end
```

The `make_lerp` function generates a Terra function using `+`, `-`, `*`. For `float`, these are native operators. For `Color`, they dispatch to our metamethods. The generated code is component-wise arithmetic — no runtime type check.

This is the pattern that makes expression compilers work on both scalar and color properties with one codepath.


### Example 5: Compile-time dispatch with `__methodmissing` and `__entrymissing`

Demonstrates: macros as metamethods, compile-time decision making, ASDL classification data driving code generation.

```lua
local asdl = require 'asdl'
local List = require 'terralist'
local C = terralib.includecstring [[ #include <stdio.h> ]]

local M = asdl.NewContext()
M:Define [[
    PropDef = (string name, string type, boolean dynamic)
]]

-- Simulate a "classified style" — some properties are constant,
-- some vary per-element

local schema = List {
    M.PropDef("width",  "f32", false),    -- constant
    M.PropDef("height", "f32", false),    -- constant
    M.PropDef("color",  "f32", true),     -- dynamic (per element)
    M.PropDef("opacity","f32", true),     -- dynamic (per element)
    M.PropDef("label",  "str", false),    -- constant
}

-- Build a struct where constant props are baked in,
-- dynamic props are stored as fields
local make_element = terralib.memoize(function(schema, constants)
    local T = terralib.types.newstruct("Element")

    -- Only dynamic fields get struct entries
    T.metamethods.__getentries = function(self)
        return schema:filter(function(p) return p.dynamic end)
            :map(function(p)
                if p.type == "f32" then
                    return {field = p.name, type = float}
                elseif p.type == "str" then
                    return {field = p.name, type = rawstring}
                end
            end)
    end

    -- __entrymissing: constant props return inlined values,
    -- dynamic props should never miss (they're real fields)
    T.metamethods.__entrymissing = macro(function(entryname, obj)
        local name = entryname:asvalue()
        -- Look up in constants table
        if constants[name] ~= nil then
            local val = constants[name]
            if type(val) == "number" then
                return `[float](val)
            elseif type(val) == "string" then
                return `[rawstring](val)
            end
        end
        error("unknown property: " .. name)
    end)

    -- __methodmissing: get_X() returns the value regardless
    -- of whether it's constant or dynamic.
    -- The caller doesn't know which it is.
    T.metamethods.__methodmissing = macro(function(name, obj)
        local method_name = name:asvalue()
        local prop_name = method_name:sub(5)  -- strip "get_"
        if not method_name:match("^get_") then
            error("unknown method: " .. method_name)
        end

        -- Check if it's a dynamic field
        for _, p in ipairs(schema) do
            if p.name == prop_name and p.dynamic then
                return `obj.[prop_name]  -- real field access
            end
        end
        -- Must be constant — check entrymissing will handle it
        if constants[prop_name] ~= nil then
            local val = constants[prop_name]
            return `[float](val)
        end
        error("unknown property: " .. prop_name)
    end)

    return T
end)

-- Create an element type with specific constant values
local Elem = make_element(schema, {
    width = 100,
    height = 50,
    label = "hello",
})

-- This function uses __entrymissing and __methodmissing.
-- Constant props are inlined. Dynamic props are field reads.
-- The generated code has NO dispatch.
terra process(elems: &Elem, count: int) : float
    var total : float = 0.0f
    for i = 0, count do
        var e = elems[i]

        -- e.width → __entrymissing → `100.0f (constant, inlined)
        -- e.color → real field access (dynamic)
        -- e:get_opacity() → __methodmissing → real field access
        -- e:get_width() → __methodmissing → `100.0f (constant)

        total = total + e.color * e.opacity * e.width * e.height
    end
    return total
end

process:disas()
-- The disassembly shows: load color, load opacity,
-- multiply by 100.0 * 50.0 = 5000.0 (constant-folded by LLVM),
-- accumulate. No property lookup, no string comparison.
```

This is the core of the MapLibre pattern: properties classified as constant become inlined values via `__entrymissing`. Properties classified as dynamic become field reads. The user code (`e.width`, `e.color`, `e:get_opacity()`) looks uniform. The generated code is specialized.


### Example 6: Full pipeline with modules, phases, and lowering

Demonstrates: ASDL modules as compiler phases, methods on each phase that lower to the next, progressive resolution of sum types, `unique` for structural identity, the complete flow from source to machine code.

```lua
local asdl = require 'asdl'
local List = require 'terralist'
local C = terralib.includecstring [[
    #include <stdio.h>
    #include <math.h>
]]

local T = asdl.NewContext()
T:Extern("TerraType", terralib.types.istype)

T:Define [[
    -- Phase 1: Source — the parsed representation
    -- Sum types everywhere: types unresolved, ops as strings
    module Src {
        Type = IntType | FloatType | BoolType
             | ArrayType(Src.Type elem, number size)

        Expr = Lit(number v)
             | Var(string name)
             | BinOp(string op, Src.Expr lhs, Src.Expr rhs)
             | ArrayNew(Src.Expr* elems)
             | ArrayGet(Src.Expr arr, Src.Expr idx)
             | Let(string name, Src.Expr value, Src.Expr body)
             | If(Src.Expr cond, Src.Expr then_e, Src.Expr else_e)

        Decl = FnDecl(string name, Src.Param* params,
                       Src.Type ret, Src.Expr body)
        Param = (string name, Src.Type type)
    }

    -- Phase 2: Typed — types resolved, every node annotated
    -- Fewer sum types: Type is concrete
    module Typed {
        Expr = Lit(number v, TerraType type)
             | Var(string name, TerraType type)
             | BinOp(string op, Typed.Expr lhs, Typed.Expr rhs,
                     TerraType type)
             | ArrayNew(Typed.Expr* elems, TerraType type)
             | ArrayGet(Typed.Expr arr, Typed.Expr idx, TerraType type)
             | Let(string name, Typed.Expr value, Typed.Expr body,
                   TerraType type)
             | If(Typed.Expr cond, Typed.Expr then_e,
                  Typed.Expr else_e, TerraType type)
    }
]]

-- === Phase 1 → Phase 2: Type checking ===
-- Methods on Src types that produce Typed types

function T.Src.Type.IntType:to_terra()   return int end
function T.Src.Type.FloatType:to_terra() return double end
function T.Src.Type.BoolType:to_terra()  return bool end
function T.Src.Type.ArrayType:to_terra()
    return self.elem:to_terra()[self.size]
end

-- Type check: Src.Expr → Typed.Expr
function T.Src.Expr:check(env)
    error("check not implemented for " .. self.kind)
end

function T.Src.Expr.Lit:check(env)
    local t = (math.floor(self.v) == self.v) and int or double
    return T.Typed.Expr.Lit(self.v, t)
end

function T.Src.Expr.Var:check(env)
    local entry = env[self.name]
    if not entry then error("undefined: " .. self.name) end
    return T.Typed.Expr.Var(self.name, entry.type)
end

function T.Src.Expr.BinOp:check(env)
    local l = self.lhs:check(env)
    local r = self.rhs:check(env)
    -- Simple: both must be same type
    assert(l.type == r.type,
        "type mismatch in " .. self.op)
    return T.Typed.Expr.BinOp(self.op, l, r, l.type)
end

function T.Src.Expr.If:check(env)
    local c = self.cond:check(env)
    local t = self.then_e:check(env)
    local e = self.else_e:check(env)
    assert(t.type == e.type, "if branches must match")
    return T.Typed.Expr.If(c, t, e, t.type)
end

function T.Src.Expr.Let:check(env)
    local v = self.value:check(env)
    local new_env = {}
    for k, val in pairs(env) do new_env[k] = val end
    new_env[self.name] = {type = v.type}
    local b = self.body:check(new_env)
    return T.Typed.Expr.Let(self.name, v, b, b.type)
end

function T.Src.Expr.ArrayNew:check(env)
    local checked = self.elems:map(function(e) return e:check(env) end)
    local elem_type = checked[1].type
    for _, c in ipairs(checked) do
        assert(c.type == elem_type, "array elements must match")
    end
    return T.Typed.Expr.ArrayNew(checked, elem_type[#checked])
end

function T.Src.Expr.ArrayGet:check(env)
    local arr = self.arr:check(env)
    local idx = self.idx:check(env)
    assert(arr.type:isarray(), "not an array")
    return T.Typed.Expr.ArrayGet(arr, idx, arr.type.type)
end


-- === Phase 2 → Terra: Code generation ===
-- Methods on Typed types that produce Terra quotes

function T.Typed.Expr:compile(env)
    error("compile not implemented for " .. self.kind)
end

function T.Typed.Expr.Lit:compile(env)
    return `[self.type](self.v)
end

function T.Typed.Expr.Var:compile(env)
    return `[env[self.name]]
end

function T.Typed.Expr.BinOp:compile(env)
    local l = self.lhs:compile(env)
    local r = self.rhs:compile(env)
    local ops = {
        ["+"]  = function(a,b) return `a + b end,
        ["-"]  = function(a,b) return `a - b end,
        ["*"]  = function(a,b) return `a * b end,
        ["/"]  = function(a,b) return `a / b end,
        ["<"]  = function(a,b) return `[int](a < b) end,
        [">"]  = function(a,b) return `[int](a > b) end,
        ["=="] = function(a,b) return `[int](a == b) end,
    }
    return ops[self.op](l, r)
end

function T.Typed.Expr.If:compile(env)
    local c = self.cond:compile(env)
    local t = self.then_e:compile(env)
    local e = self.else_e:compile(env)
    return `terralib.select(c ~= 0, t, e)
end

function T.Typed.Expr.Let:compile(env)
    local v = self.value:compile(env)
    local s = symbol(self.value.type, self.name)
    local new_env = {}
    for k, val in pairs(env) do new_env[k] = val end
    new_env[self.name] = s
    local b = self.body:compile(new_env)
    return quote var [s] = [v] in [b] end
end

function T.Typed.Expr.ArrayNew:compile(env)
    local compiled = self.elems:map(function(e) return e:compile(env) end)
    return `arrayof([self.type.type], [compiled])
end

function T.Typed.Expr.ArrayGet:compile(env)
    local arr = self.arr:compile(env)
    local idx = self.idx:compile(env)
    return `arr[idx]
end

-- === Compile a function declaration ===
local compile_fn = terralib.memoize(function(fn_decl)
    -- Type-check
    local env = {}
    local param_syms = List()
    for _, p in ipairs(fn_decl.params) do
        local tt = p.type:to_terra()
        local s = symbol(tt, p.name)
        env[p.name] = {type = tt}
        param_syms:insert(s)
    end

    local typed_body = fn_decl.body:check(env)

    -- Compile to Terra
    local compile_env = {}
    for _, p in ipairs(fn_decl.params) do
        for i, s in ipairs(param_syms) do
            if fn_decl.params[i].name == p.name then
                compile_env[p.name] = s
            end
        end
    end

    local body_quote = typed_body:compile(compile_env)
    local ret_type = fn_decl.ret:to_terra()

    local fn = terra([param_syms]) : ret_type
        return [body_quote]
    end
    fn:setname(fn_decl.name)
    return fn
end)

-- Usage: a tiny language compiled through two phases
local Src = T.Src

local program = Src.FnDecl(
    "quadratic", List {
        Src.Param("a", Src.FloatType),
        Src.Param("b", Src.FloatType),
        Src.Param("x", Src.FloatType),
    },
    Src.FloatType,
    -- a*x*x + b*x + 1.0
    Src.BinOp("+",
        Src.BinOp("+",
            Src.BinOp("*", Src.Var("a"),
                Src.BinOp("*", Src.Var("x"), Src.Var("x"))),
            Src.BinOp("*", Src.Var("b"), Src.Var("x"))),
        Src.Lit(1.0))
)

local fn = compile_fn(program)
fn:compile()
print(fn(2.0, 3.0, 4.0))  -- 2*16 + 3*4 + 1 = 45.0
fn:disas()  -- two multiplies, two adds. LLVM optimizes beautifully.
```

This is the full pipeline: `Src.Expr` → (type check) → `Typed.Expr` → (compile) → Terra quote → (JIT) → native code. Two ASDL modules, two phases, each with methods that produce the next phase's output.


### Example 7: Everything together — a compiled particle system

Demonstrates: every facility in concert. ASDL for the domain, `__getentries` for the particle struct, `__for` for iteration, `__cast` for color conversion, operator metamethods for vector math, `__entrymissing` for force field access, `__staticinitialize` for buffer helpers, `terralib.memoize` for caching by system configuration, ASDL methods returning quotes for force evaluation.

```lua
local asdl = require 'asdl'
local List = require 'terralist'
local C = terralib.includecstring [[
    #include <math.h>
    #include <stdlib.h>
]]

-- ============================================================
-- ASDL: the particle system domain
-- ============================================================

local P = asdl.NewContext()
P:Define [[
    -- Forces
    Force = Gravity(number gx, number gy)
          | Drag(number coefficient)
          | Turbulence(number strength, number frequency)
          | Attractor(number x, number y, number strength, number radius)
          | Vortex(number x, number y, number strength)

    -- Color over lifetime
    ColorKey = (number t, number r, number g, number b, number a)

    -- Size over lifetime
    SizeKey = (number t, number size)

    -- A complete particle system config
    SystemConfig = (
        Force* forces,
        ColorKey* color_keys,
        SizeKey* size_keys,
        number emit_rate,
        number lifetime,
        number speed_min,
        number speed_max,
        number spread_angle
    ) unique
]]


-- ============================================================
-- Vec2 with operator metamethods
-- ============================================================

struct Vec2 { x: float; y: float }

Vec2.metamethods.__add = terra(a: Vec2, b: Vec2): Vec2
    return Vec2 { a.x+b.x, a.y+b.y }
end
Vec2.metamethods.__sub = terra(a: Vec2, b: Vec2): Vec2
    return Vec2 { a.x-b.x, a.y-b.y }
end
Vec2.metamethods.__mul = terra(a: Vec2, b: float): Vec2
    return Vec2 { a.x*b, a.y*b }
end

terra Vec2.methods.length(self: &Vec2): float
    return C.sqrtf(self.x*self.x + self.y*self.y)
end


-- ============================================================
-- Color struct with __cast
-- ============================================================

struct RGBA { r: float; g: float; b: float; a: float }

RGBA.metamethods.__add = terra(a: RGBA, b: RGBA): RGBA
    return RGBA { a.r+b.r, a.g+b.g, a.b+b.b, a.a+b.a }
end
RGBA.metamethods.__sub = terra(a: RGBA, b: RGBA): RGBA
    return RGBA { a.r-b.r, a.g-b.g, a.b-b.b, a.a-b.a }
end
RGBA.metamethods.__mul = terra(a: RGBA, b: float): RGBA
    return RGBA { a.r*b, a.g*b, a.b*b, a.a*b }
end


-- ============================================================
-- Particle struct from config (__getentries)
-- ============================================================

struct Particle {
    pos: Vec2
    vel: Vec2
    age: float
    lifetime: float
}


-- ============================================================
-- ParticleBuffer with __for
-- ============================================================

struct ParticleBuffer {
    data: &Particle
    count: int
    capacity: int
}

ParticleBuffer.metamethods.__for = function(iter, body)
    return quote
        var buf = iter
        for i = 0, buf.count do
            [body(`buf.data[i])]
        end
    end
end


-- ============================================================
-- Force compilation: ASDL methods → Terra quotes
-- ============================================================

-- Parent method FIRST
function P.Force:apply(pos, vel, dt)
    error("apply not implemented for " .. self.kind)
end

function P.Force.Gravity:apply(pos, vel, dt)
    return quote
        vel.x = vel.x + [float](self.gx) * dt
        vel.y = vel.y + [float](self.gy) * dt
    end
end

function P.Force.Drag:apply(pos, vel, dt)
    local coeff = self.coefficient
    return quote
        var factor = 1.0f - [float](coeff) * dt
        if factor < 0.0f then factor = 0.0f end
        vel.x = vel.x * factor
        vel.y = vel.y * factor
    end
end

function P.Force.Turbulence:apply(pos, vel, dt)
    local str = self.strength
    local freq = self.frequency
    return quote
        -- Simple noise: sin-based pseudo-turbulence
        -- Frequency and strength are compile-time constants
        var nx = C.sinf(pos.x * [float](freq) + pos.y * [float](freq) * 1.3f)
        var ny = C.cosf(pos.y * [float](freq) + pos.x * [float](freq) * 0.7f)
        vel.x = vel.x + nx * [float](str) * dt
        vel.y = vel.y + ny * [float](str) * dt
    end
end

function P.Force.Attractor:apply(pos, vel, dt)
    local ax, ay = self.x, self.y
    local str, rad = self.strength, self.radius
    return quote
        var dx = [float](ax) - pos.x
        var dy = [float](ay) - pos.y
        var dist = C.sqrtf(dx*dx + dy*dy) + 0.001f
        if dist < [float](rad) then
            var force = [float](str) / (dist * dist)
            vel.x = vel.x + (dx / dist) * force * dt
            vel.y = vel.y + (dy / dist) * force * dt
        end
    end
end

function P.Force.Vortex:apply(pos, vel, dt)
    local vx, vy, str = self.x, self.y, self.strength
    return quote
        var dx = pos.x - [float](vx)
        var dy = pos.y - [float](vy)
        var dist = C.sqrtf(dx*dx + dy*dy) + 0.001f
        -- Tangential force
        vel.x = vel.x + (-dy / dist) * [float](str) * dt / dist
        vel.y = vel.y + ( dx / dist) * [float](str) * dt / dist
    end
end


-- ============================================================
-- Color interpolation: compiled from color keys
-- ============================================================

local function compile_color_lookup(color_keys)
    -- Returns a macro that takes a `t` quote and returns an RGBA quote
    -- All keys are compile-time constants. Unrolled, no loop.
    return macro(function(t_quote)
        local result = symbol(RGBA, "color")
        local stmts = terralib.newlist()

        -- Default: first key's color
        local ck = color_keys[1]
        stmts:insert(quote
            var [result] = RGBA {
                [float](ck.r), [float](ck.g),
                [float](ck.b), [float](ck.a) }
        end)

        for i = 2, #color_keys do
            local lo = color_keys[i-1]
            local hi = color_keys[i]
            stmts:insert(quote
                if [t_quote] >= [float](lo.t) and [t_quote] < [float](hi.t) then
                    var frac = ([t_quote] - [float](lo.t))
                             / ([float](hi.t) - [float](lo.t))
                    -- __sub and __mul on RGBA handle component-wise math
                    var lo_c = RGBA { [float](lo.r), [float](lo.g),
                                      [float](lo.b), [float](lo.a) }
                    var hi_c = RGBA { [float](hi.r), [float](hi.g),
                                      [float](hi.b), [float](hi.a) }
                    [result] = lo_c + (hi_c - lo_c) * frac
                end
            end)
        end

        return quote [stmts] in [result] end
    end)
end


-- ============================================================
-- The compiler: config → monomorphic update function
-- ============================================================

local compile_updater = terralib.memoize(function(config)
    local forces = config.forces
    local color_lookup = compile_color_lookup(config.color_keys)

    -- The update function: specialized for this exact config.
    -- Forces are inlined. Color keys are unrolled.
    -- No dispatch on force type at runtime.
    return terra(buf: ParticleBuffer, dt: float,
                 out_pos: &Vec2, out_color: &RGBA, out_size: &float) : int
        var alive_count = 0

        -- __for on ParticleBuffer handles iteration
        for p in buf do
            p.age = p.age + dt

            -- Skip dead particles
            if p.age >= p.lifetime then goto continue end

            var t = p.age / p.lifetime  -- 0..1 normalized age

            -- Apply ALL forces — each is inlined, not dispatched
            escape
                for _, force in ipairs(forces) do
                    emit(force:apply(`p.pos, `p.vel, `dt))
                end
            end

            -- Integrate position
            p.pos = p.pos + p.vel * dt

            -- Color lookup — compiled, unrolled, no loop
            out_color[alive_count] = color_lookup(t)

            -- Size lookup — similarly unrolled
            escape
                local sizes = config.size_keys
                local result = symbol(float, "size")
                local stmts = terralib.newlist()
                stmts:insert(quote var [result] = [float](sizes[1].size) end)
                for i = 2, #sizes do
                    local lo, hi = sizes[i-1], sizes[i]
                    stmts:insert(quote
                        if t >= [float](lo.t) and t < [float](hi.t) then
                            var frac = (t - [float](lo.t))
                                     / ([float](hi.t) - [float](lo.t))
                            [result] = [float](lo.size)
                                     + frac * ([float](hi.size) - [float](lo.size))
                        end
                    end)
                end
                emit quote [stmts]; out_size[alive_count] = [result] end
            end

            out_pos[alive_count] = p.pos
            alive_count = alive_count + 1
            ::continue::
        end

        return alive_count
    end
end)


-- ============================================================
-- Usage
-- ============================================================

-- Define a fire particle system
local fire = P.SystemConfig(
    -- Forces: gravity pulls up, drag slows, turbulence adds life
    List {
        P.Gravity(0, -50),
        P.Drag(0.5),
        P.Turbulence(30, 2.0),
    },
    -- Color: white → yellow → orange → red → black
    List {
        P.ColorKey(0.0,  1.0, 1.0, 0.9, 1.0),
        P.ColorKey(0.2,  1.0, 0.8, 0.2, 0.9),
        P.ColorKey(0.5,  0.9, 0.3, 0.1, 0.7),
        P.ColorKey(0.8,  0.3, 0.1, 0.05, 0.3),
        P.ColorKey(1.0,  0.0, 0.0, 0.0, 0.0),
    },
    -- Size: grow then shrink
    List {
        P.SizeKey(0.0, 2.0),
        P.SizeKey(0.3, 5.0),
        P.SizeKey(1.0, 0.0),
    },
    -- Emit: 200 particles/sec, 1.5s lifetime, 50-100 speed, 30° spread
    200, 1.5, 50, 100, 30
)

-- Compile the updater for this specific fire configuration.
-- terralib.memoize: same SystemConfig (unique) → same function.
local update_fire = compile_updater(fire)
update_fire:compile()

-- The compiled function has:
-- - Gravity: vel.y -= 50*dt (constant folded)
-- - Drag: vel *= (1 - 0.5*dt) (coefficient baked in)
-- - Turbulence: sin/cos with freq=2.0, str=30 baked in
-- - Color: 5 keys, 4 lerps, unrolled
-- - Size: 3 keys, 2 lerps, unrolled
-- - No force-type dispatch, no color key array, no runtime config
update_fire:disas()

-- Changing to a snow system: different forces, different colors.
-- A completely different compiled function.
local snow = P.SystemConfig(
    List { P.Gravity(0, 20), P.Turbulence(15, 0.5) },
    List {
        P.ColorKey(0.0, 1,1,1, 0.0),
        P.ColorKey(0.1, 1,1,1, 0.8),
        P.ColorKey(0.9, 1,1,1, 0.8),
        P.ColorKey(1.0, 1,1,1, 0.0),
    },
    List { P.SizeKey(0.0, 3.0), P.SizeKey(1.0, 3.0) },
    100, 4.0, 10, 30, 180
)

local update_snow = compile_updater(snow)
-- Different config → different terralib.memoize key → new function.
-- But if we call compile_updater(fire) again, we get the cached one.
```

What this example demonstrates:

- **ASDL types** (`Force`, `ColorKey`, `SizeKey`, `SystemConfig`) model the domain
- **`unique` on `SystemConfig`** means structurally identical configs are `==`, enabling `terralib.memoize`
- **ASDL methods** (`Force:apply`) return Terra quotes — each force variant produces different code
- **`escape/emit`** iterates the force list — the only place Lua loops over ASDL children
- **`__for` on `ParticleBuffer`** generates the particle iteration loop
- **`__add`, `__sub`, `__mul` on `Vec2` and `RGBA`** make arithmetic read naturally
- **`macro()`** for `color_lookup` — a macro that receives a quote (`t`) and returns a quote (interpolated color)
- **`terralib.memoize`** caches by `SystemConfig` identity — same particle system config → same compiled function
- **Compile-time constant folding**: force parameters, color keys, and size keys are all Lua numbers that become constants in the generated code. LLVM folds `0 - 50*dt` to `-50*dt`, etc.

The fire updater and snow updater are completely different compiled functions. Each contains only the forces, colors, and sizes for that specific system. No runtime dispatch on force type, no array of color keys, no config struct to read. Just arithmetic.


## Summary

The pattern rests on **exotypes** (DeVito et al., PLDI 2014): user-defined types whose behavior and layout are defined by Lua property functions queried lazily during Terra's typechecking. We structure these property functions using four facilities:

1. **`require 'asdl'`** — define domain types with modules, sum types, product types, unique, external types. Methods on types return Terra quotes. ASDL is the domain model that exotype property functions inspect.

2. **Struct metamethods + macros** — these ARE the exotype property functions. `__getentries` computes layout. `__entrymissing` and `__methodmissing` (macros) dispatch at compile time. `__cast` handles conversions. `__for` generates iteration. `__staticinitialize` generates post-layout code. Operators define domain arithmetic. Each returns a quote that implements the operation — the `(Opᵢ → Quote)` from the formal model.

3. **`terralib.memoize`** — same configuration → same compiled function. Combined with ASDL `unique`, gives structural caching. Combined with lazy property evaluation, gives composable type constructors.

4. **The schema DSL** (optional, separate project) — a Terra language extension that replaces raw ASDL definition strings with validated syntax. Uses Terra's language extension API and Pratt parser to make ASDL structural errors into standard Terra errors with file names and line numbers. Checks variant count, field uniqueness, phase ordering, method direction, type resolution, recursion safety, and value constraints. Produces the same ASDL contexts as `context:Define()`. Everything downstream works identically.

The developer's job: define the domain in ASDL (via the schema DSL or raw strings). Write `:compile(ctx)` methods that return quotes. Install exotype properties (metamethods) on the output structs. Wrap the generator in `terralib.memoize`. Everything else — typechecking, property evaluation, cycle detection, caching, code generation, LLVM optimization — is Terra.
