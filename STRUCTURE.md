# Code structure guide

How to lay out a research analysis repo so that one command reproduces every result and
figure. It follows the structure of `idm-demo-repo`: a library package in `src/`, analysis
and plotting script pairs in `scripts/`, a LaTeX document of each analysis's mathematics in
`docs/`, and a Snakemake workflow joining them up.

Placeholders: `<pkg>` is the library package (for example `pmo`), and `<name>` is one
analysis (for example `outbreak_risk`). In the code skeletons, the analysis is called
`example`.

## 1. Layout

```
pyproject.toml      # dependencies, pixi tasks, ruff and pytest config
pixi.lock           # exact dependency versions (committed)
Snakefile           # the reproduction pipeline: the single source of truth
src/<pkg>/          # library package: reusable, tested code
  __init__.py       #   re-exports the public API in __all__
  <module>.py       #   one topic per module
scripts/            # a package at the repo root, not under src/
  __init__.py
  inputs.py         #   get_inputs_<name>() for every analysis
  <name>.py         #   heavy compute → results/<name>/*.csv
  <name>_plots.py   #   reads those CSVs → figures/<name>/*.svg and *.png
docs/               # the mathematics of each analysis
  <name>.tex        #   model, likelihood, estimators, plotted quantities
  <name>.pdf        #   built from <name>.tex by Snakemake (committed)
tests/              # top-level pytest suite
  conftest.py       #   shared fixtures
  test_<module>.py  #   one per package module
  test_public_api.py
data/               # inputs (raw data, published estimates)
results/<name>/     # generated numerical outputs (committed)
figures/<name>/     # generated figures (committed)
notebooks/          # optional: exploration only, never part of the pipeline
```

## 2. The library package (`src/<pkg>/`)

### Setup

- **src layout, installed editable.** In `pyproject.toml`:
  `[tool.pixi.pypi-dependencies] <pkg> = { path = ".", editable = true }`. Edits take effect
  without reinstalling.
- **`__init__.py` defines the public API.** It imports the public names from each module and
  lists them in `__all__`. `tests/test_public_api.py` asserts the exact set, so any change to
  the exports updates both files in the same change.

```python
# src/<pkg>/__init__.py
from <pkg>.data import CaseData, load_cases, prepare_cases
from <pkg>.models import Model, seir_model

__all__: list[str] = ["CaseData", "Model", "load_cases", "prepare_cases", "seir_model"]
```

### Modules

- **One topic per module**, for example: data loading and preparation, models, likelihood,
  inference, simulation.
- **Imports run one way, with no cycles.** For example: `data` and `models` are used by
  `likelihood`, which is used by `inference`. If two modules need each other, the shared part
  belongs in a third.
- **Order within a module:** the docstring (what the module covers, units and conventions),
  then public classes and functions, then `_private` helpers.
- The package contains no file paths, figure code or analysis-specific parameter values; those
  go in `scripts/`.

### When to use a class

Classes hold data or bundle a model. All other code is plain functions; a module already
groups related functions.

**Prepared data: a `NamedTuple` of arrays**, built by a `prepare_*` function from a tidy
DataFrame. Loading and cleaning (`load_*`) stays separate from flattening to arrays
(`prepare_*`), so the cleaned table can be inspected and tested on its own.

```python
class CaseData(NamedTuple):
    """Case data as flat arrays, ready for the likelihood."""

    onset_day: np.ndarray  # per-case: day of symptom onset
    group: np.ndarray  # per-case: group index (0, ..., G - 1)
    group_size: np.ndarray  # per-group: number of members


def load_cases(path: str | Path, *, min_age: float) -> pd.DataFrame:
    """Load the raw spreadsheet as a tidy table, applying study exclusions."""


def prepare_cases(df: pd.DataFrame) -> CaseData:
    """Flatten the tidy table into arrays."""
```

**A model: one frozen dataclass and a factory function per variant.** The dataclass holds
everything the fitting and summary code needs (parameter names, priors, the model's
functions). Each factory takes the fixed parameters and priors as keyword-only arguments and
returns an instance. Variants are factories, not subclasses, so the inference code handles
every model the same way.

