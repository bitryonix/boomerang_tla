# Boomerang TLA+ Workspace

This repository is a formal-specification workspace for the Boomerang withdrawal protocol. It is not an application repository or a Rust workspace. The current artifacts are a large English state-machine specification, a first TLA+ model slice for the withdrawal core, a TLC model configuration, and a bundled copy of the TLA+ tools JAR.

This README is meant to make the repository easier to navigate without changing any existing source artifacts.

> **Important:** This repository is a work in progress. It does **not** contain a final, canonical, or complete formal model of the Boomerang protocol. Nothing here should be treated as the definitive specification, a completed verification artifact, or proof that the protocol has been fully modeled or fully checked.

## Repository Map

The repository is organized in three layers:

1. Narrative specification
2. Formal model
3. Model-checking toolchain

Current files:

| Path | Role |
| --- | --- |
| `docs/boomerang_authoritative_state_machine_spec.md` | The current long-form English working specification. Within this repository, it is the main narrative reference for actor roles, variables, states, transitions, trust assumptions, failure modes, and modeling guidance. |
| `spec/BoomerangWithdrawalCore.tla` | The first formal TLA+ slice of the withdrawal core. It starts after setup, assumes the milestone has already been reached, and ends at `ReadyToSign`. |
| `spec/MC_BoomerangWithdrawalCore.cfg` | TLC configuration for the current `BoomerangWithdrawalCore` model. |
| `tools/tla2tools.jar` | Bundled TLC / TLA+ command-line tooling. |

## What This Repository Models

The current formalization focuses on the distinctive part of the protocol: the boomerang-regime withdrawal ceremony.

The modeled slice starts after setup, with inherited setup state already fixed:

- `boomerang_params` are fixed
- each peer already has its `duress_consent_set_i`, `doxing_key_i`, and `mystery_i`
- `milestone_block_0` has already been reached
- the initiator is about to submit a PSBT

The TLA+ model then covers:

- local `tx_id` fixation
- all-peer approval collection
- the initial duress check
- initiator / non-initiator commitment asymmetry
- the WT-coordinated digging game
- the all-peers-reached break condition
- transition to `ReadyToSign`

The model intentionally abstracts cryptography, QR transport, and byte-level message encoding into symbolic values and guards.

## What Is Not Yet Modeled

The current repository does not yet formalize the full protocol lifecycle. In particular, the present TLA+ slice does not try to model:

- setup from first principles
- deterministic fallback spending
- detailed Bitcoin mempool / mining behavior
- SAR’s off-protocol real-world rescue process
- ancillary operational procedures such as switching WT, changing devices, or activating `Boomletwo`
- the signing, broadcast, and post-broadcast recovery details beyond the `ReadyToSign` boundary

## Read This Repository In This Order

1. Start with `docs/boomerang_authoritative_state_machine_spec.md`.
   It explains the actor catalog, system boundaries, variable inventory, composite states, transitions, progress conditions, and unresolved design questions.
2. Then read `spec/BoomerangWithdrawalCore.tla`.
   This is the executable formal slice derived from the narrative spec.
3. Then inspect `spec/MC_BoomerangWithdrawalCore.cfg`.
   This shows the current finite model used for TLC exploration.

## The Most Important Narrative Sections

If you do not want to read the full English spec front to back, these sections are the highest leverage:

- Section 1: protocol intent and scope
- Section 4: actor catalog
- Section 5: system boundaries and trust assumptions
- Section 6: state variable catalog
- Section 7: setup and withdrawal flow breakdown
- Section 10: per-actor machines
- Section 11: transitions
- Section 15: failure handling and gaps
- Section 18: TLA+ guidance, especially the recommended first slice

## What The TLA+ Module Checks

`spec/BoomerangWithdrawalCore.tla` defines a safety-oriented base spec:

- `Spec == Init /\\ [][Next]_vars`
- an optional fairness-augmented variant `SpecWF`
- safety invariants such as `TypeOK`, `TxIdFrozen`, `NoEarlySigning`, `PlaceholderAuthentic`, `WTBreakConditionCorrect`, and `PostDuressNoRevert`
- temporal properties such as `ReachedFlagsMonotone`, `ReachedCollectionsMonotone`, `CounterMonotone`, and `PingSeqStrictAfterFirst`

One especially important surrogate property is `ObservationalConsistencySurrogate`, which encodes the design intent that duress and non-duress executions should not diverge in observable protocol flow at the modeled boundary.

## Running TLC

The repository includes a local `tools/tla2tools.jar`, so you can run TLC directly if Java is installed.
For a one-shot local run, pass `-workers auto` to let TLC use all available cores.

Example:

```bash
java -jar tools/tla2tools.jar -workers auto -config spec/MC_BoomerangWithdrawalCore.cfg spec/BoomerangWithdrawalCore.tla
```

If you want TLC metadata out of the repository tree, use a temporary metadir:

