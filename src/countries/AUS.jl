# ============================================================
# Australian Personal Income Tax — Resident Individual
#
# Configurations from 2009-10 to 2025-26.
# Sources: ATO tax rate tables, ATO LITO/LMITO schedules,
#          ATO Medicare levy low-income thresholds.
#
# Each financial year is a NamedTuple of PiecewiseLinear instances.
# FY(2025) means the year ending 30 June 2025 (i.e. 2024-25).
# ============================================================

module AUS

using ..Fisco: PiecewiseLinear, StepFunction

struct FY
    year::Int  # ending year
end
Base.show(io::IO, fy::FY) = print(io, "$(fy.year-1)-$(string(fy.year)[3:4])")
Base.hash(fy::FY, h::UInt) = hash(fy.year, h)
Base.:(==)(a::FY, b::FY) = a.year == b.year

# Helper: compute LITO zero crossing from taper
_lito_zero(threshold, taper_rate, level) = threshold + level / taper_rate

# Helper: compute Medicare crossover
# Shade-in rate s, full rate r, lower threshold L:
#   s(x - L) = r*x  →  x = s*L/(s - r)
_ml_crossover(lower, shade_rate, full_rate) = shade_rate * lower / (shade_rate - full_rate)

# ============================================================
# Income tax brackets
# ============================================================

# 2024-25, 2025-26 (Stage 3)
const BRACKETS_2025 = PiecewiseLinear(
    (0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0),
    (0.0, 0.16,     0.30,     0.37,      0.45),
    0.0
)

# 2020-21 to 2023-24 (Stage 2)
const BRACKETS_2021 = PiecewiseLinear(
    (0.0, 18_200.0, 45_000.0, 120_000.0, 180_000.0),
    (0.0, 0.19,     0.325,    0.37,      0.45),
    0.0
)

# 2019-20 (Stage 1)
const BRACKETS_2020 = PiecewiseLinear(
    (0.0, 18_200.0, 37_000.0, 90_000.0, 180_000.0),
    (0.0, 0.19,     0.325,    0.37,     0.45),
    0.0
)

# 2018-19
const BRACKETS_2019 = BRACKETS_2020

# 2017-18
const BRACKETS_2018 = PiecewiseLinear(
    (0.0, 18_200.0, 37_000.0, 87_000.0, 180_000.0),
    (0.0, 0.19,     0.325,    0.37,     0.45),
    0.0
)

# 2016-17
const BRACKETS_2017 = BRACKETS_2018

# 2015-16
const BRACKETS_2016 = PiecewiseLinear(
    (0.0, 18_200.0, 37_000.0, 80_000.0, 180_000.0),
    (0.0, 0.19,     0.325,    0.37,     0.45),
    0.0
)

# 2014-15
const BRACKETS_2015 = BRACKETS_2016

# 2013-14
const BRACKETS_2014 = BRACKETS_2016

# 2012-13
const BRACKETS_2013 = BRACKETS_2016

# 2011-12
const BRACKETS_2012 = PiecewiseLinear(
    (0.0, 6_000.0, 37_000.0, 80_000.0, 180_000.0),
    (0.0, 0.15,    0.30,     0.37,     0.45),
    0.0
)

# 2010-11
const BRACKETS_2011 = BRACKETS_2012

# 2009-10
const BRACKETS_2010 = PiecewiseLinear(
    (0.0, 6_000.0, 35_000.0, 80_000.0, 180_000.0),
    (0.0, 0.15,    0.30,     0.38,     0.45),
    0.0
)

# ============================================================
# Low Income Tax Offset (LITO)
# ============================================================

# 2020-21 to 2025-26: max $700
# Tapers: 5c/$1 from $37,500 to $45,000 (to $325)
#         1.5c/$1 from $45,000 to ~$66,667 (to $0)
const LITO_2021 = PiecewiseLinear(
    (0.0, 37_500.0, 45_000.0, _lito_zero(45_000.0, 0.015, 325.0)),
    (0.0, -0.05,    -0.015,   0.0),
    700.0
)

# 2012-13 to 2019-20: max $445
# Tapers: 1.5c/$1 from $37,000 to ~$66,667 (to $0)
const LITO_2013 = PiecewiseLinear(
    (0.0, 37_000.0, _lito_zero(37_000.0, 0.015, 445.0)),
    (0.0, -0.015,   0.0),
    445.0
)

