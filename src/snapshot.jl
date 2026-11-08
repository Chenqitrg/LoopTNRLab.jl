"""Restart data: one committed cell and, when needed, a cache-free split snapshot."""
struct TNRSnapshot{A<:LoopTNR,C<:PlaquetteGates,S}
    algorithm::A
    cell::C
    completed_rg::Int
    active_split::S
end

# capture(ref, state) calls this once. Never save Tasks, generators or caches.
function ExperimentLab.copy_state(state::LoopTNRState)
    split = isnothing(state.active_split) ? nothing : ExperimentLab.copy_state(state.active_split)
    return TNRSnapshot(deepcopy(state.algorithm), copy(state.cell), state.completed_rg, split)
end

"""
    restore_tnr(snapshot)

Rebuild numerical workspaces from the saved configuration. During an active
split the saved cell is already filtered; it is reused without filtering again. The next generator
continues after the captured boundary, without replaying measurements or logs.
"""
function restore_tnr(saved::TNRSnapshot)
    algorithm, rg = saved.algorithm, saved.completed_rg
    -1 <= rg <= algorithm.max_rg_steps || throw(ArgumentError("invalid completed RG count"))
    if !isnothing(saved.active_split)
        0 <= rg < algorithm.max_rg_steps || throw(ArgumentError("active split outside an RG step"))
    end
    assertconsistency(saved.cell)
    cell = copy(saved.cell)
    split = isnothing(saved.active_split) ? nothing :
        MPSSplitLab.restore_split(saved.active_split, PeriodicMPS(cell; copy=false); algorithm=algorithm.split)
    return LoopTNRState(deepcopy(algorithm), cell, rg, split)
end

Base.show(io::IO, saved::TNRSnapshot) = print(io,
    "TNRSnapshot(completed_rg=", saved.completed_rg, "/", saved.algorithm.max_rg_steps,
    ", active_split=", !isnothing(saved.active_split), ")")
