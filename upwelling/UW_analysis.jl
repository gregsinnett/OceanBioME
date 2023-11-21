using OceanBioME, Oceananigans, Printf
using Oceananigans.Units

# Now load the saved output,
ζ = FieldTimeSeries("eady_turbulence_bgc.jld2", "ζ")
P = FieldTimeSeries("eady_turbulence_bgc.jld2", "P")
NO₃ = FieldTimeSeries("eady_turbulence_bgc.jld2", "NO₃")
NH₄ = FieldTimeSeries("eady_turbulence_bgc.jld2", "NH₄")
DIC = FieldTimeSeries("eady_turbulence_bgc.jld2", "DIC")

times = ζ.times

xζ, yζ, zζ = nodes(ζ)
xc, yc, zc = nodes(P)
nothing #hide

# Get things to plot


# Example plot
using CairoMakie

fig = Figure(resolution = (1000, 1500), fontsize = 20)

axis_kwargs = (xlabel = "Time (days)", ylabel = "z (m)", limits = ((0, times[end] / days), (-100meters, 0)))

axP = Axis(fig[1, 1]; title = "Phytoplankton concentration (mmol N / m³)", axis_kwargs...)
hmP = heatmap!(times / days, zc, interior(P, 1, 1, :, :)', colormap = :batlow)
Colorbar(fig[1, 2], hmP)

fig