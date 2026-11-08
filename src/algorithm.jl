"""Configurable tensor-cell normalization strategy."""
abstract type AbstractNormalization <: ExperimentLab.AbstractAlgorithmConfig end

"""Normalize independent cell tensors by their geometric-mean infinity norm."""
Configurations.@option struct InfinityNormNormalization <: AbstractNormalization end

"""
    LoopTNR(; split, max_rg_steps, normalization=InfinityNormNormalization(), filtering=ProjectorGaugeFix(...))

Numerical RG settings. Schedule measurements and storage in an ExperimentLab
callback; they are independent of the tensors required for the next RG step.
`filtering` acts on the lattice before each split; set it to `nothing` to disable
that stage. It is independent of the split initialization's gauge policy.
"""
Configurations.@option struct LoopTNR{S<:MPSSplitLab.AbstractSplit,N<:AbstractNormalization,F<:Union{Nothing,PMPSLab.ProjectorGaugeFix}} <: ExperimentLab.AbstractAlgorithmConfig
    split::S
    max_rg_steps::Int
    normalization::N = InfinityNormNormalization()
    filtering::F = PMPSLab.ProjectorGaugeFix(tol=1e-13, trunc=truncerror(rtol=1e-12))

    function LoopTNR{S,N,F}(split::S, max_rg_steps::Integer, normalization::N, filtering::F) where {S,N,F}
        max_rg_steps >= 0 || throw(ArgumentError("max_rg_steps must be non-negative"))
        return new{S,N,F}(split, Int(max_rg_steps), normalization, filtering)
    end
end
LoopTNR(split::S, steps::Integer, normalization::N, filtering::F) where {S,N,F} =
    LoopTNR{S,N,F}(split, steps, normalization, filtering)

"""
    default_looptnr(; max_rg_steps, dcut)

Build the standard dense-environment [`LoopTNR`](@ref) configuration. The
preliminary SVD retains at most `2dcut` states and periodic projector gauge
fixing then reduces the universal bond dimension to `dcut`.
The nested preset is constructed with ExperimentLab's `@config` tree syntax.
"""
function default_looptnr(; max_rg_steps::Integer, dcut::Integer)
    dcut > 0 || throw(ArgumentError(
        "dcut must be positive, got $dcut"
    ))
    max_rg_steps >= 0 || throw(ArgumentError("max_rg_steps must be non-negative"))
    preliminary_rank = Base.checked_mul(2, Int(dcut))
    numerical_truncation = truncerror(; rtol=1.0e-13)
    return ExperimentLab.@config """
    LoopTNR
    ├─ max_rg_steps: max_rg_steps
    ├─ filtering: PMPSLab.ProjectorGaugeFix
    │  ├─ tol: 1.0e-13
    │  └─ trunc: numerical_truncation
    └─ split: MPSSplitLab.ALSSplit
       ├─ initialization: MPSSplitLab.GaugeInitialization
       │  ├─ initialization: MPSSplitLab.SVDInitialization
       │  │  └─ trunc: truncrank(preliminary_rank) & numerical_truncation
       │  └─ gauge_fix: PMPSLab.ProjectorGaugeFix
       │     ├─ tol: 1.0e-13
       │     ├─ maxiter: 100
       │     └─ trunc: truncrank(dcut) & numerical_truncation
       ├─ sweep: UpdateLab.CircularSweep
       │  └─ max_sweeps: 40
       ├─ solver: TensorLinearSolveLab.LDLTSolve()
       ├─ environments: MPSSplitLab.SplitEnvironmentPolicy
       │  ├─ normal: PMPSLab.DenseTransferPolicy()
       │  └─ mixed: PMPSLab.DenseTransferPolicy()
       └─ stopping: MPSSplitLab.CostTolerance
          ├─ atol: 1.0e-9
          ├─ rtol: 1.0e-2
          └─ min_sweeps: 5
    """
end

const CONFIG_REGISTRY = ExperimentLab.ConfigRegistry(
    ExperimentLab.ConfigRegistry(
        "LoopTNRLab.LoopTNR" => LoopTNR,
        "LoopTNRLab.InfinityNormNormalization" => InfinityNormNormalization,
    ),
    ExperimentLab.config_registry(MPSSplitLab.AbstractSplit),
)
ExperimentLab.config_registry(::Type{<:LoopTNR}) = CONFIG_REGISTRY
ExperimentLab.config_registry(::Type{InfinityNormNormalization}) = CONFIG_REGISTRY
