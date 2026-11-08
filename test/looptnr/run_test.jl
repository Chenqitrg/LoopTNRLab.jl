@testset "RG 0 copies and normalizes each cell representation" begin
    gate = set_gate_norm!(normalization_gate(), 4.0)
    for cell in (UniformGates(gate), CheckerboardGates(gate, gate),
                 PlaquetteGates(fill(gate, 2, 2); copy=false))
        before = copy.(collect(cell))
        state = LoopTNRLab.initialize_tnr(cell, small_algorithm(steps=0))
        result, events = finish_tnr(state)
        @test events == [(:rg, 0, 0)]
        @test result.completed_rg == 0
        @test result.cell === state.cell
        @test all(norm(t, Inf) ≈ 1 for t in state.cell)
        @test all(collect(cell) .== before)
        @test !hasproperty(state, :log) && !hasproperty(state, :measurement_results)
        @test !occursin("TensorMap", sprint(show, state))
    end
end

@testset "RG composition agrees with explicit split and contraction" begin
    cell = CheckerboardGates(normalization_gate(), normalization_gate())
    before = copy.(collect(cell))
    split = ALSSplit(initialization=SVDInitialization(trunc=truncrank(2)),
        sweep=CircularSweep(max_sweeps=0), solver=CholeskySolve())
    algorithm = LoopTNR(; split, max_rg_steps=2, filtering=nothing)
    expected = PlaquetteGates(cell)
    normalize!(expected, algorithm.normalization)
    for _ in 1:2
        optimized = MPSSplitLab.split(PeriodicMPS(expected), split)
        expected = PlaquetteGates(LoopTNRLab._coarse_grain(optimized.mps))
        normalize!(expected, algorithm.normalization)
    end
    state = LoopTNRLab.initialize_tnr(cell, algorithm)
    actual, events = finish_tnr(state)
    @test events == [(:rg, rg, 0) for rg in 0:2]
    @test all(a ≈ b for (a, b) in zip(actual.cell, expected))
    @test all(collect(cell) .== before)
end

@testset "Direct child generator yields every site; Session controls pauses" begin
    for regularization in (MPSSplitLab.NoRegularization(), NuclearNorm())
        state = LoopTNRLab.initialize_tnr(scalar_cell(), small_algorithm(; regularization))
        events = Tuple{Symbol,Int,Int}[]
        session = start_run(LoopTNRLab.tnr_steps(state); threaded=false,
            onstep=(session, event) -> begin
                push!(events, signature(event, state))
                event isa MPSSplitLab.SplitProgress && state.completed_rg == 0 &&
                    event.site == 4 && pause!(session)
            end)
        @test timedwait(() -> run_status(session) == ExperimentLab.PAUSED, 20) == :ok
        @test state.active_split.progress.completed_updates == 4
        @test state.completed_rg == 0
        resume!(session)
        result = fetch(session)
        @test result.completed_rg == 2
        @test events == vcat([(:rg, 0, 0)],
            [(:site, 1, site) for site in 1:8], [(:rg, 1, 0)],
            [(:site, 2, site) for site in 1:8], [(:rg, 2, 0)])
        @test isnothing(state.active_split)
    end
end

@testset "Cancellation and failures belong to Session" begin
    state = LoopTNRLab.initialize_tnr(scalar_cell(), small_algorithm())
    session = start_run(LoopTNRLab.tnr_steps(state); threaded=false,
        onstep=(session, event) -> event isa MPSSplitLab.SplitProgress && cancel!(session))
    wait(session)
    @test run_status(session) == ExperimentLab.CANCELLED
    @test state.active_split.progress.completed_updates == 1
    @test_throws ArgumentError fetch(session)

    cell = scalar_cell()
    fill!(cell.gate.data, 0)
    state = LoopTNRLab.initialize_tnr(cell, small_algorithm())
    before = copy.(collect(state.cell))
    failed = start_run(LoopTNRLab.tnr_steps(state); threaded=false)
    @test_throws CapturedException fetch(failed)
    @test run_status(failed) == ExperimentLab.FAILED
    @test state.completed_rg == -1
    @test all(collect(state.cell) .== before)

    state = LoopTNRLab.initialize_tnr(scalar_cell(), small_algorithm())
    failed = start_run(LoopTNRLab.tnr_steps(state); threaded=false,
        onstep=(_, _) -> error("callback failure"))
    @test_throws CapturedException fetch(failed)
    @test state.completed_rg == 0 # Numerical commit precedes the external callback.
end
