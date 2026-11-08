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

import ExperimentLab

@testset "LoopTNRLab configuration identities" begin
    registry = ExperimentLab.config_registry(LoopTNR)
    owned = Set{Type}()
    for name in names(LoopTNRLab; all=true)
        isdefined(LoopTNRLab, name) || continue
        type = getfield(LoopTNRLab, name)
        type isa Type && type <: ExperimentLab.AbstractAlgorithmConfig || continue
        isabstracttype(type) && continue
        parentmodule(type) === LoopTNRLab && push!(owned, type)
    end
    @test owned == Set(type for type in keys(registry.names) if parentmodule(type) === LoopTNRLab)
    configs = (InfinityNormNormalization(), default_looptnr(max_rg_steps=2, dcut=3))
    for config in configs, defaults in (true, false)
        registry = ExperimentLab.config_registry(typeof(config))
        record = ExperimentLab.config_record(registry, config; include_defaults=defaults)
        @test record["type"] == "LoopTNRLab." * string(nameof(typeof(config)))
        @test haskey(record, "parameters")
        io = IOBuffer()
        ExperimentLab.writeconfig(io, config; include_defaults=defaults)
        text = String(take!(io))
        @test isequal(ExperimentLab.readconfig(IOBuffer(text), typeof(config)), config)
    end
end
