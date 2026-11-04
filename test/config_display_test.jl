using TensorKit: MatrixAlgebraKit

@testset "LoopTNR editable configuration display" begin
    original = default_looptnr(; max_rg_steps=4, dcut=16)
    tree = sprint(show, MIME"text/plain"(), original)
    restored = include_string(@__MODULE__, "@config " * repr(tree))
    @test isequal(restored, original)
    @test isequal(restored.split.ansatz.initial_split.trunc,
                  truncrank(32) & truncerror(; rtol=1e-13))
    @test isequal(restored.split.ansatz.gauge_fix.trunc,
                  truncrank(16) & truncerror(; rtol=1e-13))
    @test isequal(restored.split.ansatz.gauge_fix.orthogonalization_algorithm,
                  original.split.ansatz.gauge_fix.orthogonalization_algorithm)
    @test isequal(include_string(@__MODULE__, sprint(show, original)), original)
    @test sprint(show, original; context=:compact=>true) == "LoopTNR(...)"
end
