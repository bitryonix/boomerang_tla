# `MC_BoomerangWithdrawalCore_safety.cfg` Guide

## Purpose

`spec/MC_BoomerangWithdrawalCore_safety.cfg` is the smallest curated invariant-focused regression harness.

It is meant to fail fast if we break:

- ST/Boomlet nonce-transcript binding
- placeholder-instance binding
- SAR replay suppression
- acceptance-time freshness witnesses
- signing-ticket binding
- fallback/signing separation

## Line-By-Line Guide

| Lines | Purpose |
| --- | --- |
| `1-3` | Human comment, `Spec`, and deadlock policy. Deadlock is off here because this harness is for fast invariant regression checking. |
| `5-30` | Tiny constant bindings: two peers, one session, one tx, explicit `ChallengeNonces`, eight placeholder ids, and small block-height bounds. |
| `32-69` | Safety invariants checked in every reachable state. |

## Manual Verification

```bash
META=$(mktemp -d /tmp/bwcore-safety.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config spec/MC_BoomerangWithdrawalCore_safety.cfg -metadir "$META" spec/BoomerangWithdrawalCore.tla
```

What to check:

- initial states compute successfully
- no invariant violation appears
- the transcript-binding and non-initiator local-review invariants fail fast if the approval path is wired incorrectly
- the run gets meaningfully into the state space without an early counterexample

## Notes

- This is the first harness to run after touching the PlusCal algorithm.
- It checks the new witness-based `AcceptedEvidenceWasFresh` invariant; freshness is no longer merely a comment-level note in this cfg.
