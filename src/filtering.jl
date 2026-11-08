# Inverse of the four explicit permutations in _periodic_mps. Only the
# plaquette's internal bonds have changed; its eight external legs are retained.
function _cell_from_plaquette(mps::PeriodicMPS)
    return PlaquetteGates(
        transpose(mps[1], ((3, 4), (2, 1))),
        transpose(mps[4], ((4, 1), (3, 2))),
        transpose(mps[2], ((2, 3), (1, 4))),
        transpose(mps[3], ((1, 2), (4, 3))),
    )
end

# Infinite-chain gauges can discard a scalar closed-loop contribution on a
# finite plaquette. Restore the best overlap amplitude, including its phase.
# For an exact CDL this restores the entire plaquette wavefunction. For a
# general truncated state the residual remains an approximation diagnostic.
function _restore_plaquette_amplitude!(filtered::PeriodicMPS, original::PeriodicMPS)
    before = real(PMPSLab.expectation(original, original))
    after = real(PMPSLab.expectation(filtered, filtered))
    overlap = PMPSLab.expectation(filtered, original)
    isfinite(before) && before > 0 && isfinite(after) && after > 0 ||
        throw(ArgumentError("filtering requires nonzero, finite plaquette norms"))
    amplitude = overlap / after
    isfinite(amplitude) && !iszero(amplitude) ||
        throw(ArgumentError("filtered plaquette has zero or non-finite input overlap"))
    filtered[1] = amplitude * filtered[1]
    fidelity = abs(overlap) / sqrt(after) / sqrt(before)
    residual = max(0.0, 1 - fidelity^2)
    return sqrt(Float64(residual))
end

"""
    filter_entanglement(cell, algorithm::ProjectorGaugeFix)

Filter only the inner virtual loop of the current four-site plaquette and
return `(; cell, relative_error)`, without mutating the input. Its eight outer
physical legs are unchanged. Do not shift to a second plaquette here: remaining
outer CDL structure is handled after the next RG changes the plaquette grouping.
PMPSLab constructs and absorbs the projectors; LoopTNRLab owns the permutations.

Restore the finite plaquette's optimal overlap amplitude, including complex
phase, inside a tensor. This preserves the scalar weight of a removed CDL loop.
For a general truncation `relative_error` diagnoses the residual change, limited
by overlap-contraction roundoff. No dense physical state is materialized.
Degenerate dominant corner spectra need not compress.
"""
function filter_entanglement(cell::AbstractTensorCell, algorithm::PMPSLab.ProjectorGaugeFix)
    original = PeriodicMPS(cell; copy=false)
    filtered = PeriodicMPS(cell)
    PMPSLab.gaugefix!(filtered, algorithm)
    relative_error = _restore_plaquette_amplitude!(filtered, original)
    return (; cell=_cell_from_plaquette(filtered), relative_error)
end

_cell_bond_dimensions(cell::PlaquetteGates) = ntuple(8) do index
    site, leg = divrem(index - 1, 2)
    # East and south enumerate the eight distinct periodic bonds in this cell.
    tensor = cell[mod1(site + 1, 2), div(site, 2) + 1]
    dim(leg == 0 ? domain(tensor)[2] : codomain(tensor)[2])
end
