using PMPSLab: SVDInitialization
using Configurations: @option
using ResumableFunctions: ResumableFunctions, @resumable, @yield
import ExperimentLab: algorithm_steps

# A real non-ALS factorization, with no ALS workspace/progress/snapshot fields.
@option struct DirectSVDSplit <: PMPSLab.AbstractSplit
    rank::Int = 2
end
ExperimentLab.config_registry(::Type{DirectSVDSplit}) =
    ExperimentLab.ConfigRegistry("test.DirectSVDSplit" => DirectSVDSplit)

mutable struct DirectSVDState{M} <: PMPSLab.AbstractSplitState
    policy::DirectSVDSplit
    factors::M
    emitted::Bool
end

struct SVDCompleted <: ExperimentLab.AbstractLogEvent
    rank::Int
end
const SVD_EVENTS = ExperimentLab.EventRegistry("test.svd.completed.v1" => SVDCompleted)
function log_svd(event::SVDCompleted)
    fields = ExperimentLab.event_record(SVD_EVENTS, event)
    @info "SVD factorization completed" fields...
end

function PMPSLab.initialize_split(target::PeriodicMPS, policy::DirectSVDSplit)
    factors = initial_approximation(target, SVDInitialization(trunc=truncrank(policy.rank)))
    return DirectSVDState(policy, factors, false)
end

@resumable function algorithm_steps(state::DirectSVDState)::SVDCompleted
    if !state.emitted
        state.emitted = true
        event = SVDCompleted(state.policy.rank)
        log_svd(event)
        @yield event
    end
    return (; mps=state.factors)
end

# ExperimentLab's default copy_state already deep-copies this cache-free state.
function PMPSLab.restore_split(saved::DirectSVDState, target::PeriodicMPS;
        algorithm::DirectSVDSplit=saved.policy)
    algorithm == saved.policy || throw(ArgumentError("split configuration mismatch"))
    length(saved.factors) == 2length(target) || throw(DimensionMismatch("split site count"))
    return deepcopy(saved)
end

@testset "LoopTNR delegates to a non-ALS split" begin
    @test DirectSVDState <: ExperimentLab.AbstractAlgorithmState
    cell = UniformGates(normalization_gate())
    algorithm = LoopTNR(split=DirectSVDSplit(), max_rg_steps=2, filtering=nothing)
    io = IOBuffer()
    writeconfig(io, algorithm)
    seekstart(io)
    @test isequal(readconfig(io, typeof(algorithm)), algorithm)
    target = PeriodicMPS(cell)
    @test keys(PMPSLab.split(target, algorithm.split)) == (:mps,)

    mktempdir() do path
        store = DataStore(path)
        config = ExperimentLab.record_algorithm!(store, algorithm)
        state = LoopTNRLab.initialize_tnr(cell, algorithm)
        saved = Ref{ExperimentLab.SnapshotRef}()
        session = start_run(store, config, ExperimentLab.algorithm_steps(state); threaded=false,
            onstep=(session, event) -> begin
                if event isa SVDCompleted && state.completed_rg == 0
                    ref = record_state!(store, session.execution; step=0)
                    saved[] = save_snapshot!(store, capture(ref, state))
                    pause!(session)
                end
            end)
        @test timedwait(() -> run_status(session) == ExperimentLab.PAUSED, 20) == :ok
        @test state.active_split isa DirectSVDState
        @test occursin("active_split=true", sprint(show, state))
        snapshot = load_snapshot(store, saved[])
        @test snapshot.active_split isa DirectSVDState
        resume!(session)
        expected = fetch(session)

        restored = LoopTNRLab.restore_tnr(snapshot)
        @test restored.active_split.factors[1] !== snapshot.active_split.factors[1]
        @test restored.active_split.factors[1] ≈ snapshot.active_split.factors[1]
        events = ExperimentLab.AbstractLogEvent[]
        actual = fetch(start_run(ExperimentLab.algorithm_steps(restored); threaded=false,
            onstep=(_, event) -> push!(events, event)))
        @test map(typeof, events) == [LoopTNRLab.RGProgress, SVDCompleted, LoopTNRLab.RGProgress]
        @test actual.completed_rg == expected.completed_rg == 2
        @test all(a ≈ b for (a, b) in zip(actual.cell, expected.cell))

        changed = @set snapshot.algorithm.split.rank = 1
        @test_throws ArgumentError LoopTNRLab.restore_tnr(changed)
        log_path = joinpath(path, ExperimentLab.info(store, session.execution)["log_path"])
        rows = ExperimentLab.JSON.parse.(readlines(log_path))
        @test [row["event"] for row in rows] == ["looptnr.rg.completed.v1",
            "test.svd.completed.v1", "looptnr.rg.completed.v1",
            "test.svd.completed.v1", "looptnr.rg.completed.v1"]
    end
end
