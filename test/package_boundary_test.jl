@testset "LoopTNRLab owns lattice renormalization" begin
    @test parentmodule(LoopTNR) === LoopTNRLab
    @test parentmodule(PlaquetteGates) === LoopTNRLab
    @test parentmodule(MeasurementHistory) === LoopTNRLab
    @test parentmodule(SplitRun) === PMPSLab
    @test !isdefined(PMPSLab, :LoopTNR)
    @test !isdefined(PMPSLab, :MeasurementHistory)
end