# 2010-11, 2011-12: max $1,500
# Tapers: 4c/$1 from $30,000 to ~$67,500 (to $0)
const LITO_2011 = PiecewiseLinear(
    (0.0, 30_000.0, _lito_zero(30_000.0, 0.04, 1_500.0)),
    (0.0, -0.04,    0.0),
    1_500.0
)

# 2009-10: max $1,350
# Tapers: 4c/$1 from $30,000 to ~$63,750 (to $0)
const LITO_2010 = PiecewiseLinear(
    (0.0, 30_000.0, _lito_zero(30_000.0, 0.04, 1_350.0)),
    (0.0, -0.04,    0.0),
    1_350.0
)

# ============================================================
# Medicare Levy (singles, non-SAPTO)
# 2% rate, 10% shade-in from lower threshold
#
# Lower thresholds sourced from ATO. Crossover computed exactly
# so PiecewiseLinear is continuous.
# ============================================================

function _medicare(lower::Float64)
    crossover = _ml_crossover(lower, 0.10, 0.02)
    PiecewiseLinear(
        (0.0, lower, crossover),
        (0.0, 0.10,  0.02),
        0.0
    )
end

const MEDICARE_2025 = _medicare(27_222.0)  # 2024-25, 2025-26
const MEDICARE_2024 = MEDICARE_2025
const MEDICARE_2023 = _medicare(26_000.0)  # 2022-23, 2023-24
const MEDICARE_2022 = _medicare(23_365.0)  # 2021-22
const MEDICARE_2021 = _medicare(23_226.0)  # 2020-21
const MEDICARE_2020 = _medicare(22_801.0)  # 2019-20
const MEDICARE_2019 = _medicare(21_980.0)  # 2018-19
const MEDICARE_2018 = _medicare(21_655.0)  # 2017-18
const MEDICARE_2017 = _medicare(21_335.0)  # 2016-17
const MEDICARE_2016 = _medicare(20_896.0)  # 2015-16
const MEDICARE_2015 = _medicare(20_542.0)  # 2014-15
const MEDICARE_2014 = _medicare(20_542.0)  # 2013-14
const MEDICARE_2013 = _medicare(20_542.0)  # 2012-13
const MEDICARE_2012 = _medicare(19_404.0)  # 2011-12
const MEDICARE_2011 = _medicare(18_839.0)  # 2010-11
const MEDICARE_2010 = _medicare(18_488.0)  # 2009-10

# ============================================================
# System lookup
# ============================================================

const SYSTEMS = Dict(
    FY(2026) => (brackets=BRACKETS_2025, lito=LITO_2021, medicare=MEDICARE_2025),
    FY(2025) => (brackets=BRACKETS_2025, lito=LITO_2021, medicare=MEDICARE_2025),
    FY(2024) => (brackets=BRACKETS_2021, lito=LITO_2021, medicare=MEDICARE_2023),
    FY(2023) => (brackets=BRACKETS_2021, lito=LITO_2021, medicare=MEDICARE_2023),
    FY(2022) => (brackets=BRACKETS_2021, lito=LITO_2021, medicare=MEDICARE_2022),
    FY(2021) => (brackets=BRACKETS_2021, lito=LITO_2021, medicare=MEDICARE_2021),
    FY(2020) => (brackets=BRACKETS_2020, lito=LITO_2013, medicare=MEDICARE_2020),
    FY(2019) => (brackets=BRACKETS_2019, lito=LITO_2013, medicare=MEDICARE_2019),
    FY(2018) => (brackets=BRACKETS_2018, lito=LITO_2013, medicare=MEDICARE_2018),
    FY(2017) => (brackets=BRACKETS_2017, lito=LITO_2013, medicare=MEDICARE_2017),
    FY(2016) => (brackets=BRACKETS_2016, lito=LITO_2013, medicare=MEDICARE_2016),
    FY(2015) => (brackets=BRACKETS_2015, lito=LITO_2013, medicare=MEDICARE_2015),
    FY(2014) => (brackets=BRACKETS_2014, lito=LITO_2013, medicare=MEDICARE_2014),
    FY(2013) => (brackets=BRACKETS_2013, lito=LITO_2013, medicare=MEDICARE_2013),
    FY(2012) => (brackets=BRACKETS_2012, lito=LITO_2011, medicare=MEDICARE_2012),
    FY(2011) => (brackets=BRACKETS_2011, lito=LITO_2011, medicare=MEDICARE_2011),
    FY(2010) => (brackets=BRACKETS_2010, lito=LITO_2010, medicare=MEDICARE_2010),
)

