import glob

# Each analysis lists its outputs here, mirroring get_inputs_<name>() in scripts/inputs.py,
# for example:
#   example_results = ["results/example/summary.csv"]
#   example_figures = ["figures/example/summary.svg"]
results_paths = []
figure_paths = []

# Globbed rather than listed by hand: every package module is an input to every analysis, and
# an omission here silently stops results being rebuilt when that module changes.
package_paths = sorted(glob.glob("src/analysis_template/*.py"))
shared_input_paths = package_paths + ["scripts/inputs.py"]


rule all:
    input:
        figure_paths,


rule results:
    input:
        results_paths,


# Each analysis gets a pair of rules, for example:
#
# rule example_results:
#     input:
#         shared_input_paths,
#         "scripts/example.py",
#         "data/example.csv",
#     output:
#         example_results,
#     shell:
#         "pixi run python -m scripts.example -r"
#
#
# rule example_plots:
#     input:
#         shared_input_paths,
#         "scripts/example_plots.py",
#         example_results,
#     output:
#         example_figures,
#     shell:
#         "pixi run python -m scripts.example_plots"
