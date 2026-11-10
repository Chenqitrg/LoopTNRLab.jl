module LoopTNRLab

using TensorKit, LinearAlgebra
using ResumableFunctions: ResumableFunctions, @resumable, @yield, @yieldfrom, @nosave
import Configurations, ExperimentLab, PMPSLab
import ExperimentLab: algorithm_steps
import TensorLinearSolveLab, LatticeIteratorLab
import PMPSLab: PeriodicMPS
import TensorLatticeLab
using TensorLatticeLab: AbstractTensorCell, UniformGates, CheckerboardGates, PlaquetteGates
using TensorLatticeLab: GenericGateTensor, assertconsistency

export LoopTNR, default_looptnr, renormalize, InfinityNormNormalization
public AbstractNormalization, RGProgress, FilteringProgress
public filter_entanglement
public LoopTNRState, TNRSnapshot, initialize_tnr, restore_tnr

include("algorithm.jl")
include("normalization.jl")
include("contractions.jl")
include("filtering.jl")
include("state.jl")
include("iteration.jl")
include("snapshot.jl")

end
