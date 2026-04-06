# `MC_BoomerangWithdrawalCore.cfg` Guide

## Purpose

`spec/MC_BoomerangWithdrawalCore.cfg` is the broader safety/history harness for the authoritative withdrawal model.

It is meant to exercise:

- three peers instead of the tiny two-peer cases
- two sequential `session_id` values in one run
- explicit `ChallengeNonces` choices in the ST/Boomlet transcript surface
- multiple `PSBT` / `TXID` choices
- the strengthened safety invariants
- the monotone history properties that still make sense after reset-enabled sessions

## Line-By-Line Guide

| Lines | Purpose |
| --- | --- |
| `1-3` | Human comment, `Spec`, and deadlock policy. Deadlock is intentionally off here because this cfg is for broader safety/history exploration, not deadlock classification. |
| `5-33` | Constant bindings. Three peers, two sessions, explicit `ChallengeNonces`, 24 placeholder ids, two PSBTs, two tx ids, longer block-height space, and the standard freshness/distance bounds. |
| `35-72` | Safety invariants checked in every reachable state, including the ST/Boomlet transcript-binding invariants. |
| `74-78` | Monotone history properties checked in the same run. |

## Why These Bounds

This cfg is broader than the tiny runs because it can actually exercise:

- sequential session reuse prevention
- more placeholder allocation pressure
- more ST/Boomlet nonce-transcript interleavings
- more interleavings in approval, commit, and digging-game collection
- more than one signing/export transcript witness

It still does not model concurrent withdrawals.

## Manual Verification

```bash
META=$(mktemp -d /tmp/bwcore-main.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- TLC starts cleanly
- the safety invariants do not fail
- the nonce-transcript and local-review invariants (`ApprovalsRequireAcceptedTxIdTranscript`, `NonInitiatorTxIdPathRequiresLocalPsbtReview`, `CommitsRequireAcceptedInitialDuressTranscript`, `RecurringChecksRequireAcceptedTranscript`) do not fail
- the history properties (`UsedSessionsMonotone`, `CompletedWithdrawalsMonotone`, `PlaceholderLedgerMonotone`, `SARReplayMemoryMonotone`) do not fail

## Notes

- This cfg no longer pretends that multiple session constants are enough by themselves. It relies on the reset-enabled model to make those extra session ids meaningful.
- Monotone history properties are not liveness claims.
