module Fisco

export PiecewiseLinear, StepFunction, PiecewiseConstant, evaluate, marginal_rate

# ============================================================
# Fisco: composable primitives for fiscal rule systems.
#
# Two types:
#   PiecewiseLinear — continuous schedules (tax brackets,
#     offset tapers, levy phase-ins, subsidy rate tapers)
#   StepFunction — discrete thresholds (activity tests,
#     tiered flat rates, eligibility cutoffs)
#
# Both are immutable, type-stable (NTuples), callable,
# and AD-compatible (T<:Real admits ForwardDiff duals).
#
# The representation is (breakpoints, rates, levels) where:
#   - breakpoints[i]: the left edge of segment i
#   - rates[i]: the slope on segment i
#   - levels[i]: the function value at breakpoints[i]
#
# Evaluation: f(x) = levels[i] + rates[i] * (x - breakpoints[i])
# where i is the segment containing x.
#
# The user provides breakpoints, rates, and an initial value
# (f at the leftmost breakpoint). levels is derived automatically.
#
# Design choices:
#   - NTuple for type stability and compile-time unrolling
#   - T<:Real to carry ForwardDiff duals
#   - Immutable for AD compatibility and stack allocation
#   - levels is precomputed at construction, not at evaluation
# ============================================================

"""
    PiecewiseLinear{T<:Real, N}

A piecewise linear function with `N` segments.

For input `x` falling in segment `i`:

    f(x) = levels[i] + rates[i] * (x - breakpoints[i])

where `levels[i]` is the precomputed function value at `breakpoints[i]`.

# Fields
- `breakpoints::NTuple{N, T}` — left edges of each segment (strictly increasing)
- `rates::NTuple{N, T}` — slope on each segment
- `levels::NTuple{N, T}` — function value at each breakpoint (derived)

# Constructors

    PiecewiseLinear(breakpoints, rates, initial)

Provide breakpoints, marginal rates, and the function value at the
first breakpoint. The `levels` values for subsequent segments are
derived from continuity.

    PiecewiseLinear(breakpoints, rates, levels)  # inner constructor

Direct construction with all three tuples — no validation.
"""
struct PiecewiseLinear{T<:Real, N}
    breakpoints::NTuple{N, T}
    rates::NTuple{N, T}
    levels::NTuple{N, T}
end

# ---- Outer constructor: derive levels from initial value ----

function PiecewiseLinear(
    breakpoints::NTuple{N, T},
    rates::NTuple{N, T},
    initial::T
) where {T<:Real, N}
    # Validate strictly increasing breakpoints
    for i in 2:N
        breakpoints[i] > breakpoints[i-1] ||
            throw(ArgumentError("breakpoints must be strictly increasing"))
    end
    levels = _build_levels(breakpoints, rates, initial)
    PiecewiseLinear{T, N}(breakpoints, rates, levels)
end

# Promotion convenience: allow mixed numeric types
function PiecewiseLinear(
    breakpoints::NTuple{N},
    rates::NTuple{N},
    initial::Real
) where {N}
    T = promote_type(eltype(breakpoints), eltype(rates), typeof(initial))
    PiecewiseLinear(
        NTuple{N, T}(breakpoints),
        NTuple{N, T}(rates),
        T(initial)
    )
end

# ---- Construct from (breakpoints, levels) — derive rates ----

"""
    PiecewiseLinear(breakpoints; levels, last_rate=0)

Construct from breakpoints and function values at each breakpoint.
Rates are derived: `rates[i] = (levels[i+1] - levels[i]) / (breakpoints[i+1] - breakpoints[i])`.
The last segment uses `last_rate` (default: zero, i.e. flat extrapolation).

    # CCS taper — flat beyond last breakpoint
    PiecewiseLinear((0.0, 72_466.0, 356_757.0); levels=(0.85, 0.85, 0.0))

    # Tax brackets — 45% beyond last breakpoint
    PiecewiseLinear((0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0);
        levels=(0.0, 0.0, 4_288.0, 31_288.0, 51_638.0), last_rate=0.45)
"""
function PiecewiseLinear(
    breakpoints::NTuple{N};
    levels::NTuple{N},
    last_rate::Real = 0
) where {N}
    T = promote_type(eltype(breakpoints), eltype(levels), typeof(last_rate))
    bp = NTuple{N, T}(breakpoints)
    lv = NTuple{N, T}(levels)
    for i in 2:N
        bp[i] > bp[i-1] ||
            throw(ArgumentError("breakpoints must be strictly increasing"))
    end
    rates = _derive_rates(bp, lv, T(last_rate))
    PiecewiseLinear{T, N}(bp, rates, lv)
end

