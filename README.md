# analysis-template

A template for research analysis repos: a library package in `src/analysis_template/`,
analysis and plotting script pairs in `scripts/`, and a [Snakemake](https://snakemake.readthedocs.io/)
workflow that rebuilds every result and figure. [`STRUCTURE.md`](STRUCTURE.md) explains the
layout and conventions, and [`AGENTS.md`](AGENTS.md) records them for coding agents. Adapted
from `idm-demo-repo`.

## Analyses

None yet.

## Installation

We recommend using the [pixi](https://pixi.prefix.dev/) package manager. Once pixi is
installed, running

```bash
pixi install --locked
```

creates a local environment (under `.pixi/`) containing the exact dependency versions
recorded in `pixi.lock`. Prefixing a command with `pixi run` executes it in that environment.

## Reproducing the results

Individual analyses are run as modules of the [`scripts`](scripts/) package from the
repository root, e.g.

```bash
pixi run python -m scripts.<name>
```

Alternatively, the full pipeline for all results and figures can be run with Snakemake:

```bash
pixi run snakemake --cores 1 --forceall
```