```python
@dataclass(frozen=True, eq=False)
class Model:
    """A model, with its priors and derived summaries."""

    param_names: tuple[str, ...]
    log_prior: Callable[[Params], float]
    log_likelihood: Callable[[Params, CaseData], float]
    summaries: Callable[[Params], Params]


def seir_model(*, latent_mean: float, beta_prior: tuple[float, float]) -> Model:
    """SEIR model with a fixed latent period; beta has a lognormal prior (log mean, log sd)."""

    def log_prior(params): ...
    def log_likelihood(params, data): ...
    def summaries(params): ...

    return Model(("beta", "gamma"), log_prior, log_likelihood, summaries)
```

**Fit or simulation output: a `NamedTuple`.**

```python
class FitResult(NamedTuple):
    """Posterior draws, each of shape (n_chains, n_draws)."""

    params: dict[str, np.ndarray]
    log_likelihood: np.ndarray
```

## 3. The scripts (`scripts/`)

### Running

Run scripts **as modules from the repo root**:

```bash
pixi run python -m scripts.<name>        # compute and plot
pixi run python -m scripts.<name> -r     # compute only
pixi run python -m scripts.<name>_plots  # plot from saved results
```

Never `python scripts/<name>.py`: the editable install puts only `src/` on `sys.path`, so
`from scripts.inputs import ...` fails when a script is run by path.

### `scripts/inputs.py`: every input in one place

Each analysis has a `get_inputs_<name>()` returning a dict with the prepared data, models,
settings (including random seeds), `results_paths` and `fig_paths`. It's the only place
file paths and parameter values are written. Both scripts in a pair call it, so they always
agree on where the results are.

```python
"""Inputs for each analysis: data, model settings and output paths."""

from pathlib import Path

from <pkg> import load_cases, prepare_cases, seir_model

DATA_DIR = Path("data")
RESULTS_DIR = Path("results")
FIGURES_DIR = Path("figures")


def get_inputs_example() -> dict:
    """Inputs for fitting the SEIR model to the case data (cite the source of values here)."""
    results_dir = RESULTS_DIR / "example"
    return {
        "case_data": prepare_cases(load_cases(DATA_DIR / "cases.csv", min_age=16)),
        "model": seir_model(latent_mean=5.0, beta_prior=(0.0, 1.0)),
        "settings": {"seed": 2026, "n_draws": 1000},
        "results_paths": {
            "posterior": results_dir / "posterior.csv",
            "summary": results_dir / "summary.csv",
        },
        # Figure paths have no suffix: each figure is saved as both .svg and .png.
        "fig_paths": {"posterior": FIGURES_DIR / "example" / "posterior"},
    }
```

### `scripts/<name>.py`: the compute

The analysis script never imports scienceplots or sets a plot style; that belongs only in
the plot script.

```python
"""Fit the SEIR model to the case data and summarise the posterior."""

import argparse

import pandas as pd

from <pkg> import fit_model
from scripts.example_plots import make_plots
from scripts.inputs import get_inputs_example


def run_analyses(results_only: bool = False) -> None:
    """Fit the model and write posterior draws and summaries."""
    inputs = get_inputs_example()
    paths = inputs["results_paths"]
    result = fit_model(inputs["model"], inputs["case_data"], **inputs["settings"])
    posterior = _posterior_table(result)

    paths["posterior"].parent.mkdir(parents=True, exist_ok=True)
    posterior.to_csv(paths["posterior"], index=False)
    _summarise(posterior).to_csv(paths["summary"], index=False)

    if not results_only:
        make_plots()


def _posterior_table(result) -> pd.DataFrame: ...


def _summarise(posterior: pd.DataFrame) -> pd.DataFrame: ...


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-r", "--results-only", action="store_true", help="skip making the figures"
    )
    run_analyses(results_only=parser.parse_args().results_only)
```

### `scripts/<name>_plots.py`: the figures

