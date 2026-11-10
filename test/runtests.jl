using Test, LoopTNRLab, PMPSLab, ExperimentLab
using TensorLatticeLab
using Random
using LatticeIteratorLab, TensorLinearSolveLab
using TensorKit, LinearAlgebra, Logging
using Accessors: @set

include("fixtures.jl")
@testset "cross-package method ambiguities" begin
    @test isempty(detect_ambiguities(LoopTNRLab, TensorLatticeLab, PMPSLab, ExperimentLab; recursive=true))
end
include("package_boundary_test.jl")
include("accessors_test.jl")
include("config_display_test.jl")
include("configuration_test.jl")
include("tensorcell_test.jl")
include("cdl_test.jl")
with_logger(NullLogger()) do
    include("looptnr/runtests.jl")
    include("split_interface_test.jl")
    include("filtering_test.jl")
end
include("storage_test.jl")
