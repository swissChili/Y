# Y interpreter
# Copyright (C) 2020  swissChili

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
            

include("YTypes.jl")
include("YStd.jl")

function char(l::Lexer)
    if l.i <= length(l.input)
        l.input[l.i]
    else
        return nothing
    end
end

function ws(l::Lexer)
    while char(l) != nothing && char(l) |> isspace
        l.i += 1
    end
    if char(l) == '«'
        l.i += 1
        while char(l) != '»'
            if char(l) == nothing
                throw("Expected » before end of input")
            end
            l.i += 1
        end
        l.i += 1
        
        if char(l) != nothing
            ws(l)
        end
    end
end

function tok(l::Lexer)
    if char(l) == nothing
        return nothing
    end
    
    ws(l)
    
    if char(l) == nothing
        return nothing
    end
    
    if isdigit(char(l))
        str = ""
        while char(l) != nothing && isdigit(char(l))
            str *= char(l)
            l.i += 1
        end
        if char(l) == '.'
            # float
            str *= '.'
            l.i += 1
            while char(l) != nothing isdigit(char(l))
                str *= l.input[l.i]
                l.i += 1
            end
            return parse(Float64, str)
        else
            return parse(Int, str)
        end
    elseif char(l) in ['(', ')']
        c = char(l)
        l.i += 1
        return c
    elseif char(l) in special_chars
        c = char(l)
        l.i += 1
        return String([c])
    elseif isprint(char(l))
        str = ""
        while char(l) != nothing && isprint(char(l)) && !isdigit(char(l)) &&
            !isspace(char(l)) && !(char(l) in special_chars)
            str *= char(l)
            l.i += 1
        end
        return str
    end
end

function peek(l::Lexer)
    i = l.i
    t = tok(l)
    l.i = i
    return t
end

# compile byte-code (not actually byte-code)
function cbc(l::Lexer, types::Dict{String, ValueType}, precedence::Dict{String, Int64}; defaultp=5)
    stack::Array{Inst, 1} = []
    ops = Array{String, 1}()
    
    gettype(t) = if !(t in keys(types))
        throw(t * " does not have a defined type")
    else
        return types[t]
    end
    
    popmonads() = while length(ops) > 0 && types[ops[end]] == MONAD
        push!(stack, CallMonad(pop!(ops)))
    end
    
    getp(name) = if name in keys(precedence)
        precedence[name]
    else
        defaultp
    end

    function callx(x)
        tt = gettype(x)
        if tt == DYAD || tt == DYADL
            CallDyad(x)
        elseif tt == MONAD
            CallMonad(x)
        else
            throw("Leftover value " * x * " of type " * string(tt))
        end
    end

    quote_next = false
    
    while (t = tok(l)) != nothing

        if t == "\\"
            quote_next = true
            continue
        end
        
        if isa(t, Int) || isa(t, Float64)
            push!(stack, PushConst(t))
            popmonads()
        elseif isa(t, Char)
            if t == '('
                push!(ops, "(")
            elseif t == ')'
                while length(ops) > 0 && ops[end] != "("
                    push!(stack, callx(pop!(ops)))
                end
                if length(ops) == 0
                    throw("Expected matching opening (, end of ops stack")
                end
                if pop!(ops) != "("
                    throw("Expected matching opening (")
                end
                popmonads()
            end
        elseif isa(t, String)
            n = peek(l)
            if n != nothing && n[1] in ['←', '=', '↔']
                push!(stack, PushVarRef(t))
                types[t] = Dict('←' => MONAD, '=' => VAR, '↔' => DYADL)[n[1]];
                continue
            end
            
            tt = gettype(t)
            if tt == VAR
                push!(stack, quote_next ? PushVarRef(t) : PushVar(t))
                popmonads()
            elseif quote_next && !(t in ["{", "}"])
                push!(stack, PushVar(t))
                popmonads()
            elseif tt == MONAD
                push!(ops, t)
            elseif tt == DYAD || tt == DYADL || tt == GROUPING
                prec = getp(t)
                
                while length(ops) > 0 && types[ops[end]] != GROUPING &&
                    (getp(ops[end]) > prec ||
                     (getp(ops[end]) == prec && tt == DYADL))
                    
                    last = pop!(ops)
                    if !(types[last] in [DYAD, DYADL])
                        throw("Expected a dyad on top of ops stack")
                        break
                    end
                    push!(stack, CallDyad(last))
                end
                if t == "{"
                    if quote_next
                        push!(stack, QuoteNext())
                    end
                    push!(stack, BeginArray())
                    push!(ops, "{")
                elseif t == "["
                    push!(stack, BeginTuple())
                    push!(ops, "[")
                elseif t == "}" || t == "]"
                    opening = (t == "}" ? "{" : "[")
                    while length(ops) > 0 && ops[end] != opening
                        push!(stack, callx(pop!(ops)))
                    end
                    @show ops
                    if length(ops) == 0
                        throw("Expected matching opening " * t * ", got end of operator stack")
                    end
                    if pop!(ops) != opening
                        throw("Expected matching opening " * opening)
                    end
                    push!(stack, t == "}" ? EndArray() : EndTuple())
                    popmonads()
                elseif t == ";"
                    # ignored
                else
                    push!(ops, t)
                end
            end
        end

        quote_next = false
    end
    
    while length(ops) > 0
        push!(stack, CallDyad(pop!(ops)))
    end
    
    stack
