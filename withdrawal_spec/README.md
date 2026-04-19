# Withdrawal Spec Workspace

<a id="table-of-contents"></a>

## Table of Contents

- [Contents](#contents)
- [Markdown Docs](#markdown-docs)
- [Reading Order](#reading-order)
- [Verification Workflow](#verification-workflow)
  - [Core model](#core-model)
  - [Wire model](#wire-model)
- [Harness Notes](#harness-notes)

This directory contains the current Boomerang withdrawal-model TLA+ work.
Everything here is still a work in progress: these files are the active
formalization surface for the withdrawal slice, not a finished proof of the
full system.

<a id="contents"></a>
## Contents

[Back to TOC](#table-of-contents)

| Path | Role |
| --- | --- |
| [`withdrawal_spec/BoomerangWithdrawalCore.tla`](BoomerangWithdrawalCore.tla) | Current main withdrawal model. |
| [`withdrawal_spec/MC_BoomerangWithdrawalCore.cfg`](MC_BoomerangWithdrawalCore.cfg) | Broader three-peer safety/history run with two sequential session ids available. |
| [`withdrawal_spec/MC_BoomerangWithdrawalCore_safety.cfg`](MC_BoomerangWithdrawalCore_safety.cfg) | Small invariant-focused regression harness. |
| [`withdrawal_spec/MC_BoomerangWithdrawalCore_sanity.cfg`](MC_BoomerangWithdrawalCore_sanity.cfg) | Small safety plus history-property harness. |
| [`withdrawal_spec/MC_BoomerangWithdrawalCore_deadlock.cfg`](MC_BoomerangWithdrawalCore_deadlock.cfg) | Tiny deadlock-on classification harness. |
| [`withdrawal_spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg`](MC_BoomerangWithdrawalCore_five_peer_safety.cfg) | Tiny 5-peer safety harness. |
| [`withdrawal_spec/MC_BoomerangWithdrawalCore_five_peer_broad.cfg`](MC_BoomerangWithdrawalCore_five_peer_broad.cfg) | Broader 5-peer safety harness with richer bounds than the tiny smoke check. |
| [`withdrawal_spec/MC_BoomerangWithdrawalCore_liveness.cfg`](MC_BoomerangWithdrawalCore_liveness.cfg) | Tiny fairness-backed liveness harness. |
| [`withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla`](withdrawal_wire/BoomerangWithdrawalWire.tla) | Secondary wire-faithful withdrawal model. |
| [`withdrawal_spec/withdrawal_wire/MC_BoomerangWithdrawalWire_safety.cfg`](withdrawal_wire/MC_BoomerangWithdrawalWire_safety.cfg) | Curated bounded safety harness for the wire model. |

<a id="markdown-docs"></a>
## Markdown Docs

[Back to TOC](#table-of-contents)

| Path | Role |
| --- | --- |
| [`withdrawal_spec/core_model_guide.md`](core_model_guide.md) | Guide to the current main withdrawal model. |
| [`withdrawal_spec/plain_language_walkthrough.md`](plain_language_walkthrough.md) | Plain-language walkthrough of the current core model. |
| [`withdrawal_spec/withdrawal_wire/README.md`](withdrawal_wire/README.md) | Guide to the wire-faithful model. |

<a id="reading-order"></a>
## Reading Order

[Back to TOC](#table-of-contents)

1. [`withdrawal_spec/core_model_guide.md`](core_model_guide.md)
2. [`withdrawal_spec/plain_language_walkthrough.md`](plain_language_walkthrough.md)
3. [`withdrawal_spec/BoomerangWithdrawalCore.tla`](BoomerangWithdrawalCore.tla)
4. [`withdrawal_spec/withdrawal_wire/README.md`](withdrawal_wire/README.md)
5. [`withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla`](withdrawal_wire/BoomerangWithdrawalWire.tla)

<a id="verification-workflow"></a>
## Verification Workflow

[Back to TOC](#table-of-contents)

Run these commands from the repository root.

<a id="core-model"></a>
### Core model

[Back to TOC](#table-of-contents)

```bash
java -cp tools/tla2tools.jar pcal.trans withdrawal_spec/BoomerangWithdrawalCore.tla
java -cp tools/tla2tools.jar tla2sany.SANY withdrawal_spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-safety.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/MC_BoomerangWithdrawalCore_safety.cfg -metadir "$META" withdrawal_spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-sanity.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/MC_BoomerangWithdrawalCore_sanity.cfg -metadir "$META" withdrawal_spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-deadlock.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/MC_BoomerangWithdrawalCore_deadlock.cfg -metadir "$META" withdrawal_spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-five.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/MC_BoomerangWithdrawalCore_five_peer_safety.cfg -metadir "$META" withdrawal_spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-five-broad.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/MC_BoomerangWithdrawalCore_five_peer_broad.cfg -metadir "$META" withdrawal_spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-liveness.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/MC_BoomerangWithdrawalCore_liveness.cfg -metadir "$META" withdrawal_spec/BoomerangWithdrawalCore.tla

META=$(mktemp -d /tmp/bwcore-main.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/MC_BoomerangWithdrawalCore.cfg -metadir "$META" withdrawal_spec/BoomerangWithdrawalCore.tla
```

<a id="wire-model"></a>
### Wire model

[Back to TOC](#table-of-contents)

```bash
java -cp tools/tla2tools.jar pcal.trans withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla
java -cp tools/tla2tools.jar tla2sany.SANY withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla

META=$(mktemp -d /tmp/bwwire-safety.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/withdrawal_wire/MC_BoomerangWithdrawalWire_safety.cfg -metadir "$META" withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla
```

<a id="harness-notes"></a>
## Harness Notes

[Back to TOC](#table-of-contents)

- The shipped safety harnesses disable deadlock checking on purpose. The
  dedicated deadlock harness is for surfacing deadlock traces and classifying
  them against the repo's explicit deadlock predicate.
- The curated wire TLC harness binds `DURESS_VALUE_CARDINALITY = 2` for
  tractability while preserving the design's 5-column control-flow shape.
- The curated core and wire TLC harnesses bind
  `DURESS_CHECK_INTERVAL_IN_BLOCKS = 2` so both recurring-duress outcomes remain
  reachable while still following the documented modulo rule.
- The sanity harness checks history properties, not liveness. Monotonic ledger
  growth is not eventual progress.
- The dedicated liveness harness uses `SpecWithFairness`. Any liveness statement
  outside that fairness boundary should be treated as non-proven.
- Sequential withdrawals are modeled by reset-enabled sessions. Concurrent
  sessions are still out of scope.
- `pcal.trans` may rewrite [`withdrawal_spec/BoomerangWithdrawalCore.cfg`](BoomerangWithdrawalCore.cfg) and
  [`withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.cfg`](withdrawal_wire/BoomerangWithdrawalWire.cfg); those files are
  translator byproducts, not curated harnesses.
- The design corpus is canonical on the modulo trigger for recurring duress
  checks, but still ambiguous on PRNG seed/state details. The models implement
  the trigger directly while leaving generator construction abstract.
