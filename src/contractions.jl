"""
    PeriodicMPS(cell::AbstractTensorCell; copy=true)

Convert a square-lattice gate cell into a four-site periodic MPS. Every input
is first promoted to a `PlaquetteGates`, then its corners follow the U-shaped
order northwest, southwest, southeast, northeast. The remaining north bond
closes the periodic chain.

Gate legs follow `(West, South; North, East)`. At each MPS site the first leg
points to the previous corner, the middle two legs point outside the plaquette,
and the domain leg points to the next corner. The physical-leg pairs are
`(North, West)`, `(West, South)`, `(South, East)`, and `(East, North)`.
"""
function PeriodicMPS(cell::AbstractTensorCell; copy::Bool = true)
    plaquette = PlaquetteGates(cell; copy=false)
    return _periodic_mps(plaquette; copy)
end

function _periodic_mps(cell::PlaquetteGates; copy::Bool)
    tensors = [
        transpose(cell.northwest, ((4, 3, 1), (2,)); copy),
        transpose(cell.southwest, ((3, 1, 2), (4,)); copy),
        transpose(cell.southeast, ((1, 2, 4), (3,)); copy),
        transpose(cell.northeast, ((2, 4, 3), (1,)); copy),
    ]
    return PeriodicMPS(tensors)
end

"""
    _coarse_grain(mps)

Contract the eight-site, one-physical-leg periodic MPS produced by the LoopTNR
split into the next checkerboard tensor cell. The site ordering is the U-shaped
ordering established by `PeriodicMPS(::AbstractTensorCell)` followed by the
two-physical-leg tensor split.
"""
function _coarse_grain(
        mps::PeriodicMPS{<:AbstractTensorMap{E,S,2,1}},
    ) where {E,S}
    length(mps) == 8 || throw(DimensionMismatch(
        "LoopTNR coarse graining requires eight split sites, got $(length(mps))"
    ))

    @plansor white[-1 -2; -3 -4] :=
        mps[1][S W; -1] *
        mps[8][-2 E; S] *
        mps[4][-3 W; N] *
        mps[5][N E; -4]
    @plansor black[-1 -2; -3 -4] :=
        mps[2][-4 N; E] *
        mps[3][E S; -2] *
        mps[6][-1 S; W] *
        mps[7][W N; -3]

    return CheckerboardGates(black, white)
end