"""
    tax_system(fy::FY)
    tax_system(year::Int)

Return the tax system (brackets, lito, medicare) for a financial year.
`year` is the ending year: `tax_system(2025)` returns the 2024-25 system.
"""
tax_system(fy::FY) = SYSTEMS[fy]
tax_system(year::Int) = tax_system(FY(year))

"""
    income_tax(taxable_income, fy; kwargs...)

Total personal income tax for a non-senior Australian resident,
including Medicare levy, net of LITO.
"""
function income_tax(
    taxable_income::Real,
    fy::Union{FY, Int};
    brackets = nothing,
    lito     = nothing,
    medicare = nothing,
)
    sys = tax_system(fy isa Int ? FY(fy) : fy)
    b = brackets !== nothing ? brackets : sys.brackets
    l = lito     !== nothing ? lito     : sys.lito
    m = medicare !== nothing ? medicare : sys.medicare

    gt = b(taxable_income)
    lo = l(taxable_income)
    net = max(zero(gt), gt - lo)
    ml = m(taxable_income)
    return net + ml
end

# ============================================================
# TRANSFERS — Income test tapers (2024-25)
#
# These encode the taper schedules ONLY. Base rates are
# provided as constants but change with indexation (Mar/Sep).
# The PiecewiseLinear gives you: payment = taper(income),
# starting from the max rate and tapering to zero.
#
# VERIFY base rates against Services Australia before use.
# Rates below are approximate as at 20 March 2025.
# ============================================================

# ── Child Care Subsidy (2024-25) ──
# Input: family adjusted taxable income (annual)
# Output: subsidy rate (0.0 to 0.90)
# Taper: 1pp per $5,000 of income above $83,280
# Zero at $533,280

const CCS_RATE_2025 = PiecewiseLinear(
    (0.0, 83_280.0, 533_280.0),
    (0.0, -0.01/5_000, 0.0),
    0.90
)

# CCS activity test: maps fortnightly activity hours to max
# subsidised care hours per fortnight.
# The lower-activity parent determines the cap.
# Note: families below income threshold get 24hrs even with
# 0-7 activity hours — that logic is in the caller, not here.
const CCS_ACTIVITY_2025 = StepFunction(
    (0.0, 8.0, 17.0, 49.0),
    (0.0, 36.0, 72.0, 100.0),
)

# CCS hourly rate caps by care type (2024-25)
const CCS_HOURLY_CAP_CENTRE_2025    = 14.29
const CCS_HOURLY_CAP_FDC_2025       = 12.40
const CCS_HOURLY_CAP_OSHC_2025      = 12.48
const CCS_HOURLY_CAP_IHC_2025       = 34.52

# ── Family Tax Benefit Part A (2024-25) ──
# Two income tests; whichever gives HIGHER payment applies.
# Both are per-child annual amounts tapered on family ATI.
#
# Test 1: max rate reduces by 20c/$1 above $65,189
#   Max rate (0-12): $5,772.08/yr; (13-19): $7,510.28/yr
#   Tapers to base rate: $1,856.28/yr per child
#
# Test 2: base rate reduces by 30c/$1 above $118,771
#   Tapers to zero.
#
# These tapers give ANNUAL per-child amounts.

const FTB_A_MAX_0_12 = 5_772.08   # per child per year
const FTB_A_MAX_13   = 7_510.28   # per child per year
const FTB_A_BASE     = 1_856.28   # per child per year

# Test 1 taper (from max to base)
const FTB_A_TEST1_0_12 = PiecewiseLinear(
    (0.0, 65_189.0, 65_189.0 + (FTB_A_MAX_0_12 - FTB_A_BASE) / 0.20),
    (0.0, -0.20,    0.0),
    FTB_A_MAX_0_12
)

const FTB_A_TEST1_13 = PiecewiseLinear(
    (0.0, 65_189.0, 65_189.0 + (FTB_A_MAX_13 - FTB_A_BASE) / 0.20),
    (0.0, -0.20,    0.0),
    FTB_A_MAX_13
)

# Test 2 taper (from base to zero)
const FTB_A_TEST2 = PiecewiseLinear(
    (0.0, 118_771.0, 118_771.0 + FTB_A_BASE / 0.30),
    (0.0, -0.30,     0.0),
    FTB_A_BASE
)

