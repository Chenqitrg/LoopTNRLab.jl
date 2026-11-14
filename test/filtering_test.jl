using PMPSLab: SVDInitialization
import Random

function cdl_partition(cell::AbstractTensorCell)
    nw, ne, sw, se = cell[1,1], cell[1,2], cell[2,1], cell[2,2]
    @tensor value = nw[a b; c d] * ne[d e; f a] * sw[g c; b h] * se[h f; e g]
    return value
end

function cdl_filter_algorithm(; filtering=true, sweeps=1, steps=2)
    gauge = ProjectorGaugeFix(tol=1e-13, trunc=truncerror(rtol=1e-12))
    initialization = SVDInitialization(trunc=truncerror(rtol=1e-12))
    return LoopTNR(max_rg_steps=steps, filtering=filtering ? gauge : nothing,
        split=ALSSplit(; initialization, sweep=CircularSweep(max_sweeps=sweeps),
            solver=CholeskySolve()))
end

@testset "CDL filtering preserves finite loop amplitudes" begin
    policy = cdl_filter_algorithm().filtering
    for phase in (1.0, exp(0.17im))
        corner = TensorMap(phase * [1.0 0; 0 0.3], ℂ^2 ← ℂ^2)
        original = PlaquetteGates(UniformGates(cdl_tensor(corner)))
        before = copy(original)
        filtered = LoopTNRLab.filter_entanglement(original, policy)
        inner = PeriodicMPS(filtered.cell)
        @test all(dim.(right_virtualspace(inner)) .== 2)
        @test physicalspaces(inner) == physicalspaces(PeriodicMPS(original))
        @test dense(inner) ≈ dense(PeriodicMPS(original)) rtol=2e-12
        twice = LoopTNRLab.filter_entanglement(filtered.cell, policy).cell
        @test all(space(a) == space(b) && norm(a-b) <= 2e-12 * norm(a)
            for (a,b) in zip(filtered.cell, twice))
        @test cdl_partition(filtered.cell) ≈ cdl_partition(original) rtol=2e-12
        @test cdl_partition(original) ≈ tr(convert(Array, corner)^4)^4
        @test filtered.relative_error < 1e-7 # Overlap subtraction roundoff.
        @test all(a == b for (a,b) in zip(original,before))
        @test TensorLatticeLab.assertconsistency(filtered.cell) === nothing
    end

    # Equal dominant eigenvalues are not artificially forced to rank one.
    degenerate = UniformGates(cdl_tensor(id(Float64, ℂ^2)))
    filtered = LoopTNRLab.filter_entanglement(degenerate, policy)
    @test LoopTNRLab._cell_bond_dimensions(filtered.cell) == ntuple(_ -> 4, 8)
    @test cdl_partition(filtered.cell) ≈ cdl_partition(degenerate)
end

@testset "Successive RGs remove inner then remaining CDL structure" begin
    corner = TensorMap([1.0 0; 0 0.3], ℂ^2 ← ℂ^2)
    cell = UniformGates(cdl_tensor(corner))
    algorithm = cdl_filter_algorithm()
    state = LoopTNRLab.initialize_tnr(cell, algorithm)
    saved = LoopTNRLab.TNRSnapshot[]
    events = ExperimentLab.AbstractLogEvent[]
    result = fetch(start_run(ExperimentLab.algorithm_steps(state); threaded=false,
        onstep=(_, event) -> begin
            push!(events, event)
            push!(saved, ExperimentLab.copy_state(state))
        end))
    @test all(LoopTNRLab._cell_bond_dimensions(result.cell) .== 1)
    @test events[2] isa LoopTNRLab.FilteringProgress
    @test events[2].bonds_before == ntuple(_ -> 4, 8)
    @test sort(collect(events[2].bonds_after)) == [2,2,2,2,4,4,4,4]
    @test events[2].duration >= 0
    @test count(e -> e isa PMPSLab.SplitProgress, events) == 16

    # The same SVD initialization without lattice filtering leaves a CDL.
    control = renormalize(cell, cdl_filter_algorithm(filtering=false, sweeps=0, steps=1))
    @test all(LoopTNRLab._cell_bond_dimensions(control) .== 4)
    first_rg = renormalize(cell, cdl_filter_algorithm(sweeps=0, steps=1))
    @test all(LoopTNRLab._cell_bond_dimensions(first_rg) .== 2)
    next_filter = LoopTNRLab.filter_entanglement(first_rg, algorithm.filtering)
    @test dense(PeriodicMPS(next_filter.cell)) ≈ dense(PeriodicMPS(first_rg)) rtol=2e-12
    @test physicalspaces(PeriodicMPS(next_filter.cell)) == physicalspaces(PeriodicMPS(first_rg))
    filtered_svd = renormalize(cell, cdl_filter_algorithm(sweeps=0))
    @test all(LoopTNRLab._cell_bond_dimensions(filtered_svd) .== 1)

    # Filtering is committed with its prepared split. Restoring any safe boundary
    # must neither apply it twice nor replay its event or a completed site.
    for (i, snapshot) in enumerate(saved)
        restored = LoopTNRLab.restore_tnr(snapshot)
        remaining = ExperimentLab.AbstractLogEvent[]
        resumed = fetch(start_run(ExperimentLab.algorithm_steps(restored); threaded=false,
            onstep=(_, event) -> push!(remaining, event)))
        @test map(typeof, remaining) == map(typeof, events[i+1:end])
        @test [e.site for e in remaining if e isa PMPSLab.SplitProgress] ==
            [e.site for e in events[i+1:end] if e isa PMPSLab.SplitProgress]
        @test all(a ≈ b for (a,b) in zip(resumed.cell, result.cell))
    end
