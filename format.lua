-- MIT License
--
-- Copyright (c) 2022-2023 JackMacWindows
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local lex do
    local error_mt = {}
    function error_mt.__tostring(self)
        return (self.src or "unknown") .. ":" .. self.line .. ": " .. self.text
    end

    local function util_error(line, col, text)
        error(setmetatable({line = line, col = col, text = text}, error_mt), 0)
    end

    local classes = {
        operator = "^([;:=%.,%[%]%(%)%{%}%+%-%*/%^%%<>~#&|][=%.]?%.?)()",
        name = "^([%a_][%w_]*)()",
        number = "^(%d+%.?%d*)()",
        scinumber = "^(%d+%.?%d*[eE][%+%-]?%d+)()",
        hexnumber = "^(0[xX]%x+%.?%x*)()",
        scihexnumber = "^(0[xX]%x+%.?%x*[pP][%+%-]?%x+)()",
        linecomment = "^(%-%-[^\n]*)()",
        blockcomment = "^(%-%-%[(=*)%[.-%]%2%])()",
        emptyblockcomment = "^(%-%-%[(=*)%[%]%2%])()",
        blockquote = "^(%[(=*)%[.-%]%2%])()",
        emptyblockquote = "^(%[(=*)%[%]%2%])()",
        dquote = '^("[^"]*")()',
        squote = "^('[^']*')()",
        whitespace = "^(%s+)()",
        invalid = "^([^%w%s_;:=%.,%[%]%(%)%{%}%+%-%*/%^%%<>~#&|]+)()",
    }

    local classes_precedence = {"name", "scihexnumber", "hexnumber", "scinumber", "number", "blockcomment", "emptyblockcomment", "linecomment", "blockquote", "emptyblockquote", "operator", "dquote", "squote", "whitespace", "invalid"}

    local keywords = {
        ["break"] = true,
        ["do"] = true,
        ["else"] = true,
        ["elseif"] = true,
        ["end"] = true,
        ["for"] = true,
        ["function"] = true,
        ["if"] = true,
        ["in"] = true,
        ["local"] = true,
        ["repeat"] = true,
        ["return"] = true,
        ["then"] = true,
        ["until"] = true,
        ["while"] = true,
    }

    local operators = {
        ["and"] = true,
        ["not"] = true,
        ["or"] = true,
        ["+"] = true,
        ["-"] = true,
        ["*"] = true,
        ["/"] = true,
        ["%"] = true,
        ["^"] = true,
        ["#"] = true,
        ["=="] = true,
        ["~="] = true,
        ["<="] = true,
        [">="] = true,
        ["<"] = true,
        [">"] = true,
        ["="] = true,
        ["("] = true,
        [")"] = true,
        ["{"] = true,
        ["}"] = true,
        ["["] = true,
        ["]"] = true,
        ["::"] = true,
        [";"] = true,
        [":"] = true,
        [","] = true,
        ["."] = true,
        [".."] = true,
    }

    local bitops = {
        ["&"] = true,
        ["~"] = true,
        ["|"] = true,
        ["<<"] = true,
        [">>"] = true,
        ["//"] = true,
    }

    local constants = {
        ["true"] = true,
        ["false"] = true,
        ["nil"] = true,
        ["..."] = true,
    }

    local function tokenize(state, text)
        local start = 1
        text = state.pending .. text
        state.pending = ""
        while true do
            local found = false
            for i, v in ipairs(classes_precedence) do
                local s, e, e2 = text:match(classes[v], start)
                if s then
                    if v == "dquote" or v == "squote" then
                        local ok = true
                        while not s:gsub("\\.", ""):match(classes[v]) do
                            local s2
                            s2, e = text:match(classes[v], e - 1)
                            if not s2 then ok = false break end
                            s = s .. s2:sub(2)
                        end
                        if not ok then break end
                    elseif v == "operator" and #s > 1 then
                        while not (operators[s] or s == "...") and #s > 1 do s, e = s:sub(1, -2), e - 1 end
                    end
                    if e2 then e = e2 end
                    found = true
                    state[#state+1] = {type = v, text = s, line = state.line, col = state.col}
                    start = e
                    local nl = select(2, s:gsub("\n", "\n"))
                    if nl == 0 then
                        state.col = state.col + #s
                    else
                        state.line = state.line + nl
                        state.col = #s:match("[^\n]*$")
                    end
                    break
                end
            end
            if not found then state.pending = text:sub(start) break end
        end
    end

    -- valid token types: operator, constant, keyword, string, number, name, whitespace, comment
    local function reduce(state, version, trim)
        for _, v in ipairs(state) do
            if v.type == "operator" then
                if v.text == "..." then v.type = "constant"
                elseif not operators[v.text] and (version < 3 or not bitops[v.text]) then util_error(v.line, v.col, "invalid operator '" .. v.text .. "'") end
            elseif v.type == "name" then
                if keywords[v.text] then v.type = "keyword"
                elseif operators[v.text] then v.type = "operator"
                elseif constants[v.text] then v.type = "constant" end
            elseif v.type == "dquote" or v.type == "squote" or v.type == "blockquote" or v.type == "emptyblockquote" then v.type = "string"
            elseif v.type == "linecomment" or v.type == "blockcomment" or v.type == "emptyblockcomment" then v.type = "comment"
            elseif v.type == "hexnumber" or v.type == "scinumber" or v.type == "scihexnumber" then v.type = "number"
            elseif v.type == "invalid" then util_error(v.line, v.col, "invalid characters") end
        end
        if trim then
            local retval = {}
            for _, v in ipairs(state) do
                if v.type == "number" and retval[#retval].type == "operator" and retval[#retval].text == "-" then
                    local op = retval[#retval-1]
                    if (op.type == "operator" and op.text ~= "}" and op.text ~= "]" and op.text ~= ")") or (op.type == "keyword" and op.text ~= "end") then
                        v.text = "-" .. v.text
                        retval[#retval] = nil
                    end
                end
                if v.type ~= "whitespace" and (trim ~= 2 or v.type ~= "comment") then retval[#retval+1] = v.text end
            end
            return retval
        end
        state.pending, state.line, state.col = nil, nil, nil
        local tokens = {}
        for i, v in ipairs(state) do tokens[i] = v.text end
        return tokens
    end

    function lex(reader, version, trim)
        if type(reader) == "string" then
            local data = reader
            function reader() local d = data data = nil return d end
        end
        local state = {pending = "", line = 1, col = 1}
        while true do
            local data = reader()
            if not data then break end
            tokenize(state, data)
        end
        if state.pending ~= "" then util_error(state.line, state.col, "unfinished string") end
        return reduce(state, version, trim)
    end
end

local binop = {
    ["and"] = {2, 2},
    ["or"] = {1, 1},
    ["+"] = {6, 6},
    ["-"] = {6, 6},
    ["*"] = {7, 7},
    ["/"] = {7, 7},
    ["%"] = {7, 7},
    ["^"] = {10, 9},
    [".."] = {5, 4},
    ["=="] = {3, 3},
    ["~="] = {3, 3},
    ["<="] = {3, 3},
    [">="] = {3, 3},
    ["<"] = {3, 3},
    [">"] = {3, 3},
    --["&"] = true,
    --["~"] = true,
    --["|"] = true,
    --["<<"] = true,
    --[">>"] = true,
    --["//"] = true,
}

local function advance(tokens, start, indent, res, amount)
    local i = start
    while i <= start + amount do
        if tokens[i] and tokens[i]:match "^%-%-" then
            res.comment = res.comment .. tokens[i] .. "\n" .. (" "):rep(indent)
            amount = amount + 1
        end
        i = i + 1
    end
    return start + amount
end

local body, tbl, exp

function tbl(tokens, start, indent, res)
    indent = indent + 4
    start = advance(tokens, start, indent, res, 1)
    if tokens[start] == "}" then
        res.str = res.str .. "{}"
        return advance(tokens, start, indent, res, 1)
    else
        res.str = res.str .. "{\n" .. (" "):rep(indent)
    end
    while start <= #tokens do
        local v = tokens[start]
        --print("tbl", indent, v, start)
        if v == "[" then
            res.str = res.str .. "["
            start = exp(tokens, advance(tokens, start, indent, res, 1), indent, res)
            res.str = res.str .. "] = "
            start = exp(tokens, advance(tokens, start, indent, res, 2), indent, res)
        elseif v == "{" then start = tbl(tokens, advance(tokens, start, indent, res, 1), indent, res)
        elseif v == "}" then
            if tokens[start-1] == "," then res.str = res.str:sub(1, -5) .. "}"
            else res.str = res.str .. "\n" .. (" "):rep(indent - 4) .. "}" end
            return advance(tokens, start, indent, res, 1)
        elseif v == "," or v == ";" then res.str = res.str .. v .. "\n" .. (" "):rep(indent) start = advance(tokens, start, indent, res, 1)
        elseif tokens[start+1] == "=" then
            res.str = res.str .. v .. " = "
            start = exp(tokens, advance(tokens, start, indent, res, 2), indent, res)
        else
            start = exp(tokens, start, indent, res)
        end
    end
    return start
end

local subexpr, explist

local function prefixexp(tokens, start, indent, res)
    if tokens[start] == "(" then
        res.str = res.str .. "("
        --print("prefixexp")
        start = subexpr(tokens, advance(tokens, start, indent, res, 1), indent, res, 0)
        res.str = res.str .. ")"
        --print("prefixexp exit", advance(tokens, start, indent, res, 1))
        return advance(tokens, start, indent, res, 1)
    else
        res.str = res.str .. tokens[start]
        return advance(tokens, start, indent, res, 1)
    end
end

local function primaryexp(tokens, start, indent, res)
    start = prefixexp(tokens, start, indent, res)
    while true do
        local v = tokens[start]
        --print("primaryexp", indent, v, start)
        if v == nil then return start
        elseif v == "." or v == ":" then
            res.str = res.str .. v .. tokens[start+1]
            start = advance(tokens, start, indent, res, 2)
        elseif v == "[" then
            res.str = res.str .. "["
            start = advance(tokens, subexpr(tokens, advance(tokens, start, indent, res, 1), indent, res, 0), indent, res, 1)
            res.str = res.str .. "]"
        elseif v == "{" then
            start = tbl(tokens, start, indent, res)
        elseif v:match "^[\"']" or v:match "^%[=*%[" then
            res.str = res.str .. " " .. v
            start = advance(tokens, start, indent, res, 1)
        elseif v == "(" then
            res.str = res.str .. "("
            start = advance(tokens, start, indent, res, 1)
            if tokens[start] ~= ")" then
                start = explist(tokens, start, indent, res)
            end
            res.str = res.str .. ")"
            start = advance(tokens, start, indent, res, 1)
        else
            --print("primaryexp exit", start)
            return start
        end
    end
end

local function simpleexp(tokens, start, indent, res)
    local v = tokens[start]
    --print("simpleexp", indent, v, start)
    if tonumber(v) or v:match "^[\"']" or v:match "^%[=*%[" or v == "nil" or v == "true" or v == "false" or v == "..." then
        res.str = res.str .. v
        return advance(tokens, start, indent, res, 1)
    elseif v == "{" then
        return tbl(tokens, start, indent, res)
    elseif v == "function" then
        res.str = res.str .. "function("
        start = advance(tokens, start, indent, res, 2)
        while tokens[start] ~= ")" do
            if tokens[start] == "," then res.str = res.str .. ", "
            else res.str = res.str .. tokens[start] end
            start = advance(tokens, start, indent, res, 1)
        end
        res.str = res.str .. ")\n" .. (" "):rep(indent + 4)
        return body(tokens, advance(tokens, start, indent, res, 1), indent + 4, res)
    else
        return primaryexp(tokens, start, indent, res)
    end
end

function subexpr(tokens, start, indent, res, limit)
    local v = tokens[start]
    --print("subexpr", indent, v, start)
    if v == "-" or v == "#" or v == "not" then
        res.str = res.str .. v .. (v == "not" and " " or "")
        start = subexpr(tokens, advance(tokens, start, indent, res, 1), indent, res, 8) -- UNARY_PRIORITY = 8
    else
        start = simpleexp(tokens, start, indent, res)
        --print("simpleexp exit", start)
    end
    v = tokens[start]
    while binop[v] and binop[v][1] > limit do
        --print("subexpr", indent, v)
        res.str = res.str .. " " .. v .. " "
        start = subexpr(tokens, advance(tokens, start, indent, res, 1), indent, res, binop[v][2])
        v = tokens[start]
    end
    --print("subexpr exit", start)
    return start
end

function explist(tokens, start, indent, res)
    start = exp(tokens, start, indent, res)
    while tokens[start] == "," do
        res.str = res.str .. ", "
        start = exp(tokens, advance(tokens, start, indent, res, 1), indent, res)
    end
    return start
end

function exp(tokens, start, indent, res)
    return subexpr(tokens, start, indent, res, 0)
end

local function namelist(tokens, start, indent, res)
    if tokens[start]:match "^%-%-" then
        res.str = res.str .. tokens[start] .. "\n" .. (" "):rep(indent)
        start = advance(tokens, start, indent, res, 1)
    end
    res.str = res.str .. tokens[start]
    start = advance(tokens, start, indent, res, 1)
    while tokens[start] == "," do
        res.str = res.str .. ", " .. tokens[start+1]
        start = advance(tokens, start, indent, res, 2)
    end
    return start
end

function body(tokens, start, indent, res)
    while start and start <= #tokens do
        local v = tokens[start]
        if v:match "^%-%-" then
            res.str = res.str .. v .. "\n" .. (" "):rep(indent) .. res.comment
            res.comment = ""
            start = advance(tokens, start, indent, res, 1)
        elseif v == "break" then
            res.str = res.str .. v .. "\n" .. (" "):rep(indent) .. res.comment
            res.comment = ""
            start = advance(tokens, start, indent, res, 1)
        elseif v == "do" then
            res.str = res.str .. "do\n" .. res.comment .. (" "):rep(indent + 4)
            start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
            res.str = res.str .. "\n"  .. (" "):rep(indent) .. res.comment
        elseif v == "end" then
            res.str = res.str:sub(1, -5) .. "end"
            return advance(tokens, start, indent - 4, res, 1)
        elseif v == "while" then
            res.str = res.str .. "while "
            start = exp(tokens, advance(tokens, start, indent, res, 1), indent, res)
            res.str = res.str .. " do\n" .. (" "):rep(indent + 4) .. res.comment
            res.comment = ""
            start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
            res.str = res.str .. "\n" .. (" "):rep(indent) .. res.comment
        elseif v == "repeat" then
            res.str = res.str .. "repeat\n" .. (" "):rep(indent + 4) .. res.comment
            start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
            res.str = res.str .. "\n" .. (" "):rep(indent) .. res.comment
        elseif v == "until" then
            res.str = res.str:sub(1, -5) .. "until "
            return exp(tokens, advance(tokens, start, indent - 4, res, 1), indent - 4, res)
        elseif v == "if" then
            res.str = res.str .. "if "
            start = exp(tokens, advance(tokens, start, indent, res, 1), indent, res)
            res.str = res.str .. " then\n" .. (" "):rep(indent + 4) .. res.comment
            res.comment = ""
            start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
            res.str = res.str .. "\n"  .. (" "):rep(indent) .. res.comment
        elseif v == "elseif" then
            res.str = res.str:sub(1, -5) .. "elseif "
            start = exp(tokens, advance(tokens, start, indent, res, 1), indent, res)
            res.str = res.str .. " then\n" .. (" "):rep(indent) .. res.comment
            res.comment = ""
            start = advance(tokens, start, indent, res, 1)
        elseif v == "else" then
            res.str = res.str:sub(1, -5) .. "else\n" .. (" "):rep(indent) .. res.comment
            res.comment = ""
            start = advance(tokens, start, indent, res, 1)
        elseif v == "for" then
            if tokens[start+2] == "=" then
                res.str = res.str .. "for " .. tokens[start+1] .. " = "
                start = exp(tokens, advance(tokens, start, indent, res, 3), indent, res)
                res.str = res.str .. ", "
                start = exp(tokens, advance(tokens, start, indent, res, 1), indent, res)
                if tokens[start] == "," then
                    res.str = res.str .. ", "
                    start = exp(tokens, advance(tokens, start, indent, res, 1), indent, res)
                end
                res.str = res.str .. " do\n" .. (" "):rep(indent + 4) .. res.comment
                res.comment = ""
                start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
                res.str = res.str .. "\n"  .. (" "):rep(indent) .. res.comment
            else
                res.str = res.str .. "for "
                start = namelist(tokens, advance(tokens, start, indent, res, 1), indent, res)
                res.str = res.str .. " in "
                start = explist(tokens, advance(tokens, start, indent, res, 1), indent, res)
                res.str = res.str .. " do\n" .. (" "):rep(indent + 4) .. res.comment
                res.comment = ""
                start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
                res.str = res.str .. "\n"  .. (" "):rep(indent) .. res.comment
            end
        elseif v == "function" then
            res.str = res.str .. "function " .. tokens[start+1]
            start = advance(tokens, start, indent, res, 2)
            while tokens[start] == "." or tokens[start] == ":" do
                res.str = res.str .. tokens[start] .. tokens[start+1]
                start = advance(tokens, start, indent, res, 2)
            end
            res.str = res.str .. "("
            if tokens[start+1] ~= ")" then
                start = namelist(tokens, advance(tokens, start, indent, res, 1), indent, res)
            else start = advance(tokens, start, indent, res, 1) end
            res.str = res.str .. ")\n" .. (" "):rep(indent + 4) .. res.comment
            start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
            res.str = res.str .. "\n\n" .. (" "):rep(indent) .. res.comment
        elseif v == "local" then
            if tokens[start+1] == "function" then
                res.str = res.str .. "local function " .. tokens[start+2] .. "("
                if tokens[start+4] ~= ")" then
                    start = namelist(tokens, advance(tokens, start, indent, res, 4), indent, res)
                else start = advance(tokens, start, indent, res, 4) end
                res.str = res.str .. ")\n" .. (" "):rep(indent + 4) .. res.comment
                res.comment = ""
                start = body(tokens, advance(tokens, start, indent + 4, res, 1), indent + 4, res)
                res.str = res.str .. "\n\n"  .. (" "):rep(indent) .. res.comment
            else
                res.str = res.str .. "local "
                start = namelist(tokens, advance(tokens, start, indent, res, 1), indent, res)
                if tokens[start] == "=" then
                    res.str = res.str .. " = "
                    start = explist(tokens, advance(tokens, start, indent, res, 1), indent, res)
                end
                res.str = res.str .. "\n" .. (" "):rep(indent) .. res.comment
            end
        elseif v == "return" then
            res.str = res.str .. "return "
            local idx = advance(tokens, start, indent, res, 1)
            if tokens[idx] ~= "end" and tokens[idx] ~= ";" and tokens[idx] ~= "::" then
                start = explist(tokens, idx, indent, res)
            else start = idx end
            res.str = res.str .. "\n" .. (" "):rep(indent) .. res.comment
        elseif v == ";" then
            res.str = res.str .. ";" .. "\n" .. (" "):rep(indent) .. res.comment
        elseif binop[v] then error(tokens[start-1] .. v .. tokens[start+1])
        else
            start = primaryexp(tokens, start, indent, res)
            if tokens[start] == "," or tokens[start] == "=" then
                while tokens[start] == "," do
                    res.str = res.str .. ", "
                    start = primaryexp(tokens, advance(tokens, start, indent, res, 1), indent, res)
                end
                res.str = res.str .. " = "
                start = explist(tokens, advance(tokens, start, indent, res, 1), indent, res)
            end
            res.str = res.str .. "\n" .. (" "):rep(indent) .. res.comment
        end
        res.comment = ""
    end
    return start
end

local function format(text)
    assert((loadstring or load)(text))
    local res = {str = "", comment = ""}
    body(lex(text, 1, true), 1, 0, res)
    return res.str
end
return format