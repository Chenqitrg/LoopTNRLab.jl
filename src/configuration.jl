import AlgorithmConfigLab: config_defaults, config_codecs, config_registry, ConfigRegistry

config_defaults(::Type{<:LoopTNR}) = (; measurement=TNRMeasurement())
config_defaults(::Type{<:TNRMeasurement}) = (;
    normalization=InfinityNormNormalization(), fixed_point=NoFixedPointMeasurement(),
)

config_codecs(::Type{<:LoopTNR}) = Tuple(
    "LoopTNRLab." * string(nameof(T)) => T for T in (
        LoopTNR, TNRMeasurement, InfinityNormNormalization, NoFixedPointMeasurement,
    )
)

config_registry(::Type{<:LoopTNR}) = ConfigRegistry(config_codecs(LoopTNR), config_registry(ALSSplit))
