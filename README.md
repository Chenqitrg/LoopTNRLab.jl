# LoopTNRLab

Loop tensor-network renormalization built from PMPSLab and ExperimentLab.
LoopTNRLab owns square-lattice tensor cells, their conversion to periodic MPS,
lattice entanglement filtering, coarse-graining contractions, normalization and the numerical state needed to
continue RG. It does not keep execution status, log histories or measurement histories.

## Run a calculation

```julia
using LoopTNRLab, PMPSLab, LatticeIteratorLab, TensorLinearSolveLab, TensorKit

cell = UniformGates(ones(ComplexF64, ℂ^1 ⊗ ℂ^1, ℂ^1 ⊗ ℂ^1))
algorithm = LoopTNR(max_rg_steps=1,
    split=ALSSplit(sweep=CircularSweep(max_sweeps=1), solver=CholeskySolve()))
result = renormalize(cell, algorithm)
result.cell
result.completed_rg
```

This scalar example demonstrates the workflow, not a physical model. The input is
copied. RG 0 normalizes the initial cell; each later RG filters the current plaquette's inner loop, optimizes its split,
contracts the eight-site MPS into a new cell and normalizes it.
`default_looptnr(max_rg_steps=..., dcut=...)` supplies the standard SVD/gauge/ALS
settings. Set `filtering=nothing` to disable lattice filtering independently of
the initialization gauge. Add `regularization=PMPSLab.NuclearNorm(...)` to the nested ALSSplit when wanted.
Configuration JSON identifies the root and its nested Lab policies automatically.

`LoopTNR.split` accepts any `PMPSLab.AbstractSplit`. ALS is the default preset,
not a requirement of RG. A split implementation supplies `initialize_split`,
`split_steps`, and snapshot restoration; its generator returns a result containing
`mps`. LoopTNR forwards that implementation's own progress events and contracts
the returned MPS without inspecting optimizer-specific workspace fields.

For a corner-double-line input, use `cdl_tensor(corner)` or
`cdl_tensor(northwest, northeast, southeast, southwest)` with TensorKit corner maps.
`random_cdl_tensor(ComplexF64, 2)` generates four random corners with line dimension
2, giving gate-leg dimension 4. Wrap the returned tensor in `UniformGates` to run
RG. See [the CDL example](examples/04_cdl_tensor.jl) for explicit and random inputs.

## Entanglement filtering

`algorithm.filtering` is a PMPSLab `ProjectorGaugeFix`. It filters the inner
virtual loop of the current four-site plaquette and leaves its eight outer
physical legs unchanged. It does not immediately filter a translated plaquette.
Remaining outer CDL structure is handled by the next RG's plaquette grouping.
The eight-site split initialization has its own, separate gauge policy.

`LoopTNRLab.filter_entanglement(cell, algorithm.filtering)` returns the filtered
cell and a local relative error. It keeps the finite-loop amplitude, including
complex phase, by multiplying the filtered plaquette by
`dot(filtered, original) / dot(filtered, filtered)`. These overlaps use PMPSLab
transfer contractions, not a dense eight-physical-leg state. The factor is
absorbed into a tensor and subsequently handled by the existing RG normalization.
A general truncation can change the state beyond a scalar; the reported residual
measures that change and is limited by overlap-subtraction roundoff.

For a nondegenerate diagonal CDL corner `diag(1, 0.3)`, the first filter reduces
inner bonds from 4 to 2 while leaving outer legs at 4. The first RG produces
bond dimension 2; the second RG reaches dimension 1. In this diagonal example,
the second filter leaves bond dimensions unchanged; the subsequent SVD and
coarse graining finish the reduction. Repeating the filter on the same plaquette is
numerically idempotent, rather than continuing to remove the outer structure.
Equal dominant corner eigenvalues need not compress. See [the physical test
and JSON example](examples/05_entanglement_filtering.jl). Standard tests also
check complex phases, retained loop weights, and restoration at every yield.

## Execution and progress

