# `MC_BoomerangWithdrawalCore_liveness.cfg` Guide

## Purpose

`spec/MC_BoomerangWithdrawalCore_liveness.cfg` is the dedicated fairness-backed liveness harness.

It checks only the narrow liveness claims that the current model can honestly support:

- fresh pending SAR acknowledgements are eventually delivered
- loss eventually triggers fallback

## Line-By-Line Guide

| Lines | Purpose |
| --- | --- |
| `1-3` | Human comment, `SpecWithFairness`, and deadlock policy. |
| `5-30` | Tiny constant bindings for a tractable fairness run, including explicit `ChallengeNonces`. |
| `32-41` | Minimal invariant set needed to keep the liveness run honest, including the ST/Boomlet transcript-binding invariants. |
| `43-45` | Fairness-backed liveness properties. |

## Manual Verification

```bash
META=$(mktemp -d /tmp/bwcore-liveness.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_liveness.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- TLC accepts `SpecWithFairness`
- the transcript-binding invariants hold alongside the fairness assumptions
- the two liveness properties do not fail under the tiny bounds

## Notes

- This cfg is where liveness belongs. The safety cfgs intentionally do not imply liveness by accident.
