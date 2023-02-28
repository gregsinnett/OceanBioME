module Sediments

export Soetaert

using KernelAbstractions
using OceanBioME: ContinuousFormBiogeochemistry
using Oceananigans.Architectures: device_event, device
using Oceananigans.Utils: launch!
using Oceananigans.Advection: div_Uc
using Oceananigans.Units: day
using Oceananigans.Fields: CenterField
using Oceananigans.Biogeochemistry: biogeochemical_drift_velocity, biogeochemical_advection_scheme

import Oceananigans.Biogeochemistry: update_tendencies!

abstract type AbstractSediment end
abstract type FlatSediment <: AbstractSediment end

sediment_fields(::AbstractSediment) = ()

include("coupled_timesteppers.jl")

function update_tendencies!(bgc::ContinuousFormBiogeochemistry{<:Any, <:FlatSediment}, model)
    arch = model.grid.architecture

    events = []

    sediment = bgc.sediment_model

    for (i, tracer) in enumerate(sediment_tracers(sediment))    
        field_event = launch!(arch, model.grid, :xy, store_sediment_tendencies!, sediment.tendencies.Gⁿ[i], sediment.tendencies.G⁻[i], dependencies = device_event(arch))

        push!(events, field_event)
    end

    wait(device(model.architecture), MultiEvent(Tuple(events)))

    event = launch!(arch, model.grid, :xy,
                    calculate_tendencies!,
                    bgc.sediment_model, bgc, model,
                    dependencies = device_event(arch))

    wait(device(arch), event)
    return nothing
end

@kernel function store_sediment_tendencies!(G⁻, G⁰)
    i, j = @index(Global, NTuple)
    @inbounds G⁻[i, j, 1] = G⁰[i, j, 1]
end

struct Soetaert{FT, P1, P2, P3, P4, F, TE} <: FlatSediment
    fast_decay_rate :: FT
    slow_decay_rate :: FT

    fast_redfield :: FT
    slow_redfield :: FT

    fast_fraction :: FT
    slow_fraction :: FT
    refactory_fraction :: FT

    nitrate_oxidation_params :: P1
    denitrifcaiton_params :: P2
    anoxic_params :: P3
    solid_dep_params :: P4

    fields :: F
    tendencies :: TE
end

function Soetaert(grid; 
                  fast_decay_rate::FT = 2/day,
                  slow_decay_rate::FT = 0.2/day,
                  fast_redfield::FT = 0.1509,
                  slow_redfield::FT = 0.13,
                  fast_fraction::FT = 0.74,
                  slow_fraction::FT = 0.26,
                  refactory_fraction::FT = 0.1,
                  nitrate_oxidation_params::P1 = (A = - 1.9785, B = 0.2261, C = -0.0615, D = -0.0289, E = - 0.36109, F = - 0.0232),
                  denitrifcaiton_params::P2 = (A = - 3.0790, B = 1.7509, C = 0.0593, D = - 0.1923, E = 0.0604, F = 0.0662),
                  anoxic_params::P3 = (A = - 3.9476, B = 2.6269, C = - 0.2426, D = -1.3349, E = 0.1826, F = - 0.0143),
                  depth = 100,
                  solid_dep_params::P4 = (A = 0.233, B = 0.336, C = 982, D = - 1.548, depth = depth)) where {FT, P1, P2, P3, P4}

    @warn "Sediment models are an experimental feature and have not yet been validated"

    tracer_names = (:C_slow, :C_fast, :N_slow, :N_fast, :C_ref, :N_ref)

    fields = NamedTuple{tracer_names}(Tuple(CenterField(grid; indices = (:, :, 1)) for tracer in tracer_names))
    tendencies = (Gⁿ = NamedTuple{tracer_names}(Tuple(CenterField(grid; indices = (:, :, 1)) for tracer in tracer_names)),
                  G⁻ = NamedTuple{tracer_names}(Tuple(CenterField(grid; indices = (:, :, 1)) for tracer in tracer_names)))

    F = typeof(fields)
    TE = typeof(tendencies)

    return Soetaert{FT, P1, P2, P3, P4, F, TE}(fast_decay_rate, slow_decay_rate,
                                               fast_redfield, slow_redfield,
                                               fast_fraction, slow_fraction, refactory_fraction,
                                               nitrate_oxidation_params,
                                               denitrifcaiton_params,
                                               anoxic_params,
                                               solid_dep_params,
                                               fields,
                                               tendencies)
end

sediment_tracers(::Soetaert) = (:C_slow, :C_fast, :C_ref, :N_slow, :N_fast, :N_ref)
sediment_fields(model::Soetaert) = (C_slow = model.fields.C_slow, C_fast = model.fields.C_fast, N_slow = model.fields.N_slow, N_fast = model.fields.N_fast, C_ref = model.fields.C_ref, N_ref = model.fields.N_ref)

