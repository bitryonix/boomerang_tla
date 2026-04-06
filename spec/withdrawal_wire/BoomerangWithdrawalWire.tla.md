# `BoomerangWithdrawalWire.tla` Guide

## Purpose

`spec/withdrawal_wire/BoomerangWithdrawalWire.tla` is the withdrawal-only wire model derived directly from the canonical withdrawal sources in `BD.zip`. WORK IN PROGRESS.

Source priority:

1. `withdrawal/README.md`
2. `withdrawal/initiator_withdrawal_diagram_without_states.puml`
3. `withdrawal/non_initiator_withdrawal_diagram_without_states.puml`
4. `setup/README.md` only for inherited post-setup state
5. `SPEC.md` only when the withdrawal sources are silent

## Shape Of The Model

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
- no peer-facing `WTBroadcast`

## Actor Ownership

- `User_i` owns PSBT agreement, ST acknowledgements, duress index choice, and Iso-connect intent.
- `Niso_i` owns only relay-visible state: saved PSBT/tx id, local event height, reached collection, and hydrated PSBT.
- `Boomlet_i` owns committed tx id, duress state, placeholder plaintext/ciphertext, digging-game state, and export state.
- `ST_i` owns the last tx-id challenge and the last duress-check challenge it decrypted.
- `Iso_i` owns nonce/partialsig and signed-PSBT artifacts for the signing exchange.
- `SAR_i` owns seen placeholder IVs and rescue/doxing artifacts.
- `WT` owns approval, commit, ping, reply, signed-fragment, and final relay state.

## Canonical Step Mapping

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

The model keeps the wire surface constrained to canonical diagram wrapper names:

- `CanonicalWireMessageKinds` enumerates the allowed wrapper names.
- `WireSurfaceOnlyCanonical` checks every hop in `wire_trace`.
- `NoExtraWTHops` rules out WT-to-User fanout and any synthetic `WTBroadcast`.

## Structural Checks

The module exposes view operators intended for future hostile-`Niso` work:

- `NisoVisibleState(i)`
- `NisoVisibleMessages(i)`
- `BoomletVisibleState(i)`

These are observational only in this version; the model still assumes honest behavior from all processes.

## Verification

Run these from the repository root:

```bash
java -cp tools/tla2tools.jar pcal.trans spec/withdrawal_wire/BoomerangWithdrawalWire.tla
java -cp tools/tla2tools.jar tla2sany.SANY spec/withdrawal_wire/BoomerangWithdrawalWire.tla
```

## Current Invariants

- `WireSurfaceOnlyCanonical`
- `NoExtraWTHops`
- `CommittedTxConsistent`
- `HydratedPsbtPreservesCommittedTx`
- `WTRelayRequiresAllSigned`
