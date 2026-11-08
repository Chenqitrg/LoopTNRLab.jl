using PMPSLab: SVDInitialization
function small_algorithm(; steps=2, sweeps=1, regularization=PMPSLab.NoRegularization())
    split = ALSSplit(; initialization=SVDInitialization(),
        sweep=CircularSweep(max_sweeps=sweeps), solver=CholeskySolve(), regularization)
    return LoopTNR(; split, max_rg_steps=steps, filtering=nothing)
end
scalar_cell() = UniformGates(ones(ComplexF64, ℂ^1 ⊗ ℂ^1, ℂ^1 ⊗ ℂ^1))
signature(event::LoopTNRLab.RGProgress, state) = (:rg, event.rg, 0)
signature(event::PMPSLab.SplitProgress, state) = (:site, state.completed_rg + 1, event.site)

function finish_tnr(state)
    events = Tuple{Symbol,Int,Int}[]
    result = fetch(start_run(LoopTNRLab.tnr_steps(state); threaded=false,
        onstep=(_, event) -> push!(events, signature(event, state))))
    return result, events
end
