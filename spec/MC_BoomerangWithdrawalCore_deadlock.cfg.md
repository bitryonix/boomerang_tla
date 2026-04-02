# `MC_BoomerangWithdrawalCore_deadlock.cfg` Guide

## Purpose

`spec/MC_BoomerangWithdrawalCore_deadlock.cfg` is the dedicated deadlock-on regression harness.

Its job is not to suppress deadlocks. Its job is to classify them.

## Line-By-Line Guide

| Lines | Purpose |
| --- | --- |
| `1-3` | Human comment, `Spec`, and `CHECK_DEADLOCK TRUE`. |
| `5-30` | Tiny constant bindings matching the smallest safety scale, including explicit `ChallengeNonces`. |
| `32-46` | A focused invariant set for deadlock classification, including the ST/Boomlet transcript-binding invariants. |
| `48-49` | `DeadlockStatesAreClassified`, the repo’s explicit deadlock-classification predicate. With `CHECK_DEADLOCK TRUE`, TLC still reports the deadlock before it can return a clean affirmative property result. |

## Manual Verification

```bash
META=$(mktemp -d /tmp/bwcore-deadlock.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_deadlock.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- TLC can run with deadlock checking enabled
- no transcript-binding invariant fails before the deadlock is surfaced
- if TLC finds a deadlock, inspect the final state in the trace and compare it against `ClassifiedDeadlockState`
- treat `DeadlockStatesAreClassified` as the intended classification predicate, not as a separately witnessed "pass" under `CHECK_DEADLOCK TRUE`

## Notes

- This cfg exists so the shipped safety cfgs can stay focused on safety without pretending deadlock questions do not exist.
