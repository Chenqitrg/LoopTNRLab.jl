@testset "LoopTNRLab owns lattice renormalization" begin
    @test parentmodule(LoopTNR) === LoopTNRLab
    @test parentmodule(PlaquetteGates) === LoopTNRLab
    @test parentmodule(MeasurementHistory) === LoopTNRLab
    @test parentmodule(SplitRun) === PMPSLab
    @test !isdefined(PMPSLab, :LoopTNR)
    @test !isdefined(PMPSLab, :MeasurementHistory)
end

@testset "shared execution interfaces" begin
    @test parentmodule(AbstractAlgorithmRun) === ExecutionLab
    @test LoopTNRLab.initialize_run === ExecutionLab.initialize_run
    @test LoopTNRLab.snapshot === ExecutionLab.snapshot
    @test PMPSLab.LocalRunSession === ExecutionLab.LocalRunSession
end