end

function ebc(bc::Array{Inst, 1}, ctx::Context; idx=1)
    s = VMState([], false)
    quote_next = false
    
    while idx <= length(bc)
        i = bc[idx]
        
        if isa(i, PushVar)
            push!(s.stack, quote_next ? Symbol(i.name) : ctx[i.name])
        elseif isa(i, PushVarRef)
            push!(s.stack, Symbol(i.name))
        elseif isa(i, PushConst)
            push!(s.stack, i.val)
        elseif isa(i, CallDyad)
            y = pop!(s.stack)
            x = pop!(s.stack)
            push!(s.stack, callfn(ctx[i.name], s, ctx, x, y))
        elseif isa(i, CallMonad)
            x = pop!(s.stack)
            push!(s.stack, callfn(ctx[i.name], s, ctx, x))
        elseif isa(i, QuoteNext)
            quote_next = true
            idx += 1
            continue
        elseif isa(i, BeginArray)
            idx += 1
            if quote_next
                arr = []
                while !isa(bc[idx], EndArray)
                    push!(arr, bc[idx])
                    idx += 1
                end
                push!(s.stack, QuotedArray(ctx, arr))
            else
                idx, arr = ebc(bc, ctx; idx=idx)
                push!(s.stack, arr)
            end
        elseif isa(i, BeginTuple)
            idx += 1
            idx, tpl = ebc(bc, ctx; idx=idx)
            push!(s.stack, tpl)
        elseif isa(i, EndArray)
            return idx, s.stack
        elseif isa(i, EndTuple)
            @show s.stack
            return idx, Tuple(s.stack)
        else
            throw("Unknown instruction ", i)
        end
        
        idx += 1
        quote_next = false

        #@show s.stack
    end

    return isempty(s.stack) ? nothing : s.stack[end]
end

function main()
    ctx = Context(Context(nothing, internal_funs), Dict())
    
    if length(ARGS) < 1
        print_header()
        while isopen(stdin)
            print("\033[33mY \033[0m")
            flush(stdout)
            line = readline()
            if length(line) == 0
                println()
                continue
            end
            l = Lexer(collect(line), 1)

            bc = cbc(l, types, precedence)
            println(bc)
            yshow(ebc(bc, ctx)) |> println
        end
    else
        body = read(ARGS[1], String)
        l = Lexer(collect(body), 1)
        bc = cbc(l, types, precedence)
        #display(bc)
        #println()
        ebc(bc, ctx)# |> yshow |> println
    end
end

main()
