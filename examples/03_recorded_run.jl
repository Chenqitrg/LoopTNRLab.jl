# Run from LoopTNRLab: julia --project=. examples/03_recorded_run.jl
using LoopTNRLab, PMPSLab, TensorKit, LinearAlgebra
using ExperimentLab, Configurations
import LatticeIteratorLab, TensorLinearSolveLab

# Measurement definitions belong to the application (or a scientific package).
# They use ExperimentLab directly; LoopTNR needs no measurement adapter/history.
@option struct CellNorms <: AbstractMeasurement end
struct CellNormResult <: AbstractMeasurementResult
    norms::Vector{Float64}
end
ExperimentLab.measure(::CellNorms, cell::AbstractTensorCell) =
    CellNormResult(vec([norm(tensor) for tensor in cell]))
ExperimentLab.config_registry(::Type{CellNorms}) =
    ExperimentLab.ConfigRegistry("example.CellNorms" => CellNorms)

cell = UniformGates(ones(ComplexF64, ℂ^1 ⊗ ℂ^1, ℂ^1 ⊗ ℂ^1))
algorithm = LoopTNR(max_rg_steps=1,
    split=ALSSplit(sweep=LatticeIteratorLab.CircularSweep(max_sweeps=1),
        solver=TensorLinearSolveLab.CholeskySolve()))
store = DataStore(mktempdir())
config = ExperimentLab.record_algorithm!(store, algorithm)
state = LoopTNRLab.initialize_tnr(cell, algorithm)
snapshots = ExperimentLab.SnapshotRef[]
session = start_run(store, config, ExperimentLab.algorithm_steps(state); threaded=false,
    onstep=(session, progress) -> begin
        if progress isa LoopTNRLab.RGProgress
            ref = record_state!(store, session.execution; step=progress.rg)
            push!(snapshots, save_snapshot!(store, capture(ref, state)))
            attempt = measure!(store, CellNorms(), state.cell; state=ref)
            @assert ExperimentLab.info(store, attempt)["status"] == "completed"
            @assert all(isfinite, load_result(store, attempt).norms)
        end
    end)
result = fetch(session)
ExperimentLab.showtree(store)
println()
@show ExperimentLab.info(store, session.execution)["log_path"]

# Restore RG 0 into a new execution. The store keeps the original measurements;
# restarting numerical work neither loads nor repeats that measurement history.
saved = first(snapshots)
restored = LoopTNRLab.restore_tnr(load_snapshot(store, saved))
branch = start_run(store, config, ExperimentLab.algorithm_steps(restored); threaded=false,
    initial_state=ExperimentLab.parent_ref(store, saved), label="restart from RG 0")
@assert fetch(branch).completed_rg == result.completed_rg
nothing
