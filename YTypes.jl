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


const YELLOW_SHADES = [
    220,
    214,
    172,
    208,
    166
]

const Y_MAJOR_VERSION = "0"
const Y_MINOR_VERSION = "1"
const Y_PATCH = "0-alpha"

const ANSI_COLORS = map(x -> "\033[38;5;$(x)m", YELLOW_SHADES)

const REPL_HEADER = [
    " __   __  ",
    " \\ \\ / /  ",
    "  \\ V /   ",
    "   | |    ",
    "   |_|    ",
]

const REPL_MSG = [
    "",
    "Y interpreter $Y_MAJOR_VERSION.$Y_MINOR_VERSION.$Y_PATCH" *
    " Copyright © 2020 swissChili",
    "This program comes with ABSOLUTELY NO WARRANTY; see COPYING.",
    "This is free software, and you are welcome to redistribute",
    "it under the conditions of the GNU GPL version 3 or later."
]

function print_header()
    for (i, l) in enumerate(REPL_HEADER)
        println(ANSI_COLORS[i], l, "\033[0m", REPL_MSG[i])
    end
    println()
end


mutable struct Lexer
    input::Array{Char, 1}
    i::Int
end

abstract type Inst
end

struct QuoteNext <: Inst
end

struct BeginArray <: Inst
end

struct EndArray <: Inst
end

struct BeginTuple <: Inst
end

struct EndTuple <: Inst
end

struct PushVar <: Inst
    name::String
end

struct PushVarRef <: Inst
    name::String
end

struct PushConst <: Inst
    val::Union{Int, Float64}
end

struct CallMonad <: Inst
    name::String
end

struct CallDyad <: Inst
    name::String
end

struct DefMonad <: Inst
    name::String
    body::Array{Inst, 1}
end

struct DefDyad <: Inst
    name::String
    body::Array{Inst, 1}
end

struct Context
    parent::Union{Nothing, Context}
    defs::Dict{String, Any}
end

struct QuotedArray
    ctx::Context
    val::Array{Inst, 1}
end

# Dyads are by default right associative
@enum ValueType VAR=1 MONAD=2 DYAD=3 DYADL=4 GROUPING=5

struct VarRef
    name::String
end

struct VMState
    stack::Array{Any, 1}
    last_if_was::Bool
end

abstract type Callable
end

struct JuliaFun <: Callable
    numargs::Int # monad or dyad
    fun::Function
end

struct SpecialFun <: Callable
    numargs::Int # monad or dyad
    fun::Function # this also takes VMState and Context arguments
end

function callfn(fn::JuliaFun, s::VMState, c::Context, x, y)
    if fn.numargs != 2
        throw("Calling monad as dyad")
    end
    fn.fun(x, y)
end

function callfn(fn::SpecialFun, s::VMState, c::Context, x, y)
    if fn.numargs != 2
        throw("Calling monad as dyad")
    end
    fn.fun(s, c, x, y)
end

function callfn(fn::JuliaFun, s::VMState, c::Context, x)
    if fn.numargs != 1
        throw("Calling dyad as monad")
    end
    fn.fun(x)
end

function callfn(fn::SpecialFun, s::VMState, c::Context, x)
    if fn.numargs != 1
        throw("Calling dyad as monad")
    end
    fn.fun(s, c, x)
end

function callfn(fn::QuotedArray, s::VMState, c::Context, x)
    newctx = Context(fn.ctx, Dict("x" => x))
    ebc(fn.val, newctx)
end

function callfn(fn::QuotedArray, s::VMState, c::Context, x, y)
    newctx = Context(fn.ctx, Dict("x" => x, "y" => y))
    ebc(fn.val, newctx)
end

function Base.getindex(ctx::Context, key::String)
    if haskey(ctx.defs, key)
        ctx.defs[key]
    elseif ctx.parent != nothing
        ctx.parent[key]
    else
        nothing
    end
end

const special_chars = collect("←↔→«»+_*/^%\$#@~`\\';¤÷·∘∋∌{}[]<>()")
precedence = Dict{String, Int}()
types = Dict{String, ValueType}()

for (s, p) in (";" => -1, "←=↔" => 0, "→,}]" => 1, "{[" => 6)
    for char in s
        precedence[String([char])] = p
        types[String([char])] = DYADL
    end
end

for g in ["(", ")", "{", "}", "[", "]"]
    types[g] = GROUPING
end

types["x"] = VAR
types["y"] = VAR

internal_funs = Dict{String, Callable}()

function exposefun(f, name::String, type::ValueType, p::Int=5)
    if !(type in [MONAD, DYAD, DYADL])
        throw("Can only expose MONADs, DYADs or DYADLs")
    end
    
    internal_funs[name] = JuliaFun(type == MONAD ? 1 : 2, f)
    types[name] = type
    precedence[name] = p
end

function exposespecial(f, name::String, type::ValueType, p::Int=5)
    if !(type in [MONAD, DYAD, DYADL])
        throw("Can only expose MONADs, DYADs or DYADLs")
    end

    internal_funs[name] = SpecialFun(type == MONAD ? 1 : 2, f)
    types[name] = type
    precedence[name] = p
end

function defmonad(f, name::String, p::Int=5)
    exposefun(f, name, MONAD, p)
end

function defdyad(f, name::String, p::Int=5; r=false)
    exposefun(f, name, r ? DYAD : DYADL, p)
end
