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

local function next_name_value(lex, value)
    if lex:matches(lex.name) and lex:cur().value == value then
        lex:next()
        return true
    end
    return false
end

local function current_line(lex)
    local tok = lex:cur()
    return tok and tok.linenumber or nil
end

local function read_file_text(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local text = f:read("*all")
    f:close()
    return text
end

local function get_lex_source_text(lex)
    if lex._schema_source_text ~= nil then
        return lex._schema_source_text or nil
    end

    local src = rawget(lex, "source")
    local tok = lex:cur()
    local filename = tok and tok.filename or (type(src) == "table" and src.filename)
    if filename then
        local text = read_file_text(filename)
        if text then
            lex._schema_source_text = text
            return text
        end
    end

    if type(src) == "string" and src:find("\n", 1, true) then
        lex._schema_source_text = src
        return src
    elseif type(src) == "table" then
        for _, key in ipairs({ "text", "string", "src", "source", "contents" }) do
            if type(src[key]) == "string" and src[key]:find("\n", 1, true) then
                lex._schema_source_text = src[key]
                return src[key]
            end
        end
    end

    lex._schema_source_text = false
    return nil
end

local function previous_line_range(text, end_idx)
    if not text or end_idx < 1 then
        return nil
    end
    local line_end = end_idx
    while line_end > 0 and text:sub(line_end, line_end) == "\r" do
        line_end = line_end - 1
    end
    if line_end < 1 then
        return nil
    end
    local line_start = line_end
    while line_start > 1 and text:sub(line_start - 1, line_start - 1) ~= "\n" do
        line_start = line_start - 1
    end
    return line_start, line_end
end

local function attached_doc_comment(lex)
    local text = get_lex_source_text(lex)
    local tok = lex:cur()
    if not text or not tok or not tok.offset then
        return nil
    end

    local token_text = tostring(tok.value or tok.type)
    local token_start = tok.offset - #token_text + 2
    local line_start = token_start
    while line_start > 1 and text:sub(line_start - 1, line_start - 1) ~= "\n" do
        line_start = line_start - 1
    end

    local prefix = text:sub(line_start, token_start - 1)
    if not (prefix:match("^%s*$") or prefix:match("^%s*local%s+$")) then
        return nil
    end

    local idx = line_start - 2
    local parts = {}
    while idx > 0 do
        local prev_line_start, prev_line_end = previous_line_range(text, idx)
        if not prev_line_start then
            break
        end
        local line = text:sub(prev_line_start, prev_line_end)
        local doc_text = line:match("^%s*%-%-%-(.*)$")
        if doc_text ~= nil then
            if doc_text:sub(1, 1) == " " then
                doc_text = doc_text:sub(2)
            end
            table.insert(parts, 1, doc_text)
            idx = prev_line_start - 2
        elseif line:match("^%s*$") then
            if #parts == 0 then
                return nil
            end
            break
        else
            break
        end
    end

    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "\n")
end

local function parse_text_value(lex)
    lex:expect("=")
    return lex:expect(lex.string).value
end

