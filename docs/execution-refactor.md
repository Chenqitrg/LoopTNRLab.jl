# Delegate execution and records to the owning packages

The goal of this refactor is less domain code to review and maintain. There is
no compatibility layer: no production data or applications require the old API.

## Ownership

| Work | Owner |
| --- | --- |
| Cell layout, normalization and coarse graining | LoopTNRLab |
| Site updates, convergence, NNR and split restart | MPSSplitLab |
| Pause, resume, cancel, failure and final return | ExperimentLab Session |
| Log files, state/snapshot references and measurement history | ExperimentLab DataStore |
| Which measurements/snapshots to retain | Application callback |

The outer generator uses `@yieldfrom MPSSplitLab.split_steps(...)`. It forwards
the original SplitProgress values and adds an RGProgress only after a committed
normalization/coarse-graining boundary. No second phase enum or stepping protocol
is required. Each package records its own events in the current execution log.
MPSSplitLab receives no RG context or logging parameters from the outer algorithm.
LoopTNR accepts AbstractSplit algorithms. SplitProgress is specific to ALS;
other implementations yield their own events. Coarse graining consumes the
generator's returned `mps`, rather than reaching into the optimizer's workspace.

## Smaller numerical state

LoopTNRState holds its configuration, committed cell, completed RG count and an
optional split workspace. The initial count is -1. A new cell is committed only
after its contraction and normalization succeed. An external measurement failure
does not roll back a committed numerical step; ExperimentLab records its attempt.
An external callback failure fails the Session, leaving numerical state inspectable.

TNRSnapshot stores the same continuation information, replacing the split
workspace with MPSSplitLab's cache-free snapshot. The split target is derived
from the committed cell. It is not written again. No diagnostic history or live
generator is saved. Restoration validates the RG range and split configuration;
The split implementation validates and rebuilds its own continuation. The outer
snapshot does not require an ALS-specific snapshot type or field layout.

## Removed interfaces

- LoopTNRRun, LoopTNRPhase and manual step!/isfinished/tnr_result dispatch.
- LoopTNRResult: the result is now `(cell, completed_rg)`.
- LoopTNRLog and RGLog: recorded execution logs retain the history.
- TNRMeasurement and NoFixedPointMeasurement: use ExperimentLab measurements
  directly in the callback. Normalization is a direct LoopTNR configuration field.
- The copied measurement/log histories and separate snapshot problem identity.
- LoopTNR-specific wrappers around split progress and their display machinery.
- NormalizationResult: normalization returns `(; scale, log_scale)` rather than
  a measurement-result wrapper. AbstractNormalization remains the strategy
  interface: different normalization methods need not be equivalent.
  InfinityNormNormalization is the current implementation. The normalization
  field retains its concrete type through the LoopTNR type parameter.

## Verification

Tests preserve tensor-space and normalization checks and compare the RG sequence
with explicit split/contraction composition. They exercise zero sweeps, ALS and
NNR, cancellation and failures, restart at every yielded boundary, snapshot
isolation, fresh-process restoration, and JSON-only log/measurement ownership.
The JSON reader checks that each site appears once and is flushed before onstep.

At this migration boundary, source size changed from 1,402 to 828 physical lines
(including comments and blanks): 574 fewer lines, approximately 41%. The lattice
container implementation is unchanged. The execution sequence is 45 lines, the
numerical state/commit code 35, and snapshot/capture/restoration 37.
