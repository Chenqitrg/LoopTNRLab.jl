# Run from LoopTNRLab: julia --project=. examples/02_run_and_pause.jl
using LoopTNRLab, PMPSLab, TensorKit
import ExperimentLab, LatticeIteratorLab, TensorLinearSolveLab

cell = UniformGates(ones(ComplexF64, ℂ^1 ⊗ ℂ^1, ℂ^1 ⊗ ℂ^1))
algorithm = LoopTNR(max_rg_steps=1,
    split=ALSSplit(sweep=LatticeIteratorLab.CircularSweep(max_sweeps=1),
        solver=TensorLinearSolveLab.CholeskySolve()))

# The blocking entry point returns only the final cell and completed RG count.
result = renormalize(cell, algorithm)
@show result.completed_rg

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
resumed_result = fetch(session)
@assert resumed_result.completed_rg == 1
nothing
