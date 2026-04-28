# Boomerang TLA+ Workspace

## Table of Contents

- [Current Status](#current-status)
- [Repository Map](#repository-map)
- [What The Current Models Cover](#what-the-current-models-cover)
- [What They Still Do Not Prove](#what-they-still-do-not-prove)
- [Where To Start](#where-to-start)


This repository is a formal-specification workspace for the Boomerang design.
The TLA+ work here is still a work in progress: post-setup, withdrawal-only,
PlusCal-first, and focused on turning the withdrawal ceremony into executable
models while making proof-boundary assumptions explicit.

It is not yet a full end-to-end proof of Boomerang.
## Current Status

[Back to TOC](#table-of-contents)


- [`withdrawal_spec/BoomerangWithdrawalCore.tla`](withdrawal_spec/BoomerangWithdrawalCore.tla) is the current main withdrawal
  model in this WIP proof effort.
- [`withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla`](withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla) is a secondary,
  more wire-faithful WIP model.
- [`setup_spec/setup_wire/BoomerangSetupWire.tla`](setup_spec/setup_wire/BoomerangSetupWire.tla) captures the setup transcript
  surface as a definition-oriented wire model.
- Detailed verification commands, harness descriptions, and command-specific
  notes live in [`withdrawal_spec/README.md`](withdrawal_spec/README.md).
## Repository Map

[Back to TOC](#table-of-contents)


| Path | Role |
| --- | --- |
| [`withdrawal_spec/README.md`](withdrawal_spec/README.md) | Entry point for the withdrawal-spec docs, including verification workflow and harness notes. |
| [`withdrawal_spec/walkthrough.md`](withdrawal_spec/walkthrough.md) | Plain-language walkthrough of the withdrawal core model. |
| [`withdrawal_spec/BoomerangWithdrawalCore.tla`](withdrawal_spec/BoomerangWithdrawalCore.tla) | Current main withdrawal model. |
| [`withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla`](withdrawal_spec/withdrawal_wire/BoomerangWithdrawalWire.tla) | Secondary wire-faithful withdrawal model. |
| [`setup_spec/setup_wire/README.md`](setup_spec/setup_wire/README.md) | Setup wire-model guide and verification notes. |
| [`setup_spec/setup_wire/BoomerangSetupWire.tla`](setup_spec/setup_wire/BoomerangSetupWire.tla) | Wire-faithful setup transcript model. |
| [`english_state_machine/boomerang_authoritative_state_machine_spec.md`](english_state_machine/boomerang_authoritative_state_machine_spec.md) | Broader English design context retained alongside the current TLA+ work. |
| [`tools/tla2tools.jar`](tools/tla2tools.jar) | Bundled PlusCal, TLA+, SANY, and TLC toolchain. |
## What The Current Models Cover

[Back to TOC](#table-of-contents)


The current withdrawal models focus on:

- a single active post-setup withdrawal session at a time
- locked `(session_id, tx_id)` binding across approvals, commits, pings, and
  signing/export state
- explicit nonce-bound `tx_id` and duress transcript handling
- watchtower coordination, SAR acknowledgement flow, and digging-game progress
- abstract signing-ticket binding, signed-PSBT export, and WT broadcast
- sequential-session reset after successful broadcast
## What They Still Do Not Prove

[Back to TOC](#table-of-contents)


The current TLA+ work still does not prove:

- setup correctness or setup-to-withdrawal derivation
- the full deterministic fallback ceremony
- the full MuSig2 nonce and partial-signature transcript
- a full privacy or non-interference theorem for WT
- a full attacker-controlled network semantics
- real Bitcoin mempool/mining behavior
- off-protocol SAR rescue operations
- the literal ST country-grid UI and human-factor encoding rules behind the
  symbolic `consent_match` abstraction
- explicit PSBT satisfiability checking
- explicit `peer_ids_collection` / initiator-id membership checking
## Where To Start

[Back to TOC](#table-of-contents)


1. Read [`withdrawal_spec/README.md`](withdrawal_spec/README.md).
2. Read [`withdrawal_spec/walkthrough.md`](withdrawal_spec/walkthrough.md).
3. Read [`withdrawal_spec/withdrawal_wire/README.md`](withdrawal_spec/withdrawal_wire/README.md).
4. Read [`setup_spec/setup_wire/README.md`](setup_spec/setup_wire/README.md).
