# `MC_BoomerangWithdrawalCore_sanity.cfg` Guide

## Purpose

`spec/MC_BoomerangWithdrawalCore_sanity.cfg` keeps the same tiny bounds as the safety cfg, but also checks the temporal/history properties that remain meaningful after reset-enabled sessions.

## Line-By-Line Guide

| Lines | Purpose |
| --- | --- |
| `1-3` | Human comment, `Spec`, and deadlock policy. |
| `5-30` | Tiny constant bindings identical in scale to the safety cfg, including explicit `ChallengeNonces`. |
| `32-69` | Safety invariants. |
| `71-75` | History properties. These are not liveness claims. |

## Manual Verification

```bash
META=$(mktemp -d /tmp/bwcore-sanity.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_sanity.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- the safety invariants still hold
- the ST/Boomlet transcript-binding invariants still hold under the same tiny bounds
- the history properties also hold

## Notes

- The old monotonicity checks over `session_id`, `broadcast_record`, and current signed PSBT state were intentionally replaced because reset-enabled sessions make those old formulas false for the right reason.
- The properties here are history/ledger stability checks, not eventual-progress proofs.
