# Run from LoopTNRLab: julia --project=. examples/04_cdl_tensor.jl
using LoopTNRLab, PMPSLab, TensorKit, Random
using Test: @test

# 1. Choose the corner weights explicitly. No random initialization is involved.
corner = TensorMap([1.0 0.0; 0.0 0.3], ℂ^2 ← ℂ^2)
tensor = cdl_tensor(corner)
@show space(tensor)
@test dim(codomain(tensor)[1]) == 4 # Two lines of dimension 2 per gate leg.

# 2. Use the ordinary lattice wrappers and conversion to the split target.
cell = UniformGates(tensor)
display(cell)
target = PeriodicMPS(cell)
@show length(target)
@test length(target) == 4
@test assertconsistency(target) === nothing

# 3. Four distinct corners are accepted in clockwise order: NW, NE, SE, SW.
anisotropic = cdl_tensor(corner, 2corner, 3corner, 4corner)
@test anisotropic ≈ 24tensor

# 4. Random fixtures can use an explicit RNG for repeatability, or omit it.
random_tensor = random_cdl_tensor(Xoshiro(42), ComplexF64, 2)
@test random_tensor == random_cdl_tensor(Xoshiro(42), ComplexF64, 2)
another_tensor = random_cdl_tensor(ComplexF64, 2)
@show space(random_tensor)
nothing
