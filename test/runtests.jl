using Test
using .Fisco

@testset "Fisco.jl" begin

@testset "PiecewiseLinear — construction and levels derivation" begin
    # 2-segment: zero then slope 2
    pl = PiecewiseLinear((0.0, 10.0), (0.0, 2.0), 0.0)
    @test pl.levels == (0.0, 0.0)
    @test pl(5.0) == 0.0
    @test pl(10.0) == 0.0
    @test pl(15.0) == 10.0

    # 3-segment: constant 5, slope 1, slope -1
    pl2 = PiecewiseLinear((0.0, 10.0, 20.0), (0.0, 1.0, -1.0), 5.0)
    @test pl2.levels == (5.0, 5.0, 15.0)
    @test pl2(0.0) == 5.0
    @test pl2(15.0) == 10.0
    @test pl2(25.0) == 10.0  # 15 + (-1)*5

    # Non-sorted breakpoints → error
    @test_throws ArgumentError PiecewiseLinear((10.0, 5.0), (1.0, 2.0), 0.0)
end

@testset "PiecewiseLinear — evaluate" begin
    # Progressive tax-like schedule
    pl = PiecewiseLinear(
        (0.0, 100.0, 200.0, 500.0),
        (0.0, 0.10,  0.20,  0.30),
        0.0
    )

    @test pl(0.0) == 0.0
    @test pl(50.0) == 0.0
    @test pl(100.0) == 0.0
    @test pl(150.0) ≈ 5.0       # 0 + 0.10 × 50
    @test pl(200.0) ≈ 10.0      # 0 + 0.10 × 100
    @test pl(300.0) ≈ 30.0      # 10 + 0.20 × 100
    @test pl(500.0) ≈ 70.0      # 10 + 0.20 × 300
    @test pl(600.0) ≈ 100.0     # 70 + 0.30 × 100

    # Offset-like schedule (negative rates, positive initial)
    offset = PiecewiseLinear(
        (0.0, 50.0, 100.0),
        (0.0, -0.10, 0.0),
        10.0
    )

    @test offset(0.0) ≈ 10.0
    @test offset(50.0) ≈ 10.0
    @test offset(75.0) ≈ 7.5    # 10 - 0.10 × 25
    @test offset(100.0) ≈ 5.0   # 10 - 0.10 × 50
    @test offset(200.0) ≈ 5.0   # flat after last breakpoint
end

@testset "PiecewiseLinear — single segment" begin
    pl = PiecewiseLinear((0.0,), (0.5,), 0.0)
    @test pl(0.0) == 0.0
    @test pl(10.0) ≈ 5.0
end

@testset "PiecewiseLinear — type promotion" begin
    pl = PiecewiseLinear((0, 10, 20), (0.0, 1.0, 2.0), 0.0)
    @test eltype(pl.breakpoints) == Float64
    @test pl(15.0) ≈ 5.0
end

@testset "PiecewiseLinear — type stability" begin
    pl = PiecewiseLinear((0.0, 10.0), (0.0, 2.0), 0.0)
    @inferred pl(15.0)
    @inferred evaluate(pl, 15.0)
end

@testset "PiecewiseLinear — continuity" begin
    # Verify the function is continuous at every breakpoint
    pl = PiecewiseLinear(
        (0.0, 10.0, 30.0, 50.0),
        (1.0, -0.5, 2.0, 0.0),
        0.0
    )
    for i in 2:4
        bp = pl.breakpoints[i]
        left = pl.levels[i-1] + pl.rates[i-1] * (bp - pl.breakpoints[i-1])
        right = pl.levels[i]
        @test left ≈ right
    end
end

