using Accessors: @set, @reset

@testset "Accessors — functional algorithm updates" begin
    algorithm = default_looptnr(; max_rg_steps=3, dcut=8)

    modified = algorithm
    @reset modified.max_rg_steps = 5
    @reset modified.split.sweep.max_sweeps = 60
    @reset modified.split.stopping.atol = 1e-10
    @test modified.max_rg_steps == 5
    @test modified.split.sweep.max_sweeps == 60
    @test modified.split.stopping.atol == 1e-10
    @test modified.split.stopping.rtol == algorithm.split.stopping.rtol
    @test modified.measurement === algorithm.measurement

    replacement_trunc = algorithm.split.initialization.gauge_fix.trunc
    retruncated = (@set algorithm.split.initialization.initialization.trunc = replacement_trunc)
    @test retruncated.split.initialization.initialization.trunc == replacement_trunc

    @test algorithm.max_rg_steps == 3
    @test algorithm.split.sweep.max_sweeps == 40
    @test algorithm.split.stopping.atol == 1e-9
end

@testset "Accessors — concrete strategy replacement" begin
    algorithm = default_looptnr(; max_rg_steps=3, dcut=8)
    modified = @set algorithm.split.stopping = NoStopping()

    @test modified.split.stopping isa NoStopping
    @test typeof(modified.split) !== typeof(algorithm.split)
    @test modified.split.initialization === algorithm.split.initialization
end

@testset "Accessors — paths and constructors are validated" begin
    algorithm = default_looptnr(; max_rg_steps=3, dcut=8)

    @test_throws ArgumentError @set algorithm.unknown = 1
    @test_throws ArgumentError @set algorithm.split.unknown = 1
    @test_throws ArgumentError @set algorithm.max_rg_steps = -1
    @test_throws ArgumentError @set algorithm.split.stopping.min_sweeps = 1

end
