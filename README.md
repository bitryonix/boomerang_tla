# Boomerang TLA+ Workspace

This repository is a focused TLA+ workspace centered on `BoomerangWithdrawalCore`.

The current authoritative proof effort is intentionally narrow:

- post-setup only
- withdrawal only
- one active withdrawal session at a time
- PlusCal-first modeling
- exact transcript and binding hygiene around approvals, duress checks, commits, ping/pong coordination, and signed export

It is not yet a full end-to-end proof of the full Boomerang system.

## Current Scope

The main authoritative model is [`spec/BoomerangWithdrawalCore.tla`](spec/BoomerangWithdrawalCore.tla). It starts after setup and models:

- milestone-gated initiator start
- explicit `session_id` and `tx_id` locking
- nonce-bound ST/Boomlet `tx_id` challenge and acknowledgement before approval
- initiator submission and peer approval collection
- initial and recurring nonce-bound duress transcripts
- commit collection with exact `(sid, peer, txid, phase, seq, placeholder_instance)` SAR-ack binding
- WT-coordinated ping/pong rounds with stronger sequence and block-distance checks
- abstract signing-ticket binding, signed-PSBT export, and WT broadcast
- post-broadcast cleanup and reset so sequential withdrawals can be exercised in one run
- deterministic fallback only as a modeled boundary condition, not as a full spend ceremony

This workspace also contains a secondary work-in-progress wire-faithful model at [`spec/withdrawal_wire/BoomerangWithdrawalWire.tla`](spec/withdrawal_wire/BoomerangWithdrawalWire.tla), but that file is not the primary authoritative repo surface.

## Current Proof Boundary

This workspace still does not prove:

- setup correctness or setup-to-withdrawal derivation
- concurrent withdrawals
- a full deterministic fallback ceremony
- the full MuSig2 nonce and partial-signature transcript
- a full attacker-controlled network semantics
- real Bitcoin mempool or mining behavior
- off-protocol SAR rescue operations
- a full privacy or non-interference theorem for WT
- the literal ST country-grid UX beyond the symbolic `consent_match` abstraction

The current results are strongest when read as:

- bounded safety evidence for one withdrawal session at a time
- binding and replay-hygiene evidence around approvals, commits, duress acknowledgements, signing tickets, and broadcast
- explicit proof-boundary assumptions surfaced by formalization

They should not be read as a complete privacy proof, a complete liveness proof for a deployed protocol, or a full proof of setup, fallback, or the real signing transcript.

## Repository Map

| Path | Role |
| --- | --- |
| `spec/BoomerangWithdrawalCore.tla` | Current authoritative withdrawal-core model. |
| `spec/BoomerangWithdrawalCore.tla.md` | Guide to the current authoritative TLA+ module. |
| `spec/BoomerangWithdrawalCore_human_evaluation.md` | English reconstruction of the current withdrawal-core model derived directly from the TLA+ source. |
| `spec/MC_BoomerangWithdrawalCore.cfg` | Broader three-peer safety/history run with two sequential session ids. |
| `spec/MC_BoomerangWithdrawalCore.cfg.md` | Guide for the broader cfg. |
| `spec/MC_BoomerangWithdrawalCore_safety.cfg` | Small invariant-focused regression cfg. |
| `spec/MC_BoomerangWithdrawalCore_safety.cfg.md` | Guide for the small safety cfg. |
| `spec/MC_BoomerangWithdrawalCore_sanity.cfg` | Small safety plus history-property cfg. |
| `spec/MC_BoomerangWithdrawalCore_sanity.cfg.md` | Guide for the small sanity cfg. |
| `spec/MC_BoomerangWithdrawalCore_deadlock.cfg` | Tiny deadlock-on classification harness. |
| `spec/MC_BoomerangWithdrawalCore_deadlock.cfg.md` | Guide for the deadlock cfg. |
| `spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg` | Smallest curated five-peer safety harness. |
| `spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg.md` | Guide for the five-peer cfg. |
| `spec/MC_BoomerangWithdrawalCore_liveness.cfg` | Tiny fairness-backed liveness harness. |
| `spec/MC_BoomerangWithdrawalCore_liveness.cfg.md` | Guide for the liveness cfg. |
| `spec/withdrawal_wire/BoomerangWithdrawalWire.tla` | Secondary WIP wire-faithful withdrawal model. |
| `spec/withdrawal_wire/BoomerangWithdrawalWire.tla.md` | Guide to the WIP withdrawal-wire model. |
| `docs/boomerang_authoritative_state_machine_spec.md` | Broader English setup-plus-withdrawal design/spec context retained for reference. |
| `spec/assumption_register.md` | Reference assumption register and design-gap analysis compiled from a broader design corpus than this trimmed workspace. |
| `spec/BoomerangWithdrawalCore.toolbox/BoomerangWithdrawalCore___Model_1.launch` | Optional TLC Toolbox launch artifact. |
| `tools/tla2tools.jar` | Bundled PlusCal, TLA+, SANY, and TLC toolchain. |

