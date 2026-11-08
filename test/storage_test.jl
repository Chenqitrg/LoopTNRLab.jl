using Configurations: @option
using ExperimentLab: JSON

@option struct StoredCellMeasurement <: ExperimentLab.AbstractMeasurement end
struct StoredCellResult <: ExperimentLab.AbstractMeasurementResult
    count::Int
end
ExperimentLab.config_registry(::Type{StoredCellMeasurement}) =
    ExperimentLab.ConfigRegistry("test.CellCount" => StoredCellMeasurement)
function ExperimentLab.measure(::StoredCellMeasurement, cell::AbstractTensorCell)
    @info "Measured cell" count=length(cell)
    return StoredCellResult(length(cell))
end

@testset "Recorded RGs: site logs, measurements, pause and fresh-process restart" begin
    state = LoopTNRLab.initialize_tnr(scalar_cell(), small_algorithm())
    mktempdir() do path
        store = DataStore(path)
        config = ExperimentLab.record_algorithm!(store, state.algorithm)
        session = start_run(store, config, LoopTNRLab.tnr_steps(state); threaded=false,
            onstep=(session, progress) -> begin
                # The latest log must already be on disk when the callback runs.
                log_path = joinpath(path, ExperimentLab.info(store, session.execution)["log_path"])
                row = JSON.parse(last(readlines(log_path)))
                @assert row["owner"]["id"] == string(session.execution.id)
                if progress isa LoopTNRLab.RGProgress
                    @assert row["event"] == "looptnr.rg.completed.v1"
                    @assert row["data"]["rg"] == progress.rg
                    ref = record_state!(store, session.execution; step=progress.rg)
                    measure!(store, StoredCellMeasurement(), state.cell; state=ref)
                else
                    @assert row["event"] == "mps.split.update.v1"
                    @assert !haskey(row, "rg") && !haskey(row["data"], "rg")
                    @assert row["data"]["site"] == progress.site
                    if state.completed_rg == 0 && progress.site == 4
                        ref = record_state!(store, session.execution; step=4,
                            metadata=(; rg=1, site=4))
                        save_snapshot!(store, capture(ref, state))
                        pause!(session)
                    end
                end
            end)
        @test timedwait(() -> run_status(session) == ExperimentLab.PAUSED, 20) == :ok
        saved = only(ExperimentLab.records(store, :snapshot))
        saved_state = ExperimentLab.parent_ref(store, saved)
        snapshot = load_snapshot(DataStore(path), saved)
        @test snapshot.active_split.progress.completed_updates == 4
        resume!(session)
        expected = fetch(session)

        restored = LoopTNRLab.restore_tnr(snapshot)
        branch = start_run(store, config, LoopTNRLab.tnr_steps(restored); threaded=false,
            initial_state=saved_state, label="resumed")
        actual = fetch(branch)
        @test actual.completed_rg == expected.completed_rg == 2
        @test all(a ≈ b for (a, b) in zip(actual.cell, expected.cell))
        @test ExperimentLab.info(store, session.execution)["status"] == "completed"
        @test ExperimentLab.parent_ref(store, branch.execution) == config

        # These assertions only read JSON/JSONL; no tensor or Julia type name parsing.
        index = JSON.parsefile(joinpath(path, "index.json"))
        execution = index["executions"][string(session.execution.id)]
        rows = JSON.parse.(readlines(joinpath(path, execution["log_path"])))
        sites = filter(row -> row["event"] == "mps.split.update.v1", rows)
        rgs = filter(row -> row["event"] == "looptnr.rg.completed.v1", rows)
        @test length(rows) == 19 # Exactly 16 site records and three RG records.
        @test all(!haskey(row, "rg") && !haskey(row["data"], "rg") for row in sites)
        @test [row["data"]["site"] for row in sites] == repeat(1:8, 2)
        @test all(row["data"]["sweep"] == 1 && row["data"]["duration"] >= 0 for row in sites)
        @test all(isfinite(row["data"]["local_cost"]) for row in sites)
        @test [row["data"]["rg"] for row in rgs] == [0, 1, 2]
        @test all(row["data"]["duration"] >= 0 && row["data"]["scale"] > 0 for row in rgs)
        @test index["algorithms"][string(config.id)]["config"]["type"] == "LoopTNRLab.LoopTNR"
        attempts = ExperimentLab.records(store, :measurement)
        @test length(attempts) == 3
        for attempt in attempts
            @test load_result(store, attempt).count == 4
            record = index["measurements"][string(attempt.id)]
            logs = JSON.parse.(readlines(joinpath(path, record["log_path"])))
            @test only(logs)["owner"] == Dict("kind" => "measurement", "id" => string(attempt.id))
        end
        branch_rows = JSON.parse.(readlines(joinpath(path, ExperimentLab.info(store, branch.execution)["log_path"])))
        @test !haskey(first(branch_rows), "rg")
        @test first(branch_rows)["data"]["site"] == 5
        @test all(row["owner"]["id"] == string(branch.execution.id) for row in branch_rows)

        # A fresh process reconstructs native state; no suspended generator is saved.
        script = """
        using ExperimentLab, LoopTNRLab
        store = DataStore(ARGS[1])
        saved = only(ExperimentLab.records(store, :snapshot))
        state = LoopTNRLab.restore_tnr(load_snapshot(store, saved))
        sites = Int[]
        result = fetch(start_run(LoopTNRLab.tnr_steps(state); threaded=false,
            onstep=(_, event) -> event isa LoopTNRLab.RGProgress || push!(sites, event.site)))
        @assert first(sites) == 5
        @assert result.completed_rg == 2
        """
        project = dirname(Base.active_project())
        command = `$(Base.julia_cmd()) --startup-file=no -O0 --threads=1 --project=$project -e $script $path`
        @test success(pipeline(command; stdout=devnull, stderr=stderr))
    end
end
