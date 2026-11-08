"""One committed RG boundary. Duration covers coarse graining and normalization."""
struct RGProgress <: ExperimentLab.AbstractLogEvent
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
struct FilteringProgress <: ExperimentLab.AbstractLogEvent
    rg::Int
    bonds_before::NTuple{8,Int}
    bonds_after::NTuple{8,Int}
    relative_error::Float64
    duration::Float64
end
const RG_EVENTS = ExperimentLab.EventRegistry(
    "looptnr.rg.completed.v1" => RGProgress,
    "looptnr.filtering.completed.v1" => FilteringProgress,
)
function _log_filtering(progress::FilteringProgress)
    record = ExperimentLab.event_record(RG_EVENTS, progress)
    @info "Entanglement filtering completed" record...
end

function _log_rg(progress::RGProgress)
    record = ExperimentLab.event_record(RG_EVENTS, progress)
    @info "RG completed" record...
end

"""
    tnr_steps(state)

Yield FilteringProgress before each split and RGProgress after normalization
(including RG 0), and forward the split
algorithm's own events unchanged. ExperimentLab owns pause/cancel/failure status.
At a split boundary the current RG is state.completed_rg + 1. Each package logs
its own events. Returns (cell, completed_rg), without accumulating histories.
"""
@resumable function tnr_steps(state::LoopTNRState)::ExperimentLab.AbstractLogEvent
    if state.completed_rg == -1
        @nosave progress = _commit_rg!(state, copy(state.cell), 0, time())
        _log_rg(progress)
        @yield progress
    end
    while state.completed_rg < state.algorithm.max_rg_steps
        if isnothing(state.active_split)
            @nosave filtering = _begin_rg!(state)
            if !isnothing(filtering)
                _log_filtering(filtering)
                @yield filtering
            end
        end
        result = @yieldfrom PMPSLab.split_steps(something(state.active_split))
        @nosave progress = _finish_rg!(state, result.mps)
        result = nothing
        _log_rg(progress)
        @yield progress
    end
    return (; cell=state.cell, completed_rg=state.completed_rg)
end

"""Run to completion using ExperimentLab. The input cell is copied."""
renormalize(cell::AbstractTensorCell, algorithm::LoopTNR) =
    fetch(ExperimentLab.start_run(tnr_steps(initialize_tnr(cell, algorithm)); threaded=false))
