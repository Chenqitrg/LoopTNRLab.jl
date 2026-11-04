function rg0_split()
    return ALSSplit(;
        initialization=SVDInitialization(),
        sweep=CircularSweep(; max_sweeps=0),
        solver=CholeskySolve(),
    )
end

@testset "LoopTNR configuration" begin
    custom_split = rg0_split()
    measurement = TNRMeasurement()
    algorithm = LoopTNR(;
        split=custom_split, max_rg_steps=0, measurement
    )

    @test algorithm.split === custom_split
    @test algorithm.max_rg_steps == 0
    @test algorithm.measurement === measurement
    @test algorithm == deepcopy(algorithm)
    @test hash(algorithm) == hash(deepcopy(algorithm))
    @test algorithm.split.initialization isa SVDInitialization

    @test_throws ArgumentError LoopTNR(; split=custom_split, max_rg_steps=-1)
end

@testset "LoopTNR default split configuration" begin
    dcut = 7
    algorithm = default_looptnr(; dcut, max_rg_steps=3)
    numerical_truncation = TensorKit.truncerror(; rtol=1.0e-13)
    expected_svd = TensorKit.truncrank(2dcut) & numerical_truncation
    expected_projector =
        TensorKit.truncrank(dcut) & numerical_truncation

    @test algorithm.max_rg_steps == 3
    @test algorithm.split.initialization isa GaugeInitialization
    @test algorithm.split.initialization.initialization.trunc == expected_svd
    @test algorithm.split.initialization.gauge_fix.tol == 1.0e-13
    @test algorithm.split.initialization.gauge_fix.maxiter == 100
    @test algorithm.split.initialization.gauge_fix.trunc == expected_projector
    @test algorithm.split.sweep == CircularSweep(; max_sweeps=40)
    @test algorithm.split.solver == LDLTSolve()
    @test algorithm.split.environments.normal isa DenseTransferPolicy
    @test algorithm.split.environments.mixed isa DenseTransferPolicy
    @test algorithm.split.stopping == CostTolerance(;
        atol=1.0e-9,
        rtol=1.0e-2,
        min_sweeps=5,
    )
    @test algorithm.measurement.normalization isa InfinityNormNormalization
    @test algorithm.measurement.fixed_point isa NoFixedPointMeasurement
    @test_throws ArgumentError default_looptnr(; dcut=0, max_rg_steps=1)
    @test_throws ArgumentError default_looptnr(; dcut=2, max_rg_steps=-1)
end
