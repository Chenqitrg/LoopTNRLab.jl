using LatticeIteratorLab
using TensorLinearSolveLab
# Run from LoopTNRLab: julia --project=. examples/01_configuration_tree.jl
using ExperimentLab: @config
import LoopTNRLab, PMPSLab
using Test: @test

config = @config """
LoopTNRLab.LoopTNR
├─ max_rg_steps: 2
└─ split: PMPSLab.ALSSplit
   ├─ initialization: PMPSLab.SVDInitialization()
   ├─ solver: TensorLinearSolveLab.CholeskySolve()
   └─ sweep: LatticeIteratorLab.CircularSweep
      └─ max_sweeps: 4
"""
display(config)
@test config.max_rg_steps == 2
# Both LoopTNR and ALSSplit have required arguments: construction does not start
# by trying LoopTNR() or ALSSplit(). Their own constructors validate this tree.
nothing
