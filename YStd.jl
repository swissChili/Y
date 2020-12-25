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


issomething(x) = x != false && x != nothing

defmonad((!)∘issomething, "!")
defmonad(issomething, "Bool")

defdyad(==, "==", 2)
defdyad(!=, "!=", 2)
defdyad(<, "<", 2)
defdyad(>, ">", 2)
defdyad("&", 2) do x, y
    issomething(x) && issomething(y)
end
defdyad("|", 2) do x, y
    issomething(x) || issomething(y)
end

defdyad(+, "+", 3; r=true)
defdyad(-, "-", 3; r=true)
defdyad(mod, "%", 3)

defdyad(*, "*", 4; r=true)
defdyad(*, "×", 4; r=true)
defdyad(*, "·", 4; r=true)
defdyad(/, "/", 4; r=true)
defdyad(/, "÷", 4; r=true)

defmonad(length, "#")
defdyad("∋") do x, y
    if isa(y, Dict)
        x in keys(y)
    else
        x in y
    end
end
defdyad("∌") do x, y
    if isa(y, Dict)
        !(x in keys(y))
    else
        !(x in y)
    end
end

function adddef(s, ctx, name, body)
    ctx.defs[String(name)] = body
    body
end

# Declarations and assignments
exposespecial(adddef, "←", DYAD, 0)
exposespecial(adddef, "↔", DYAD, 0)
exposespecial(adddef, "=", DYAD, 0)


function yshow(val::QuotedArray; indent=0)
    ("  " ^ indent) * "<Callable: quoted array>"
end

function yshow(val::JuliaFun; indent=0)
    ("  " ^ indent) * "<Callable: internal function>"
end

function yshow(val::SpecialFun; indent=0)
    ("  " ^ indent) * "<Callable: special function>"
end

function yshow(val::Set{}; indent=0)
    ("  " ^ indent) * "Set\n" * yshow(collect(val); indent=indent+1)
end

function yshow(val::Array{}; indent=0)
    pad = "  " ^ indent
    pad * "{ " * join([yshow(x; indent=indent+1) for x in val], "\n" * pad * "; ") * "\n" * pad * "}"
end

function yshow(val::Any; indent=0)
    ("  " ^ indent) *string(val)
end

defmonad("Str") do x
    yshow(x)
end

defmonad("Show") do x
    print(yshow(x))
    nothing
end

defmonad("ShowLn") do x
    println(yshow(x))
    nothing
end

defmonad("Set") do x
    Set(x)
end

defdyad("∩") do x, y
    intersect(x, y)
end

defdyad("∪") do x, y
    union(x, y)
end

defdyad("At") do coll::Array{}, ind
    coll[ind]
end

exposespecial("⋱", DYADL) do state, ctx, coll, fun
    reduce((o, x) -> callfn(fun, state, ctx, o, x), coll)
end
