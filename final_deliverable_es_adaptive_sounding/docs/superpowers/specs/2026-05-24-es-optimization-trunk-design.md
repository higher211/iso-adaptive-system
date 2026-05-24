# Es Optimization Trunk Lightweight Refactor Design

## Purpose

This design defines the next-stage cleanup for the Es adaptive resounding system after the frequency-window rule has been fixed. The optimizer must no longer search `fStartMHz` or `fEndMHz`. The resounding range is generated before optimization from task mode, initial scan features, IRI background prior, initial scan step, and user margin. NSGA-II then searches only the strategy parameters inside that fixed window.

## Scope

The work stays inside the current trunk MATLAB implementation:

- `code/es_only_adaptive_sounding_system.m`

No large file split is planned in this step. The goal is to make the optimizer path internally consistent, remove stale frequency-window optimization remnants, and verify all task modes.

## Fixed Inputs

The optimization stage receives these values as fixed context:

- `initialCfg`: initial sounding strategy and coarse sweep step.
- `initialFeature`: extracted Es/E-layer features from the initial ionogram.
- `pref.taskMode`: user-selected task mode.
- `target.requiredRangeMHz`: fixed resounding frequency range generated before NSGA-II.

`target.requiredRangeMHz(1)` becomes the only allowed `fStartMHz`, and `target.requiredRangeMHz(2)` becomes the only allowed `fEndMHz`.

## Optimization Variables

NSGA-II may optimize only:

- `dfMHz`
- `PRP`
- `chipLength`
- `Ncoh`
- `codeType` / `codeLength`

The existing internal chromosome may remain seven-dimensional for minimal disruption, but the bounds and repair logic must force `fStartMHz` and `fEndMHz` to the fixed target values. No mutation, crossover, seed strategy, constraint, or final selection should effectively change the frequency window.

## Metrics

Each candidate strategy is evaluated with:

- `scanTimeSec`
- `nFreq`
- `heightResolutionKm`
- `hAmbKm`
- `dutyRatio`
- `integrationGainDb`
- `EsCoverage`
- `observabilityScore`
- `resolutionCost`

These metrics form both the task objective vectors and the constraint checks.

## Constraints

The optimizer should treat these as feasibility or practical-use constraints:

- fixed target window is fully covered
- maximum scan time is not exceeded
- task-specific adaptive scan time is respected
- frequency sample count is sufficient
- Es coverage is sufficient
- integration gain is sufficient
- height ambiguity is safe
- duty ratio is safe
- coded pulse fits inside PRP with guard time
- selected code type and code length match
- `Ncoh` is an integer from the configured search grid

Because the window is fixed, constraints related to aggressive range shrinking should be removed or made inert. They were useful only when `fStartMHz/fEndMHz` participated in optimization.

## Task Objectives

The objective vectors remain task-driven:

- Fast detection: minimize scan time, maximize coverage, maximize observability.
- foEs reading: minimize `dfMHz`, minimize scan time, maximize integration gain.
- h'Es stability: minimize height resolution, minimize scan time, maximize integration gain.
- Weak Es visibility: maximize observability, maximize integration gain, minimize scan time.
- Complete trace: maximize coverage, minimize resolution cost, minimize scan time, maximize observability.
- Balanced: minimize scan time, minimize resolution cost, maximize observability.

The final selected point should come from feasible Pareto candidates whenever possible, then use the task-specific lexicographic sorter as the recommendation rule.

## Cleanup Targets

The refactor should focus on:

- making fixed-window behavior explicit in `nsga2_bounds`, `repair_nsga2_x`, and candidate initialization;
- removing stale non-fixed-window branches that still reference `iriPriorStartFlexMHz` or `iriPriorEndFlexMHz` in the optimizer path;
- removing or neutralizing `maxAggressiveShrinkRatio` logic from optimizer feasibility because the window is not shrinkable;
- simplifying reason-table text so it explains "fixed task window + parameter optimization";
- adding verification output that shows target range and optimized config range are identical.

## Verification

After implementation, run:

- MATLAB syntax/static check on `code/es_only_adaptive_sounding_system.m`.
- One simulation for each task mode: `fast`, `foEs`, `hEs`, `weakEs`, `full_trace`, `balanced`.

For each mode, verify:

- target range is generated before optimization;
- optimized `fStartMHz/fEndMHz` exactly equal `target.requiredRangeMHz`;
- optimizer changes only `dfMHz`, `PRP`, `chipLength`, `Ncoh`, and code choice;
- final strategy satisfies the relevant constraints or reports which constraint prevented full feasibility.

## Out of Scope

This step does not:

- redesign the previously confirmed frequency-window generation rule;
- add blanketing Es logic;
- split the MATLAB trunk into multiple files;
- change IRI background acquisition;
- change initial ionogram feature extraction unless a direct optimizer dependency is broken.
