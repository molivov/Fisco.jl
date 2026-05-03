# Fisco.jl

A Julia package for modelling fiscal rules — tax schedules, benefit tapers, levy phase-ins, subsidy rates, activity tests, and eligibility cutoffs — as composable primitives.

Fisco provides two primitives: `PiecewiseLinear` for continuous schedules and `StepFunction` for discrete thresholds. Both are immutable, type-stable, and compatible with automatic differentiation (ForwardDiff, Zygote).

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/molivov/Fisco.jl")
```

## Quick start

```julia
using Fisco

# Australian income tax brackets (2024-25)
brackets = PiecewiseLinear(
    (0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0),
    (0.0, 0.16,     0.30,     0.37,      0.45),
    0.0
)

brackets(50_000.0)   # → 5788.0
brackets(200_000.0)  # → 56138.0

marginal_rate(brackets, 50_000.0)  # → 0.30
marginal_rate(brackets, 200_000.0) # → 0.45
```

Printing a schedule shows its full structure:

```julia
julia> brackets
PiecewiseLinear{Float64} with 5 segments:
  [0.0, 18200.0) → rate 0.0, level 0.0
  [18200.0, 45000.0) → rate 0.16, level 0.0
  [45000.0, 135000.0) → rate 0.3, level 4288.0
  [135000.0, 190000.0) → rate 0.37, level 31288.0
  [190000.0, ∞) → rate 0.45, level 51638.0
```

## PiecewiseLinear

A piecewise linear function defined by breakpoints, slopes, and an initial value. The function value at each breakpoint is precomputed at construction for fast evaluation.

### Rates constructor

Specify breakpoints, marginal rates, and the function value at the first breakpoint:

```julia
# LITO: starts at $700, tapers down
lito = PiecewiseLinear(
    (0.0, 37_500.0, 45_000.0, 66_666.67),
    (0.0, -0.05,    -0.015,   0.0),
    700.0
)

lito(30_000.0)   # → 700.0 (full offset)
lito(50_000.0)   # → 250.0 (partially tapered)
lito(80_000.0)   # → 0.0   (fully tapered)

marginal_rate(lito, 40_000.0)  # → -0.05
```

### Levels constructor

Specify breakpoints and the function value at each breakpoint. Rates are derived automatically. The last segment extrapolates flat:

```julia
# CCS rate taper with plateaus (2022-23)
ccs = PiecewiseLinear(
    (0.0, 72_466.0, 177_466.0, 256_756.0, 346_756.0, 356_756.0, 356_757.0);
    levels=(0.85, 0.85, 0.50, 0.50, 0.20, 0.20, 0.0)
)

ccs(100_000.0)   # → 0.758 (tapering from 85% toward 50%)
ccs(200_000.0)   # → 0.50  (plateau)
ccs(400_000.0)   # → 0.0   (above cutoff)
```

### marginal_rate

Returns the slope at a given input — no AD required, just a bracket lookup:

```julia
marginal_rate(brackets, 50_000.0)   # → 0.30 (in the 30% bracket)
marginal_rate(brackets, 18_200.0)   # → 0.16 (at the start of the 16% bracket)
marginal_rate(lito, 50_000.0)       # → -0.015 (LITO tapering at 1.5c/$1)
```

## StepFunction

A piecewise constant function for hard thresholds — activity tests, tiered flat rates, eligibility cutoffs. Also available as `PiecewiseConstant`:

```julia
# CCS activity test: fortnightly hours → max subsidised hours
activity = StepFunction(
    (0.0, 8.0, 17.0, 49.0),
    (0.0, 36.0, 72.0, 100.0),
)

activity(5.0)    # → 0.0  (below threshold)
activity(10.0)   # → 36.0
activity(30.0)   # → 72.0
activity(50.0)   # → 100.0
```

## Composing a tax-transfer calculator

The primitives are building blocks. Composition is plain Julia:

```julia
using Fisco

# Define components
brackets = PiecewiseLinear(
    (0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0),
    (0.0, 0.16, 0.30, 0.37, 0.45), 0.0
)

lito = PiecewiseLinear(
    (0.0, 37_500.0, 45_000.0, 66_666.67),
    (0.0, -0.05, -0.015, 0.0), 700.0
)

medicare = PiecewiseLinear(
    (0.0, 27_222.0, 34_027.5),
    (0.0, 0.10, 0.02), 0.0
)

# Compose
function income_tax(taxable_income)
    gt = brackets(taxable_income)
    lo = lito(taxable_income)
    net = max(0.0, gt - lo)
    ml = medicare(taxable_income)
    return net + ml
end

income_tax(50_000.0)   # → 6538.0
income_tax(200_000.0)  # → 60138.0
```

## Automatic differentiation

Every component is differentiable. Get marginal tax rates analytically:

```julia
using ForwardDiff

# Effective marginal tax rate at $50,000
ForwardDiff.derivative(income_tax, 50_000.0)  # → 0.32

# Or without AD, using marginal_rate on each component:
# brackets: 0.30, lito: -0.015, medicare: 0.02
# effective: 0.30 - (-0.015) + 0.02 = 0.335
# (differs from ForwardDiff because LITO reduces tax, not income)
```

Differentiate with respect to policy parameters by constructing schedules inside the function:

```julia
# How does revenue change if we move the 30% rate?
ForwardDiff.derivative(0.30) do rate
    sched = PiecewiseLinear(
        (0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0),
        (0.0, 0.16, rate, 0.37, 0.45), 0.0
    )
    sched(80_000.0)
end
# → 35000.0 (income in the 30% bracket)
```

## Country modules

Fisco includes pre-built tax-transfer configurations:

```julia
using Fisco

# Look up a financial year (year = ending year)
sys = Fisco.AUS.tax_system(2025)  # 2024-25
sys.brackets(100_000.0)

# Use the built-in calculator
Fisco.AUS.income_tax(80_000.0, 2025)

# Counterfactual: what if we kept 2020 brackets?
Fisco.AUS.income_tax(80_000.0, 2025;
    brackets=Fisco.AUS.BRACKETS_2020
)
```

Australian coverage includes income tax brackets (2009-10 to 2025-26), LITO, Medicare levy, CCS, FTB Parts A and B, JobSeeker, and Parenting Payment.

## Design principles

- **Tax system as data, not code.** A new financial year is a new set of parameters, not new logic.
- **Zero dependencies.** The core package has no dependencies beyond Julia Base.
- **AD-compatible by construction.** All types use `T<:Real` to admit ForwardDiff dual numbers. All structs are immutable. All computation is pure.
- **Composable primitives.** `PiecewiseLinear` and `StepFunction` are the atoms. Tax-transfer calculators are functions that combine them.

