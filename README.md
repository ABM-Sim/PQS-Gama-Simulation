[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23859766.svg)](https://doi.org/10.5281/zenodo.23859766)

# PQS-Gama-Simulation

Agent-based model (GAMA platform, BDI architecture) of the diffusion of post-quantum-safe (PQS)
encryption across a heterogeneous market of organisations, with a focus on the position of small
and medium-sized enterprises (SMEs). The model implements the concept by Schindler and
Dubberstein (2023) and extends it with a single government actor, type-differentiated starting
inertia and outdegree-weighted market pressure.

Current model version: **v2.28** (`models/bdi-hierarchy-reworked_v2.28.gaml`). The full version
history and an overview of all equations, parameters and output files are in the header of the
model file.

## Requirements

- GAMA 2025.6.4 (other versions untested)
- The `includes/` folder of this repository (network shapefiles and agent icons)

## Repository structure

```
models/      GAML model (one file)
includes/    shapefiles (agent positions) and icons used by the model
headless/    experiment plans (XML) for headless batch execution
```

## Running the model

**Interactive:** import the project into GAMA and run the experiment `Agent_Model`.

**Batch (headless), Windows:**

```
cd <GAMA installation>\headless
gama-headless.bat -hpc 1 <path>\headless\plan_scenario1_baseline_and_calibration.xml <output folder>
```

The plans reference the model as `../models/bdi-hierarchy-reworked_v2.28.gaml`. If GAMA reports
that it cannot find the model, replace `sourcePath` in the plan with the absolute path to the
model file.

Recommended GAMA preferences (Parallelism):
- "Allow experiments to run simulations in parallel" = Yes
- "In batch, allow to run simulations with all available processors" = No

Very long single headless sessions (more than ~12 hours) have produced native JVM crashes.
The suite is therefore split into several plans:

| Plan | Experiments | Content |
|---|---|---|
| `plan_scenario1_baseline_and_calibration.xml` | 27 | Scenario 1 baseline, 1B high-resolution curve, 1C constant sweep, 1D/1E/1F starting inertia, 1G government check, 1H market-pressure diagnostic |
| `plan_scenario1i_ensemble.xml` | 20 | 20 independent baseline invocations (path-dependence analysis) |
| `plan_scenario2_improved_runs.xml` | 9 | cost x knowledge weights |
| `plan_scenario3_government.xml` | 3 | government subsidy and desire weights |
| `plan_scenario4_topdown.xml` | 1 | top-down influence (hub companies) |
| `plan_scenario5_bottomup.xml` | 1 | bottom-up influence (eager small adopters) |
| `plan_scenario6_sensitivity.xml` | 27 | one-factor-at-a-time weight sensitivity |
| `plan_scenario7_interaction.xml` | 16 | government x top-down / bottom-up |
| `plan_everything.xml` | 104 | all of the above |

## Output files

Every batch experiment writes, prefixed with the model version:

| File | Content |
|---|---|
| `<name>.csv` | periodic trajectory log (every 5 cycles by default) |
| `<name>_milestones.csv` | cycle at which 5/10/20/35/50/60/75/80/90/95/97/99/100 % of all organisations had adopted (one row per replicate) |
| `<name>_group_milestones.csv` | the same checkpoints, separately for SMEs (business_small + startup_it) and large organisations (enterprise + enterprise_medium) |
| `<name>_finecurve.csv` | first cycle for every 1 % adoption step (one row per replicate) |

Notes for analysis:
- Take completion times from the milestone files, not from the last row of the trajectory log.
  In batch mode GAMA does not always stop a replicate immediately when its `until:` condition is
  met, so the trajectory log can continue past completion.
- Every replicate writes its own header row; remove repeated header rows when combining files
  (e.g. `df = df[df["seed"] != "seed"]` in pandas).
- The list column of `_finecurve.csv` is written unquoted. Split each line only on the first five
  commas (`line.split(",", 5)`) and parse the last field as a list.
- Within one experiment, replicates can tip consistently towards one group finishing first
  (path dependence through the shared market-pressure signal). Compare groups across independent
  invocations (Scenario 1I) rather than relying on a single pooled mean.

## Citation

If you use this model, please cite it using the metadata in `CITATION.cff`.

## Reference

Schindler, P., Dubberstein, D., 2023. Concept of an agent-based simulation of the spread of
quantum computer-safe encryption measures. 15th International Conference on Humanities,
Psychology and Social Sciences, March 2023.
