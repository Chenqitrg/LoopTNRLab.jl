using Test, LoopTNRLab, PMPSLab, MPSSplitLab, ExecutionLab, AlgorithmConfigLab
using GaugeFixingLab, TransferEnvironmentsLab, PeriodicProductsLab
using TensorKit

@testset "cross-package method ambiguities" begin
    @test isempty(detect_ambiguities(LoopTNRLab, PMPSLab, MPSSplitLab, ExecutionLab; recursive=true))
end
include("package_boundary_test.jl")
include("setconfig_test.jl")
include("config_display_test.jl")
include("measurement_test.jl")
include("tensorcell_test.jl")
include("looptnr/runtests.jl")
include("checkpoint_test.jl")
include("fresh_process_checkpoint_test.jl")

include("configuration_test.jl")
