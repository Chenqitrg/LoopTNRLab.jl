using JLD2
import ExecutionLab

function checkpoint_loop_fixture()
    gate = ones(ComplexF64, ℂ^1 ⊗ ℂ^1, ℂ^1 ⊗ ℂ^1)
    split_algorithm = ALSSplit(;
        initialization=SVDInitialization(),
        sweep=CircularSweep(; max_sweeps=1),
        solver=CholeskySolve(),
    )
    algorithm = LoopTNR(; split=split_algorithm, max_rg_steps=1)
    return initialize_run(UniformGates(gate), algorithm), algorithm
end

@testset "LoopTNRSnapshot checkpoint — active split round trip" begin
    run, algorithm = checkpoint_loop_fixture()
    step!(run)
    for _ in 1:3
        step!(run)
    end
    saved = snapshot(run)

    mktempdir() do directory
        path = joinpath(directory, "looptnr.jld2")
        @test isnothing(write_checkpoint(path, saved))
        @test jldopen(path, "r") do file
            file["header/algorithm"] == "looptnr"
        end
        loaded = read_checkpoint(path)

        @test loaded isa LoopTNRSnapshot
        @test loaded.phase == LoopTNRLab.TNR_OPTIMIZE
        @test loaded.completed_rg == 0
        @test length(loaded.measurement_results) == 1
        @test loaded.measurement_results[1].rg == 0
        @test loaded.active_split isa ExecutionLab.AbstractAlgorithmSnapshot
        @test length(loaded.active_split.log.site_logs) == 3

        restored = restore_run(loaded, algorithm)
        next_event = step!(restored)
        @test next_event isa LoopTNRSplitStepCompleted
        @test next_event.event.log.state == SweepState{Forward}(4, 0)

        while !isfinished(run)
            step!(run)
        end
        while !isfinished(restored)
            step!(restored)
        end
        expected = run_result(run)
        actual = run_result(restored)
        @test getfield.(actual.measurement_results, :rg) == [0, 1]
        @test getfield.(actual.measurement_results, :rg) ==
              getfield.(expected.measurement_results, :rg)
        @test all(
            actual_tensor ≈ expected_tensor
            for (actual_tensor, expected_tensor) in
                zip(collect(actual.cell), collect(expected.cell))
        )
    end
end

@testset "LoopTNR local pause-and-checkpoint — split continuation" begin
    run, algorithm = checkpoint_loop_fixture()
    reached_site_four = Channel{Nothing}(1)
    observer = event -> begin
        if event isa LoopTNRSplitStepCompleted &&
                event.event.log.state.site == 4
            put!(reached_site_four, nothing)
        end
        return nothing
    end
    session = LocalRunSession(run; observer, threaded=false)

    mktempdir() do directory
        path = joinpath(directory, "paused-looptnr.jld2")
        start_run!(session)
        take!(reached_site_four)
        @test pause_and_checkpoint!(session, path) ==
              ExecutionLab.LOCAL_CHECKPOINT_WRITTEN
        @test run_status(session) == ExecutionLab.LOCAL_PAUSED

        loaded = read_checkpoint(path)
        @test loaded isa LoopTNRSnapshot
        @test loaded.completed_rg == 0
        @test length(loaded.measurement_results) == 1
        @test length(loaded.active_split.log.site_logs) == 4

        restored = restore_run(loaded, algorithm)
        next_event = step!(restored)
        @test next_event.event.log.state == SweepState{Forward}(5, 0)
        while !isfinished(restored)
            step!(restored)
        end
        @test getfield.(run_result(restored).measurement_results, :rg) == [0, 1]
    end
end


@testset "LoopTNR checkpoint compatibility across packages" begin
    run, _ = checkpoint_loop_fixture()
    saved = snapshot(run)
    mktempdir() do directory
        path = joinpath(directory, "metadata.jld2")
        write_checkpoint(path, saved)
        jldopen(path, "r") do file
            @test file["header/package_version"] == string(Base.pkgversion(ExecutionLab))
            @test file["header/metadata"] == Dict("LoopTNRLab" => string(Base.pkgversion(LoopTNRLab)), "PMPSLab" => string(Base.pkgversion(PMPSLab)), "MPSSplitLab" => string(Base.pkgversion(MPSSplitLab)))
        end
        for (key, value) in (
            ("header/metadata", Dict("LoopTNRLab" => "999.0.0")),
            ("header/metadata", merge(ExecutionLab.checkpoint_metadata(saved), Dict("PMPSLab" => "999.0.0"))),
            ("header/metadata", merge(ExecutionLab.checkpoint_metadata(saved), Dict("MPSSplitLab" => "999.0.0"))),
            ("header/metadata", Dict("LoopTNRLab" => "999.0.0", "PMPSLab" => string(Base.pkgversion(PMPSLab)), "MPSSplitLab" => string(Base.pkgversion(MPSSplitLab)))),
            ("header/metadata", Dict{String,String}()),
            ("header/algorithm", "split"),
            ("header/package_version", "999.0.0"),
            ("header/schema_version", UInt8(2)),
        )
            write_checkpoint(path, saved)
            jldopen(path, "a+") do file
                delete!(file, key)
                file[key] = value
            end
            @test_throws ArgumentError read_checkpoint(path)
        end
    end
end
