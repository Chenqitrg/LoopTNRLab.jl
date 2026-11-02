# Register LoopTNR snapshots with the shared durable execution protocol.
checkpoint_algorithm(::LoopTNRSnapshot) = :looptnr

checkpoint_metadata(::LoopTNRSnapshot) = Dict(
    "PMPSLab" => string(Base.pkgversion(PMPSLab)),
    "LoopTNRLab" => string(Base.pkgversion(@__MODULE__)),
)
