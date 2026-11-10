@testset "TensorLatticeLab CDL cells convert to PMPSLab" begin
    for V in (ℂ^2, U1Space(0 => 1, 1 => 1), SU2Space(0 => 1, 1//2 => 1))
        cell = UniformGates(random_cdl_tensor(Xoshiro(41), ComplexF64, V))
        @test PMPSLab.assertconsistency(PeriodicMPS(cell)) === nothing
    end
end
