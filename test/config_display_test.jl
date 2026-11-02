@testset "LoopTNR configuration display" begin
    looptnr_text = sprint(
        show,
        MIME"text/plain"(),
        default_looptnr(; max_rg_steps=4, dcut=16),
    )
    @test occursin(
        "trunc: truncrank(32) & truncerror(rtol=1.0e-13)",
        looptnr_text,
    )
    @test occursin(
        "trunc: truncrank(16) & truncerror(rtol=1.0e-13)",
        looptnr_text,
    )
    @test occursin("orthogonalization_algorithm: Householder", looptnr_text)
    @test !occursin("TruncationIntersection", looptnr_text)
    @test !occursin("DefaultDriver", looptnr_text)
    @test sprint(
        show,
        default_looptnr(; max_rg_steps=4, dcut=16),
    ) == "LoopTNR(...)"

end
