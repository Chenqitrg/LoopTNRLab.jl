# Executed in a new Julia process by fresh_process_checkpoint_test.jl.
using Test, ExecutionLab, PMPSLab, MPSSplitLab, LoopTNRLab, TensorKit, JLD2
using ExecutionLab: step!, isfinished, run_result
using PeriodicProductsLab

directory = only(ARGS)
inputs = load(joinpath(directory, "inputs.jld2"))
@testset "fresh-process restoration" begin
    @test MPSSplitLab.step! === LoopTNRLab.step! === ExecutionLab.step!
    saved_split = read_checkpoint(joinpath(directory, "split.jld2"))
    @test saved_split isa SplitSnapshot
    split_run = restore_run(saved_split, inputs["target"], inputs["split_algorithm"])
    @test step!(split_run).log.state == SweepState{Forward}(2, 0)
    while !isfinished(split_run)
        step!(split_run)
    end
    @test dense(run_result(split_run).mps) ≈ inputs["expected_split"]

    saved_loop = read_checkpoint(joinpath(directory, "loop.jld2"))
    @test saved_loop isa LoopTNRSnapshot
    @test saved_loop.active_split isa SplitSnapshot
    loop_run = restore_run(saved_loop, inputs["loop_algorithm"])
    @test step!(loop_run).event.log.state == SweepState{Forward}(4, 0)
    while !isfinished(loop_run)
        step!(loop_run)
    end
    @test all(isapprox.(collect(run_result(loop_run).cell), inputs["expected_cell"]))
end
