using ExperimentLab: @config, configtree
using Configurations: to_dict, from_dict
using TensorKit: MatrixAlgebraKit

@testset "default LoopTNR configuration interchange" begin
    original = default_looptnr(; max_rg_steps=2, dcut=8)
    for mode in (:full, :compact)
        @test isequal(include_string(@__MODULE__, "@config " * repr(configtree(original; mode))), original)
        @test isequal(from_dict(typeof(original), to_dict(original; include_defaults=(mode === :full))), original)
    end
    @test !occursin("site_count", configtree(original; mode=:compact))
end
