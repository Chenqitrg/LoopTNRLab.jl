using Test, LoopTNRLab, PMPSLab
using TensorKit

@testset "cross-package method ambiguities" begin
    @test isempty(detect_ambiguities(LoopTNRLab, PMPSLab; recursive=true))
end
include("package_boundary_test.jl")
include("setconfig_test.jl")
include("config_display_test.jl")
include("measurement_test.jl")
include("tensorcell_test.jl")
include("looptnr/runtests.jl")
include("checkpoint_test.jl")
