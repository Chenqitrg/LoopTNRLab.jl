@testset "Domain state stays in LoopTNR; infrastructure stays upstream" begin
    @test parentmodule(LoopTNR) === LoopTNRLab
    @test parentmodule(PlaquetteGates) === LoopTNRLab
    @test parentmodule(ExperimentLab.Session) === ExperimentLab
    for name in (:LoopTNRPhase, :LoopTNRRun, :LoopTNRResult, :LoopTNRLog,
                 :RGLog, :TNRMeasurement, :NoFixedPointMeasurement, :step!, :isfinished)
        @test !isdefined(LoopTNRLab, name)
    end
    @test !Base.isexported(LoopTNRLab, :AbstractMeasurement)
    @test !isdefined(PMPSLab, :SplitRun)
    @test !isdefined(PMPSLab, :LoopTNR)
    loaded = Set(pkg.name for pkg in keys(Base.loaded_modules))
    @test !("MPSSplitLab" in loaded)
    @test !("TransferMatricesLab" in loaded)
    @test !("GaugeFixingLab" in loaded)
    @test !("TransferEnvironmentsLab" in loaded)
    @test !("ExecutionLab" in loaded)
    @test !("AlgorithmDataLab" in loaded)
end
