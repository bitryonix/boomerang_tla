# `MC_BoomerangWithdrawalCore_five_peer_safety.cfg` Guide

## Purpose

`spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg` is the smallest curated harness that actually exercises the design’s five-peer cardinality.

## Line-By-Line Guide

| Lines | Purpose |
| --- | --- |
| `1-3` | Human comment, `Spec`, and deadlock policy. |
| `5-33` | Five-peer constant bindings with otherwise tiny bounds, including explicit `ChallengeNonces`. |
| `35-72` | The same strengthened safety invariants used by the other safety harnesses, including the ST/Boomlet transcript checks. |

## Manual Verification

```bash
META=$(mktemp -d /tmp/bwcore-five.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- TLC starts cleanly at five peers
- the nonce-transcript invariants still hold at five-peer cardinality
- no invariant fails immediately in a 5-peer-specific interleaving

## Notes

- This cfg is intentionally otherwise tiny. The point is to expose five-peer asymmetries, not to make the state space arbitrarily huge.
