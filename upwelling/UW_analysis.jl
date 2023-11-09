using JLD2

# Load the output file
output_file_path = "eady_turbulence_bgc.jld2"
output_data = load(output_file_path)

# Extract variables of interest
ζ = output_data["ζ"]
P = output_data["P"]
NO₃ = output_data["NO₃"]
NH₄ = output_data["NH₄"]
DIC = output_data["DIC"]

# You can now perform analysis on these variables as needed.
