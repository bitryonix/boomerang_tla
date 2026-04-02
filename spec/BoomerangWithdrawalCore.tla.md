# `BoomerangWithdrawalCore.tla` Guide

## Purpose

`spec/BoomerangWithdrawalCore.tla` is the authoritative withdrawal model for this phase of the Boomerang proof effort.

It keeps the repo scoped to:

- post-setup withdrawal only
- one active withdrawal session at a time
- PlusCal-first protocol structure
- abstract fallback boundary instead of a full fallback spend ceremony
- abstract signing-ticket binding instead of a full MuSig2 transcript

Compared with the earlier merged version, this file now also carries:

- opaque placeholder-instance modeling
- explicit nonce-bound ST/Boomlet `txid_challenge/txid_ack` transcripts
- explicit nonce-bound ST/Boomlet `duress_challenge/duress_ack` transcripts
- SAR replay suppression per peer
- durable acceptance witnesses for freshness-sensitive evidence
- reset-enabled sequential withdrawals
- separate fairness-backed liveness operators

## What This File Covers

The model covers:

- milestone-gated initiator start
- `session_id` and `tx_id` freezing during an active withdrawal
- approval emission only after a matching accepted `tx_id` transcript
- initial and recurrent duress resolution only through matching accepted nonce-bound transcripts
- commit collection with exact placeholder-instance SAR acknowledgements
- WT-coordinated ping/pong rounds with stronger seq and block-distance checks
- all-reached transition to signing readiness
- signing-ticket binding across hydration, signed export, and WT broadcast
- post-broadcast cleanup and `mystery` regeneration
- fallback as a separate boundary condition

It intentionally does not fully model:

- setup
- concurrent withdrawals
- the full deterministic fallback ceremony
- the full MuSig2 signing transcript
- real Bitcoin mempool/mining semantics
- off-protocol SAR rescue operations

## Merge And Hardening Decisions

The important proof-boundary choices in this file are:

- placeholder instances are opaque identities, not plaintext payload tokens
- SAR is modeled as single per peer
- ST/Boomlet freshness is represented by exact transcript binding on `{sid, tx_id, peer, stage, seq, nonce}`
- the literal country-grid challenge content is still abstracted to symbolic `consent_match`
- replay suppression is per peer over placeholder-instance memory
- freshness witnesses are recorded at acceptance time
- signing is bound by a lightweight signing ticket
- sequential withdrawals are allowed only through explicit reset after successful broadcast
- fairness-backed liveness is separated from the default safety `Spec`

## Line-By-Line Guide

| Lines | Purpose |
| --- | --- |
| `1-123` | Module header, constants, assumptions, and shared domains. This is where `ChallengeNonces`, the new nonce-aware peer states, and the symbolic duress stages enter the model. |
| `124-154` | TLC helper operators used for constant binding in curated cfgs. |
| `156-289` | Symbolic message constructors for approvals, bundles, commits, SAR acknowledgements, pings, pongs, signed PSBTs, broadcasts, and the explicit ST/Boomlet transcript records. |
| `291-856` | Structural, matching, freshness, replay, digging-game, and well-formedness helpers. This is the message-shape layer and transcript-binding layer for the whole model. |
| `858-1708` | PlusCal variables and processes. This is where the peer-local `AwaitingInitialTxIdAck`, `AwaitingInitialDuressAck`, and `AwaitingRecurringDuressAck` substates live, along with post-broadcast reset. |
| `1712-3982` | Generated PlusCal translation. Regenerate this block with `pcal.trans` after editing the PlusCal algorithm. |
| `3988-4585` | Post-translation state predicates and safety invariants. This is where the accepted transcript witnesses, observable-envelope surrogate, freshness checks, signing-ticket invariants, and deadlock classification live. |
| `4588-4641` | Temporal/history properties and fairness-backed liveness operators. This includes `SpecWithFairness` and the scoped liveness properties. |

## How To Read It Manually

Use this order:

1. Read `1-109` for the state vocabulary.
2. Read `156-856` for messages, transcript matching, freshness, replay, and digging helpers.
3. Read the PlusCal algorithm at `858-1708`.
4. Treat `1712-3982` as generated executable form.
5. Read the safety properties at `3988-4585`.
6. Finish with the temporal and liveness operators at `4588-4641`.

## Manual Verification

Run these from the repository root.

### 1. Regenerate the translation after editing the PlusCal block

```bash
java -cp tools/tla2tools.jar pcal.trans spec/BoomerangWithdrawalCore.tla
```

What to check:

- the translation still begins around line `1654`
- only the `\* BEGIN TRANSLATION` to `\* END TRANSLATION` block changes
- `spec/BoomerangWithdrawalCore.cfg` may be rewritten by the translator; that file is a translator byproduct, not one of the curated `MC_*.cfg` harnesses

### 2. Run SANY

```bash
java -cp tools/tla2tools.jar tla2sany.SANY spec/BoomerangWithdrawalCore.tla
```

What to check:

- parsing succeeds
- semantic processing succeeds
- there are no unknown operators or malformed record/domain errors

### 3. Run the tiny safety cfg

```bash
META=$(mktemp -d /tmp/bwcore-safety.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_safety.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- no invariant fails
- the strengthened placeholder, nonce-transcript, freshness, and signing-ticket properties hold

### 4. Run the tiny sanity cfg

```bash
META=$(mktemp -d /tmp/bwcore-sanity.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_sanity.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- the same safety invariants still hold
- the history-style temporal properties (`UsedSessionsMonotone`, `PlaceholderLedgerMonotone`, `SARReplayMemoryMonotone`, `CompletedWithdrawalsMonotone`) also hold

### 5. Run the deadlock, 5-peer, and liveness harnesses

```bash
META=$(mktemp -d /tmp/bwcore-deadlock.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_deadlock.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-five.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-liveness.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_liveness.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- deadlock traces, if found, can be checked against `DeadlockStatesAreClassified`, but TLC will still halt on the deadlock first when `CHECK_DEADLOCK TRUE`
- the 5-peer harness does not reveal a cardinality-specific safety regression
- the fairness-backed liveness harness does not falsify the scoped service-progress properties

## Notes

- `ObservableEnvelopeConsistentUnderPrivateDuress` is intentionally narrower than a full privacy proof.
- `Spec` is safety-only. `SpecWithFairness` is the separate fairness-backed liveness surface.
- The reset logic is for sequential withdrawals only. The model still assumes a single active withdrawal at a time.
