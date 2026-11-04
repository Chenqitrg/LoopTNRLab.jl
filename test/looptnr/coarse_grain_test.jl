@testset "LoopTNR coarse graining — designed split input" begin
    black = normalization_gate()
    white = normalization_gate()
    source = CheckerboardGates(black, white)
    optimized = initial_approximation(PeriodicMPS(source), SVDInitialization())
    tensors_before = copy.(collect(optimized))

    coarse = LoopTNRLab._coarse_grain(optimized)

    @test coarse isa CheckerboardGates
    @test TensorKit.scalartype(coarse.black) == ComplexF64
    @test TensorKit.scalartype(coarse.white) == ComplexF64
    @test isnothing(assertconsistency(coarse))
    @test all(collect(optimized) .== tensors_before)
end

@testset "LoopTNR coarse graining — input contract" begin
    short = one_mps(ComplexF64, 4, 2, 2)
    wrong_rank = one_mps(ComplexF64, 8, (2, 2), 2)

    @test_throws DimensionMismatch LoopTNRLab._coarse_grain(short)
    @test_throws MethodError LoopTNRLab._coarse_grain(wrong_rank)
end