```python
"""Plot the posterior of the SEIR model parameters (maths in docs/example.tex)."""

import matplotlib as mpl
import matplotlib.pyplot as plt
import pandas as pd
import scienceplots  # noqa: F401

from scripts.inputs import get_inputs_example

plt.style.use(["science", "notebook", "no-latex"])
mpl.rcParams.update({
    "axes.spines.top": False,
    "axes.spines.right": False,
    "xtick.top": False,
    "ytick.right": False,
    "xtick.minor.visible": False,
    "ytick.minor.visible": True,
})

_COLOURS = {"beta": "#0072BD", "gamma": "#D95319"}


def make_plots() -> None:
    """Histograms of the posterior draws of each parameter."""
    inputs = get_inputs_example()
    posterior = pd.read_csv(inputs["results_paths"]["posterior"])
    fig, axes = plt.subplots(1, len(_COLOURS), layout="constrained")
    for ax, (param, colour) in zip(axes, _COLOURS.items()):
        ax.hist(posterior[param], color=colour)
        ax.set(xlabel=param)

    path = inputs["fig_paths"]["posterior"]
    path.parent.mkdir(parents=True, exist_ok=True)
    for suffix in (".svg", ".png"):
        fig.savefig(path.with_suffix(suffix), dpi=300)
    plt.close(fig)


if __name__ == "__main__":
    make_plots()
```

### Script rules

- Each script has **one public entry point** (`run_analyses` or `make_plots`) at the top.
  Every other function is `_private` and goes below it.
- **Plot scripts only read saved results**, and never recompute. This means you can restyle a
  figure without rerunning the fit.
- A helper that does a general task (not one analysis's step) and is used across scripts
  moves into the package. Don't factor out a one-liner just because it repeats.
- Outputs go to `results/<name>/<output>.csv` and `figures/<name>/<output>.{svg,png}`. Every
  figure is saved as both SVG and PNG (300 dpi); the LaTeX documents use the PNGs.
- **Plot scripts set the scienceplots style** at the top, after the imports, exactly as in the
  skeleton above. The analysis script never sets it. Keep the style's default font sizes:
  don't set `fontsize`, `labelsize` or font-size rcParams.
- **Scripts don't explain the maths.** No markdown cells (`# %% [markdown]`), long docstrings
  or comment blocks deriving equations; these go in `docs/<name>.tex` (section 4), and a
  short docstring points there.
- If paper figures are put together from per-analysis panels, figure numbers appear only in
  that compile script and the Snakefile, since anywhere else they go stale when figures are
  renumbered.

## 4. The maths documents (`docs/`)

Every analysis comes with a LaTeX document, `docs/<name>.tex`, setting out the mathematics
behind its results and figures: the model, likelihood, priors, estimators and any derived
quantities that are plotted. It replaces the explanatory markdown a notebook would have.

- **Accurate to the code.** Notation and parameter names match the code, and the equations
  describe what the code computes. Update the document in the same change as the code.
- **Figures are included as PNGs**, by paths relative to the `.tex` file.
- **Built by Snakemake** into `docs/<name>.pdf` with tectonic (a self-contained LaTeX engine
  installed by pixi; the first build downloads the LaTeX packages it needs). Never build the
  PDF by hand. The PDF is committed, like `results/` and `figures/`.

```latex
% docs/example.tex
\documentclass{article}
\usepackage{amsmath}
\usepackage{graphicx}

\title{Example: SEIR model fit}
\begin{document}
\maketitle

\section{Model}
With transmission rate $\beta$ and recovery rate $\gamma$ (\texttt{beta}, \texttt{gamma} in
the code),
\begin{align}
  \frac{dS}{dt} &= -\beta S I, &
  \frac{dI}{dt} &= \beta S I - \gamma I.
\end{align}

\section{Posterior}
\begin{figure}[h]
  \centering
  \includegraphics[width=\linewidth]{../figures/example/posterior.png}
  \caption{Posterior draws of $\beta$ and $\gamma$.}
\end{figure}

\end{document}
```

## 5. The Snakefile

The Snakefile is the only way to reproduce the results. Don't add separate reproduction
commands; add them as rules. Every results and plot rule lists all the package modules (by
glob) as inputs, so a change to shared code triggers a rebuild.

```python
import glob

example_results = [
    "results/example/posterior.csv",
    "results/example/summary.csv",
]
example_figures = ["figures/example/posterior.svg", "figures/example/posterior.png"]
example_docs = ["docs/example.pdf"]

results_paths = example_results
figure_paths = example_figures
doc_paths = example_docs

# Globbed so that no module can be left out by mistake.
package_paths = sorted(glob.glob("src/<pkg>/*.py"))
shared_input_paths = package_paths + ["scripts/inputs.py"]


rule all:
    input:
        figure_paths,
        doc_paths,


rule results:
    input:
        results_paths,


rule example_results:
    input:
        shared_input_paths,
        "scripts/example.py",
        "data/cases.csv",
    output:
        example_results,
    shell:
        "pixi run python -m scripts.example -r"


rule example_plots:
    input:
        shared_input_paths,
        "scripts/example_plots.py",
        example_results,
    output:
        example_figures,
    shell:
        "pixi run python -m scripts.example_plots"


rule example_docs:
    input:
        "docs/example.tex",
        "figures/example/posterior.png",  # the PNGs the document includes
    output:
        example_docs,
    shell:
        "pixi run tectonic --outdir docs docs/example.tex"
```

Each analysis has three rules: `<name>_results`, `<name>_plots` and `<name>_docs`. `all`
builds every figure and document; `results` builds only the results files.

If one analysis needs another's results (for example a cleaned dataset or a fitted
posterior), list those results files as inputs of its rule.

