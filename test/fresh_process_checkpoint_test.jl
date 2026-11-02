@testset "fresh-process split and LoopTNR checkpoints" begin
    mktempdir() do directory
        target = rand(PeriodicMPS, ComplexF64, 2, (2, 2), 1)
        split_algorithm = ALSSplit(;
            ansatz=SVDAnsatz(),
            sweep=CircularSweep(; site_count=4, max_sweeps=1),
            solver=CholeskySolve(),
        )
        split_run = initialize_run(target, split_algorithm)
        step!(split_run)
        write_checkpoint(joinpath(directory, "split.jld2"), snapshot(split_run))

        loop_run, loop_algorithm = checkpoint_loop_fixture()
        step!(loop_run)
        for _ in 1:3
            step!(loop_run)
        end
        write_checkpoint(joinpath(directory, "loop.jld2"), snapshot(loop_run))
        while !isfinished(split_run)
            step!(split_run)
        end
        while !isfinished(loop_run)
            step!(loop_run)
        end
        jldsave(joinpath(directory, "inputs.jld2");
            target, split_algorithm, loop_algorithm,
            expected_split=dense(run_result(split_run).mps),
            expected_cell=collect(run_result(loop_run).cell),
        )

        reader = joinpath(@__DIR__, "fresh_process_reader.jl")
        project = dirname(Base.active_project())
        command = `$(Base.julia_cmd()) --startup-file=no --project=$project $reader $directory`
        @test success(command)
    end
end