end

@testset "Filtering logs are flushed JSON and snapshots resume before the first site" begin
    cell = UniformGates(2 * cdl_tensor(TensorMap([1.0 0; 0 0.3], ℂ^2 ← ℂ^2)))
    algorithm = cdl_filter_algorithm()
    mktempdir() do path
        store = DataStore(path)
        config = ExperimentLab.record_algorithm!(store, algorithm)
        state = LoopTNRLab.initialize_tnr(cell, algorithm)
        saved = Ref{ExperimentLab.SnapshotRef}()
        session = start_run(store, config, ExperimentLab.algorithm_steps(state); threaded=false,
            onstep=(session, event) -> begin
                if event isa LoopTNRLab.FilteringProgress && event.rg == 1
                    ref = record_state!(store, session.execution; step=0, metadata=(; stage="filtered", rg=1))
                    saved[] = save_snapshot!(store, capture(ref, state))
                    pause!(session)
                end
            end)
        @test timedwait(() -> run_status(session) == ExperimentLab.PAUSED, 20) == :ok
        log_path = joinpath(path, ExperimentLab.info(store, session.execution)["log_path"])
        rows = ExperimentLab.JSON.parse.(readlines(log_path))
        filtering = last(rows)
        @test filtering["event"] == "looptnr.filtering.completed.v1"
        @test filtering["data"]["rg"] == 1
        @test filtering["data"]["bonds_before"] == fill(4, 8)
        @test sort(filtering["data"]["bonds_after"]) == [2,2,2,2,4,4,4,4]
        @test filtering["data"]["duration"] >= 0
        @test filtering["data"]["relative_error"] < 1e-7
        @test filtering["owner"]["id"] == string(session.execution.id)
        snapshot = load_snapshot(DataStore(path), saved[])
        @test snapshot.active_split.progress.completed_updates == 0
        resume!(session)
        expected = fetch(session)
        restored = LoopTNRLab.restore_tnr(snapshot)
        branch = start_run(store, config, ExperimentLab.algorithm_steps(restored); threaded=false,
            initial_state=ExperimentLab.parent_ref(store, saved[]))
        actual = fetch(branch)
        @test all(a ≈ b for (a,b) in zip(actual.cell,expected.cell))
        branch_path = joinpath(path, ExperimentLab.info(store, branch.execution)["log_path"])
        branch_rows = ExperimentLab.JSON.parse.(readlines(branch_path))
        @test first(branch_rows)["event"] == "mps.split.update.v1"
        @test first(branch_rows)["data"]["site"] == 1
        @test count(row -> row["event"] == "looptnr.filtering.completed.v1", branch_rows) == 1 # Only the next RG filters again.
        rows = ExperimentLab.JSON.parse.(readlines(log_path))
        @test count(row -> row["event"] == "looptnr.filtering.completed.v1", rows) == 2
        rgs = [row["data"] for row in rows if row["event"] == "looptnr.rg.completed.v1"]
        # A 4×4 CDL torus contains 16, then 8, then 4 tensors. The
        # normalization factors are weighted by the number of tensors per layer.
        recovered_partition = rgs[1]["scale"]^16 * rgs[2]["scale"]^8 *
            rgs[3]["scale"]^4 * cdl_partition(actual.cell)
        @test recovered_partition ≈ cdl_partition(cell)^4 rtol=3e-12
    end
end

@testset "Filtering preserves nonsymmetric plaquette orientation and is idempotent" begin
    # Different complex tensors and horizontal/vertical dimensions prevent CDL
    # symmetry from hiding an incorrect inverse permutation or bond orientation.
    rng = Random.Xoshiro(619)
    gate_space = ℂ^3 ⊗ ℂ^2 ← ℂ^2 ⊗ ℂ^3
    cell = PlaquetteGates(ntuple(_ -> rand(rng, ComplexF64, gate_space), 4)...)
    roundtrip = LoopTNRLab._cell_from_plaquette(PeriodicMPS(cell))
    @test all(a ≈ b for (a,b) in zip(cell, roundtrip))
    policy = ProjectorGaugeFix(tol=1e-13)
    once = LoopTNRLab.filter_entanglement(cell, policy).cell
    twice = LoopTNRLab.filter_entanglement(once, policy).cell
    @test physicalspaces(PeriodicMPS(once)) == physicalspaces(PeriodicMPS(cell))
    @test dense(PeriodicMPS(once)) ≈ dense(PeriodicMPS(cell)) rtol=2e-12
    @test cdl_partition(once) ≈ cdl_partition(cell) rtol=2e-12
    @test all(norm(a-b) <= 1e-10 * norm(a) for (a,b) in zip(once, twice))
end