@kernel function calculate_tendencies!(sediment::Soetaert, bgc, model)
    i, j = @index(Global, NTuple)

    carbon_deposition = div_Uc(i, j, 1, model.grid, biogeochemical_advection_scheme(bgc, Val(:sPOC)), biogeochemical_drift_velocity(bgc, Val(:sPOC)), model.tracers.sPOC) + 
                        div_Uc(i, j, 1, model.grid, biogeochemical_advection_scheme(bgc, Val(:bPOC)), biogeochemical_drift_velocity(bgc, Val(:bPOC)), model.tracers.bPOC)
                        
    nitrogen_deposition = div_Uc(i, j, 1, model.grid, biogeochemical_advection_scheme(bgc, Val(:sPON)), biogeochemical_drift_velocity(bgc, Val(:sPON)), model.tracers.sPON) + 
                          div_Uc(i, j, 1, model.grid, biogeochemical_advection_scheme(bgc, Val(:bPON)), biogeochemical_drift_velocity(bgc, Val(:bPON)), model.tracers.bPON)

    @inbounds begin
        # rates
        Cᵐⁱⁿ = sediment.fields.C_slow[i, j, 1] * sediment.slow_decay_rate + sediment.fields.C_fast[i, j, 1] * sediment.fast_decay_rate
        Nᵐⁱⁿ = sediment.fields.N_slow[i, j, 1] * sediment.slow_decay_rate + sediment.fields.N_fast[i, j, 1] * sediment.fast_decay_rate
        
        k = Cᵐⁱⁿ * day / (sediment.fields.C_slow[i, j, 1] + sediment.fields.C_fast[i, j, 1])

        # sediment evolution
        sediment.tendencies.Gⁿ.C_slow[i, j, 1] = (1 - sediment.refactory_fraction) * sediment.slow_fraction * carbon_deposition - sediment.slow_decay_rate * sediment.fields.C_slow[i, j, 1]
        sediment.tendencies.Gⁿ.C_fast[i, j, 1] = (1 - sediment.refactory_fraction) * sediment.fast_fraction * carbon_deposition - sediment.slow_decay_rate * sediment.fields.C_fast[i, j, 1]
        sediment.tendencies.Gⁿ.C_ref[i, j, 1] = sediment.refactory_fraction * carbon_deposition

        sediment.tendencies.Gⁿ.N_slow[i, j, 1] = (1 - sediment.refactory_fraction) * sediment.slow_fraction * nitrogen_deposition - sediment.slow_decay_rate * sediment.fields.N_slow[i, j, 1]
        sediment.tendencies.Gⁿ.N_fast[i, j, 1] = (1 - sediment.refactory_fraction) * sediment.fast_fraction * nitrogen_deposition - sediment.slow_decay_rate * sediment.fields.N_fast[i, j, 1]
        sediment.tendencies.Gⁿ.N_ref[i, j, 1] = sediment.refactory_fraction * nitrogen_deposition

        # efflux/influx
        O₂ = model.tracers.O₂[i, j, 1]
        NO₃ = model.tracers.NO₃[i, j, 1]
        NH₄ = model.tracers.NH₄[i, j, 1]

        pₙᵢₜ = exp(sediment.nitrate_oxidation_params.A + 
                   sediment.nitrate_oxidation_params.B * log(Cᵐⁱⁿ * day) * log(O₂) + 
                   sediment.nitrate_oxidation_params.C * log(Cᵐⁱⁿ * day) ^ 2 + 
                   sediment.nitrate_oxidation_params.D * log(k) * log(NH₄) + 
                   sediment.nitrate_oxidation_params.E * log(Cᵐⁱⁿ * day) + 
                   sediment.nitrate_oxidation_params.F * log(Cᵐⁱⁿ * day) * log(NH₄)) / (Nᵐⁱⁿ * day)
                   
        pᵈᵉⁿⁱᵗ = exp(sediment.denitrifcaiton_params.A + 
                     sediment.denitrifcaiton_params.B * log(Cᵐⁱⁿ * day) + 
                     sediment.denitrifcaiton_params.C * log(NO₃) ^ 2 + 
                     sediment.denitrifcaiton_params.D * log(Cᵐⁱⁿ * day) ^ 2 + 
                     sediment.denitrifcaiton_params.E * log(k) ^ 2 + 
                     sediment.denitrifcaiton_params.F * log(O₂) * log(k)) / (Cᵐⁱⁿ * day)

        pₐₙₒₓ = exp(sediment.anoxic_params.A + 
                    sediment.anoxic_params.B * log(Cᵐⁱⁿ * day) + 
                    sediment.anoxic_params.C * log(Cᵐⁱⁿ * day) ^ 2 + 
                    sediment.anoxic_params.D * log(k) + 
                    sediment.anoxic_params.E * log(O₂) * log(k) + 
                    sediment.anoxic_params.F * log(NO₃) ^ 2) / (Cᵐⁱⁿ * day)

        pₛₒₗᵢ = sediment.solid_dep_params.A * (sediment.solid_dep_params.C * sediment.solid_dep_params.depth ^ sediment.solid_dep_params.D) ^ sediment.solid_dep_params.B

        model.timestepper.Gⁿ.NH₄[i, j, 1] += Nᵐⁱⁿ * (1 - pₙᵢₜ)
        model.timestepper.Gⁿ.NO₃[i, j, 1] += Nᵐⁱⁿ * pₙᵢₜ - Cᵐⁱⁿ * pᵈᵉⁿⁱᵗ * 0.8
        model.timestepper.Gⁿ.DIC[i, j, 1] += Cᵐⁱⁿ
        model.timestepper.Gⁿ.O₂[i, j, 1] -= (1 - pᵈᵉⁿⁱᵗ - pₐₙₒₓ * pₛₒₗᵢ) * Cᵐⁱⁿ
    end
end

end # module