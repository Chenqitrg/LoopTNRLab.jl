# LoopTNRLab

Loop tensor-network renormalization built on [PMPSLab](../PMPSLab).
LoopTNRLab owns square-lattice tensor cells, plaquette-to-MPS conversion,
coarse graining, RG normalization, measurements, and the outer RG run.
PMPSLab owns periodic-MPS optimization; [ExecutionLab](../ExecutionLab) owns
generic run control and checkpoint storage.

## Local setup

Keep the packages as siblings:

```text
GitHub/
├── ExecutionLab/
├── PMPSLab/
└── LoopTNRLab/
```

From the LoopTNRLab directory:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=.
```

The project uses relative sources `../PMPSLab` and `../ExecutionLab`, both
version 0.1.0. Julia 1.12 or later is required. LoopTNRLab exports its RG and
lattice APIs, PMPSLab exports optimization APIs, and ExecutionLab exports run
control. PMPSLab retains its old execution names as aliases.

```julia
using LoopTNRLab
using PMPSLab
using ExecutionLab
using TensorKit

gate_space = ℂ^2 ⊗ ℂ^2 ← ℂ^2 ⊗ ℂ^2
gates = rand(UniformGates, ComplexF64, gate_space)
```

## Run LoopTNR

`LoopTNR` repeatedly turns a tensor cell into its designed eight-site split
problem, optimizes that split, coarse-grains it back to a tensor cell, and then
normalizes and measures the new RG boundary. The blocking API returns a named
result rather than a tuple. All accepted input cell layouts are copied into a
canonical `PlaquetteGates`; run, snapshot, and result cells therefore always
use that representation:

```julia
tnr = default_looptnr(; max_rg_steps=2, dcut=8)
result = renormalize(gates, tnr)

@show result.cell
@show length(result.measurement_results)  # RG 0, 1, and 2
@show length(result.log.rg_logs)
```

The default uses an eight-site circular ALS split with at most 40 sweeps,
dense normal and mixed environments, an LDLT local solve, and a periodic-gauge
ansatz. Its preliminary SVD retains at most `2dcut` states before projector
 gauge fixing reduces the universal bond dimension to `dcut`. After five
complete sweeps it stops when both `abs(cost) < 1e-9` and the relative
sweep-to-sweep cost change is below `1e-2`. Every RG boundary is normalized by
the coefficient infinity norm; fixed-point transfer measurements remain
disabled until their eigensolver is available.

Algorithm configurations are immutable values. Use `@setconfig` to derive a
modified configuration. Its `/`-separated paths follow the displayed
configuration tree from root to leaf:

```julia
tnr = @setconfig tnr begin
    max_rg_steps = 4
    split/sweep/max_sweeps = 60
    split/stopping/atol = 1e-10
end
```

The original `tnr` is unchanged unless the returned value is assigned back to
it. A whole strategy can also be replaced, even when that changes the concrete
configuration type:

```julia
tnr = @setconfig tnr split/stopping = NoStopping()
```

In an interactive session the default observer uses one replaceable progress
entry for the current RG split, spanning all of its split sweeps, and leaves
concise sweep and RG summaries behind:

```text
[ Info: LoopTNR started · RG 0/2 normalization pending
[ Info: LoopTNR RG 0/2 initialized · scale <Real>
[ Info: LoopTNR RG 1/2 · split sweep 1 completed · cost <Float64> · duration <Float64> s
[ Info: LoopTNR RG 1/2 completed · cost <Float64> · split <Float64> s · coarse grain <Float64> s · scale <Real>
...
[ Info: LoopTNR completed · RG 2/2 · 3 measurements
```

Typing a run at the REPL shows its next safe action without expanding tensor
storage. During an active split it has this shape:

```text
LoopTNRRun(RG 1/2 · split sweep 3 · next site 5/8)
  committed cell: 2×2 PlaquetteGates(ComplexF64, ComplexSpace)
  RG logs: 1
  measurements: 1
  active split: 20/320 site updates
```

LoopTNR uses the same controllable execution interface as a standalone split:

```julia
run = initialize_run(gates, tnr)
session_ref = Ref{LocalRunSession}()
pause_requested = Ref(false)
observer = event -> begin
    if !pause_requested[] &&
            event isa LoopTNRSplitStepCompleted &&
            event.event.log.state.site == 4
        pause_requested[] = true
        pause!(session_ref[])
    end
    nothing
end

session = LocalRunSession(run; observer)
session_ref[] = session
start_run!(session)

wait(session)  # stops after the current split site or complete RG action
run_status(session) == ExecutionLab.LOCAL_PAUSED || error("run did not pause")
display(run)   # reports the exact continuation point
resume!(session)
result = fetch(session)
```

Here the observer requests the pause once, after split site 4 completes. This
avoids racing an external `pause!` call against a short run. An external pause
request is still valid, but completion wins if the run finishes first.

A custom observer replaces the display and receives both nested split-site
events and committed RG events. Physical measurement results are carried by
the RG event, separately from the control-only logs:

```julia
observer = event -> begin
    event isa LoopTNRCoarseGrained || return
    measurement = event.result
    println("RG $(event.rg): normalization scale = ",
            measurement.normalization.scale)
end

result = renormalize(gates, tnr; observer)
```

Durable pause stores the committed outer cell, its measurement history, and an
active split snapshot when the pause lands inside a split. Restoring a LoopTNR
checkpoint therefore needs the algorithm configuration, but not the original
input cell:

```julia
session = start_run(initialize_run(gates, tnr))
outcome = pause_and_checkpoint!(session, "paused-looptnr.jld2")

if outcome == ExecutionLab.LOCAL_CHECKPOINT_WRITTEN
    saved = read_checkpoint("paused-looptnr.jld2")
    restored = restore_run(saved, tnr)
    result = fetch(start_run(restored))
else
    result = fetch(session)
end
```


## Tests

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The suite covers cell geometry, normalization, nested optimization, observer
progress, snapshots, and durable checkpoints. ExecutionLab, PMPSLab, and
LoopTNRLab versions are checked when reading a LoopTNR checkpoint. Legacy
PMPSLab checkpoint formats require their original environment and are not
migrated. PMPSLab and LoopTNRLab remain `0.1.0`; ExecutionLab starts at `0.1.0`.

## Scope and status

The first resumable LoopTNR implementation is complete. Built-in fixed-point
measurements and conformal spectra remain future work. The
[implementation plan](design/looptnr-implementation-plan.md) records the existing
algorithm; the [acceleration research plan](design/looptnr-als-acceleration-research-plan.md)
records deferred experiments.

## Provenance and credits

Extracted from PMPSLab commit `dbd1fb7` on 2026-11-02. Numerical kernels and
space conventions were moved without changing the algorithm. The original
history remains in the sibling PMPSLab repository.

LoopTNRLab builds on TensorKit, MPSKit through PMPSLab, and the algorithms and
earlier implementation work in [TNRKit](https://github.com/QuantumKitHub/TNRKit.jl).
TNRKit is not a runtime dependency. Credit belongs to the authors and
contributors of those projects as described in PMPSLab's upstream acknowledgments.
