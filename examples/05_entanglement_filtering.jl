# Run from LoopTNRLab: julia --project=. examples/05_entanglement_filtering.jl
using PMPSLab: SVDInitialization
using TensorLatticeLab, LoopTNRLab, PMPSLab, TensorKit
using ExperimentLab, Test
import LatticeIteratorLab, TensorLinearSolveLab

# Each gate leg contains two corner lines: dimension 2 × 2 = 4.
corner = TensorMap([1.0 0; 0 0.3], ℂ^2 ← ℂ^2)
input = UniformGates(cdl_tensor(corner))
filtering = ProjectorGaugeFix(tol=1e-13, trunc=truncerror(rtol=1e-12))
filtered = LoopTNRLab.filter_entanglement(input, filtering)
@show dim(codomain(input.gate)[1])                     # 4
@show dim(right_virtualspace(PeriodicMPS(filtered.cell), 1)) # Inner bond: 2
@test physicalspaces(PeriodicMPS(filtered.cell)) == physicalspaces(PeriodicMPS(input))
# Outer legs remain dimension 4. A second call on this same plaquette is idempotent.

# Filtering keeps the closed-loop weights, not just the normalized state.
function partition_2x2(cell)
    nw, ne, sw, se = cell[1,1], cell[1,2], cell[2,1], cell[2,2]
    @tensor value = nw[a b; c d] * ne[d e; f a] * sw[g c; b h] * se[h f; e g]
    return value
end
@test partition_2x2(filtered.cell) ≈ partition_2x2(input) rtol=2e-12
@show partition_2x2(input) partition_2x2(filtered.cell)

# Use plain SVD initialization to isolate lattice filtering. There is no
# additional initialization gauge fixing or nuclear-norm regularization here.
algorithm = LoopTNR(max_rg_steps=2, filtering=filtering,
    split=ALSSplit(
        initialization=SVDInitialization(trunc=truncerror(rtol=1e-12)),
        sweep=LatticeIteratorLab.CircularSweep(max_sweeps=1),
        solver=TensorLinearSolveLab.CholeskySolve()))
store = DataStore(mktempdir())
config = ExperimentLab.record_algorithm!(store, algorithm)
state = LoopTNRLab.initialize_tnr(input, algorithm)
session = start_run(store, config, ExperimentLab.algorithm_steps(state); threaded=false)
result = fetch(session)
@test all(dim(space(tensor, leg)) == 1 for tensor in result.cell for leg in 1:4)
println("After two RGs: every bond has dimension 1; both CDL layers have been removed.")

# A frontend needs only this JSONL file: filtering, site updates and RG events
# remain separately identified. ExperimentLab flushes each message as it arrives.
log_path = joinpath(store.path, ExperimentLab.info(store, session.execution)["log_path"])
rows = ExperimentLab.JSON.parse.(readlines(log_path))
filter_rows = [row for row in rows if row["event"] == "looptnr.filtering.completed.v1"]
for row in filter_rows
    println(ExperimentLab.JSON.json(row["data"]))
end
@show log_path
nothing
