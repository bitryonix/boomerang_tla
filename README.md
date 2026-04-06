# Boomerang TLA+ Workspace

This repository is a formal-specification workspace for the Boomerang design. The current proof effort is intentionally narrow: post-setup, withdrawal-only, PlusCal-first, and focused on the boomerang-regime withdrawal ceremony plus the security assumptions that become explicit while formalizing it.

It is not yet a full end-to-end proof of Boomerang.

## Repository Map

| Path | Role |
| --- | --- |
| `docs/boomerang_authoritative_state_machine_spec.md` | Long-form English withdrawal state machine derived from the design corpus. |
| `spec/BoomerangWithdrawalCore.tla` | Authoritative merged withdrawal model. |
| `spec/BoomerangWithdrawalCore.tla.md` | Line-by-line guide for the authoritative TLA+ module. |
| `spec/MC_BoomerangWithdrawalCore.cfg` | Broader three-peer safety/history run with two sequential session ids available. |
| `spec/MC_BoomerangWithdrawalCore.cfg.md` | Guide for the broader cfg. |
| `spec/MC_BoomerangWithdrawalCore_safety.cfg` | Small invariant-focused regression cfg. |
| `spec/MC_BoomerangWithdrawalCore_safety.cfg.md` | Guide for the small safety cfg. |
| `spec/MC_BoomerangWithdrawalCore_sanity.cfg` | Small safety plus history-property cfg. |
| `spec/MC_BoomerangWithdrawalCore_sanity.cfg.md` | Guide for the small sanity cfg. |
| `spec/MC_BoomerangWithdrawalCore_deadlock.cfg` | Tiny deadlock-on classification harness. |
| `spec/MC_BoomerangWithdrawalCore_deadlock.cfg.md` | Guide for the deadlock cfg. |
| `spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg` | Tiny 5-peer safety harness. |
| `spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg.md` | Guide for the 5-peer cfg. |
| `spec/MC_BoomerangWithdrawalCore_liveness.cfg` | Tiny fairness-backed liveness cfg. |
| `spec/MC_BoomerangWithdrawalCore_liveness.cfg.md` | Guide for the liveness cfg. |
| `spec/assumption_register.md` | Proof-boundary assumptions and derived design gaps. |
| `spec/withdrawal_audit_changelog.md` | Repo-owned response to third-party audit findings. |
| `boomerang_design.zip` | Bundled design corpus. |
| `tools/tla2tools.jar` | Bundled PlusCal/TLA+/TLC toolchain. |

## What The Current Model Covers

`spec/BoomerangWithdrawalCore.tla` starts after setup and models:

- milestone-gated initiator start
- explicit `session_id` and `tx_id` locking
- explicit nonce-bound ST/Boomlet `tx_id` challenge and acknowledgement before any peer emits approval
- initiator submission and peer approval collection
- initial and recurring nonce-bound ST/Boomlet duress transcripts
- commit collection with exact `(sid, peer, txid, phase, seq, placeholder_instance)` SAR-ack binding
- the digging game with stricter ping/pong sequence and block-distance checks
- abstract signing-ticket binding, signed-PSBT export, and WT broadcast
- post-broadcast cleanup and reset so sequential withdrawals can be exercised in one run
- deterministic fallback only as a boundary condition, not as a fully modeled spend ceremony

The model now treats SAR as a single SAR per peer. Any old repo-owned text implying multi-SAR-per-peer behavior was wrong and has been corrected.

## What The Current Model Still Does Not Prove

This workspace still does not prove:

- setup correctness or setup-to-withdrawal derivation
- a full deterministic fallback ceremony
- the full MuSig2 nonce and partial-signature transcript
- a full privacy or non-interference theorem for WT
- a full attacker-controlled network semantics
- real Bitcoin mempool/mining behavior
- off-protocol SAR rescue operations
- the literal country-grid ST UI and human-factor encoding rules behind the symbolic `consent_match` abstraction

WT privacy is now documented as a deferred proof obligation rather than a checked invariant. The old frozen-flag placeholder was removed from shipped configs.

## Reading Order

1. Read `docs/boomerang_authoritative_state_machine_spec.md`.
2. Read `spec/BoomerangWithdrawalCore.tla.md`.
3. Read `spec/BoomerangWithdrawalCore.tla`.
4. Read the cfg guides in `spec/*.cfg.md`.
5. Read `spec/assumption_register.md`.
6. Read `spec/withdrawal_audit_changelog.md`.

## Verification Workflow

### Regenerate the TLA+ translation after editing the PlusCal block

```bash
java -cp tools/tla2tools.jar pcal.trans spec/BoomerangWithdrawalCore.tla
```

### Run SANY

```bash
java -cp tools/tla2tools.jar tla2sany.SANY spec/BoomerangWithdrawalCore.tla
```

### Run the smallest invariant-focused regression check

```bash
META=$(mktemp -d /tmp/bwcore-safety.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_safety.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### Run the tiny safety-plus-history sanity check

```bash
META=$(mktemp -d /tmp/bwcore-sanity.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_sanity.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### Run the tiny deadlock-on classification harness

```bash
META=$(mktemp -d /tmp/bwcore-deadlock.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_deadlock.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### Run the tiny fairness-backed liveness harness

```bash
META=$(mktemp -d /tmp/bwcore-liveness.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_liveness.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

### Run the broader three-peer withdrawal model

```bash
META=$(mktemp -d /tmp/bwcore-main.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

## Verification Notes

- The shipped safety cfgs disable deadlock checking on purpose. The dedicated deadlock cfg is for surfacing deadlock traces and classifying them against the repo's explicit deadlock predicate.
- The sanity cfg’s temporal properties are history properties, not liveness. Monotonic ledger growth is not eventual progress.
- The dedicated liveness cfg uses `SpecWithFairness`. Any liveness statement outside that fairness boundary should be treated as non-proven.
- Sequential withdrawals are now modeled by reset-enabled sessions. Concurrent sessions are still out of scope.
- `pcal.trans` may rewrite `spec/BoomerangWithdrawalCore.cfg`; that translator byproduct is not one of the curated `MC_*.cfg` files.

## Current Proof Boundary

The current results are strongest when read as:

- small-bounded safety evidence for one withdrawal session at a time
- exact binding hygiene around approvals, commits, pings, pongs, SAR acknowledgements, signing tickets, and broadcast
- explicit proof-boundary assumptions surfaced by the act of modeling

They should not yet be read as:

- a complete privacy proof
- a complete liveness proof for the real deployed protocol
- a proof of setup, full fallback, or the full signing transcript
