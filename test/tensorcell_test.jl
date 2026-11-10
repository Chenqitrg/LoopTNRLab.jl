@testset "gate cells convert to U-shaped periodic MPS" begin
    horizontal_ab = ℂ^2
    horizontal_ba = ℂ^3
    horizontal_cd = ℂ^4
    horizontal_dc = ℂ^5
    vertical_ac = ℂ^6
    vertical_ca = ℂ^7
    vertical_bd = ℂ^8
    vertical_db = ℂ^9

    northwest = randn(
        ComplexF64,
        horizontal_ba ⊗ vertical_ac,
        vertical_ca ⊗ horizontal_ab,
    )
    northeast = randn(
        ComplexF64,
        horizontal_ab ⊗ vertical_bd,
        vertical_db ⊗ horizontal_ba,
    )
    southwest = randn(
        ComplexF64,
        horizontal_dc ⊗ vertical_ca,
        vertical_ac ⊗ horizontal_cd,
    )
    southeast = randn(
        ComplexF64,
        horizontal_cd ⊗ vertical_db,
        vertical_bd ⊗ horizontal_dc,
    )
    plaquette = PlaquetteGates(
        northwest, northeast, southwest, southeast
    )
    mps = PeriodicMPS(plaquette)

    @test length(mps) == 4
    @test assertconsistency(mps) === nothing
    @test all(
        !isdual(PMPSLab.left_virtualspace(tensor)) &&
        !isdual(PMPSLab.right_virtualspace(tensor))
        for tensor in mps
    )

    uniform = UniformGates(test_gate())
    checkerboard = CheckerboardGates(uniform)
    for cell in (uniform, checkerboard)
        promoted = PeriodicMPS(PlaquetteGates(cell; copy=false))
        @test all(PeriodicMPS(cell)[site] ≈ promoted[site] for site in 1:4)
    end
end


@testset "U1 cell conversion preserves the contracted periodic state" begin
    west = U1Space(0 => 1, 1 => 1)
    south = U1Space(0 => 1, -1 => 1)
    gate = rand(ComplexF64, west ⊗ south ← south ⊗ west)
    cell = PlaquetteGates(UniformGates(gate); copy=false)
    raw = [
        transpose(cell.northwest, ((4, 3, 1), (2,)); copy=false),
        transpose(cell.southwest, ((3, 1, 2), (4,)); copy=false),
        transpose(cell.southeast, ((1, 2, 4), (3,)); copy=false),
        transpose(cell.northeast, ((2, 4, 3), (1,)); copy=false),
    ]
    @plansor expected[-1 -2 -3 -4 -5 -6 -7 -8] :=
        raw[1][a -1 -2; b] * raw[2][b -3 -4; c] *
        raw[3][c -5 -6; d] * raw[4][d -7 -8; a]
    @test dense(PeriodicMPS(cell)) ≈ expected
end
