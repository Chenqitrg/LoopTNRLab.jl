"""One committed RG boundary. Duration covers coarse graining and normalization."""
struct RGProgress <: AbstractLogEvent
    rg::Int
    scale::Float64
    log_scale::Float64
    duration::Float64
end
"""
Lattice filtering completed; the following split has not updated a site yet.
Bond dimensions list east/south at (1,1), (2,1), (1,2), (2,2). Only inner
plaquette bonds are filtered. Duration excludes split initialization.
"""
struct FilteringProgress <: AbstractLogEvent
    rg::Int
    bonds_before::NTuple{8,Int}
    bonds_after::NTuple{8,Int}
    relative_error::Float64
    duration::Float64
end
const RG_EVENTS = EventRegistry(
    "looptnr.rg.completed.v1" => RGProgress,
    "looptnr.filtering.completed.v1" => FilteringProgress,
)
function _log_filtering(progress::FilteringProgress)
    record = event_record(RG_EVENTS, progress)
    @info "Entanglement filtering completed" record...
end

function _log_rg(progress::RGProgress)
    record = event_record(RG_EVENTS, progress)
    @info "RG completed" record...
end

# Delegate to the configured split implementation, including custom split algorithms.
_split_steps(split::PMPSLab.AbstractSplitState) = algorithm_steps(split)

"""
    algorithm_steps(state)

Normalize the input cell at RG 0. For each RG step, optionally filter the
plaquette, initialize its split, and forward the split algorithm's events.
A FilteringProgress event marks a filtered cell with its split ready to run.
Coarse-grain the resulting eight-site MPS into a new cell and yield RGProgress
after normalization. Return the same updated `state` on completion.
"""
@resumable function algorithm_steps(state::LoopTNRState)::AbstractLogEvent
    # RG 0. Normalize the input plaquette and report its scale before the first split.
    if state.completed_rg == -1
        @nosave rg_progress = _normalize_and_commit_rg!(state, copy(state.cell), 0, time())
        _log_rg(rg_progress)
        @yield rg_progress
    end

    while state.completed_rg < state.algorithm.max_rg_steps
        # Prepare the split. After optional filtering, the default SVD initialization
        # splits each of the four corner tensors into two, forming an eight-site ring.
        # A snapshot taken during the split already contains this ring.
        if isnothing(state.active_split)
            @nosave filtering_event = _prepare_plaquette_split!(state)
            if !isnothing(filtering_event)
                _log_filtering(filtering_event)
                @yield filtering_event
            end
        end

        # Run the split. The default ALS solver optimizes the ring one site at a time.
        # Forward each update to the caller and collect the final MPS when the split ends.
        split_result = @yieldfrom _split_steps(something(state.active_split))

        # Coarse-grain the ring into black and white tensors, then normalize the new cell.
        @nosave rg_progress = _coarse_grain_and_normalize!(state, split_result.mps)
        split_result = nothing
        _log_rg(rg_progress)
        @yield rg_progress
    end
    return state
end

"""
    renormalize(cell, algorithm; onstep=nothing)

Run RG on a copy of the input cell and return the final normalized plaquette.
When supplied, `onstep(session, event)` receives each yielded progress event.
"""
function renormalize(cell::AbstractTensorCell, algorithm::LoopTNR; onstep=nothing)
    state = initialize_tnr(cell, algorithm)
    session = start_run(algorithm_steps(state); threaded=false, onstep)
    return fetch(session).cell
end
