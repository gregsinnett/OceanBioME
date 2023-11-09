import julia
from julia import Main

# Start Julia
Main.eval("using JLD2")

# Load the output file
Main.eval("output_data = load('eady_turbulence_bgc.jld2')")

# Access the variables in Python
zeta = Main.eval("output_data['ζ']")
P = Main.eval("output_data['P']")
NO_3 = Main.eval("output_data['NO₃']")
NH_4 = Main.eval("output_data['NH₄']")
DIC = Main.eval("output_data['DIC']")

# Now you can use these variables in your Python code (e.g., with pandas or xarray)
