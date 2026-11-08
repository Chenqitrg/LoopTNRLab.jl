@testset "CDL corners and fusion preserve the component formula" begin
    V = ℂ^2
    corners = ntuple(_ -> rand(ComplexF64, V ← V), 4)
    before = copy.(corners)
    tensor = cdl_tensor(corners...)
    fused = fuse(V ⊗ V')
    fusion = unitary(ComplexF64, V ⊗ V', fused)
    unfused = (fusion ⊗ fusion) * tensor * (fusion' ⊗ fusion')
    array = convert(Array, unfused)
    nw, ne, se, sw = convert.(Array, corners)

    @test space(tensor) == (fused ⊗ fused ← fused ⊗ fused)
    @test corners == before
    for indices in CartesianIndices(array)
        w1, w2, s1, s2, n1, n2, e1, e2 = Tuple(indices)
        @test array[indices] ≈ nw[w1,n1] * ne[n2,e1] * se[e2,s2] * sw[s1,w2]
    end
    @test norm(tensor) ≈ prod(norm, corners)
    @test cdl_tensor(first(corners)) ≈ cdl_tensor(ntuple(_ -> first(corners), 4)...)

    # A 2×2 periodic square lattice has four independent closed corner loops.
    @tensor partition = tensor[a b; c d] * tensor[d e; f a] *
        tensor[g c; b h] * tensor[h f; e g]
    loop_weight = tr(nw * sw * se * ne)
    @test partition ≈ loop_weight^4
end

@testset "CDL tensor construction integrates with cells and MPS" begin
    for V in (ℂ^2, U1Space(0 => 1, 1 => 1), SU2Space(0 => 1, 1//2 => 1))
        tensor = random_cdl_tensor(Xoshiro(41), ComplexF64, V)
        @test tensor == random_cdl_tensor(Xoshiro(41), ComplexF64, V)
        @test space(tensor) == (fuse(V ⊗ V') ⊗ fuse(V ⊗ V') ← fuse(V ⊗ V') ⊗ fuse(V ⊗ V'))
        cell = UniformGates(tensor)
        @test assertconsistency(cell) === nothing
        @test assertconsistency(PeriodicMPS(cell)) === nothing
    end
    tensor = random_cdl_tensor(Xoshiro(7), Float64, 2)
    @test tensor == random_cdl_tensor(Xoshiro(7), Float64, ℂ^2)
    @test scalartype(tensor) == Float64
    @test dim(codomain(tensor)[1]) == 4
    @test random_cdl_tensor(Float64, 1) isa TensorMap
    @test random_cdl_tensor(ComplexF64, ℂ^1) isa TensorMap
    @test_throws ArgumentError random_cdl_tensor(Float64, 0)
    @test_throws ArgumentError random_cdl_tensor(Float64, -1)
end
