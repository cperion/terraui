local asdl = require("asdl")

local unpack_fn = table and table.unpack or unpack

local function push(t, v)
    t[#t + 1] = v
    return v
end

local builtin_types = {
    ["nil"] = true,
    ["any"] = true,
    ["number"] = true,
    ["string"] = true,
    ["boolean"] = true,
    ["table"] = true,
    ["thread"] = true,
    ["userdata"] = true,
    ["cdata"] = true,
    ["function"] = true,
}

local function parse_name(lex)
    return lex:expect(lex.name).value
end

local function parse_dotted_name(lex)
    local name = parse_name(lex)
    while lex:nextif(".") do
        name = name .. "." .. parse_name(lex)
    end
    return name
end

local function expect_arrow(lex)
    if lex:nextif("->") then
        return
    end
    lex:expect("-")
    lex:expect(">")
end

local function parse_constraint_term(lex)
    if lex:nextif("-") then
        local tok = lex:expect(lex.number)
        return { kind = "literal", value = -tok.value }
    elseif lex:matches(lex.number) then
        return { kind = "literal", value = lex:next().value }
    elseif lex:matches(lex.string) then
        return { kind = "literal", value = lex:next().value }
    elseif lex:nextif("true") then
        return { kind = "literal", value = true }
    elseif lex:nextif("false") then
        return { kind = "literal", value = false }
    elseif lex:nextif("nil") then
        return { kind = "literal", value = nil }
    elseif lex:matches(lex.name) then
        return { kind = "field", name = parse_name(lex) }
    end
    lex:error("expected constraint term")
end

local function parse_constraint_op(lex)
    local ops = {
        ["<"] = true,
        ["<="] = true,
        [">"] = true,
        [">="] = true,
        ["=="] = true,
        ["~="] = true,
    }
    local tok = lex:cur().type
    if ops[tok] then
        lex:next()
        return tok
    end
    lex:error("expected constraint comparison operator")
end

local function parse_constraint_chain(lex)
    local chain = {
        kind = "chain",
        terms = { parse_constraint_term(lex) },
        ops = {},
    }
    push(chain.ops, parse_constraint_op(lex))
    push(chain.terms, parse_constraint_term(lex))
    while true do
        local tok = lex:cur().type
        if tok == "<" or tok == "<=" or tok == ">" or tok == ">=" or tok == "==" or tok == "~=" then
            push(chain.ops, parse_constraint_op(lex))
            push(chain.terms, parse_constraint_term(lex))
        else
            break
        end
    end
    return chain
end

local function parse_constraint_expr(lex)
    local expr = {
        kind = "and",
        parts = { parse_constraint_chain(lex) },
    }
    while lex:nextif("and") do
        push(expr.parts, parse_constraint_chain(lex))
    end
    return expr
end

local function parse_field(lex)
    local field = {
        name = parse_name(lex),
    }
    lex:expect(":")
    field.type = parse_dotted_name(lex)
    if lex:nextif("?") then
        field.mod = "?"
    elseif lex:nextif("*") then
        field.mod = "*"
    end
    if lex:nextif("=") then
        field.default = lex:luaexpr()
    end
    if lex:nextif("where") then
        field.constraint = parse_constraint_expr(lex)
    end
    return field
end

local function parse_field_list_in_braces(lex)
    local fields = {}
    lex:expect("{")
    if not lex:matches("}") then
        repeat
            push(fields, parse_field(lex))
        until not lex:nextif(",")
    end
    lex:expect("}")
    return fields
end

local function parse_record(lex, phase)
    lex:expect("record")
    local decl = {
        kind = "record",
        phase = phase.name,
        name = parse_name(lex),
        fields = {},
        unique = false,
    }
    if phase.type_names[decl.name] then
        lex:error(("duplicate type '%s' in phase '%s'"):format(decl.name, phase.name))
    end
    phase.type_names[decl.name] = true

    while not lex:matches("end") do
        if lex:nextif("unique") then
            decl.unique = true
        else
            push(decl.fields, parse_field(lex))
            lex:nextif(",")
        end
    end
    lex:expect("end")
    return decl
end

local function parse_enum(lex, phase)
    lex:expect("enum")
    local decl = {
        kind = "enum",
        phase = phase.name,
        name = parse_name(lex),
        variants = {},
    }
    if phase.type_names[decl.name] then
        lex:error(("duplicate type '%s' in phase '%s'"):format(decl.name, phase.name))
    end
    phase.type_names[decl.name] = true

    local variant_names = {}
    while not lex:matches("end") do
        local variant = {
            name = parse_name(lex),
            fields = nil,
            unique = false,
        }
        if variant_names[variant.name] then
            lex:error(("duplicate variant '%s' in enum '%s'"):format(variant.name, decl.name))
        end
        variant_names[variant.name] = true

        if lex:matches("{") then
            variant.fields = parse_field_list_in_braces(lex)
        end
        if lex:nextif("unique") then
            variant.unique = true
        end
        push(decl.variants, variant)
        lex:nextif(",")
    end
    lex:expect("end")
    return decl
end

local function parse_flags(lex, phase)
    lex:expect("flags")
    local decl = {
        kind = "flags",
        phase = phase.name,
        name = parse_name(lex),
        values = {},
    }
    if phase.type_names[decl.name] then
        lex:error(("duplicate type '%s' in phase '%s'"):format(decl.name, phase.name))
    end
    phase.type_names[decl.name] = true

    local value_names = {}
    while not lex:matches("end") do
        local value = parse_name(lex)
        if value_names[value] then
            lex:error(("duplicate flag '%s' in flags '%s'"):format(value, decl.name))
        end
        value_names[value] = true
        push(decl.values, value)
        lex:nextif(",")
    end
    lex:expect("end")
    return decl
end

local function parse_method_arg(lex)
    local arg = {
        name = parse_name(lex),
    }
    lex:expect(":")
    arg.type = parse_dotted_name(lex)
    return arg
end

local function parse_methods(lex, phase)
    lex:expect("methods")
    local decl = {
        kind = "methods",
        phase = phase.name,
        items = {},
    }

    while not lex:matches("end") do
        local item = {
            receiver = parse_dotted_name(lex),
        }
        lex:expect(":")
        item.name = parse_name(lex)
        item.args = {}
        lex:expect("(")
        if not lex:matches(")") then
            repeat
                push(item.args, parse_method_arg(lex))
            until not lex:nextif(",")
        end
        lex:expect(")")
        expect_arrow(lex)
        item.return_type = parse_dotted_name(lex)
        push(decl.items, item)
        lex:nextif(",")
    end
    lex:expect("end")
    return decl
end

local function parse_phase(lex, schema)
    lex:expect("phase")
    local phase = {
        kind = "phase",
        name = parse_name(lex),
        decls = {},
        type_names = {},
    }
    if schema.phase_names[phase.name] then
        lex:error(("duplicate phase '%s'"):format(phase.name))
    end
    schema.phase_names[phase.name] = true

    while not lex:matches("end") do
        if lex:matches("record") then
            push(phase.decls, parse_record(lex, phase))
        elseif lex:matches("enum") then
            push(phase.decls, parse_enum(lex, phase))
        elseif lex:matches("flags") then
            push(phase.decls, parse_flags(lex, phase))
        elseif lex:matches("methods") then
            push(phase.decls, parse_methods(lex, phase))
        else
            lex:error(("expected record, enum, flags, methods, or end in phase '%s'"):format(phase.name))
        end
    end
    lex:expect("end")
    phase.type_names = nil
    return phase
end

local function parse_extern(lex, schema)
    lex:expect("extern")
    local ext = {
        name = parse_name(lex),
    }
    if schema.extern_names[ext.name] then
        lex:error(("duplicate extern '%s'"):format(ext.name))
    end
    schema.extern_names[ext.name] = true
    lex:expect("=")
    ext.expr = lex:luaexpr()
    return ext
end

local function parse_schema(lex)
    lex:expect("schema")
    local schema = {
        kind = "schema",
        name = parse_name(lex),
        externs = {},
        phases = {},
        phase_names = {},
        extern_names = {},
    }

    while not lex:matches("end") do
        if lex:matches("extern") then
            push(schema.externs, parse_extern(lex, schema))
        elseif lex:matches("phase") then
            push(schema.phases, parse_phase(lex, schema))
        else
            lex:error("expected extern, phase, or end inside schema")
        end
    end
    lex:expect("end")
    schema.phase_names = nil
    schema.extern_names = nil
    return schema
end

local function emit_field(field)
    local ty = field.type
    if field.mod then
        ty = ty .. field.mod
    end
    return ty .. " " .. field.name
end

local function emit_field_tuple(fields)
    if #fields == 0 then
        return "()"
    end
    local parts = {}
    for i, field in ipairs(fields) do
        parts[i] = emit_field(field)
    end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local function emit_record(decl, indent)
    local line = indent .. decl.name .. " = " .. emit_field_tuple(decl.fields)
    if decl.unique then
        line = line .. " unique"
    end
    return { line }
end

local function emit_variant(variant)
    local line = variant.name
    if variant.fields ~= nil then
        line = line .. emit_field_tuple(variant.fields)
    end
    if variant.unique then
        line = line .. " unique"
    end
    return line
end

local function emit_enum(decl, indent)
    local lines = {}
    for i, variant in ipairs(decl.variants) do
        local prefix = (i == 1) and (indent .. decl.name .. " = ") or (indent .. "     | ")
        push(lines, prefix .. emit_variant(variant))
    end
    return lines
end

local function emit_flags(decl, indent)
    local lines = {}
    for i, value in ipairs(decl.values) do
        local prefix = (i == 1) and (indent .. decl.name .. " = ") or (indent .. "     | ")
        push(lines, prefix .. value)
    end
    return lines
end

local function emit_asdl(schema)
    local lines = {}
    for pindex, phase in ipairs(schema.phases) do
        push(lines, ("module %s {"):format(phase.name))
        for dindex, decl in ipairs(phase.decls) do
            if decl.kind == "record" then
                for _, line in ipairs(emit_record(decl, "    ")) do
                    push(lines, line)
                end
            elseif decl.kind == "enum" then
                for _, line in ipairs(emit_enum(decl, "    ")) do
                    push(lines, line)
                end
            elseif decl.kind == "flags" then
                for _, line in ipairs(emit_flags(decl, "    ")) do
                    push(lines, line)
                end
            elseif decl.kind == "methods" then
                -- ASDL itself does not support methods; they are preserved as metadata.
            else
                error("unknown declaration kind: " .. tostring(decl.kind))
            end
            if dindex < #phase.decls then
                push(lines, "")
            end
        end
        push(lines, "}")
        if pindex < #schema.phases then
            push(lines, "")
        end
    end
    return table.concat(lines, "\n")
end

local function qualify_type_name(type_name, phase_name, extern_lookup)
    if type_name:find("%.") then
        return type_name
    end
    if builtin_types[type_name] or extern_lookup[type_name] then
        return type_name
    end
    return phase_name .. "." .. type_name
end

local function collect_methods(schema)
    local extern_lookup = {}
    for _, ext in ipairs(schema.externs) do
        extern_lookup[ext.name] = true
    end

    local methods = {}
    for _, phase in ipairs(schema.phases) do
        for _, decl in ipairs(phase.decls) do
            if decl.kind == "methods" then
                for _, item in ipairs(decl.items) do
                    local method = {
                        phase = phase.name,
                        receiver = qualify_type_name(item.receiver, phase.name, extern_lookup),
                        name = item.name,
                        args = {},
                        return_type = qualify_type_name(item.return_type, phase.name, extern_lookup),
                    }
                    for _, arg in ipairs(item.args) do
                        push(method.args, {
                            name = arg.name,
                            type = qualify_type_name(arg.type, phase.name, extern_lookup),
                        })
                    end
                    push(methods, method)
                end
            end
        end
    end
    return methods
end

local function make_extern_lookup(schema)
    local extern_lookup = {}
    for _, ext in ipairs(schema.externs) do
        extern_lookup[ext.name] = true
    end
    return extern_lookup
end

local function build_type_index(schema)
    local index = {}
    local phase_order = {}

    for i, phase in ipairs(schema.phases) do
        phase_order[phase.name] = i
        for _, decl in ipairs(phase.decls) do
            if decl.kind == "record" or decl.kind == "enum" or decl.kind == "flags" then
                local fqname = phase.name .. "." .. decl.name
                if index[fqname] then
                    return nil, ("duplicate type name '%s'"):format(fqname)
                end
                index[fqname] = {
                    fqname = fqname,
                    phase = phase.name,
                    phase_index = i,
                    kind = decl.kind,
                    decl = decl,
                }
            end
            if decl.kind == "enum" then
                for _, variant in ipairs(decl.variants) do
                    local vqname = phase.name .. "." .. variant.name
                    if index[vqname] then
                        return nil, ("duplicate constructor/type name '%s'"):format(vqname)
                    end
                    index[vqname] = {
                        fqname = vqname,
                        phase = phase.name,
                        phase_index = i,
                        kind = "variant",
                        parent = phase.name .. "." .. decl.name,
                        decl = variant,
                    }
                end
            end
        end
    end

    return index, phase_order
end

local function resolve_type_ref(type_name, phase_name, extern_lookup)
    return qualify_type_name(type_name, phase_name, extern_lookup)
end

local function validate_unique_field_names(fields, owner_name)
    local names = {}
    for _, field in ipairs(fields) do
        if names[field.name] then
            return ("duplicate field '%s' in '%s'"):format(field.name, owner_name)
        end
        names[field.name] = true
    end
end

local function validate_field_refs(fields, owner_name, phase_name, type_index, extern_lookup)
    local err = validate_unique_field_names(fields, owner_name)
    if err then
        return err
    end

    local field_names = {}
    for _, field in ipairs(fields) do
        field_names[field.name] = true
        local resolved = resolve_type_ref(field.type, phase_name, extern_lookup)
        if not builtin_types[resolved] and not extern_lookup[resolved] and not type_index[resolved] then
            return ("field '%s' in '%s' references unknown type '%s'"):format(field.name, owner_name, resolved)
        end
    end

    for _, field in ipairs(fields) do
        if field.constraint then
            for _, chain in ipairs(field.constraint.parts) do
                for _, term in ipairs(chain.terms) do
                    if term.kind == "field" and not field_names[term.name] then
                        return ("constraint for '%s.%s' references unknown field '%s'"):format(owner_name, field.name, term.name)
                    end
                end
            end
        end
    end
end

local function validate_method_decl(item, phase_name, type_index, extern_lookup)
    local receiver = resolve_type_ref(item.receiver, phase_name, extern_lookup)
    local return_type = resolve_type_ref(item.return_type, phase_name, extern_lookup)

    if builtin_types[receiver] or extern_lookup[receiver] then
        return ("method receiver '%s' must be a schema type, not builtin/extern type '%s'"):format(item.name, receiver)
    end
    if not type_index[receiver] then
        return ("method '%s' references unknown receiver type '%s'"):format(item.name, receiver)
    end

    if not builtin_types[return_type] and not extern_lookup[return_type] and not type_index[return_type] then
        return ("method '%s' returns unknown type '%s'"):format(item.name, return_type)
    end

    for _, arg in ipairs(item.args) do
        local arg_type = resolve_type_ref(arg.type, phase_name, extern_lookup)
        if not builtin_types[arg_type] and not extern_lookup[arg_type] and not type_index[arg_type] then
            return ("method '%s' argument '%s' references unknown type '%s'"):format(item.name, arg.name, arg_type)
        end
    end

    local receiver_phase = type_index[receiver].phase_index
    local return_info = type_index[return_type]
    if return_info and return_info.phase_index < receiver_phase then
        return ("method '%s' on '%s' returns earlier-phase type '%s'"):format(item.name, receiver, return_type)
    end
end

local function validate_schema(schema)
    local extern_lookup = make_extern_lookup(schema)
    local type_index, phase_order_or_err = build_type_index(schema)
    if not type_index then
        return phase_order_or_err
    end
    local phase_order = phase_order_or_err

    for _, phase in ipairs(schema.phases) do
        for _, decl in ipairs(phase.decls) do
            if decl.kind == "record" then
                local err = validate_field_refs(decl.fields, phase.name .. "." .. decl.name, phase.name, type_index, extern_lookup)
                if err then
                    return err
                end
            elseif decl.kind == "enum" then
                if #decl.variants < 2 then
                    return ("enum '%s.%s' must have at least 2 variants; use a record instead"):format(phase.name, decl.name)
                end
                for _, variant in ipairs(decl.variants) do
                    local fields = variant.fields or {}
                    local err = validate_field_refs(fields, phase.name .. "." .. variant.name, phase.name, type_index, extern_lookup)
                    if err then
                        return err
                    end
                end
            elseif decl.kind == "methods" then
                local seen = {}
                for _, item in ipairs(decl.items) do
                    local receiver = resolve_type_ref(item.receiver, phase.name, extern_lookup)
                    local sig_key = receiver .. ":" .. item.name
                    if seen[sig_key] then
                        return ("duplicate method declaration '%s' in phase '%s'"):format(sig_key, phase.name)
                    end
                    seen[sig_key] = true
                    local err = validate_method_decl(item, phase.name, type_index, extern_lookup)
                    if err then
                        return err
                    end
                end
            end
        end
    end

    return nil, {
        type_index = type_index,
        phase_order = phase_order,
        extern_lookup = extern_lookup,
    }
end

local function eval_constraint_term(term, field_env)
    if term.kind == "literal" then
        return term.value
    elseif term.kind == "field" then
        return field_env[term.name]
    end
    error("unknown constraint term kind: " .. tostring(term.kind))
end

local function apply_constraint_op(op, lhs, rhs)
    if op == "<" then
        return lhs < rhs
    elseif op == "<=" then
        return lhs <= rhs
    elseif op == ">" then
        return lhs > rhs
    elseif op == ">=" then
        return lhs >= rhs
    elseif op == "==" then
        return lhs == rhs
    elseif op == "~=" then
        return lhs ~= rhs
    end
    error("unknown constraint operator: " .. tostring(op))
end

local function constraint_to_string(expr)
    if not expr then
        return ""
    end
    local pieces = {}
    for i, chain in ipairs(expr.parts or {}) do
        local chain_pieces = {}
        for j, term in ipairs(chain.terms) do
            if term.kind == "literal" then
                push(chain_pieces, tostring(term.value))
            else
                push(chain_pieces, term.name)
            end
            if chain.ops[j] then
                push(chain_pieces, chain.ops[j])
            end
        end
        push(pieces, table.concat(chain_pieces, " "))
        if i < #(expr.parts or {}) then
            push(pieces, "and")
        end
    end
    return table.concat(pieces, " ")
end

local function check_constraint(expr, field_env)
    for _, chain in ipairs(expr.parts) do
        for i, op in ipairs(chain.ops) do
            local lhs = eval_constraint_term(chain.terms[i], field_env)
            local rhs = eval_constraint_term(chain.terms[i + 1], field_env)
            if not apply_constraint_op(op, lhs, rhs) then
                return false
            end
        end
    end
    return true
end

local function install_field_wrapper(class, owner_name, fields, schema_env)
    local needs_wrapper = false
    for _, field in ipairs(fields) do
        if field.default or field.constraint then
            needs_wrapper = true
            break
        end
    end
    if not needs_wrapper then
        return
    end

    local mt = getmetatable(class)
    local original_call = mt.__call
    mt.__call = function(self, ...)
        local values = {}
        local field_env = {}
        for i, field in ipairs(fields) do
            local v = select(i, ...)
            if v == nil and field.default then
                v = field.default(schema_env)
            end
            values[i] = v
            field_env[field.name] = v
        end
        for _, field in ipairs(fields) do
            if field.constraint and not check_constraint(field.constraint, field_env) then
                error(("constraint failed for %s.%s: %s"):format(owner_name, field.name, constraint_to_string(field.constraint)), 2)
            end
        end
        return original_call(self, unpack_fn(values, 1, #fields))
    end
end

local function install_defaults_and_constraints(ctx, schema_ast, schema_env)
    for _, phase in ipairs(schema_ast.phases) do
        local ns = ctx[phase.name]
        for _, decl in ipairs(phase.decls) do
            if decl.kind == "record" then
                install_field_wrapper(ns[decl.name], phase.name .. "." .. decl.name, decl.fields, schema_env)
            elseif decl.kind == "enum" then
                for _, variant in ipairs(decl.variants) do
                    if variant.fields then
                        install_field_wrapper(ns[variant.name], phase.name .. "." .. variant.name, variant.fields, schema_env)
                    end
                end
            end
        end
    end
end

local function build_schema_object(schema_ast, env)
    local ctx = asdl.NewContext()
    local extern_values = {}

    for _, ext in ipairs(schema_ast.externs) do
        local checker = ext.expr(env)
        if type(checker) ~= "function" then
            error(("extern '%s' must evaluate to a checker function, got %s"):format(ext.name, type(checker)))
        end
        ctx:Extern(ext.name, checker)
        extern_values[ext.name] = checker
    end

    local asdl_text = emit_asdl(schema_ast)
    ctx:Define(asdl_text)
    install_defaults_and_constraints(ctx, schema_ast, env)

    local phases = {}
    for _, phase in ipairs(schema_ast.phases) do
        push(phases, phase.name)
    end

    return setmetatable({
        name = schema_ast.name,
        types = ctx,
        phases = phases,
        methods = collect_methods(schema_ast),
        externs = extern_values,
        asdl = asdl_text,
        ast = schema_ast,
    }, {
        __tostring = function(self)
            return ("Schema(%s)"):format(self.name)
        end,
    })
end

local function parse_and_construct(lex)
    local schema_ast = parse_schema(lex)
    local validation_error = validate_schema(schema_ast)
    if validation_error then
        lex:error(validation_error)
    end
    local constructor = function(envfn)
        local env = envfn and envfn() or {}
        return build_schema_object(schema_ast, env)
    end
    return schema_ast, constructor
end

local schema_lang = {
    name = "schema",
    entrypoints = { "schema" },
    keywords = { "extern", "phase", "record", "enum", "flags", "methods", "unique", "where" },
}

function schema_lang:expression(lex)
    local _, constructor = parse_and_construct(lex)
    return constructor
end

function schema_lang:statement(lex)
    local schema_ast, constructor = parse_and_construct(lex)
    return constructor, { schema_ast.name }
end

function schema_lang:localstatement(lex)
    local schema_ast, constructor = parse_and_construct(lex)
    return constructor, { schema_ast.name }
end

return schema_lang