@testset "PiecewiseLinear — levels constructor" begin
    # Same tax-like schedule, specified by (breakpoints, levels)
    pl = PiecewiseLinear(
        (0.0, 100.0, 200.0, 500.0);
        levels=(0.0, 0.0, 10.0, 70.0)
    )

    # Rates should be derived correctly
    @test pl.rates[1] ≈ 0.0
    @test pl.rates[2] ≈ 0.10
    @test pl.rates[3] ≈ 0.20
    @test pl.rates[4] ≈ 0.0   # last segment: flat

    # Should evaluate identically to rates-based version
    pl2 = PiecewiseLinear(
        (0.0, 100.0, 200.0, 500.0),
        (0.0, 0.10,  0.20,  0.30),
        0.0
    )
    for x in [0.0, 50.0, 150.0, 300.0, 500.0]
        @test pl(x) ≈ pl2(x)
    end
    # Except beyond last breakpoint: levels constructor has flat,
    # rates constructor has slope 0.30
    @test pl(600.0) ≈ 70.0    # flat
    @test pl2(600.0) ≈ 100.0  # slope 0.30

    # CCS-style: plateaus and tapers
    ccs = PiecewiseLinear(
        (0.0, 72_466.0, 177_466.0, 256_756.0, 346_756.0, 356_756.0, 356_757.0);
        levels=(0.85, 0.85, 0.50, 0.50, 0.20, 0.20, 0.0)
    )
    @test ccs(50_000.0) ≈ 0.85
    @test ccs(177_466.0) ≈ 0.50
    @test ccs(300_000.0) ≈ 0.50 + (0.20 - 0.50) / (346_756.0 - 256_756.0) * (300_000.0 - 256_756.0)
    @test ccs(350_000.0) ≈ 0.20
    @test ccs(400_000.0) ≈ 0.0

    # Type promotion
    pl3 = PiecewiseLinear((0, 10, 20); levels=(0.0, 5.0, 15.0))
    @test eltype(pl3.breakpoints) == Float64
    @test pl3(15.0) ≈ 10.0

    # last_rate: tax brackets with 45% beyond last breakpoint
    tax = PiecewiseLinear(
        (0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0);
        levels=(0.0, 0.0, 4_288.0, 31_288.0, 51_638.0),
        last_rate=0.45
    )
    tax_rates = PiecewiseLinear(
        (0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0),
        (0.0, 0.16, 0.30, 0.37, 0.45),
        0.0
    )
    # Both constructors produce identical results everywhere
    for x in [0.0, 18_200.0, 50_000.0, 135_000.0, 190_000.0, 250_000.0]
        @test tax(x) ≈ tax_rates(x)
    end
    @test tax.rates[5] == 0.45

    # last_rate with levels constructor matches rates constructor fully
    pl_lr = PiecewiseLinear(
        (0.0, 100.0, 200.0, 500.0);
        levels=(0.0, 0.0, 10.0, 70.0),
        last_rate=0.30
    )
    @test pl_lr(600.0) ≈ 100.0  # now matches pl2
end

@testset "PiecewiseLinear — marginal_rate" begin
    pl = PiecewiseLinear(
        (0.0, 18_200.0, 45_000.0, 135_000.0, 190_000.0),
        (0.0, 0.16, 0.30, 0.37, 0.45),
        0.0
    )

    @test marginal_rate(pl, 10_000.0) == 0.0
    @test marginal_rate(pl, 18_200.0) == 0.16
    @test marginal_rate(pl, 50_000.0) == 0.30
    @test marginal_rate(pl, 135_000.0) == 0.37
    @test marginal_rate(pl, 200_000.0) == 0.45

    # Works on offsets too
    lito = PiecewiseLinear(
        (0.0, 37_500.0, 45_000.0, 66_666.67),
        (0.0, -0.05, -0.015, 0.0),
        700.0
    )
    @test marginal_rate(lito, 30_000.0) == 0.0
    @test marginal_rate(lito, 40_000.0) == -0.05
    @test marginal_rate(lito, 50_000.0) == -0.015
    @test marginal_rate(lito, 80_000.0) == 0.0
end

# ============================================================
# StepFunction — core type
# ============================================================

@testset "StepFunction — construction and evaluation" begin
    # Activity test style: hours → max subsidised hours
    sf = StepFunction((0.0, 8.0, 17.0, 48.0), (0.0, 36.0, 72.0, 100.0))

    @test sf(0.0) == 0.0
    @test sf(5.0) == 0.0
    @test sf(8.0) == 36.0
    @test sf(10.0) == 36.0
    @test sf(17.0) == 72.0
    @test sf(30.0) == 72.0
    @test sf(48.0) == 100.0
    @test sf(100.0) == 100.0
end

@testset "StepFunction — single step" begin
    sf = StepFunction((0.0,), (42.0,))
    @test sf(0.0) == 42.0
    @test sf(999.0) == 42.0
end

@testset "StepFunction — type promotion" begin
    sf = StepFunction((0, 10, 20), (1.0, 2.0, 3.0))
    @test eltype(sf.thresholds) == Float64
    @test sf(15.0) == 2.0
end

@testset "StepFunction — type stability" begin
    sf = StepFunction((0.0, 10.0), (1.0, 2.0))
    @inferred sf(5.0)
    @inferred evaluate(sf, 5.0)
end

@testset "StepFunction — non-sorted thresholds error" begin
    @test_throws ArgumentError StepFunction((10.0, 5.0), (1.0, 2.0))
end

end # top-level testset
