
# Hot bubble rising through a quiet ocean. Tests vertical momentum and NonhydrostaticModel

using Oceananigans

N = Nx = Ny = Nz = 128   # Number of grid points in each dimension.
L = Lx = Ly = Lz = 256  # Length of each dimension.
topology = (Periodic, Periodic, Bounded)
grid = RectilinearGrid(topology=topology, size=(Nx, Ny, Nz), extent=(Lx, Ly, Lz))

model = NonhydrostaticModel(grid = grid, buoyancy=SeawaterBuoyancy(), tracers=(:T, :S));

# Set a temperature perturbation with a Gaussian profile located at the center.
# This will create a buoyant thermal bubble that will rise with time.
x₀, z₀ = Lx/2, Lz/2
T₀(x, y, z) = 20 + 0.01 * exp(-100 * ((x - x₀)^2 + (z - z₀)^2) / (Lx^2 + Lz^2))
set!(model, T=T₀)

simulation = Simulation(model, Δt=10, stop_iteration=5000)
run!(simulation)