## 6. Tests

- A top-level `tests/` folder, with `[tool.pytest.ini_options] testpaths = ["tests"]` and
  `pythonpath = ["."]` so tests can import `scripts` too.
- One `test_<module>.py` per package module. Shared fixtures (such as standard model
  instances) go in `conftest.py`.
- Test files written with AI assistance start with the line
  `# Note that AI tools were used to generate tests`.
- Useful checks: compare against an independent implementation (for example scipy against a
  hand-written density), recover known parameters from simulated data, and check edge cases
  in the data cleaning.
- Change tests when the code improves. Don't bend the code to avoid touching a test.

## 7. Tooling and commands

| Task | Command |
|------|---------|
| Tests | `pixi run test` |
| Format | `pixi run format` (ruff import sort + format) |
| Lint | `pixi run lint` (ruff check) |
| Type check | `pixi run typecheck` (ty check) |
| Full reproduction | `pixi run snakemake --cores N` |
| Results only | `pixi run snakemake --cores N results` |
| What would rerun | `pixi run snakemake -n` |

- Dependencies are declared in `pyproject.toml`, from conda-forge first (`pypi-dependencies`
  only when needed). Dev-only tools go in the `dev` feature. Commit `pixi.lock`. Plotting
  uses `scienceplots`; the pipeline tools `snakemake` and `tectonic` are in `dev`.
- The only ruff config is import sorting (`extend-select = ["I"]`). Leave ruff and ty at their
  defaults otherwise.
- Run format, lint and typecheck after every code change.
- An `AGENTS.md` (with `CLAUDE.md` containing `@AGENTS.md`) records these conventions and
  describes the analyses as they currently exist.

## 8. Converting a notebook

1. **Tag each cell** as one of:
   - reusable logic (loading, cleaning, models, likelihoods, simulators, fitting): goes in
     `src/<pkg>/`
   - hard-coded parameters, file paths, data loading for this analysis: goes in
     `get_inputs_<name>()`
   - the compute that produces numbers: goes in `scripts/<name>.py`, written to CSV
   - figures: go in `scripts/<name>_plots.py`, read from the CSV
   - markdown explaining the maths: goes in `docs/<name>.tex`, checked against what the code
     computes
2. **Find duplicates across notebooks.** Code copied between notebooks (or between an existing
   `*_lib.py` and the notebooks) goes into the package once.
3. **Port one notebook all the way through** before starting another: package code with
   tests, `get_inputs_<name>()`, the script pair, `docs/<name>.tex`, and the three Snakemake
   rules.
4. **Check the outputs against the notebook**: same numbers (to Monte Carlo error, with a
   fixed seed) and the same figures.
5. **Turn shared upstream steps** (for example a cleaned dataset used by several analyses)
   into analyses of their own, and list their results as inputs of the later rules.
6. **Keep notebooks for exploration only** if you still want them. They live in
   `notebooks/`, import from `<pkg>`, and nothing in the pipeline depends on them.