```bash
META=$(mktemp -d /tmp/boomerang-tlc.XXXXXX)
java -jar tools/tla2tools.jar -workers auto -config spec/MC_BoomerangWithdrawalCore.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

If you want a run to be recoverable later, prefer an explicit worker count instead of `auto`, and use the same `-workers` value again when resuming with `-recover`.
TLC writes per-worker checkpoint files such as `BoomerangWithdrawalCore-0.chkpt`, so changing worker count between the original run and the recovery run can fail with missing `BoomerangWithdrawalCore-<n>.chkpt` files.

Example recoverable run:

```bash
java -jar tools/tla2tools.jar -workers 10 -config spec/MC_BoomerangWithdrawalCore.cfg spec/BoomerangWithdrawalCore.tla
```

Example recovery of that same run:

```bash
java -jar tools/tla2tools.jar -workers 10 -recover states/26-03-25-00-00-41 -config spec/MC_BoomerangWithdrawalCore.cfg spec/BoomerangWithdrawalCore.tla
```

## Current Verification Status

Java and the bundled TLA+ tools are present in this workspace, and the current TLC configuration now parses and starts model checking successfully.

Observed result on March 24, 2026:

- Java: OpenJDK 24.0.2
- TLC: version 2.19 dated August 8, 2024
- `spec/MC_BoomerangWithdrawalCore.cfg` parses successfully
- `spec/BoomerangWithdrawalCore.tla` parses and semantically processes successfully
- TLC computes initial states and explores the state space under the bundled command
- A review run progressed into multi-million-state exploration before being stopped manually
- No completed exhaustive TLC result is claimed by this README yet

Inside restricted sandboxes, TLC may still fail before exploration if Java is not allowed to open the local socket it uses during startup. That is an execution-environment issue, not a current parse error in the model or cfg.

That means the repository now contains a runnable in-progress formal model and TLC harness, but not yet a recorded completed end-to-end verification result in this README.

## Suggested Mental Organization For Future Work

With the current layout in place, it is useful to think about future work in three tracks:

- `Narrative spec`
  Refine the English state-machine document, close unresolved issues, and keep trust boundaries explicit.
- `Formal model`
  Extend the current TLA+ slice from withdrawal-core safety toward larger protocol coverage.
- `Executable checks`
  Keep TLC configs small and explicit, separate safety runs from fairness / progress runs, and record which bounds and assumptions were used for each result.

## Current State Of The Repository

Today this repository is best understood as:

- a protocol-design workspace
- a formalization-in-progress
- a small, focused TLA+ sandbox centered on withdrawal-core behavior

If you are new to the project, begin with the English specification, use the TLA+ file to see which variables and invariants have already been made executable, and treat the TLC config as a draft model harness that still needs cleanup before results should be trusted.

## TLA+ Slice Status

This `BoomerangWithdrawalCore` slice is an in-progress working model. It is useful for post-setup-through-`ReadyToSign` safety exploration, but it is **not** a final, canonical, or complete formal model of the Boomerang protocol.

This revision cleans up the first formal `BoomerangWithdrawalCore` slice so it is SANY-clean and TLC-hygienic for the intended safety-focused model, while preserving the protocol boundary and intended semantics from post-setup through `ReadyToSign`.

### What Was Done

- Preserved the slice boundary exactly: start after setup, end at `ReadyToSign`, with no signing, export, or broadcast steps added.
- Preserved the load-bearing protocol semantics:
  - fixed `tx_id` semantics
  - all-approval collection before commit distribution
  - initial duress check
  - initiator/non-initiator commitment asymmetry
  - SAR placeholder roundtrip
  - monotonic digging-game updates
  - WT break only when a reached ping exists for every peer
  - readiness to sign only after `reached_pings_collection` and a hydrated PSBT with the same `tx_id`
- Reworked helper predicates and message guards so TLC no longer depends on infinite record-set membership through `Nat`-typed fields such as heights and sequence numbers.
- Tightened `TypeOK` so it checks pointwise well-formedness of explicit message variables instead of forcing TLC to enumerate large or infinite record spaces.
- Kept all explicit protocol variables explicit. No hidden load-bearing state was introduced.
- Added cfg-only helper operators for complex constant construction. These are not protocol state:
  - they are operators, not variables
  - they do not appear in `VARIABLES` or `vars`
  - they do not evolve across steps
- Slightly improved the observational-consistency surrogate by including visible `last_seen_block` evolution.
- Kept ambiguity handling explicit by extending the provisional decision register instead of silently resolving modeling choices.
- Updated the TLC cfg to suppress deadlock checking for the bounded-height safety model, because finite timeout-only stalls can otherwise appear as deadlocks before a success-path action fires.

### Updated Provisional Decision Register

- `PDR-01 / ACR-03`: duress-bearing placeholders are modeled on commits, pings, and the SAR acknowledgment roundtrip, not on approval families.
- `PDR-02 / ACR-05`: positive duress latches for the remainder of the ceremony.
- `PDR-03 / ACR-08`: freshness and lag bounds remain symbolic parameters.
- `PDR-04 / ACR-09`: non-duress placeholder plaintext is modeled as `ZeroPad`.
- `PDR-05 / ACR-10`: the WT approval uses canonical field name `initiator` in this abstraction.
- `PDR-06 / ACR-12`: malformed-SAR branches remain out of scope.
- `PDR-07 / ACR-14`: ST-mediated local checks remain abstract environment choices constrained by the consent-set rule.
- `PDR-08 / MODEL-01`: the default TLC cfg suppresses deadlock checking for the bounded `BlockHeights` model so timeout-only stalls do not mask this safety slice; deadlock and liveness should be revisited in a dedicated progress model.

### Remaining Risks

- Full TLC exhaustion has not yet completed; the model explores a large state space, so a late counterexample is still possible.
- Deadlock checking is intentionally disabled in the current cfg for this bounded safety model. A separate progress/liveness run is still needed.
- The bounded `BlockHeights` model is useful for safety checking, but it can under-approximate behaviors tied to longer freshness windows or delayed progress.
- The structural well-formedness predicates assume message variables contain either `NoMessage` or properly kind-tagged symbolic records. If message domains are widened later, those predicates should be revisited.
- `WTStates` still contains control-state surface area that is broader than the currently exercised transition subset, which is harmless for this slice but worth tightening later if a stricter control-state model is desired.
