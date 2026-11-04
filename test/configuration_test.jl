using AlgorithmConfigLab: @config, configtree, configspec, construct_config, config_registry
using TensorKit: MatrixAlgebraKit

@testset "default LoopTNR configuration interchange" begin
    original = default_looptnr(; max_rg_steps=2, dcut=8)
    registry = config_registry(LoopTNR)
    for mode in (:full, :compact)
        @test isequal(include_string(@__MODULE__, "@config " * repr(configtree(original; mode))), original)
        @test isequal(construct_config(configspec(original; registry, mode); registry), original)
    end
    @test !occursin("site_count", configtree(original; mode=:compact))
end
