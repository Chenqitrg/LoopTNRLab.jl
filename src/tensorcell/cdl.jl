"""
    cdl_tensor(northwest, northeast, southeast, southwest)
    cdl_tensor(corner)

Construct a square-lattice corner-double-line TensorMap with leg order
`(West, South; North, East)`. The one-argument form uses the same map at all
four corners. Corner arguments are one-output, one-input TensorMaps.

Before fusion, the ordinary-array convention is
`T[w₁,w₂,s₁,s₂; n₁,n₂,e₁,e₂] = NW[w₁,n₁] * NE[n₂,e₁] * SE[e₂,s₂] * SW[s₁,w₂]`.
TensorKit bends the second line of each pair into its dual space and fuses
each pair with a unitary map. For corners on `V ← V`, every external leg is
`fuse(V ⊗ V')`, of dimension `dim(V)^2` for ordinary vector spaces.

Returns a tensor, without normalization or a cell wrapper. Wrap compatible
periodic tensors in UniformGates, CheckerboardGates or PlaquetteGates as needed.
"""
function cdl_tensor(
        northwest::AbstractTensorMap{E,S,1,1},
        northeast::AbstractTensorMap{E,S,1,1},
        southeast::AbstractTensorMap{E,S,1,1},
        southwest::AbstractTensorMap{E,S,1,1},
    ) where {E,S}
    @plansor raw[-1 -2 -3 -4; -5 -6 -7 -8] :=
        northwest[-1; -5] * northeast[-6; -7] *
        southeast[-8; -4] * southwest[-3; -2]

    west = codomain(raw)[1] ⊗ codomain(raw)[2]
    south = codomain(raw)[3] ⊗ codomain(raw)[4]
    north = domain(raw)[1] ⊗ domain(raw)[2]
    east = domain(raw)[3] ⊗ domain(raw)[4]
    fw = unitary(scalartype(raw), west, fuse(west))
    fs = unitary(scalartype(raw), south, fuse(south))
    fn = unitary(scalartype(raw), north, fuse(north))
    fe = unitary(scalartype(raw), east, fuse(east))
    return (fw' ⊗ fs') * raw * (fn ⊗ fe)
end

cdl_tensor(corner::AbstractTensorMap{E,S,1,1}) where {E,S} =
    cdl_tensor(corner, corner, corner, corner)

"""
    random_cdl_tensor([rng], elt, V::ElementarySpace)
    random_cdl_tensor([rng], elt, χ::Integer)

Construct a CDL tensor from four independent `rand(rng, elt, V ← V)` corners.
The integer form uses `V = ℂ^χ`; `χ` is a single-line dimension, so each fused
gate leg has dimension `χ^2`. Omit `rng` to use Julia's default RNG.
"""
function random_cdl_tensor(rng::Random.AbstractRNG, elt::Type{<:Number}, V::ElementarySpace)
    corners = ntuple(_ -> Random.rand(rng, elt, V ← V), 4)
    return cdl_tensor(corners...)
end

function random_cdl_tensor(rng::Random.AbstractRNG, elt::Type{<:Number}, χ::Integer)
    χ > 0 || throw(ArgumentError("CDL line dimension must be positive"))
    return random_cdl_tensor(rng, elt, ℂ^χ)
end

random_cdl_tensor(elt::Type{<:Number}, space::Union{ElementarySpace,Integer}) =
    random_cdl_tensor(Random.default_rng(), elt, space)