local function parse_doc_value(lex)
    lex:nextif("=")
    return lex:expect(lex.string).value
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
        line = current_line(lex),
        doc = attached_doc_comment(lex),
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
    while true do
        if next_name_value(lex, "doc") then
            field.doc = parse_doc_value(lex)
        else
            break
        end
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
    local line = current_line(lex)
    local doc = attached_doc_comment(lex)
    lex:expect("record")
    local decl = {
        kind = "record",
        phase = phase.name,
        line = line,
        doc = doc,
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
        elseif next_name_value(lex, "doc") then
            decl.doc = parse_doc_value(lex)
        else
            push(decl.fields, parse_field(lex))
            lex:nextif(",")
        end
    end
    lex:expect("end")
    return decl
end

local function parse_enum(lex, phase)
    local line = current_line(lex)
    local doc = attached_doc_comment(lex)
    lex:expect("enum")
    local decl = {
        kind = "enum",
        phase = phase.name,
        line = line,
        doc = doc,
        name = parse_name(lex),
        variants = {},
    }
    if phase.type_names[decl.name] then
        lex:error(("duplicate type '%s' in phase '%s'"):format(decl.name, phase.name))
    end
    phase.type_names[decl.name] = true

    local variant_names = {}
    while not lex:matches("end") do
        if next_name_value(lex, "doc") then
            decl.doc = parse_doc_value(lex)
            lex:nextif(",")
        else
            local variant = {
                line = current_line(lex),
                doc = attached_doc_comment(lex),
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
            while true do
                if next_name_value(lex, "doc") then
                    variant.doc = parse_doc_value(lex)
                else
                    break
                end
            end
            push(decl.variants, variant)
            lex:nextif(",")
        end
    end
    lex:expect("end")
    return decl
end

local function parse_flags(lex, phase)
    local line = current_line(lex)
    local doc = attached_doc_comment(lex)
    lex:expect("flags")
    local decl = {
        kind = "flags",
        phase = phase.name,
        line = line,
        doc = doc,
        name = parse_name(lex),
        values = {},
    }
    if phase.type_names[decl.name] then
        lex:error(("duplicate type '%s' in phase '%s'"):format(decl.name, phase.name))
    end
    phase.type_names[decl.name] = true

    local value_names = {}
    while not lex:matches("end") do
        if next_name_value(lex, "doc") then
            decl.doc = parse_doc_value(lex)
            lex:nextif(",")
        else
            local value = {
                line = current_line(lex),
                doc = attached_doc_comment(lex),
                name = parse_name(lex),
            }
            if value_names[value.name] then
                lex:error(("duplicate flag '%s' in flags '%s'"):format(value.name, decl.name))
            end
            value_names[value.name] = true
            while true do
                if next_name_value(lex, "doc") then
                    value.doc = parse_doc_value(lex)
                else
                    break
                end
            end
            push(decl.values, value)
            lex:nextif(",")
        end
    end
    lex:expect("end")
    return decl
end

local function parse_method_arg(lex)
    local arg = {
        line = current_line(lex),
        doc = attached_doc_comment(lex),
        name = parse_name(lex),
    }
    lex:expect(":")
    arg.type = parse_dotted_name(lex)
    while true do
        if next_name_value(lex, "doc") then
            arg.doc = parse_doc_value(lex)
        else
            break
        end
    end
    return arg
end

local hook_specs = {
    getentries = { key = "__getentries", family = "layout", mode = "impl" },
    staticinitialize = { key = "__staticinitialize", family = "lifecycle", mode = "impl" },
    getmethod = { key = "__getmethod", family = "dispatch", mode = "impl" },
    methodmissing = { key = "__methodmissing", family = "dispatch", mode = "macro" },
    entrymissing = { key = "__entrymissing", family = "dispatch", mode = "macro" },
    cast = { key = "__cast", family = "conversion", mode = "impl" },
    ["for"] = { key = "__for", family = "iteration", mode = "impl" },
    typename = { key = "__typename", family = "display", mode = "impl" },
    add = { key = "__add", family = "operator", mode = "either" },
    sub = { key = "__sub", family = "operator", mode = "either" },
    mul = { key = "__mul", family = "operator", mode = "either" },
    div = { key = "__div", family = "operator", mode = "either" },
    mod = { key = "__mod", family = "operator", mode = "either" },
    lt = { key = "__lt", family = "operator", mode = "either" },
    le = { key = "__le", family = "operator", mode = "either" },
    gt = { key = "__gt", family = "operator", mode = "either" },
    ge = { key = "__ge", family = "operator", mode = "either" },
    eq = { key = "__eq", family = "operator", mode = "either" },
    ne = { key = "__ne", family = "operator", mode = "either" },
    ["and"] = { key = "__and", family = "operator", mode = "either" },
    ["or"] = { key = "__or", family = "operator", mode = "either" },
    ["not"] = { key = "__not", family = "operator", mode = "either" },
    band = { key = "__and", family = "operator", mode = "either" },
    bor = { key = "__or", family = "operator", mode = "either" },
    bnot = { key = "__not", family = "operator", mode = "either" },
    xor = { key = "__xor", family = "operator", mode = "either" },
    lshift = { key = "__lshift", family = "operator", mode = "either" },
    rshift = { key = "__rshift", family = "operator", mode = "either" },
    select = { key = "__select", family = "operator", mode = "either" },
    apply = { key = "__apply", family = "operator", mode = "either" },
}

local reserved_hook_tokens = {
    ["for"] = true,
    ["and"] = true,
    ["or"] = true,
    ["not"] = true,
}

local function parse_method_item(lex)
    local item = {
        line = current_line(lex),
        doc = attached_doc_comment(lex),
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

    if lex:nextif("=") then
        item.impl = lex:luaexpr()
        return item
    end

    while true do
        if next_name_value(lex, "doc") then
            item.doc = parse_doc_value(lex)
        elseif next_name_value(lex, "status") then
            lex:expect("=")
            item.status = lex:luaexpr()
        elseif next_name_value(lex, "fallback") then
            lex:expect("=")
            item.fallback = lex:luaexpr()
        elseif next_name_value(lex, "impl") then
            lex:expect("=")
            item.impl = lex:luaexpr()
        else
            break
        end
    end

    return item
end

local function parse_methods(lex, phase)
    local line = current_line(lex)
    local doc = attached_doc_comment(lex)
    lex:expect("methods")
    local decl = {
        kind = "methods",
        phase = phase.name,
        line = line,
        doc = doc,
        items = {},
    }

    while not lex:matches("end") do
        if next_name_value(lex, "doc") then
            decl.doc = parse_doc_value(lex)
            lex:nextif(",")
        else
            push(decl.items, parse_method_item(lex))
            lex:nextif(",")
        end
    end
    lex:expect("end")
    return decl
end

local function parse_hook_name(lex)
    if lex:matches(lex.name) then
        return parse_name(lex):lower()
    end
    local tok = lex:cur()
    if reserved_hook_tokens[tok.type] or reserved_hook_tokens[tok.value] then
        return tostring(lex:next().value or tok.type)
    end
    lex:error("hook name expected")
end

local function parse_hook_item(lex)
    local item = {
        line = current_line(lex),
        doc = attached_doc_comment(lex),
        name = parse_hook_name(lex),
    }

    local spec = hook_specs[item.name]
    item.key = spec and spec.key or ("__" .. item.name)

    while true do
        if next_name_value(lex, "doc") then
            item.doc = parse_doc_value(lex)
        elseif next_name_value(lex, "impl") then
            lex:expect("=")
            item.impl = lex:luaexpr()
        elseif next_name_value(lex, "macro") then
            lex:expect("=")
            item.macro = lex:luaexpr()
        else
            break
        end
    end

    return item
end

local function parse_hooks(lex)
    local line = current_line(lex)
    local doc = attached_doc_comment(lex)
    lex:expect("hooks")
    local decl = {
        kind = "hooks",
        line = line,
        doc = doc,
        target = parse_dotted_name(lex),
        items = {},
    }

    while not lex:matches("end") do
        if next_name_value(lex, "doc") then
            decl.doc = parse_doc_value(lex)
            lex:nextif(",")
        else
            push(decl.items, parse_hook_item(lex))
            lex:nextif(",")
        end
    end
    lex:expect("end")
    return decl
end

local function parse_phase(lex, schema)
    local line = current_line(lex)
    local doc = attached_doc_comment(lex)
    lex:expect("phase")
    local phase = {
        kind = "phase",
        line = line,
        doc = doc,
        name = parse_name(lex),
        decls = {},
        type_names = {},
    }
    if schema.phase_names[phase.name] then
        lex:error(("duplicate phase '%s'"):format(phase.name))
    end
    schema.phase_names[phase.name] = true

    while not lex:matches("end") do
        if next_name_value(lex, "doc") then
            phase.doc = parse_doc_value(lex)
        elseif lex:matches("record") then
            push(phase.decls, parse_record(lex, phase))
        elseif lex:matches("enum") then
            push(phase.decls, parse_enum(lex, phase))
        elseif lex:matches("flags") then
            push(phase.decls, parse_flags(lex, phase))
        elseif lex:matches("methods") then
            push(phase.decls, parse_methods(lex, phase))
        else
            lex:error(("expected doc, record, enum, flags, methods, or end in phase '%s'"):format(phase.name))
        end
    end
    lex:expect("end")
    phase.type_names = nil
    return phase
end

local function parse_extern(lex, schema)
    local line = current_line(lex)
    lex:expect("extern")
    local ext = {
        line = line,
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
    local line = current_line(lex)
    local doc = attached_doc_comment(lex)
    lex:expect("schema")
    local schema = {
        kind = "schema",
        line = line,
        doc = doc,
        name = parse_name(lex),
        externs = {},
        phases = {},
        hooks = {},
        phase_names = {},
        extern_names = {},
    }

    while not lex:matches("end") do
        if next_name_value(lex, "doc") then
            schema.doc = parse_doc_value(lex)
        elseif lex:matches("extern") then
            push(schema.externs, parse_extern(lex, schema))
        elseif lex:matches("phase") then
            push(schema.phases, parse_phase(lex, schema))
        elseif lex:matches("hooks") then
            push(schema.hooks, parse_hooks(lex))
        else
            lex:error("expected doc, extern, phase, hooks, or end inside schema")
        end
    end
    lex:expect("end")
    schema.phase_names = nil
    schema.extern_names = nil
    return schema
end

local qualify_type_name

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
        push(lines, prefix .. value.name)
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

local function emit_doc_line(lines, indent, doc)
    if doc ~= nil then
        push(lines, indent .. "doc = " .. string.format("%q", doc))
    end
end

local function emit_surface_field(field)
    local ty = field.type
    if field.mod then
        ty = ty .. field.mod
    end
    return field.name .. ": " .. ty
end

local function emit_surface_method_signature(item)
    local parts = {}
    for i, arg in ipairs(item.args) do
        local text = arg.name .. ": " .. arg.type
        if arg.doc ~= nil then
            text = text .. " doc = " .. string.format("%q", arg.doc)
        end
        parts[i] = text
    end
    return item.receiver .. ":" .. item.name .. "(" .. table.concat(parts, ", ") .. ") -> " .. item.return_type
end

local function emit_surface_hook_signature(item)
    return item.name
end

local function emit_surface(schema)
    local lines = {}
    push(lines, "schema " .. schema.name)
    emit_doc_line(lines, "    ", schema.doc)

    for _, ext in ipairs(schema.externs) do
        push(lines, "    extern " .. ext.name .. " = <luaexpr>")
    end
    if (#schema.externs > 0 and (#schema.phases > 0 or #schema.hooks > 0)) then
        push(lines, "")
    end

    for pindex, phase in ipairs(schema.phases) do
        push(lines, "    phase " .. phase.name)
        emit_doc_line(lines, "        ", phase.doc)

        for dindex, decl in ipairs(phase.decls) do
            if decl.kind == "record" then
                push(lines, "        record " .. decl.name)
                emit_doc_line(lines, "            ", decl.doc)
                for _, field in ipairs(decl.fields) do
                    push(lines, "            " .. emit_surface_field(field))
                    emit_doc_line(lines, "                ", field.doc)
                end
                if decl.unique then
                    push(lines, "            unique")
                end
                push(lines, "        end")
            elseif decl.kind == "enum" then
                push(lines, "        enum " .. decl.name)
                emit_doc_line(lines, "            ", decl.doc)
                for _, variant in ipairs(decl.variants) do
                    local line = "            " .. variant.name
                    if variant.fields ~= nil then
                        local vparts = {}
                        for i, field in ipairs(variant.fields) do
                            vparts[i] = emit_surface_field(field)
                        end
                        line = line .. " { " .. table.concat(vparts, ", ") .. " }"
                    end
                    if variant.unique then
                        line = line .. " unique"
                    end
                    push(lines, line)
                    emit_doc_line(lines, "                ", variant.doc)
                end
                push(lines, "        end")
            elseif decl.kind == "flags" then
                push(lines, "        flags " .. decl.name)
                emit_doc_line(lines, "            ", decl.doc)
                for _, value in ipairs(decl.values) do
                    push(lines, "            " .. value.name)
                    emit_doc_line(lines, "                ", value.doc)
                end
                push(lines, "        end")
            elseif decl.kind == "methods" then
                push(lines, "        methods")
                emit_doc_line(lines, "            ", decl.doc)
                for _, item in ipairs(decl.items) do
                    push(lines, "            " .. emit_surface_method_signature(item))
                    emit_doc_line(lines, "                ", item.doc)
                end
                push(lines, "        end")
            else
                error("unknown declaration kind: " .. tostring(decl.kind))
            end
            if dindex < #phase.decls then
                push(lines, "")
            end
        end

        push(lines, "    end")
        if pindex < #schema.phases or #schema.hooks > 0 then
            push(lines, "")
        end
    end

    for hindex, hooks in ipairs(schema.hooks or {}) do
        push(lines, "    hooks " .. hooks.target)
        emit_doc_line(lines, "        ", hooks.doc)
        for _, item in ipairs(hooks.items) do
            push(lines, "        " .. emit_surface_hook_signature(item))
            emit_doc_line(lines, "            ", item.doc)
        end
        push(lines, "    end")
        if hindex < #(schema.hooks or {}) then
            push(lines, "")
        end
    end

    push(lines, "end")
    return table.concat(lines, "\n")
end

local function markdown_text(lines, text)
    if not text or text == "" then
        return
    end
    for part in tostring(text):gmatch("([^\n]+)") do
        push(lines, part)
    end
    push(lines, "")
end

local function slugify(text)
    local s = tostring(text):lower()
    s = s:gsub("[^%w]+", "-")
    s = s:gsub("^-+", "")
    s = s:gsub("-+$", "")
    if s == "" then
        s = "item"
    end
    return s
end

local function markdown_anchor(lines, name)
    push(lines, '<a name="' .. name .. '"></a>')
end

local function emit_markdown_index(lines, title, items)
    if #items == 0 then
        return
    end
    push(lines, "## " .. title)
    push(lines, "")
    for _, item in ipairs(items) do
        push(lines, "- [" .. item.label .. "](#" .. item.anchor .. ")")
    end
    push(lines, "")
end

local function emit_markdown(schema_obj, schema_ast)
    local lines = {}
    local method_meta = {}
    local hook_meta = {}
    local phase_index, type_index, method_index, hook_target_index, compile_product_index = {}, {}, {}, {}, {}

    for _, method in ipairs(schema_obj.methods or {}) do
        method_meta[method.receiver .. ":" .. method.name] = method
        local anchor = "method-" .. slugify(method.receiver .. "-" .. method.name)
        push(method_index, { label = method.receiver .. ":" .. method.name, anchor = anchor })
        if method.compile_product then
            push(compile_product_index, { label = method.receiver .. ":" .. method.name .. " -> " .. method.return_type, anchor = anchor })
        end
    end
    for _, hook in ipairs(schema_obj.hooks or {}) do
        hook_meta[hook.target .. ":" .. hook.name] = hook
    end
    for _, phase in ipairs(schema_ast.phases) do
        push(phase_index, { label = phase.name, anchor = "phase-" .. slugify(phase.name) })
        for _, decl in ipairs(phase.decls) do
            if decl.kind == "record" or decl.kind == "enum" or decl.kind == "flags" then
                push(type_index, {
                    label = phase.name .. "." .. decl.name,
                    anchor = "type-" .. slugify(phase.name .. "." .. decl.name),
                })
            end
        end
    end
    for _, hooks in ipairs(schema_ast.hooks or {}) do
        push(hook_target_index, { label = hooks.target, anchor = "hooks-" .. slugify(hooks.target) })
    end

    push(lines, "# " .. schema_ast.name)
    push(lines, "")
    markdown_text(lines, schema_ast.doc)
    emit_markdown_index(lines, "Phase index", phase_index)
    emit_markdown_index(lines, "Type index", type_index)
    emit_markdown_index(lines, "Method index", method_index)
    emit_markdown_index(lines, "Hook target index", hook_target_index)
    emit_markdown_index(lines, "Compile product index", compile_product_index)

    for _, phase in ipairs(schema_ast.phases) do
        markdown_anchor(lines, "phase-" .. slugify(phase.name))
        push(lines, "## Phase `" .. phase.name .. "`")
        push(lines, "")
        markdown_text(lines, phase.doc)

        for _, decl in ipairs(phase.decls) do
            if decl.kind == "record" then
                markdown_anchor(lines, "type-" .. slugify(phase.name .. "." .. decl.name))
                push(lines, "### Record `" .. phase.name .. "." .. decl.name .. "`")
                push(lines, "")
                markdown_text(lines, decl.doc)
                if decl.line then
                    push(lines, "- line: `" .. tostring(decl.line) .. "`")
                    push(lines, "")
                end
                if #decl.fields > 0 then
                    push(lines, "Fields:")
                    push(lines, "")
                    for _, field in ipairs(decl.fields) do
                        local suffix = field.mod or ""
                        push(lines, "- `" .. field.name .. ": " .. field.type .. suffix .. "`")
                        if field.doc then push(lines, "  - " .. field.doc) end
                        if field.line then push(lines, "  - line: `" .. tostring(field.line) .. "`") end
                    end
                    push(lines, "")
                end
            elseif decl.kind == "enum" then
                markdown_anchor(lines, "type-" .. slugify(phase.name .. "." .. decl.name))
                push(lines, "### Enum `" .. phase.name .. "." .. decl.name .. "`")
                push(lines, "")
                markdown_text(lines, decl.doc)
                if decl.line then
                    push(lines, "- line: `" .. tostring(decl.line) .. "`")
                    push(lines, "")
                end
                for _, variant in ipairs(decl.variants) do
                    push(lines, "- `" .. variant.name .. "`")
                    if variant.doc then push(lines, "  - " .. variant.doc) end
                    if variant.line then push(lines, "  - line: `" .. tostring(variant.line) .. "`") end
                    for _, field in ipairs(variant.fields or {}) do
                        local suffix = field.mod or ""
                        push(lines, "  - field `" .. field.name .. ": " .. field.type .. suffix .. "`")
                        if field.doc then push(lines, "    - " .. field.doc) end
                        if field.line then push(lines, "    - line: `" .. tostring(field.line) .. "`") end
                    end
                end
                push(lines, "")
            elseif decl.kind == "flags" then
                markdown_anchor(lines, "type-" .. slugify(phase.name .. "." .. decl.name))
                push(lines, "### Flags `" .. phase.name .. "." .. decl.name .. "`")
                push(lines, "")
                markdown_text(lines, decl.doc)
                if decl.line then
                    push(lines, "- line: `" .. tostring(decl.line) .. "`")
                    push(lines, "")
                end
                for _, value in ipairs(decl.values) do
                    push(lines, "- `" .. value.name .. "`")
                    if value.doc then push(lines, "  - " .. value.doc) end
                    if value.line then push(lines, "  - line: `" .. tostring(value.line) .. "`") end
                end
                push(lines, "")
            elseif decl.kind == "methods" then
                push(lines, "### Methods for phase `" .. phase.name .. "`")
                push(lines, "")
                markdown_text(lines, decl.doc)
                if decl.line then
                    push(lines, "- line: `" .. tostring(decl.line) .. "`")
                    push(lines, "")
                end
                for _, item in ipairs(decl.items) do
                    local signature = emit_surface_method_signature(item)
                    local meta = method_meta[qualify_type_name(item.receiver, phase.name, schema_obj._validation_info.extern_lookup) .. ":" .. item.name]
                    markdown_anchor(lines, "method-" .. slugify(item.receiver .. "-" .. item.name))
                    push(lines, "#### `" .. signature .. "`")
                    push(lines, "")
                    markdown_text(lines, item.doc)
                    if #item.args > 0 then
                        push(lines, "Arguments:")
                        push(lines, "")
                        for _, arg in ipairs(item.args) do
                            push(lines, "- `" .. arg.name .. ": " .. arg.type .. "`")
                            if arg.doc then
                                push(lines, "  - " .. arg.doc)
                            end
                            if arg.line then
                                push(lines, "  - line: `" .. tostring(arg.line) .. "`")
                            end
                        end
                        push(lines, "")
                    end
                    if meta then
                        push(lines, "- category: `" .. tostring(meta.category) .. "`")
                        push(lines, "- memoized: `" .. tostring(meta.memoized) .. "`")
                        if meta.compile_product then
                            push(lines, "- compile_product: `" .. tostring(meta.compile_product_kind or true) .. "`")
                        end
                        if meta.status then
                            push(lines, "- status: `" .. tostring(meta.status) .. "`")
                        end
                        if meta.line then
                            push(lines, "- line: `" .. tostring(meta.line) .. "`")
                        end
                        push(lines, "")
                    end
                end
            end
        end
    end

    if #(schema_ast.hooks or {}) > 0 then
        push(lines, "## Exotype hooks")
        push(lines, "")
        for _, hooks in ipairs(schema_ast.hooks) do
            markdown_anchor(lines, "hooks-" .. slugify(hooks.target))
            push(lines, "### Hooks for `" .. hooks.target .. "`")
            push(lines, "")
            markdown_text(lines, hooks.doc)
            if hooks.line then
                push(lines, "- line: `" .. tostring(hooks.line) .. "`")
                push(lines, "")
            end
            for _, item in ipairs(hooks.items) do
                local meta = hook_meta[hooks.target .. ":" .. item.name]
                push(lines, "#### `" .. item.name .. "`")
                push(lines, "")
                markdown_text(lines, item.doc)
                if meta then
                    push(lines, "- category: `" .. tostring(meta.category) .. "`")
                    push(lines, "- family: `" .. tostring(meta.family) .. "`")
                    push(lines, "- target: `" .. tostring(meta.target) .. "`")
                    push(lines, "- key: `" .. tostring(meta.key) .. "`")
                    push(lines, "- implementation_kind: `" .. tostring(meta.implementation_kind) .. "`")
                    if meta.line then
                        push(lines, "- line: `" .. tostring(meta.line) .. "`")
                    end
                    push(lines, "")
                end
            end
        end
    end

    return table.concat(lines, "\n")
end

qualify_type_name = function(type_name, phase_name, extern_lookup)
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
                        line = item.line,
                        doc = item.doc,
                        receiver = qualify_type_name(item.receiver, phase.name, extern_lookup),
                        name = item.name,
                        args = {},
                        return_type = qualify_type_name(item.return_type, phase.name, extern_lookup),
                        inline = item.impl ~= nil or item.fallback ~= nil or item.status ~= nil,
                        memoized = true,
                        has_impl = item.impl ~= nil,
                        has_fallback = item.fallback ~= nil,
                        has_status = item.status ~= nil,
                        has_doc = item.doc ~= nil,
                    }
                    for _, arg in ipairs(item.args) do
                        push(method.args, {
                            line = arg.line,
                            doc = arg.doc,
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

local function has_nonempty_doc(text)
    return type(text) == "string" and text:match("%S") ~= nil
end

local function schema_has_any_doc(schema)
    if has_nonempty_doc(schema.doc) then return true end
    for _, phase in ipairs(schema.phases) do
        if has_nonempty_doc(phase.doc) then return true end
        for _, decl in ipairs(phase.decls) do
            if has_nonempty_doc(decl.doc) then return true end
            if decl.kind == "record" then
                for _, field in ipairs(decl.fields) do
                    if has_nonempty_doc(field.doc) then return true end
                end
            elseif decl.kind == "enum" then
                for _, variant in ipairs(decl.variants) do
                    if has_nonempty_doc(variant.doc) then return true end
                    for _, field in ipairs(variant.fields or {}) do
                        if has_nonempty_doc(field.doc) then return true end
                    end
                end
            elseif decl.kind == "flags" then
                for _, value in ipairs(decl.values) do
                    if has_nonempty_doc(value.doc) then return true end
                end
            elseif decl.kind == "methods" then
                for _, item in ipairs(decl.items) do
                    if has_nonempty_doc(item.doc) then return true end
                    for _, arg in ipairs(item.args) do
                        if has_nonempty_doc(arg.doc) then return true end
                    end
                end
            end
        end
    end
    for _, hooks in ipairs(schema.hooks or {}) do
        if has_nonempty_doc(hooks.doc) then return true end
        for _, item in ipairs(hooks.items) do
            if has_nonempty_doc(item.doc) then return true end
        end
    end
    return false
end

local function require_doc(doc, owner)
    if not has_nonempty_doc(doc) then
        return ("%s must declare non-empty doc"):format(owner)
    end
end

local function validate_required_docs(schema)
    if not schema_has_any_doc(schema) then
        return nil
    end

    local err = require_doc(schema.doc, ("schema '%s'"):format(schema.name))
    if err then return err end

    for _, phase in ipairs(schema.phases) do
        err = require_doc(phase.doc, ("phase '%s'"):format(phase.name))
        if err then return err end

        for _, decl in ipairs(phase.decls) do
            if decl.kind == "record" or decl.kind == "enum" or decl.kind == "flags" then
                err = require_doc(decl.doc, ("%s '%s.%s'"):format(decl.kind, phase.name, decl.name))
                if err then return err end
            elseif decl.kind == "methods" then
                err = require_doc(decl.doc, ("methods block in phase '%s'"):format(phase.name))
                if err then return err end
                for _, item in ipairs(decl.items) do
                    err = require_doc(item.doc, ("method '%s:%s' in phase '%s'"):format(item.receiver, item.name, phase.name))
                    if err then return err end
                end
            end
        end
    end

    for _, hooks in ipairs(schema.hooks or {}) do
        err = require_doc(hooks.doc, ("hooks block '%s'"):format(hooks.target))
        if err then return err end
        for _, item in ipairs(hooks.items) do
            err = require_doc(item.doc, ("hook '%s' in hooks '%s'"):format(item.name, hooks.target))
            if err then return err end
        end
    end

    return nil
end

local function validate_hooks(schema)
    local seen_targets = {}
    for _, hooks in ipairs(schema.hooks or {}) do
        if seen_targets[hooks.target] then
            return ("duplicate hooks block '%s'"):format(hooks.target)
        end
        seen_targets[hooks.target] = true

        local seen_items = {}
        for _, item in ipairs(hooks.items) do
            local spec = hook_specs[item.name]
            if not spec then
                return ("unsupported hook '%s' in hooks '%s'"):format(item.name, hooks.target)
            end
            if seen_items[item.name] then
                return ("duplicate hook '%s' in hooks '%s'"):format(item.name, hooks.target)
            end
            seen_items[item.name] = true

            if spec.mode == "impl" then
                if item.impl == nil then
                    return ("hook '%s' in hooks '%s' must declare impl"):format(item.name, hooks.target)
                end
                if item.macro ~= nil then
                    return ("hook '%s' in hooks '%s' must not declare macro"):format(item.name, hooks.target)
                end
            elseif spec.mode == "macro" then
                if item.macro == nil then
                    return ("hook '%s' in hooks '%s' must declare macro"):format(item.name, hooks.target)
                end
                if item.impl ~= nil then
                    return ("hook '%s' in hooks '%s' must not declare impl"):format(item.name, hooks.target)
                end
            elseif spec.mode == "either" then
                if (item.impl == nil and item.macro == nil) or (item.impl ~= nil and item.macro ~= nil) then
                    return ("hook '%s' in hooks '%s' must declare exactly one of impl or macro"):format(item.name, hooks.target)
                end
            end
        end
    end
    return nil
end

local function validate_schema(schema)
    local extern_lookup = make_extern_lookup(schema)
    local type_index, phase_order_or_err = build_type_index(schema)
    if not type_index then
        return phase_order_or_err
    end
    local phase_order = phase_order_or_err

    local doc_err = validate_required_docs(schema)
    if doc_err then
        return doc_err
    end

    local hook_err = validate_hooks(schema)
    if hook_err then
        return hook_err
    end

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

local function is_canonical_compile_product_type(type_name, schema_ast, validation_info)
    local type_info = validation_info.type_index[type_name]
    if not type_info or type_info.kind ~= "record" then
        return false
    end

    local decl = type_info.decl
    local fields = decl.fields or {}
    if #fields ~= 2 then
        return false
    end

    local f1, f2 = fields[1], fields[2]
    if f1.name ~= "fn" or f2.name ~= "state_t" then
        return false
    end
    if f1.mod ~= nil or f2.mod ~= nil then
        return false
    end

    local extern_lookup = validation_info.extern_lookup
    local t1 = qualify_type_name(f1.type, type_info.phase, extern_lookup)
    local t2 = qualify_type_name(f2.type, type_info.phase, extern_lookup)
    return t1 == "TerraFunc" and t2 == "TerraType"
end

local function annotate_method_semantics(schema_obj, schema_ast, validation_info)
    for _, method in ipairs(schema_obj.methods) do
        method.category = "method_boundary"
        method.memoized = true
        method.helper = false
        method.compile_product = is_canonical_compile_product_type(method.return_type, schema_ast, validation_info)
        if method.compile_product then
            method.compile_product_kind = "unit"
        end
    end
end

local function collect_hooks(schema)
    local hooks = {}
    for _, decl in ipairs(schema.hooks or {}) do
        for _, item in ipairs(decl.items) do
            push(hooks, {
                target = decl.target,
                target_doc = decl.doc,
                line = item.line,
                doc = item.doc,
                name = item.name,
                key = item.key,
                impl = item.impl,
                macro = item.macro,
            })
        end
    end
    return hooks
end

local function group_hook_targets(schema_ast)
    local groups = {}
    for _, hooks in ipairs(schema_ast.hooks or {}) do
        groups[#groups + 1] = {
            target = hooks.target,
            doc = hooks.doc,
            line = hooks.line,
            items = hooks.items,
        }
    end
    return groups
end

local function annotate_hook_semantics(schema_obj)
    for _, hook in ipairs(schema_obj.hooks or {}) do
        local spec = hook_specs[hook.name] or {}
        hook.category = "exotype_hook"
        hook.helper = false
        hook.family = spec.family
        if spec.mode == "macro" then
            hook.implementation_kind = "macro"
        elseif spec.mode == "impl" then
            hook.implementation_kind = "lua_function"
        elseif spec.mode == "either" then
            hook.implementation_kind = hook.macro and "macro" or "impl"
        end
    end
end

local function build_inventory(schema_obj, schema_ast)
    local inventory = {
        phases = {},
        types = {},
        methods = {},
        hooks = {},
        hook_targets = group_hook_targets(schema_ast),
        compile_products = {},
    }

    for _, phase in ipairs(schema_ast.phases) do
        push(inventory.phases, {
            name = phase.name,
            line = phase.line,
            doc = phase.doc,
        })
        for _, decl in ipairs(phase.decls) do
            if decl.kind == "record" or decl.kind == "enum" or decl.kind == "flags" then
                push(inventory.types, {
                    fqname = phase.name .. "." .. decl.name,
                    phase = phase.name,
                    kind = decl.kind,
                    line = decl.line,
                    doc = decl.doc,
                })
            end
        end
    end

    for _, method in ipairs(schema_obj.methods or {}) do
        push(inventory.methods, method)
        if method.compile_product then
            push(inventory.compile_products, method)
        end
    end

    for _, hook in ipairs(schema_obj.hooks or {}) do
        push(inventory.hooks, hook)
    end

    return inventory
end

local function dotted_last_segment(name)
    local last = name:match("([^.]+)$")
    return last or name
end

local function dotted_to_path(name)
    return tostring(name):gsub("%.", "/"):lower()
end

local function build_method_test_cases(method)
    local cases = {
        {
            kind = "boundary",
            label = "boundary",
            summary = "returns " .. method.return_type .. " from the declared public boundary",
        },
    }
    if method.has_fallback then
        push(cases, {
            kind = "fallback",
            label = "fallback",
            summary = "degrades through the declared fallback boundary",
        })
    end
    push(cases, {
        kind = "memoization",
        label = "memoization",
        summary = "reuses the memoized boundary for identical semantic inputs",
    })
    if method.compile_product then
        push(cases, {
            kind = "compile_product_ownership",
            label = "compile_product_ownership",
            summary = "preserves owned compile-product ABI shape",
        })
    end
    return cases
end

local function build_hook_test_cases(hook)
    local cases = {
        {
            kind = "installation",
            label = "installation",
            summary = "installs " .. hook.key .. " on the runtime target metamethod table",
        },
    }
    if hook.family == "dispatch" then
        push(cases, {
            kind = "dispatch_behavior",
            label = "dispatch_behavior",
            summary = "verifies dispatch-family lookup or missing-method behavior",
        })
    elseif hook.family == "operator" then
        push(cases, {
            kind = "operator_behavior",
            label = "operator_behavior",
            summary = "verifies Terra operator dispatch through the installed metamethod",
        })
    elseif hook.family == "layout" or hook.family == "lifecycle" or hook.family == "conversion" or hook.family == "iteration" or hook.family == "display" then
        push(cases, {
            kind = hook.family .. "_behavior",
            label = hook.family .. "_behavior",
            summary = "verifies " .. hook.family .. "-family hook behavior",
        })
    end
    return cases
end

local function emit_method_test_skeleton(schema_obj, unit)
    local lines = {}
    push(lines, "-- " .. unit.path)
    push(lines, "-- Generated skeleton for " .. unit.key .. ".")
    push(lines, "")
    if unit.line then
        push(lines, "-- Source line: " .. tostring(unit.line))
    end
    push(lines, "-- Suggested cases:")
    for _, test_case in ipairs(unit.cases) do
        push(lines, "-- - " .. test_case.label .. ": " .. test_case.summary)
    end
    push(lines, "")
    push(lines, 'import "lib/schema"')
    push(lines, "")
    push(lines, "-- TODO: load or define schema `" .. schema_obj.name .. "` for this test file.")
    push(lines, "-- TODO: construct a valid receiver of type `" .. unit.receiver .. "`.")
    if #unit.args > 0 then
        push(lines, "-- TODO: construct semantic arguments:")
        for _, arg in ipairs(unit.args) do
            push(lines, "--   - `" .. arg.name .. ": " .. arg.type .. "`")
        end
    else
        push(lines, "-- TODO: no additional semantic arguments are required.")
    end
    push(lines, "")
    push(lines, "-- Example boundary assertion:")
    push(lines, "-- local receiver = ...")
    push(lines, "-- local result = receiver:" .. unit.name .. "(...)")
    push(lines, "-- assert(result ~= nil)")
    push(lines, "-- TODO: assert the result satisfies `" .. unit.return_type .. "` and each suggested case above.")
    push(lines, "")
    return table.concat(lines, "\n")
end

local function emit_hook_test_skeleton(unit)
    local lines = {}
    push(lines, "-- " .. unit.path)
    push(lines, "-- Generated skeleton for hook " .. unit.key .. ".")
    push(lines, "")
    if unit.line then
        push(lines, "-- Source line: " .. tostring(unit.line))
    end
    push(lines, "-- Suggested cases:")
    for _, test_case in ipairs(unit.cases) do
        push(lines, "-- - " .. test_case.label .. ": " .. test_case.summary)
    end
    push(lines, "")
    push(lines, 'import "lib/schema"')
    push(lines, "")
    push(lines, "-- TODO: load or define the schema under test.")
    push(lines, "-- TODO: create a runtime target table with `metamethods = {}`.")
    push(lines, "-- TODO: call `schema:install_hooks(bindings)` with a binding for `" .. unit.target .. "`.")
    push(lines, "-- TODO: assert `target.metamethods." .. unit.key_name .. "` is installed.")
    push(lines, "-- TODO: assert the additional suggested cases above.")
    push(lines, "")
    return table.concat(lines, "\n")
end

local function build_test_inventory(schema_obj)
    local tests = {
        methods = {},
        hooks = {},
        totals = {
            method_units = 0,
            hook_units = 0,
            case_count = 0,
        },
    }

    for _, method in ipairs(schema_obj.methods or {}) do
        local phase_path = tostring(method.phase):lower()
        local receiver_leaf = slugify(dotted_last_segment(method.receiver))
        local unit = {
            kind = "method_boundary",
            key = method.receiver .. ":" .. method.name,
            phase = method.phase,
            receiver = method.receiver,
            name = method.name,
            return_type = method.return_type,
            args = method.args,
            line = method.line,
            compile_product = method.compile_product,
            has_fallback = method.has_fallback,
            path = "tests/" .. phase_path .. "/" .. receiver_leaf .. "/" .. method.name .. ".t",
            cases = build_method_test_cases(method),
        }
        push(tests.methods, unit)
        tests.totals.method_units = tests.totals.method_units + 1
        tests.totals.case_count = tests.totals.case_count + #unit.cases
    end

    for _, hook in ipairs(schema_obj.hooks or {}) do
        local unit = {
            kind = "hook_installation",
            key = hook.target .. "." .. hook.name,
            target = hook.target,
            name = hook.name,
            family = hook.family,
            implementation_kind = hook.implementation_kind,
            key_name = hook.key,
            line = hook.line,
            path = "tests/hooks/" .. dotted_to_path(hook.target) .. "/" .. hook.name .. ".t",
            cases = build_hook_test_cases(hook),
        }
        push(tests.hooks, unit)
        tests.totals.hook_units = tests.totals.hook_units + 1
        tests.totals.case_count = tests.totals.case_count + #unit.cases
    end

    for _, unit in ipairs(tests.methods) do
        unit.content = emit_method_test_skeleton(schema_obj, unit)
    end
    for _, unit in ipairs(tests.hooks) do
        unit.content = emit_hook_test_skeleton(unit)
    end

    return tests
end

local function emit_test_markdown(schema_obj, tests)
    local lines = {}
    push(lines, "# Test plan for " .. schema_obj.name)
    push(lines, "")
    push(lines, "- method_units: `" .. tostring(tests.totals.method_units) .. "`")
    push(lines, "- hook_units: `" .. tostring(tests.totals.hook_units) .. "`")
    push(lines, "- case_count: `" .. tostring(tests.totals.case_count) .. "`")
    push(lines, "")

    if #tests.methods > 0 then
        push(lines, "## Method boundary tests")
        push(lines, "")
        for _, unit in ipairs(tests.methods) do
            push(lines, "### `" .. unit.key .. "`")
            push(lines, "")
            push(lines, "- path: `" .. unit.path .. "`")
            push(lines, "- return_type: `" .. unit.return_type .. "`")
            if unit.line then
                push(lines, "- line: `" .. tostring(unit.line) .. "`")
            end
            for _, test_case in ipairs(unit.cases) do
                push(lines, "- case `" .. test_case.label .. "`: " .. test_case.summary)
            end
            push(lines, "")
        end
    end

    if #tests.hooks > 0 then
        push(lines, "## Hook tests")
        push(lines, "")
        for _, unit in ipairs(tests.hooks) do
            push(lines, "### `" .. unit.key .. "`")
            push(lines, "")
            push(lines, "- path: `" .. unit.path .. "`")
            push(lines, "- family: `" .. unit.family .. "`")
            push(lines, "- implementation_kind: `" .. unit.implementation_kind .. "`")
            if unit.line then
                push(lines, "- line: `" .. tostring(unit.line) .. "`")
            end
            for _, test_case in ipairs(unit.cases) do
                push(lines, "- case `" .. test_case.label .. "`: " .. test_case.summary)
            end
            push(lines, "")
        end
    end

    return table.concat(lines, "\n")
end

local function resolve_binding(bindings, dotted_name)
    local cur = bindings
    for part in tostring(dotted_name):gmatch("[^.]+") do
        if type(cur) ~= "table" then
            return nil
        end
        cur = cur[part]
        if cur == nil then
            return nil
        end
    end
    return cur
end

local function install_exotype_hooks(schema_obj, schema_ast, schema_env)
    return function(self, bindings, extra_env)
        bindings = bindings or {}
        local hook_env = setmetatable(extra_env or {}, {
            __index = schema_env,
        })

        local installed = {}
        for _, decl in ipairs(schema_ast.hooks or {}) do
            local target = resolve_binding(bindings, decl.target)
            if target == nil then
                error(("hooks target '%s' not provided to install_hooks"):format(decl.target))
            end
            target.metamethods = target.metamethods or {}

            for _, item in ipairs(decl.items) do
                local spec = hook_specs[item.name] or {}
                local value
                if item.impl then
                    value = item.impl(hook_env)
                    if spec.mode == "impl" and type(value) ~= "function" then
                        error(("hook '%s' for '%s' impl must evaluate to a function, got %s"):format(item.name, decl.target, type(value)))
                    end
                elseif item.macro then
                    value = item.macro(hook_env)
                    if type(value) == "function" then
                        value = macro(value)
                    end
                end
                target.metamethods[item.key] = value
                push(installed, {
                    target = decl.target,
                    name = item.name,
                    key = item.key,
                })
            end
        end
        return installed
    end
end

local function runtime_type_matches(value, type_name, schema_obj, validation_info)
    if type_name == "any" then
        return true
    end
    if type_name == "nil" then
        return value == nil
    end
    if builtin_types[type_name] then
        return type(value) == type_name
    end

    local extern_checker = schema_obj.externs[type_name]
    if extern_checker then
        return extern_checker(value)
    end

    local type_info = validation_info.type_index[type_name]
    if not type_info then
        return false
    end

    local short_name = type_name:match("([^.]+)$")
    local ns = schema_obj.types[type_info.phase]
    local class = ns and ns[short_name]
    return class ~= nil and class:isclassof(value)
end

local function install_inline_methods(schema_obj, schema_ast, schema_env, validation_info)
    local metadata_by_key = {}
    for _, method in ipairs(schema_obj.methods) do
        metadata_by_key[method.receiver .. ":" .. method.name] = method
    end

    local methods_to_install = {}

    for _, phase in ipairs(schema_ast.phases) do
        for _, decl in ipairs(phase.decls) do
            if decl.kind == "methods" then
                for _, item in ipairs(decl.items) do
                    local receiver = qualify_type_name(item.receiver, phase.name, validation_info.extern_lookup)
                    local key = receiver .. ":" .. item.name
                    local metadata = metadata_by_key[key]

                    if metadata then
                        metadata.memoized = true
                    end

                    if item.status then
                        local status = item.status(schema_env)
                        if status ~= nil and type(status) ~= "string" then
                            error(("inline method '%s:%s' status must evaluate to a string, got %s"):format(receiver, item.name, type(status)))
                        end
                        if metadata then
                            metadata.status = status
                        end
                    end

                    if item.impl or item.fallback then
                        push(methods_to_install, {
                            phase = phase.name,
                            receiver = receiver,
                            receiver_info = validation_info.type_index[receiver],
                            name = item.name,
                            args = item.args,
                            return_type = qualify_type_name(item.return_type, phase.name, validation_info.extern_lookup),
                            memoized = true,
                            impl = item.impl,
                            fallback = item.fallback,
                            metadata = metadata,
                        })
                    end
                end
            end
        end
    end

    table.sort(methods_to_install, function(a, b)
        local ak = a.receiver_info and a.receiver_info.kind or ""
        local bk = b.receiver_info and b.receiver_info.kind or ""
        if ak ~= bk then
            if ak == "variant" then return false end
            if bk == "variant" then return true end
            return ak < bk
        end
        if a.receiver ~= b.receiver then
            return a.receiver < b.receiver
        end
        return a.name < b.name
    end)

    for _, method in ipairs(methods_to_install) do
        local impl = method.impl and method.impl(schema_env) or nil
        local fallback = method.fallback and method.fallback(schema_env) or nil

        if impl ~= nil and type(impl) ~= "function" then
            error(("inline method '%s:%s' impl must evaluate to a function, got %s"):format(method.receiver, method.name, type(impl)))
        end
        if fallback ~= nil and type(fallback) ~= "function" then
            error(("inline method '%s:%s' fallback must evaluate to a function, got %s"):format(method.receiver, method.name, type(fallback)))
        end

        local short_name = method.receiver:match("([^.]+)$")
        local receiver_phase = method.receiver_info and method.receiver_info.phase or method.phase
        local ns = schema_obj.types[receiver_phase]
        local class = ns and ns[short_name]
        if class == nil then
            error(("failed to install inline method '%s:%s': receiver class not found"):format(method.receiver, method.name))
        end

        local boundary = function(self, ...)
            local ok, result_or_err
            if impl then
                ok, result_or_err = pcall(impl, self, ...)
            else
                ok, result_or_err = false, nil
            end

            local result = result_or_err
            if not ok then
                if fallback then
                    local fb_ok, fb_result_or_err = pcall(fallback, self, result_or_err, ...)
                    if not fb_ok then
                        error(("method '%s:%s' failed in impl/fallback: %s / %s"):format(
                            method.receiver,
                            method.name,
                            tostring(result_or_err),
                            tostring(fb_result_or_err)
                        ), 2)
                    end
                    result = fb_result_or_err
                else
                    error(result_or_err, 2)
                end
            end

            if not runtime_type_matches(result, method.return_type, schema_obj, validation_info) then
                error(("method '%s:%s' returned %s, expected %s"):format(
                    method.receiver,
                    method.name,
                    type(result),
                    method.return_type
                ), 2)
            end
            return result
        end

        boundary = terralib.memoize(boundary)

        class[method.name] = function(self, ...)
            local argc = select("#", ...)
            if argc > #method.args then
                error(("method '%s:%s' expected at most %d explicit args, got %d"):format(method.receiver, method.name, #method.args, argc), 2)
            end

            for i, arg in ipairs(method.args) do
                local arg_type = qualify_type_name(arg.type, method.phase, validation_info.extern_lookup)
                local v = select(i, ...)
                if not runtime_type_matches(v, arg_type, schema_obj, validation_info) then
                    error(("method '%s:%s' argument '%s' expected %s, got %s"):format(
                        method.receiver,
                        method.name,
                        arg.name,
                        arg_type,
                        type(v)
                    ), 2)
                end
            end

            return boundary(self, ...)
        end

        if method.metadata then
            method.metadata.installed_inline = true
            method.metadata.installed_memoized = method.memoized
        end
    end
end

local function build_schema_object(schema_ast, env, validation_info)
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

    local phases = {}
    for _, phase in ipairs(schema_ast.phases) do
        push(phases, phase.name)
    end

    local schema_obj = {
        name = schema_ast.name,
        line = schema_ast.line,
        doc = schema_ast.doc,
        types = ctx,
        phases = phases,
        methods = collect_methods(schema_ast),
        hooks = collect_hooks(schema_ast),
        externs = extern_values,
        asdl = asdl_text,
        surface = emit_surface(schema_ast),
        ast = schema_ast,
        _validation_info = validation_info,
    }
    local schema_env = setmetatable({
        schema = schema_obj,
        types = ctx,
        externs = extern_values,
    }, {
        __index = env,
    })

    annotate_method_semantics(schema_obj, schema_ast, validation_info)
    annotate_hook_semantics(schema_obj)
    schema_obj.inventory = build_inventory(schema_obj, schema_ast)
    schema_obj.tests = build_test_inventory(schema_obj)
    install_defaults_and_constraints(ctx, schema_ast, schema_env)
    install_inline_methods(schema_obj, schema_ast, schema_env, validation_info)
    schema_obj.install_hooks = install_exotype_hooks(schema_obj, schema_ast, schema_env)
    schema_obj.markdown = emit_markdown(schema_obj, schema_ast)
    schema_obj.test_markdown = emit_test_markdown(schema_obj, schema_obj.tests)
    schema_obj.test_skeletons = {
        methods = schema_obj.tests.methods,
        hooks = schema_obj.tests.hooks,
    }

    return setmetatable(schema_obj, {
        __tostring = function(self)
            return ("Schema(%s)"):format(self.name)
        end,
    })
end

local function parse_and_construct(lex)
    local schema_ast = parse_schema(lex)
    local validation_error, validation_info = validate_schema(schema_ast)
    if validation_error then
        lex:error(validation_error)
    end
    local constructor = function(envfn)
        local env = envfn and envfn() or {}
        return build_schema_object(schema_ast, env, validation_info)
    end
    return schema_ast, constructor
end

local schema_lang = {
    name = "schema",
    entrypoints = { "schema" },
    keywords = { "extern", "phase", "record", "enum", "flags", "methods", "hooks", "unique", "where" },
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
