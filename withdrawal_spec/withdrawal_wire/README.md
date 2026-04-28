# `BoomerangWithdrawalWire.tla` Guide

## Table of Contents

- [Purpose](#purpose)
- [Shape Of The Model](#shape-of-the-model)
- [Actor Ownership](#actor-ownership)
- [Canonical Step Mapping](#canonical-step-mapping)
- [Wire Surface Audit](#wire-surface-audit)
- [Bounded TLC Surface](#bounded-tlc-surface)
- [Structural Checks](#structural-checks)
- [Verification](#verification)
- [Current Invariants](#current-invariants)
- [Remaining Design Ambiguity](#remaining-design-ambiguity)


## Purpose

[Back to TOC](#table-of-contents)


`withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla` is the withdrawal-only wire model derived directly from the canonical withdrawal sources in the external `boomerang_design` repository.

It now also carries a bounded curated TLC surface so the wire-faithful model can be regression-checked in the repository.

The upstream source files below are not part of this repository; they describe the external design corpus in `boomerang_design` repository this model was derived from.

Upstream source priority:

1. `withdrawal/README.md`
2. `withdrawal/initiator_withdrawal_diagram_without_states.puml`
3. `withdrawal/non_initiator_withdrawal_diagram_without_states.puml`
4. `setup/README.md` only for inherited post-setup state
5. `SPEC.md` only when the withdrawal sources are silent

## Shape Of The Model

[Back to TOC](#table-of-contents)


- post-setup only
- one active 5-peer withdrawal
- separate PlusCal processes for every actor:
  - `UserFlow \in Peers`
  - `NisoFlow \in Peers`
  - `BoomletFlow \in Peers`
  - `STFlow \in Peers`
  - `IsoFlow \in Peers`
  - `SARFlow \in Peers`
  - `Watchtower`
  - `Environment`
- explicit actor-to-actor mailboxes for every diagram edge
- exact canonical wrapper names on actor hops
- symbolic `SignatureOnMessage`, `EncryptedFor`, `PaddedMessage`, `Collection`, and `MessageWithNonce` layers
- bounded `DuressValues == 1..DURESS_VALUE_CARDINALITY` for curated TLC runs
- recurring duress gated by the documented modulo-trigger rule over an abstract bounded PRNG-draw domain
- no peer-facing `WTBroadcast`

## Actor Ownership

[Back to TOC](#table-of-contents)


- `User_i` owns PSBT agreement, ST acknowledgements, duress index choice, and Iso-connect intent.
- `Niso_i` owns only relay-visible state: saved PSBT/tx id, local event height, reached collection, and hydrated PSBT.
- `Boomlet_i` owns committed tx id, duress state, placeholder plaintext/ciphertext, digging-game state, and export state.
- `ST_i` owns the last tx-id challenge and the last duress-check challenge it decrypted.
- `Iso_i` owns nonce/partialsig and signed-PSBT artifacts for the signing exchange.
- `SAR_i` owns seen placeholder IVs and rescue/doxing artifacts.
- `WT` owns approval, commit, ping, reply, signed-fragment, and final relay state.

## Canonical Step Mapping

[Back to TOC](#table-of-contents)


This is a process-level correspondence checklist rather than a line-by-line changelog.

- Steps `1-9`:
  - `UserFlow(INITIATOR)` sends `WithdrawalNisoInput1`
  - `NisoFlow(INITIATOR)` validates PSBT and relays `WithdrawalNisoBoomletMessage1`
  - `BoomletFlow(INITIATOR)`, `STFlow(INITIATOR)`, and `UserFlow(INITIATOR)` perform the tx-id challenge/ack round
  - `BoomletFlow(INITIATOR)` emits `WithdrawalBoomletNisoMessage2`
  - `NisoFlow(INITIATOR)` forwards `WithdrawalNisoWtMessage1`

- Steps `10-27/27n`:
  - `Watchtower` validates the initiator approval and fans out `WithdrawalWtNonInitiatorNisoMessage1`
  - `NisoFlow(i # INITIATOR)` and `BoomletFlow(i # INITIATOR)` perform the non-initiator PSBT review and ST tx-id round
  - `BoomletFlow(i # INITIATOR)` emits `WithdrawalNonInitiatorBoomletNisoMessage3`
  - `Watchtower` collects non-initiator approvals and fans out `WithdrawalWtNisoMessage1` / `WithdrawalWtNonInitiatorNisoMessage2`
  - `BoomletFlow` then starts the initial duress check with `WithdrawalBoomletNisoMessage3` or `WithdrawalNonInitiatorBoomletNisoMessage4`

- Steps `28-45`:
  - `STFlow` and `UserFlow` perform the initial duress round using `Withdrawal*NisoStMessage2`, `Withdrawal*StOutput2`, `Withdrawal*StInput2`, and `Withdrawal*StNisoMessage2`
  - `BoomletFlow(INITIATOR)` emits `WithdrawalBoomletNisoMessage4`
  - `BoomletFlow(i # INITIATOR)` emits `WithdrawalNonInitiatorBoomletNisoMessage5`
  - `Watchtower` sends commit/placeholders to `SARFlow`
  - `SARFlow` returns the signed placeholder ciphertext
  - `Watchtower` fans out `WithdrawalWtNonInitiatorNisoMessage3`, then later `WithdrawalWtNisoMessage2` / `WithdrawalWtNonInitiatorNisoMessage4`
  - `BoomletFlow` transitions into the digging game from `WithdrawalNisoBoomletMessage5`

- Steps `46-61`:
  - `BoomletFlow` emits ping envelopes via `WithdrawalBoomletNisoMessage5` and `WithdrawalBoomletNisoMessage7`
  - `NisoFlow` forwards them with `WithdrawalNisoWtMessage3`, `WithdrawalNisoWtMessage4`, or `WithdrawalNonInitiatorNisoWtMessage4`
  - `Watchtower` routes each placeholder to `SARFlow` with `WithdrawalWtSarsMessage2`
  - `Watchtower` returns `WithdrawalWtNisoMessage3` pongs until all reached flags are collected
  - recurring duress refresh uses `WithdrawalBoomletNisoMessage6`, `WithdrawalNisoStMessage3`, `WithdrawalStOutput3`, `WithdrawalStInput3`, `WithdrawalStNisoMessage3`, and `WithdrawalNisoBoomletMessage7`
  - once all reached pings are present, `Watchtower` emits `WithdrawalWtNisoMessage4`
  - `NisoFlow` hydrates the PSBT and sends `WithdrawalNisoBoomletMessage8`

- Steps `62-73`:
  - `BoomletFlow` emits `WithdrawalBoomletNisoMessage8`
  - `NisoFlow` notifies `UserFlow` with `WithdrawalNisoOutput1`
  - `UserFlow`, `IsoFlow`, and `BoomletFlow` perform the canonical `WithdrawalIsoInput1`, `WithdrawalIsoBoomletMessage1`, `WithdrawalBoomletIsoMessage1`, `WithdrawalIsoBoomletMessage2`, `WithdrawalBoomletIsoMessage2`, and `WithdrawalIsoOutput1` exchange
  - `UserFlow` returns to `NisoFlow` with `WithdrawalNisoInput2`
  - `NisoFlow` asks `BoomletFlow` for export with `WithdrawalNisoBoomletMessage9`
  - `BoomletFlow` returns `WithdrawalBoomletNisoMessage9`
  - `NisoFlow` forwards `WithdrawalNisoWtMessage5`
  - `Watchtower` aggregates signed fragments and sets the terminal relay artifact `wt_broadcast`

## Wire Surface Audit

[Back to TOC](#table-of-contents)


The model keeps the wire surface constrained to canonical diagram wrapper names:

- `CanonicalWireMessageKinds` enumerates the allowed wrapper names.
- `WireSurfaceOnlyCanonical` checks every hop in `wire_trace`.
- `NoExtraWTHops` rules out WT-to-User fanout and any synthetic `WTBroadcast`.

## Bounded TLC Surface

[Back to TOC](#table-of-contents)


The wire model keeps the design's 5-peer and 5-column shape, but the curated TLC harness binds:

- `DURESS_VALUE_CARDINALITY = 2`
- `DURESS_CHECK_INTERVAL_IN_BLOCKS = 2`
- alternating consent-set values through `ModelInitConsentSetAlternating`
- distinct doxing-key values through `ModelInitDoxingKeyDistinct`

This keeps the wire surface tractable for TLC without changing the actor topology or wrapper-level control flow.

## Structural Checks

[Back to TOC](#table-of-contents)


The module exposes view operators intended for future hostile-`Niso` work:

- `NisoVisibleState(i)`
- `NisoVisibleMessages(i)`
- `BoomletVisibleState(i)`

These are observational only in this version; the model still assumes honest behavior from all processes.

The module also now exposes:

- `IsSafePaddingPlaintextForPeer(peer, plaintext)` so SAR can recognize any honest safe placeholder for that peer regardless of `stage` or `seq`
- `RecurringDuressPRNGDraws` / `RecurringDuressCheckFires(...)` so the recurring-check branch follows the design’s modulo rule instead of a free Boolean choice
- `SARDoxingIdentifiersExcludeSafePadding` to guard the SAR regression surface directly

## Verification

[Back to TOC](#table-of-contents)


Run these from the repository root:

```bash
java -cp tools/tla2tools.jar pcal.trans withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla
java -cp tools/tla2tools.jar tla2sany.SANY withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla

META=$(mktemp -d /tmp/bwwire-safety.XXXXXX)
java -jar tools/tla2tools.jar -workers 1 -config withdrawal_spec/withdrawal_wire/MC_BoomerangWithdrawalWire_safety.cfg -metadir "$META" withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla
```

## Current Invariants

[Back to TOC](#table-of-contents)


- `WireSurfaceOnlyCanonical`
- `NoExtraWTHops`
- `CommittedTxConsistent`
- `HydratedPsbtPreservesCommittedTx`
- `WTRelayRequiresAllSigned`
- `SARDoxingIdentifiersExcludeSafePadding`

## Remaining Design Ambiguity

[Back to TOC](#table-of-contents)


The design corpus is clear that repeated duress checks are triggered by a pseudo-random draw whose modulo against `DURESS_CHECK_INTERVAL_IN_BLOCKS` is zero. What it still does not define canonically is the PRNG source, seed/state persistence, or whether each peer must maintain an independently auditable PRNG stream. The wire model now implements the modulo rule directly and leaves that narrower generator question as an explicit proof-boundary assumption.
