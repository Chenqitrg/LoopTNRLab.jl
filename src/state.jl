"""Current numerical state, without tasks, logs or measurement history."""
mutable struct LoopTNRState{A<:LoopTNR,C<:PlaquetteGates} <: ExperimentLab.AbstractAlgorithmState
    algorithm::A
    cell::C
    completed_rg::Int
    # Absent between RG steps. PMPSLab owns the concrete numerical workspace;
    # its generator and the contraction below specialize at their call boundaries.
    active_split::Union{Nothing,PMPSLab.AbstractSplitState}
end

"""Copy the input cell; RG 0 normalization has not run yet."""
initialize_tnr(cell::AbstractTensorCell, algorithm::LoopTNR) =
    LoopTNRState(algorithm, PlaquetteGates(cell), -1, nothing)

# Commit only after normalization succeeds. A failed contraction/normalization
# leaves the previous cell and completed split available for inspection/restart.
function _normalize_and_commit_rg!(state::LoopTNRState, candidate::PlaquetteGates, rg::Int, started::Float64)
    result = normalize!(candidate, state.algorithm.normalization)
    state.cell = candidate
    state.completed_rg = rg
    state.active_split = nothing
    return RGProgress(rg, result.scale, result.log_scale, time() - started)
end

function _coarse_grain_and_normalize!(state::LoopTNRState, mps::PeriodicMPS)
    started = time()
    candidate = PlaquetteGates(_coarse_grain(mps))
    return _normalize_and_commit_rg!(state, candidate, state.completed_rg + 1, started)
end

function Base.show(io::IO, state::LoopTNRState)
    print(io, "LoopTNRState(completed_rg=", state.completed_rg, "/", state.algorithm.max_rg_steps)
    print(io, ", active_split=", !isnothing(state.active_split))
    print(io, ")")
end

# A single transaction prepares the next split. At the filtering yield, the
# filtered cell and active split already agree, so snapshots need no phase flag
# and restore_tnr must not filter this cell a second time.
function _prepare_plaquette_split!(state::LoopTNRState)
    cell = state.cell
    filtering_event = nothing
    policy = state.algorithm.filtering
    if !isnothing(policy)
        started = time()
        before = _cell_bond_dimensions(cell)
        filtered = filter_entanglement(cell, policy)
        cell = filtered.cell
        filtering_event = FilteringProgress(state.completed_rg + 1, before,
            _cell_bond_dimensions(cell), filtered.relative_error, time() - started)
    end

    target = PeriodicMPS(cell; copy=false)
    split = PMPSLab.initialize_split(target, state.algorithm.split)
    state.cell = cell
    state.active_split = split
    return filtering_event
end
