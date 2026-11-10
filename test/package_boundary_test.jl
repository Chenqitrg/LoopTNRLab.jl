@testset "Domain state stays in LoopTNR; infrastructure stays upstream" begin
    @test parentmodule(LoopTNR) === LoopTNRLab
    @test parentmodule(PlaquetteGates) === TensorLatticeLab
    for name in (:AbstractTensorCell, :UniformGates, :CheckerboardGates, :PlaquetteGates,
                 :mul_west, :mul_south, :mul_north, :mul_east, :cdl_tensor, :random_cdl_tensor)
        @test !Base.isexported(LoopTNRLab, name)
        @test Base.isexported(TensorLatticeLab, name)
    end
    @test parentmodule(TensorLatticeLab.assertconsistency) === TensorLatticeLab
    @test parentmodule(TensorLatticeLab.standardize) === TensorLatticeLab
    @test parentmodule(ExperimentLab.Session) === ExperimentLab
    @test LoopTNRLab.LoopTNRState <: ExperimentLab.AbstractAlgorithmState
    @test parentmodule(ExperimentLab.algorithm_steps) === ExperimentLab
    @test !isdefined(LoopTNRLab, :tnr_steps)
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
