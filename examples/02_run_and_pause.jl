# Run from LoopTNRLab: julia --project=. examples/02_run_and_pause.jl
using TensorLatticeLab, LoopTNRLab, PMPSLab, TensorKit
import ExperimentLab, LatticeIteratorLab, TensorLinearSolveLab

cell = UniformGates(ones(ComplexF64, ℂ^1 ⊗ ℂ^1, ℂ^1 ⊗ ℂ^1))
algorithm = LoopTNR(max_rg_steps=1,
    split=ALSSplit(sweep=LatticeIteratorLab.CircularSweep(max_sweeps=1),
        solver=TensorLinearSolveLab.CholeskySolve()))

# Count site updates between committed RG boundaries, including RG 0.
site_updates = Ref(0)
updates_by_rg = Dict{Int,Int}()
function record_progress(session, event)
    if event isa PMPSLab.SplitProgress
        site_updates[] += 1
    elseif event isa LoopTNRLab.RGProgress
        updates_by_rg[event.rg] = site_updates[]
        site_updates[] = 0
    end
end
coarse_cell = renormalize(cell, algorithm; onstep=record_progress)
@assert updates_by_rg == Dict(0 => 0, 1 => 8)
@assert coarse_cell isa PlaquetteGates

# The same computation can pause after any nested split site. LoopTNR forwards
# PMPSLab.SplitProgress unchanged; ExperimentLab controls the Session.
state = LoopTNRLab.initialize_tnr(cell, algorithm)
session = ExperimentLab.start_run(ExperimentLab.algorithm_steps(state); threaded=false,
    onstep=(session, progress) -> begin
        if progress isa PMPSLab.SplitProgress && progress.site == 3
            ExperimentLab.pause!(session)
        end
    end)
@assert timedwait(() -> ExperimentLab.run_status(session) == ExperimentLab.PAUSED, 20) == :ok
@show state
@show state.active_split.progress.local_cost

# In the REPL, inspect the paused state before running these two lines.
ExperimentLab.resume!(session)
@assert fetch(session) === state
@assert state.completed_rg == 1
nothing