```julia
using ExperimentLab

state = LoopTNRLab.initialize_tnr(cell, algorithm)
session = start_run(LoopTNRLab.tnr_steps(state); threaded=false,
    onstep=(session, progress) -> begin
        if progress isa PMPSLab.SplitProgress && progress.site == 3
            pause!(session)
        end
    end)
# After the Session reports PAUSED, inspect state and then resume!(session).
# fetch(session) waits for completion, including across pauses.
```

The generator directly delegates to `PMPSLab.split_steps` with `@yieldfrom`.
It yields the split algorithm's original events (`SplitProgress` after each ALS
site update), `LoopTNRLab.FilteringProgress` before the first site, and `LoopTNRLab.RGProgress` after each committed RG boundary.
There is no second scheduler or phase enum.
During a split, the RG being computed is `state.completed_rg + 1`.
ExperimentLab owns pause, resume, cancellation, failure and final result handling.

## Stored data and logs

Use `start_run(store, config_ref, generator; onstep=...)` for a recorded execution.
Its JSONL log contains each site's `mps.split.update.v1` event once, alongside
`looptnr.filtering.completed.v1` events containing RG index, bond dimensions,
the local residual and filtering duration, and `looptnr.rg.completed.v1` events containing `rg`, `scale`, `log_scale`, and `duration`.
Each package records its own fields; split events contain no RG context.
The site `duration` is the local numerical update time; the RG `duration` covers
coarse graining and normalization, excluding the split and external callbacks.
ExperimentLab binds ownership and flushes messages before the callback runs.

Measurements are independent of the numerical algorithm. Define an
`ExperimentLab.AbstractMeasurement` and `ExperimentLab.measure` method, then call
`measure!(store, definition, state.cell; state=ref)` in the RG callback. Results,
measurement configuration and measurement logs are linked by ExperimentLab.
Choose what to measure/save in that callback; no history is retained by LoopTNR.
The [recorded example](examples/03_recorded_run.jl) shows the complete flow.

## Restart

At an acknowledged pause or inside `onstep`, `capture(ref, state)` copies only:

- The current cell and algorithm configuration. During an active split this cell
  has already been filtered; restoration does not filter it again.
- The completed RG count (`-1` means initial normalization is pending).
- An active PMPSLab snapshot, if paused inside a split.

The snapshot contains no Task, generator, cache or diagnostic history. The split
target is reconstructed from the committed cell, rather than stored a second time.
After `load_snapshot`, call `LoopTNRLab.restore_tnr(saved)` and start a new
`tnr_steps` generator. Set the new recorded execution's `initial_state` to the
saved StateRef to link the branch. Previously completed sites and RG boundaries
are not replayed, including a snapshot taken after the final split site.

## Review order

1. [Configuration](examples/01_configuration_tree.jl).
2. [Run and pause](examples/02_run_and_pause.jl).
3. [Record, measure and restart](examples/03_recorded_run.jl).
4. [CDL tensors](examples/04_cdl_tensor.jl).
5. [Entanglement filtering and JSON logs](examples/05_entanglement_filtering.jl).
5. [iteration.jl](src/iteration.jl): the entire RG execution sequence.
6. [state.jl](src/state.jl) and [snapshot.jl](src/snapshot.jl): numerical commit and restart data.
7. [contractions.jl](src/contractions.jl): tensor layout and coarse graining.

`tensorcell/` contains the lattice containers, constructors and displays;
`algorithm.jl` defines settings and their JSON names; `normalization.jl` implements
normalization. Scientific tensor kernels and their space checks remain explicit.

## Local setup and tests

Keep the tensor Lab packages and ExperimentLab as sibling directories. Julia 1.12
or later is required. From this directory:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=1 julia --project=. -e 'using Pkg; Pkg.test(; julia_args=["-O0", "--threads=1"])'
```

Examples are independent files with top-level REPL variables. Tests cover tensor
spaces, numerical composition, pause/cancel, ALS and NNR restart at every yielded
boundary, JSON-only progress reading, measurement ownership and fresh-process
restoration. Historical design notes describe earlier implementations.