# ── Family Tax Benefit Part B (2024-25) ──
# Per-family payment based on secondary earner's income.
# Couples: primary earner must earn ≤ $120,007/yr.
# Secondary earner free area: $6,935/yr, then 20c/$1 taper.
# Single parents: no income test on Part B.
#
# Max rates (annual):
#   Youngest child 0-4:  $5,026.84/yr
#   Youngest child 5-18: $3,508.96/yr

const FTB_B_MAX_0_4  = 5_026.84
const FTB_B_MAX_5_18 = 3_508.96

# Taper on secondary earner income (annual)
const FTB_B_TAPER_0_4 = PiecewiseLinear(
    (0.0, 6_935.0, 6_935.0 + FTB_B_MAX_0_4 / 0.20),
    (0.0, -0.20,   0.0),
    FTB_B_MAX_0_4
)

const FTB_B_TAPER_5_18 = PiecewiseLinear(
    (0.0, 6_935.0, 6_935.0 + FTB_B_MAX_5_18 / 0.20),
    (0.0, -0.20,   0.0),
    FTB_B_MAX_5_18
)

# ── JobSeeker Payment — income test tapers (2024-25) ──
# Input: fortnightly income
# Output: fortnightly payment reduction (subtract from max rate)
#
# Single, no children (not principal carer):
#   Free area: $150/fn
#   50c/$1 from $150 to $256
#   60c/$1 above $256
#
# Single, principal carer:
#   Free area: $150/fn
#   40c/$1 above $150
#
# Base rates (approx 20 Mar 2025, verify):
#   Single no children 22+:     $762.70/fn
#   Single with children 22+:   $816.90/fn
#   Partnered (each):           $693.70/fn

const JSP_MAX_SINGLE       = 762.70
const JSP_MAX_SINGLE_KIDS  = 816.90
const JSP_MAX_PARTNERED    = 693.70

# Payment taper: starts at max, reduces with income
# Single, not principal carer
const JSP_TAPER_SINGLE = PiecewiseLinear(
    (0.0, 150.0, 256.0),
    (0.0, -0.50, -0.60),
    JSP_MAX_SINGLE
)

# Single, principal carer
const JSP_TAPER_SINGLE_CARER = PiecewiseLinear(
    (0.0, 150.0),
    (0.0, -0.40),
    JSP_MAX_SINGLE_KIDS
)

# Partnered (own income only; partner income is separate)
const JSP_TAPER_PARTNERED = PiecewiseLinear(
    (0.0, 150.0, 256.0),
    (0.0, -0.50, -0.60),
    JSP_MAX_PARTNERED
)

# ── Parenting Payment — income test tapers (2024-25) ──
# Input: fortnightly income
#
# Single (PPS):
#   Free area: $224.60/fn (1 child; +$24.60 per extra child)
#   40c/$1 above free area
#   Max rate: $987.70/fn (incl pension supplement)
#
# Partnered (PPP):
#   Free area: $150.00/fn
#   50c/$1 from $150 to $256
#   60c/$1 above $256
#   Max rate: ~$693.70/fn

const PPS_MAX = 987.70   # single, incl pension supplement
const PPP_MAX = 693.70   # partnered

# Parenting Payment Single (1 child)
const PPS_TAPER = PiecewiseLinear(
    (0.0, 224.60),
    (0.0, -0.40),
    PPS_MAX
)

# Parenting Payment Partnered (own income)
const PPP_TAPER = PiecewiseLinear(
    (0.0, 150.0, 256.0),
    (0.0, -0.50, -0.60),
    PPP_MAX
)

# ============================================================
# TRANSFERS — 2022-23 (rates as at 20 March 2023)
#
# Taper STRUCTURES are the same as 2024-25.
# Only base rates and some thresholds differ.
# ============================================================

# CCS 2022-23: piecewise linear taper with plateaus
# Source: Services Australia guide, 1 Dec 2022
#   ≤ $72,466:              85%
#   $72,466 – $177,466:     decreases by 1pp per $3,000 (to 50%)
#   $177,466 – $256,756:    flat 50%
#   $256,756 – $346,756:    decreases by 1pp per $3,000 (to 20%)
#   $346,756 – $356,756:    flat 20%
#   ≥ $356,756:             0%
# The 20%→0% drop is a hard cutoff. We encode it as a steep
# 1-dollar taper so levels remain continuous.
const CCS_RATE_2023 = PiecewiseLinear(
    (0.0, 72_466.0, 177_466.0, 256_756.0, 346_756.0, 356_756.0, 356_757.0),
    (0.0, -0.01/3_000, 0.0, -0.01/3_000, 0.0, -0.20, 0.0),
    0.85
)