## Current Vs Broader References

- `BoomerangWithdrawalCore.tla` and its guides are the current authoritative repo surface.
- `BoomerangWithdrawalCore_human_evaluation.md` is the quickest English companion to the current TLA+ model.
- `docs/boomerang_authoritative_state_machine_spec.md` is broader than the current withdrawal-core model and should be read as design/spec context, not as the exact current proof boundary.
- `spec/assumption_register.md` reflects a larger design corpus than the trimmed workspace and is retained as reference material, not as a literal inventory of current files.
- `spec/withdrawal_wire/BoomerangWithdrawalWire.tla` is a useful secondary model, but it remains work in progress.

## Reading Order

1. Read `spec/BoomerangWithdrawalCore.tla.md`.
2. Read `spec/BoomerangWithdrawalCore_human_evaluation.md`.
3. Read `spec/BoomerangWithdrawalCore.tla`.
4. Read the curated cfg guides in `spec/*.cfg.md`.
5. Read `docs/boomerang_authoritative_state_machine_spec.md` for broader design context.
6. Read `spec/assumption_register.md` as reference material from the broader design corpus.

## Prerequisites

Run the commands below from the repository root.

You need:

- a local Java runtime capable of executing `tools/tla2tools.jar`
- write access to `/tmp` for TLC metadata directories

## Verification Workflow

The commands below are the primary local verification workflow for the authoritative withdrawal-core model. The TLC runs are local model-checking commands and may be long-running, especially outside the smallest harnesses. The withdrawal-wire model has its own focused guide in `spec/withdrawal_wire/BoomerangWithdrawalWire.tla.md`.

### 1. Regenerate the TLA+ translation after editing the PlusCal block

```bash
java -cp tools/tla2tools.jar pcal.trans spec/BoomerangWithdrawalCore.tla
```

### 2. Run SANY

```bash
java -cp tools/tla2tools.jar tla2sany.SANY spec/BoomerangWithdrawalCore.tla
```

### 3. Run the smallest invariant-focused regression check

```bash
META=$(mktemp -d /tmp/bwcore-safety.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_safety.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### 4. Run the tiny safety-plus-history sanity check

```bash
META=$(mktemp -d /tmp/bwcore-sanity.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_sanity.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### 5. Run the tiny deadlock-on classification harness

```bash
META=$(mktemp -d /tmp/bwcore-deadlock.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_deadlock.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### 6. Run the smallest five-peer safety harness

```bash
META=$(mktemp -d /tmp/bwcore-five.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### 7. Run the fairness-backed liveness harness

```bash
META=$(mktemp -d /tmp/bwcore-liveness.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_liveness.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### 8. Run the broader three-peer withdrawal model

```bash
META=$(mktemp -d /tmp/bwcore-main.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

## Harness Summary

| Harness | What it is for |
| --- | --- |
| `MC_BoomerangWithdrawalCore_safety.cfg` | Smallest invariant-focused regression check. |
| `MC_BoomerangWithdrawalCore_sanity.cfg` | Small safety run plus monotone history properties. |
| `MC_BoomerangWithdrawalCore_deadlock.cfg` | Deadlock surfacing and classification. |
| `MC_BoomerangWithdrawalCore_five_peer_safety.cfg` | Smallest run that exercises five-peer cardinality. |
| `MC_BoomerangWithdrawalCore_liveness.cfg` | Narrow fairness-backed liveness claims only. |
| `MC_BoomerangWithdrawalCore.cfg` | Broader three-peer safety/history exploration with sequential sessions. |

## Verification Notes

- The safety cfgs intentionally do not imply liveness.
- The liveness cfg is the only curated harness that uses `SpecWithFairness`.
- The sanity cfg checks history properties, not eventual-progress claims.
- The deadlock cfg exists to surface deadlock traces and compare them against the model's explicit deadlock classification.
- Sequential withdrawals are modeled through explicit post-broadcast reset. Concurrent sessions are still out of scope.
- `pcal.trans` may rewrite `spec/BoomerangWithdrawalCore.cfg`; that translator byproduct is not one of the curated `MC_*.cfg` harnesses.

## If You Are New To This Repo

The fastest current path is:

1. Read `spec/BoomerangWithdrawalCore.tla.md`.
2. Read `spec/BoomerangWithdrawalCore_human_evaluation.md`.
3. Run `SANY` on `spec/BoomerangWithdrawalCore.tla`.
4. Run the tiny safety harness.

After that, use the broader English state-machine document and the assumption register as reference context rather than as the primary current model surface.