# Derive rates via recursive tuple peeling
function _derive_rates(bp::NTuple{N, T}, lv::NTuple{N, T}, last_rate::T) where {T, N}
    if N == 1
        return (last_rate,)
    end
    rate = (lv[2] - lv[1]) / (bp[2] - bp[1])
    return (rate, _derive_rates(Base.tail(bp), Base.tail(lv), last_rate)...)
end

# ---- Build levels via recursive tuple peeling ----

function _build_levels(
    bp::NTuple{N, T},
    r::NTuple{N, T},
    v::T
) where {T, N}
    if N == 1
        return (v,)
    end
    next = v + r[1] * (bp[2] - bp[1])
    return (v, _build_levels(Base.tail(bp), Base.tail(r), next)...)
end

# ---- Bracket lookup ----

"""
    _find_bracket(breakpoints::NTuple{N}, x) → Int

Return the index of the segment containing `x`.
For x < breakpoints[1], returns 1 (clamp to first segment).
Compiler unrolls since N is a type parameter.
"""
@inline function _find_bracket(bp::NTuple{N, T}, x::Real) where {T, N}
    i = 1
    while i < N && x >= bp[i + 1]
        i += 1
    end
    return i
end

# ---- Evaluation ----

"""
    evaluate(pl::PiecewiseLinear, x::Real)

Evaluate the piecewise linear function at `x`.

For `x` below the first breakpoint, extrapolates using the
first segment's rate and level.
"""
@inline function evaluate(pl::PiecewiseLinear, x::Real)
    i = _find_bracket(pl.breakpoints, x)
    return pl.levels[i] + pl.rates[i] * (x - pl.breakpoints[i])
end

# Callable struct
@inline (pl::PiecewiseLinear)(x::Real) = evaluate(pl, x)

# ---- Marginal rate lookup ----

"""
    marginal_rate(pl::PiecewiseLinear, x::Real)

Return the slope of the segment containing `x`. No AD required.
"""
@inline function marginal_rate(pl::PiecewiseLinear, x::Real)
    i = _find_bracket(pl.breakpoints, x)
    return pl.rates[i]
end

# ---- Display ----

function Base.show(io::IO, pl::PiecewiseLinear{T, N}) where {T, N}
    print(io, "PiecewiseLinear{$T} with $N segments")
end

function Base.show(io::IO, ::MIME"text/plain", pl::PiecewiseLinear{T, N}) where {T, N}
    println(io, "PiecewiseLinear{$T} with $N segments:")
    for i in 1:N
        bp = pl.breakpoints[i]
        upper = i < N ? string(pl.breakpoints[i + 1]) : "∞"
        println(io, "  [$bp, $upper) → rate $(pl.rates[i]), level $(pl.levels[i])")
    end
end

# ============================================================
# StepFunction: piecewise constant (no slopes).
#
# For step schedules like activity tests, hard cutoffs,
# tiered flat rates. Input x maps to the value associated
# with the highest threshold ≤ x.
#
# Design: same conventions as PiecewiseLinear — NTuples,
# immutable, T<:Real, callable.
# ============================================================

"""
    StepFunction{T<:Real, N}

A piecewise constant function with `N` steps.

For input `x`, returns the value associated with the highest
threshold ≤ `x`.

# Fields
- `thresholds::NTuple{N, T}` — left edges of each step (ascending)
- `values::NTuple{N, T}` — function value on each step

# Example
    sf = StepFunction((0.0, 8.0, 17.0, 48.0), (0.0, 36.0, 72.0, 100.0))
    sf(10.0)  # → 36.0
    sf(50.0)  # → 100.0
"""
struct StepFunction{T<:Real, N}
    thresholds::NTuple{N, T}
    values::NTuple{N, T}

    function StepFunction(
        thresholds::NTuple{N, T},
        values::NTuple{N, T}
    ) where {T<:Real, N}
        for i in 2:N
            thresholds[i] > thresholds[i-1] ||
                throw(ArgumentError("thresholds must be strictly increasing"))
        end
        new{T, N}(thresholds, values)
    end
end

# Promotion convenience
function StepFunction(thresholds::NTuple{N}, values::NTuple{N}) where {N}
    T = promote_type(eltype(thresholds), eltype(values))
    StepFunction(NTuple{N, T}(thresholds), NTuple{N, T}(values))
end

@inline function evaluate(sf::StepFunction{T, N}, x::Real) where {T, N}
    i = 1
    while i < N && x >= sf.thresholds[i + 1]
        i += 1
    end
    return sf.values[i]
end

@inline (sf::StepFunction)(x::Real) = evaluate(sf, x)

const PiecewiseConstant = StepFunction

# Country modules
include("countries/AUS.jl")

end # module