# Run from LoopTNRLab: julia --project=. examples/01_configuration_tree.jl
using AlgorithmConfigLab: @config
import LoopTNRLab, MPSSplitLab
using Test: @test

config = @config """
LoopTNRLab.LoopTNR
├─ max_rg_steps: 2
└─ split: MPSSplitLab.ALSSplit
   ├─ ansatz: MPSSplitLab.SVDAnsatz()
   ├─ solver: MPSSplitLab.CholeskySolve()
   └─ sweep: MPSSplitLab.CircularSweep
      ├─ site_count: 8
      └─ max_sweeps: 4
"""
display(config)
@test config.max_rg_steps == 2
# Both LoopTNR and ALSSplit have required arguments: construction does not start
# by trying LoopTNR() or ALSSplit(). Their own constructors validate this tree.
nothing
