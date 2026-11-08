using PMPSLab: NuclearNorm
@testset "Snapshots resume every boundary without replaying events" begin
    for regularization in (PMPSLab.NoRegularization(), NuclearNorm())
        state = LoopTNRLab.initialize_tnr(scalar_cell(), small_algorithm(; regularization))
        snapshots = LoopTNRLab.TNRSnapshot[ExperimentLab.copy_state(state)]
        events = Tuple{Symbol,Int,Int}[]
        expected = fetch(start_run(LoopTNRLab.tnr_steps(state); threaded=false,
            onstep=(_, event) -> begin
                push!(events, signature(event, state))
                push!(snapshots, ExperimentLab.copy_state(state))
            end))
        for (index, saved) in enumerate(snapshots)
            restored = LoopTNRLab.restore_tnr(saved)
            @test all(a !== b for (a, b) in zip(saved.cell, restored.cell))
            actual, remaining = finish_tnr(restored)
            @test remaining == events[index:end]
            @test actual.completed_rg == expected.completed_rg
            @test all(a ≈ b for (a, b) in zip(actual.cell, expected.cell))
        end
        saved = snapshots[6] # RG 0 and four completed site updates.
        @test saved.active_split.progress.completed_updates == 4
        first = LoopTNRLab.restore_tnr(saved)
        second = LoopTNRLab.restore_tnr(saved)
        first.active_split.approximation[1] *= 2
        @test first.active_split.approximation[1] != second.active_split.approximation[1]
        @test saved.active_split.approximation[1] == second.active_split.approximation[1]
        @test !hasproperty(saved.active_split, :target)
        @test !hasproperty(saved, :log) && !hasproperty(saved, :measurement_results)
        @test !occursin("TensorMap", sprint(show, saved))
        @test_throws ArgumentError LoopTNRLab.restore_tnr(@set saved.completed_rg = -1)
        @test_throws ArgumentError LoopTNRLab.restore_tnr(@set saved.completed_rg = 3)
        bad = @set saved.algorithm.split.sweep.max_sweeps = 2
        @test_throws ArgumentError LoopTNRLab.restore_tnr(bad)
    end
end