# CCS activity test 2022-23
# Source: Services Australia guide, 1 Dec 2022
#   0–7 hrs:    0 (24 via safety net if income ≤ $72,466)
#   8–16 hrs:   36
#   17–48 hrs:  72
#   49+ hrs:    100
# Note: "more than 48 hours" → step at 49, not 48
const CCS_ACTIVITY_2023 = StepFunction(
    (0.0, 8.0, 17.0, 49.0),
    (0.0, 36.0, 72.0, 100.0),
)

const CCS_HOURLY_CAP_CENTRE_2023 = 12.74

# FTB Part A 2022-23
const FTB_A_MAX_0_12_2023 = 5_380.10
const FTB_A_MAX_13_2023   = 6_934.80
const FTB_A_BASE_2023     = 1_751.84

const FTB_A_TEST1_0_12_2023 = PiecewiseLinear(
    (0.0, 58_108.0, 58_108.0 + (FTB_A_MAX_0_12_2023 - FTB_A_BASE_2023) / 0.20),
    (0.0, -0.20,    0.0),
    FTB_A_MAX_0_12_2023
)

const FTB_A_TEST1_13_2023 = PiecewiseLinear(
    (0.0, 58_108.0, 58_108.0 + (FTB_A_MAX_13_2023 - FTB_A_BASE_2023) / 0.20),
    (0.0, -0.20,    0.0),
    FTB_A_MAX_13_2023
)

const FTB_A_TEST2_2023 = PiecewiseLinear(
    (0.0, 104_184.0, 104_184.0 + FTB_A_BASE_2023 / 0.30),
    (0.0, -0.30,     0.0),
    FTB_A_BASE_2023
)

# FTB Part B 2022-23
const FTB_B_MAX_0_4_2023  = 4_663.70
const FTB_B_MAX_5_18_2023 = 3_254.30

const FTB_B_TAPER_0_4_2023 = PiecewiseLinear(
    (0.0, 5_767.0, 5_767.0 + FTB_B_MAX_0_4_2023 / 0.20),
    (0.0, -0.20,   0.0),
    FTB_B_MAX_0_4_2023
)

const FTB_B_TAPER_5_18_2023 = PiecewiseLinear(
    (0.0, 5_767.0, 5_767.0 + FTB_B_MAX_5_18_2023 / 0.20),
    (0.0, -0.20,   0.0),
    FTB_B_MAX_5_18_2023
)

# JobSeeker 2022-23 (rates as at 20 March 2023)
const JSP_MAX_SINGLE_2023       = 693.10  # single no children, incl ES
const JSP_MAX_SINGLE_KIDS_2023  = 745.20  # single with children, incl ES
const JSP_MAX_PARTNERED_2023    = 631.20  # each, incl ES

const JSP_TAPER_SINGLE_2023 = PiecewiseLinear(
    (0.0, 150.0, 256.0),
    (0.0, -0.50, -0.60),
    JSP_MAX_SINGLE_2023
)

const JSP_TAPER_SINGLE_CARER_2023 = PiecewiseLinear(
    (0.0, 150.0),
    (0.0, -0.40),
    JSP_MAX_SINGLE_KIDS_2023
)

const JSP_TAPER_PARTNERED_2023 = PiecewiseLinear(
    (0.0, 150.0, 256.0),
    (0.0, -0.50, -0.60),
    JSP_MAX_PARTNERED_2023
)

# Parenting Payment 2022-23 (rates as at 20 March 2023)
# Note: PPS youngest child cutoff was 8 in 2022-23
# (expanded to 14 from 20 September 2023)
const PPS_MAX_2023 = 922.10  # incl pension supplement
const PPP_MAX_2023 = 631.20  # partnered, incl ES

const PPS_TAPER_2023 = PiecewiseLinear(
    (0.0, 211.60),
    (0.0, -0.40),
    PPS_MAX_2023
)

const PPP_TAPER_2023 = PiecewiseLinear(
    (0.0, 150.0, 256.0),
    (0.0, -0.50, -0.60),
    PPP_MAX_2023
)

end # module AUS
