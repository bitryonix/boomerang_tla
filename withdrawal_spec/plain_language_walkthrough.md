# Plain-Language Walkthrough

<a id="table-of-contents"></a>

## Table of Contents

- [1. Executive Summary](#1-executive-summary)
- [2. Parties and Their Responsibilities](#2-parties-and-their-responsibilities)
  - [2.1 Peers](#21-peers)
  - [2.2 Watchtower](#22-watchtower)
  - [2.3 SAR](#23-sar)
  - [2.4 Fallback Monitor](#24-fallback-monitor)
- [3. Core State Concepts](#3-core-state-concepts)
  - [3.1 Locked Session and Locked Transaction](#31-locked-session-and-locked-transaction)
  - [3.2 Freshness](#32-freshness)
  - [3.3 Placeholders](#33-placeholders)
  - [3.4 Mystery Counter and Reached Condition](#34-mystery-counter-and-reached-condition)
- [4. Peer State Machine in Plain English](#4-peer-state-machine-in-plain-english)
  - [4.1 `ActiveReady`](#41-activeready)
  - [4.2 `AwaitingInitialTxIdAck`](#42-awaitinginitialtxidack)
  - [4.3 `AwaitingPeerApprovals`](#43-awaitingpeerapprovals)
  - [4.4 `AwaitingInitialDuressAck`](#44-awaitinginitialduressack)
  - [4.5 `InitialDuressResolved`](#45-initialduressresolved)
  - [4.6 `AwaitingWTInitiatorCommit`](#46-awaitingwtinitiatorcommit)
  - [4.7 `AwaitingCommitCollection`](#47-awaitingcommitcollection)
  - [4.8 `DiggingGame`](#48-digginggame)
  - [4.9 `AwaitingRecurringDuressAck`](#49-awaitingrecurringduressack)
  - [4.10 `ReadyToSign`](#410-readytosign)
  - [4.11 `Signed` and `AwaitReset`](#411-signed-and-awaitreset)
- [5. Watchtower State Machine in Plain English](#5-watchtower-state-machine-in-plain-english)
  - [5.1 `AwaitingInitiatorApproval`](#51-awaitinginitiatorapproval)
  - [5.2 `CollectingPeerApprovals`](#52-collectingpeerapprovals)
  - [5.3 `CollectingCommitments`](#53-collectingcommitments)
  - [5.4 `CollectingPings`](#54-collectingpings)
  - [5.5 `CollectingSignatures`](#55-collectingsignatures)
  - [5.6 `Broadcasted` and Reset](#56-broadcasted-and-reset)
- [6. Message Catalogue](#6-message-catalogue)
  - [6.1 Approval and Session-Locking Messages](#61-approval-and-session-locking-messages)
  - [6.2 Local Signer Transcript Messages](#62-local-signer-transcript-messages)
  - [6.3 Commit and Placeholder Witnessing Messages](#63-commit-and-placeholder-witnessing-messages)
  - [6.4 Digging-Phase Messages](#64-digging-phase-messages)
  - [6.5 Signing and Broadcast Messages](#65-signing-and-broadcast-messages)
- [7. End-to-End Message Passing Narrative](#7-end-to-end-message-passing-narrative)
  - [7.1 Session Start](#71-session-start)
  - [7.2 Approval Completion and Initial Duress](#72-approval-completion-and-initial-duress)
  - [7.3 Commit Phase](#73-commit-phase)
  - [7.4 Digging Rounds](#74-digging-rounds)
  - [7.5 Signing and Completion](#75-signing-and-completion)
- [8. Conditions That Block Progress](#8-conditions-that-block-progress)
- [9. Security and Consistency Properties Visible in the Spec](#9-security-and-consistency-properties-visible-in-the-spec)
  - [9.1 Session and Transaction Binding](#91-session-and-transaction-binding)
  - [9.2 Evidence Freshness](#92-evidence-freshness)
  - [9.3 Placeholder Authenticity and Replay Suppression](#93-placeholder-authenticity-and-replay-suppression)
  - [9.4 No Early Signing](#94-no-early-signing)
  - [9.5 Duress Persistence](#95-duress-persistence)
  - [9.6 Fallback Separation](#96-fallback-separation)
- [10. Interpretation of the Protocol's Intent](#10-interpretation-of-the-protocols-intent)
- [11. Important Ambiguities or Open Questions for a Human Reviewer](#11-important-ambiguities-or-open-questions-for-a-human-reviewer)
  - [11.1 What exactly is SAR?](#111-what-exactly-is-sar)
  - [11.2 What do placeholders represent externally?](#112-what-do-placeholders-represent-externally)
  - [11.3 Why does the digging game require a private mystery threshold?](#113-why-does-the-digging-game-require-a-private-mystery-threshold)
  - [11.4 Why can recurring duress checks occur on some rounds but not others?](#114-why-can-recurring-duress-checks-occur-on-some-rounds-but-not-others)
  - [11.5 What is the exact wire protocol?](#115-what-is-the-exact-wire-protocol)
  - [11.6 What is meant by "hydrated" PSBT?](#116-what-is-meant-by-hydrated-psbt)
- [12. Suggested Human Review Checklist](#12-suggested-human-review-checklist)
- [13. Bottom-Line Protocol Description](#13-bottom-line-protocol-description)

This document is a plain-language reconstruction of the protocol modeled in
[`BoomerangWithdrawalCore.tla`](BoomerangWithdrawalCore.tla).

Scope and method:
- This write-up is derived only from [`withdrawal_spec/BoomerangWithdrawalCore.tla`](BoomerangWithdrawalCore.tla).
- It does not rely on any external design docs or prior versions.
- Where the spec is explicit, this document states the behavior directly.
- Where the spec implies intent but does not define it in plain English, this
  document marks that as an interpretation or inference.

Suggested reading companion:
- Start with the module header, domains, and helper operators.
- Then read the peer, watchtower, SAR, and fallback processes in order.
- Finish with the invariants and temporal properties.

<a id="1-executive-summary"></a>
## 1. Executive Summary

[Back to TOC](#table-of-contents)

The modeled protocol is a coordinated multi-party withdrawal ceremony with four
logical actors:
- a set of `Peers`
- one distinguished `INITIATOR`
- a `Watchtower` (`WT`)
- an `SAR` acknowledger

The ceremony starts only after setup is already complete. The initiator picks a
PSBT, which determines the withdrawal `tx_id`. The rest of the protocol makes
all peers converge on one locked session and one locked transaction, subjects
that shared view to explicit approval and acknowledgement steps, runs a repeated
ping/pong coordination game with placeholder acknowledgements, and only then
allows collective signing and broadcast.

The key structural themes visible in the spec are:
- every important artifact is bound to a single `(session_id, tx_id)`
- freshness against block height is enforced for approvals, commits, pings, and
  pongs
- local signer transcripts are required before peers may progress
- SAR must acknowledge placeholder-bearing commits and pings
- signing is blocked until every peer has "reached"
- an abstract fallback path can preempt the ceremony before signing completes

<a id="2-parties-and-their-responsibilities"></a>
## 2. Parties and Their Responsibilities

[Back to TOC](#table-of-contents)

<a id="21-peers"></a>
### 2.1 Peers

[Back to TOC](#table-of-contents)

Every peer runs the same peer state machine, but the initiator has special
duties:
- selects the session and initial PSBT
- fixes the `tx_id` through that PSBT
- is the first party to submit to the watchtower
- emits the first commit before non-initiators are allowed to commit

All peers:
- perform local `txid_challenge` / `txid_ack` checks
- perform local `duress_challenge` / `duress_ack` checks
- create placeholder-bearing commits
- participate in the ping/pong "digging" phase
- eventually sign the PSBT if the ceremony reaches the signing gate

<a id="22-watchtower"></a>
### 2.2 Watchtower

[Back to TOC](#table-of-contents)

The watchtower is the global coordinator. It:
- accepts and validates the initiator's starting submission
- distributes the initial bundle to non-initiators
- collects peer approvals
- collects commits and waits for corresponding SAR acknowledgements
- collects pings and produces per-peer pongs
- records which peers have reached the threshold for completion
- collects final signed PSBTs
- emits the abstract broadcast event

<a id="23-sar"></a>
### 2.3 SAR

[Back to TOC](#table-of-contents)

SAR is modeled as an acknowledgement service over placeholders.

The watchtower places an expected `sar_ack` request into
`sar_pending_ack_request[i]`. SAR consumes it if the placeholder has not
already been seen for that peer, records the placeholder id in replay memory,
and returns the same acknowledgement object as `sar_ack_i[i]`.

SAR also marks `sar_escalated_i[i] := TRUE` if the placeholder's kind is
`doxing_key`.

Interpretation:
- SAR behaves like an external witness or receipt service for placeholder
  publication.
- The model does not define how SAR is contacted on the wire. That request path
  is abstracted as shared state, while the acknowledgement itself is modeled as
  a first-class message shape.

<a id="24-fallback-monitor"></a>
### 2.4 Fallback Monitor

[Back to TOC](#table-of-contents)

Fallback is not a detailed alternative protocol in this model. It is an
abstract boundary condition. The fallback monitor:
- can mark peer hardware as lost
- can activate fallback for a peer if hardware is lost or `Milestone1` is
  reached
- prevents coexistence of fallback activation with boomerang signing completion

<a id="3-core-state-concepts"></a>
## 3. Core State Concepts

[Back to TOC](#table-of-contents)

<a id="31-locked-session-and-locked-transaction"></a>
### 3.1 Locked Session and Locked Transaction

[Back to TOC](#table-of-contents)

Two global variables define the ceremony instance:
- `session_id`
- `tx_id`

The initiator chooses both indirectly by selecting a fresh session id and a
PSBT whose transaction id is `TxOfPsbt[p]`. Once the session is underway, the
spec enforces that approvals, commits, pings, pongs, signed PSBTs, and pending
local signer transcripts all remain bound to the current `(session_id, tx_id)`.

This is one of the strongest themes in the invariants:
- `ApprovalsBoundToLockedSession`
- `CommitmentsBoundToLockedSession`
- `PingsBoundToLockedSession`
- `SignedPsbtsBoundToLockedSession`
- `CurrentSessionBindingsFrozen`

<a id="32-freshness"></a>
### 3.2 Freshness

[Back to TOC](#table-of-contents)

Freshness is modeled with heights and bounded lag:
- approvals use `APPROVAL_FRESHNESS`
- commits use `COMMIT_FRESHNESS`
- pings use `PING_FRESHNESS`
- pongs use `PONG_FRESHNESS`

The watchtower and peers reject stale material. This means the protocol is not
just agreement on content; it is agreement on content that is recent enough
relative to observed chain height.

<a id="33-placeholders"></a>
### 3.3 Placeholders

[Back to TOC](#table-of-contents)

Placeholders are central to commits and pings. Each placeholder id has:
- an owner
- a kind in `{"unused", "padding", "doxing_key"}`

Each peer obtains fresh placeholder ids over time. SAR remembers which
placeholder ids it has already acknowledged for that peer, which gives the
model replay suppression.

Interpretation:
- `padding` appears to represent an innocuous placeholder.
- `doxing_key` appears to represent an escalatory or revealing placeholder.
- This interpretation is strongly suggested by the names and by the SAR
  escalation behavior, but the spec does not define the real-world payload.

<a id="34-mystery-counter-and-reached-condition"></a>
### 3.4 Mystery Counter and Reached Condition

[Back to TOC](#table-of-contents)

Each peer has a private `mystery_i[self]` threshold and a local `counter_i`.
During the digging game, successful rounds can increment the counter. Once the
counter reaches the mystery threshold, `reached_mystery_flag_i[self]` becomes
true, and the peer starts advertising `reached = TRUE` in pings.

This means the protocol's completion condition is not a fixed round count. It
is peer-local and threshold-based.

<a id="4-peer-state-machine-in-plain-english"></a>
## 4. Peer State Machine in Plain English

[Back to TOC](#table-of-contents)

Peer states are declared near the top of the module and exercised in the
PlusCal process.

<a id="41-activeready"></a>
### 4.1 `ActiveReady`

[Back to TOC](#table-of-contents)

If the peer is the initiator:
- wait until there is no active session
- choose an unused `session_id`
- choose a PSBT
- derive the corresponding `tx_id`
- issue a local `txid_challenge`
- move to `AwaitingInitialTxIdAck`

If the peer is not the initiator:
- wait for a `wt_bundle` from the watchtower
- validate it under both `NisoAcceptsWTBundle` and
  `BoomletAcceptsWTBundle`
- install the PSBT from the bundle
- issue a local `txid_challenge`
- move to `AwaitingInitialTxIdAck`

<a id="42-awaitinginitialtxidack"></a>
### 4.2 `AwaitingInitialTxIdAck`

[Back to TOC](#table-of-contents)

The peer locally accepts the pending `txid_challenge` and materializes the
matching `txid_ack`.

After that:
- the initiator sends `initiator_submission` to the watchtower
- a non-initiator sends a plain `approved` message

Then the peer moves to `AwaitingPeerApprovals`.

Meaning:
- no approval leaves a peer until it has a local secure-signer transcript for
  the exact session and txid.

<a id="43-awaitingpeerapprovals"></a>
### 4.3 `AwaitingPeerApprovals`

[Back to TOC](#table-of-contents)

The peer waits until the watchtower indicates that the full approval collection
has been delivered.

At that point the peer creates an initial `duress_challenge` with:
- stage = `initial`
- seq = 0

Then it moves to `AwaitingInitialDuressAck`.

<a id="44-awaitinginitialduressack"></a>
### 4.4 `AwaitingInitialDuressAck`

[Back to TOC](#table-of-contents)

The peer receives a `duress_ack` with a boolean `consent_match`.

Immediate consequences:
- if `consent_match = TRUE`, the peer's payload kind becomes `padding`
- if `consent_match = FALSE`, the payload kind becomes `doxing_key`
- a failed consent match latches duress forever for that session path
- the peer increments its duress check counter

Then the peer moves to `InitialDuressResolved`.

<a id="45-initialduressresolved"></a>
### 4.5 `InitialDuressResolved`

[Back to TOC](#table-of-contents)

The next action depends on whether the peer is the initiator.

Initiator path:
- allocate a fresh placeholder id
- set its kind from the current payload kind
- define the expected SAR ack for commit phase, sequence 0
- emit a `commit`
- move to `AwaitingCommitCollection`

Non-initiator path:
- send an `approvals_bundle` back to the watchtower containing the full peer
  approval collection and the WT approval
- move to `AwaitingWTInitiatorCommit`

<a id="46-awaitingwtinitiatorcommit"></a>
### 4.6 `AwaitingWTInitiatorCommit`

[Back to TOC](#table-of-contents)

Only non-initiators use this state. They wait for two conditions:
- the watchtower has accepted their `approvals_bundle`
- the initiator's commit has been acknowledged

Then they:
- allocate their own fresh placeholder
- define the expected SAR ack for commit phase, sequence 0
- emit their own `commit`
- move to `AwaitingCommitCollection`

This enforces a start-of-commit ordering: initiator commit first, others after.

<a id="47-awaitingcommitcollection"></a>
### 4.7 `AwaitingCommitCollection`

[Back to TOC](#table-of-contents)

The peer waits until the delivered commit collection is valid under:
- `NisoValidCommitCollectionForPeer`
- `BoomletValidCommitCollectionForPeer`

That means:
- all peers' commits are present
- every commit is signed by its peer
- every commit is sealed by the watchtower
- every commit is fresh
- the peer's own SAR ack exactly matches what it expected for its commit

After that, the peer:
- records the accepted SAR ack
- allocates a fresh placeholder for ping phase
- sets expected SAR ack for `phase = ping`, `seq = 0`
- initializes `counter`, `ping_seq_num`, `reached` flag, reviewed history, and
  last seen block
- emits the first `ping`
- moves to `DiggingGame`

<a id="48-digginggame"></a>
### 4.8 `DiggingGame`

[Back to TOC](#table-of-contents)

This is the core recurring phase.

There are two possible successful exits from a digging iteration.

Exit A: universal reach observed
- if the watchtower delivers the reached collection
- and the peer's SAR ack matches its expected ping ack
- and all reached pings are valid and signed
- then the peer hydrates the PSBT, receives a signing ticket, and moves to
  `ReadyToSign`

Exit B: another pong round is required
- the peer waits for a valid `pong`
- validates it under `NisoValidPongForPeer` and
  `BoomletValidPongForPeer`
- records the pong and the included SAR ack
- then either sends the next ping immediately or first performs a recurring
  duress check

The `pong` validation checks that:
- the pong is signed by WT
- it is fresh
- it is for the correct session and txid
- included peer pings are themselves fresh and well-formed
- included pings progress from earlier reviewed history
- already-advertised reached peers stay marked as reached
- each included ping is sufficiently older than the WT height by
  `MIN_PING_PONG_DISTANCE`

<a id="49-awaitingrecurringduressack"></a>
### 4.9 `AwaitingRecurringDuressAck`

[Back to TOC](#table-of-contents)

Instead of sending the next ping immediately, a peer may first run another
`duress_challenge` with:
- stage = `ping`
- seq = next ping sequence number

Once the ack arrives:
- the peer emits the next ping
- updates counter, last seen block, reached flag, and reviewed history
- increments `duress_checks_i`
- if consent failed, duress becomes latched and future placeholders are of kind
  `doxing_key`
- returns to `DiggingGame`

<a id="410-readytosign"></a>
### 4.10 `ReadyToSign`

[Back to TOC](#table-of-contents)

The peer may sign only if:
- fallback is not active
- it has a hydrated PSBT
- it has a signing ticket
- every peer is in `ReadyToSign`, `Signed`, or `AwaitReset`
- no peer has fallback active
- every peer has the same signing ticket
- every peer has the expected SAR ack for its latest placeholder

Then the peer signs and emits `signed_psbt`, moving to `Signed`.

<a id="411-signed-and-awaitreset"></a>
### 4.11 `Signed` and `AwaitReset`

[Back to TOC](#table-of-contents)

After signing, the peer waits for the watchtower's `broadcast` message that
contains the same signing ticket.

Then it moves to `AwaitReset`, and after the global reset conditions hold it
returns to `ActiveReady` with most session-specific state cleared.

<a id="5-watchtower-state-machine-in-plain-english"></a>
## 5. Watchtower State Machine in Plain English

[Back to TOC](#table-of-contents)

<a id="51-awaitinginitiatorapproval"></a>
### 5.1 `AwaitingInitiatorApproval`

[Back to TOC](#table-of-contents)

The watchtower starts a new ceremony only from the initiator's submission.

It requires:
- `approval_outbox[INITIATOR]` to contain a well-formed
  `initiator_submission`
- the embedded initiator approval to be signed by the initiator
- the embedded approval to match the current session and tx
- the approval to be fresh at WT height

Then WT:
- records the session view
- stores the initiator approval
- creates `wt_approved`
- sends a `wt_bundle` to each non-initiator
- moves to `CollectingPeerApprovals`

<a id="52-collectingpeerapprovals"></a>
### 5.2 `CollectingPeerApprovals`

[Back to TOC](#table-of-contents)

WT repeatedly accepts `approved` messages from non-initiators if they are:
- well-formed
- signed by the claimed peer
- for the current session and tx
- fresh

Once all approvals are present, WT marks approval collection as delivered to all
peers and moves to `CollectingCommitments`.

<a id="53-collectingcommitments"></a>
### 5.3 `CollectingCommitments`

[Back to TOC](#table-of-contents)

WT handles two coupled flows:

Flow A: accept approval bundles from non-initiators
- WT checks that the bundle's approval map exactly equals the current approval
  collection
- WT checks that the bundled WT approval exactly equals the current WT approval

Flow B: process commits
- WT accepts a peer's `commit` if it is well-formed, signed, session/tx bound,
  and fresh
- WT then creates an expected SAR ack request for that placeholder
- once the peer's SAR ack matches the saved expectation, WT seals the commit by
  setting `wt_signed_by = WT_ID` and inserts it into the shared commit
  collection

Special ordering rule:
- when the initiator's commit is accepted and SAR-acked, WT marks
  `initiator_commit_acked` true for every non-initiator

Once all commits are present, WT marks commit collection as delivered and moves
to `CollectingPings`.

<a id="54-collectingpings"></a>
### 5.4 `CollectingPings`

[Back to TOC](#table-of-contents)

WT accepts one round of pings from peers. For each ping it checks:
- well-formedness
- peer signature
- session/tx binding
- freshness
- monotone progress from that peer's previously accepted ping

For each accepted ping WT:
- records it as the latest accepted ping
- generates the expected SAR ack request for that ping's placeholder
- if the ping has `reached = TRUE`, stores it in the reached collection

Then WT has two branches:

Branch 1: all peers have reached
- require all round pings present
- require all SAR replies present
- require minimum ping/pong distance
- mark reached collection delivered
- move to `CollectingSignatures`

Branch 2: not all peers have reached
- require all round pings present
- require all SAR replies present
- require minimum ping/pong distance
- construct a personalized `pong` for every peer
- each pong includes all other peers' current round pings plus that peer's SAR
  ack
- clear round ping and SAR-ack buffers
- stay in `CollectingPings`

<a id="55-collectingsignatures"></a>
### 5.5 `CollectingSignatures`

[Back to TOC](#table-of-contents)

WT gathers one `signed_psbt` from each peer, checking:
- well-formedness
- peer signature
- session/tx binding
- ticket consistency with the peer's signing ticket
- PSBT-to-tx consistency

Once all signed PSBTs are present and the tickets agree, WT emits `broadcast`
and moves to `Broadcasted`.

<a id="56-broadcasted-and-reset"></a>
### 5.6 `Broadcasted` and Reset

[Back to TOC](#table-of-contents)

WT waits until all peers are in `AwaitReset`. It then:
- marks the session id as used
- increments completed withdrawals
- clears session-global volatile state
- returns to `AwaitingInitiatorApproval`

<a id="6-message-catalogue"></a>
## 6. Message Catalogue

[Back to TOC](#table-of-contents)

The following message shapes are explicit in the spec.

<a id="61-approval-and-session-locking-messages"></a>
### 6.1 Approval and Session-Locking Messages

[Back to TOC](#table-of-contents)

`approved`
- Sender: non-initiator peer
- Receiver: WT
- Fields: `sid`, `peer`, `txid`, `height`, `signed_by`
- Purpose: peer approval of the locked session/tx

`wt_approved`
- Sender: WT
- Receiver: peers, via bundle
- Fields: `sid`, `initiator`, `txid`, `height`, `signed_by`
- Purpose: WT's approval record for the locked session/tx

`initiator_submission`
- Sender: initiator
- Receiver: WT
- Fields: `sid`, `initiator_approval`, `psbt`
- Purpose: start the ceremony and convey the PSBT

`wt_bundle`
- Sender: WT
- Receiver: each non-initiator
- Fields: `sid`, `psbt`, `initiator_approval`, `wt_approval`, `signed_by`
- Purpose: provide the non-initiators with the locked PSBT and starting
  evidence

`approvals_bundle`
- Sender: non-initiator peer
- Receiver: WT
- Fields: `sid`, `peer`, `approvals`, `wt_approval`, `signed_by`
- Purpose: prove the peer observed the full approval set and WT approval before
  commitment

<a id="62-local-signer-transcript-messages"></a>
### 6.2 Local Signer Transcript Messages

[Back to TOC](#table-of-contents)

`txid_challenge`
- Sender: peer
- Receiver: local secure signer context
- Fields: `sid`, `peer`, `txid`, `nonce`, `signed_by`
- Purpose: challenge the signer to acknowledge the session and txid

`txid_ack`
- Sender: secure signer context
- Receiver: peer
- Fields: `sid`, `peer`, `txid`, `nonce`, `signed_by`
- Purpose: acknowledge the exact txid challenge

`duress_challenge`
- Sender: peer
- Receiver: local secure signer context
- Fields: `sid`, `peer`, `txid`, `stage`, `seq`, `nonce`, `signed_by`
- Purpose: collect a duress/consent transcript for either the initial phase or
  a later ping phase

`duress_ack`
- Sender: secure signer context
- Receiver: peer
- Fields: `sid`, `peer`, `txid`, `stage`, `seq`, `nonce`, `consent_match`,
  `signed_by`
- Purpose: report whether local consent matches expectations

<a id="63-commit-and-placeholder-witnessing-messages"></a>
### 6.3 Commit and Placeholder Witnessing Messages

[Back to TOC](#table-of-contents)

`commit`
- Sender: peer
- Receiver: WT
- Fields: `sid`, `peer`, `txid`, `height`, `placeholder`, `signed_by`,
  `wt_signed_by`
- Purpose: commit the peer to the current ceremony while carrying a placeholder

`sar_ack`
- Sender: SAR
- Receiver: peer or WT-visible state
- Fields: `sid`, `peer`, `txid`, `phase`, `seq`, `placeholder`, `signed_by`
- Purpose: acknowledge the exact placeholder expected for a commit or ping

Important note:
- The request to SAR is not modeled as a named wire message.
- WT writes an expected ack into `sar_pending_ack_request`.
- SAR copies that expected ack back into `sar_ack_i`.

<a id="64-digging-phase-messages"></a>
### 6.4 Digging-Phase Messages

[Back to TOC](#table-of-contents)

`ping`
- Sender: peer
- Receiver: WT
- Fields: `sid`, `peer`, `txid`, `last_seen_block`, `ping_seq_num`, `reached`,
  `placeholder`, `signed_by`
- Purpose: report peer progress in the digging game and carry a fresh
  placeholder

`pong`
- Sender: WT
- Receiver: one peer
- Fields: `sid`, `to`, `txid`, `wt_height`, `other_pings`, `sar_ack`,
  `signed_by`
- Purpose: give the peer the rest of the round's information and its own SAR
  acknowledgement

<a id="65-signing-and-broadcast-messages"></a>
### 6.5 Signing and Broadcast Messages

[Back to TOC](#table-of-contents)

`signed_psbt`
- Sender: peer
- Receiver: WT
- Fields: `sid`, `peer`, `txid`, `psbt`, `ticket`, `signed_by`
- Purpose: final signed contribution under a common signing ticket

`broadcast`
- Sender: WT
- Receiver: peers
- Fields: `sid`, `txid`, `ticket`, `signed_by`
- Purpose: abstract evidence that the fully signed withdrawal transaction is
  being broadcast

<a id="7-end-to-end-message-passing-narrative"></a>
## 7. End-to-End Message Passing Narrative

[Back to TOC](#table-of-contents)

Below is the message flow in plain sequence form.

<a id="71-session-start"></a>
### 7.1 Session Start

[Back to TOC](#table-of-contents)

1. Initiator locally forms `txid_challenge`.
2. Secure signer returns `txid_ack`.
3. Initiator sends `initiator_submission` to WT.
4. WT validates the submission and sends each non-initiator a `wt_bundle`.
5. Each non-initiator locally forms `txid_challenge`.
6. Secure signer returns `txid_ack`.
7. Each non-initiator sends `approved` to WT.

<a id="72-approval-completion-and-initial-duress"></a>
### 7.2 Approval Completion and Initial Duress

[Back to TOC](#table-of-contents)

8. WT waits until all approvals are present.
9. Each peer performs an initial `duress_challenge`.
10. Secure signer returns `duress_ack`.
11. Each peer's payload kind becomes either `padding` or `doxing_key`.

<a id="73-commit-phase"></a>
### 7.3 Commit Phase

[Back to TOC](#table-of-contents)

12. Initiator sends `commit` with its first placeholder.
13. SAR returns matching `sar_ack` for that placeholder.
14. Each non-initiator sends `approvals_bundle` to WT.
15. WT acknowledges the initiator commit to unlock the others.
16. Each non-initiator sends its own `commit`.
17. SAR returns matching `sar_ack` for each of those commits.
18. WT seals all commits and delivers the full commit collection.

<a id="74-digging-rounds"></a>
### 7.4 Digging Rounds

[Back to TOC](#table-of-contents)

19. Each peer sends initial `ping(seq = 0, reached = FALSE)`.
20. SAR returns matching `sar_ack` for each ping placeholder.
21. If all peers have reached, WT skips to signing readiness.
22. Otherwise WT sends each peer a personalized `pong` containing:
    - WT height
    - all other peers' pings from the round
    - that peer's SAR ack
23. Each peer validates the pong and then either:
    - sends the next `ping`, or
    - performs a recurring `duress_challenge`, receives `duress_ack`, then
      sends the next `ping`
24. Over repeated rounds, a peer's private counter may reach its mystery
    threshold, causing future pings to set `reached = TRUE`.
25. WT records the first reached ping for each peer.
26. Once every peer has produced a reached ping and all latest placeholders are
    SAR-acknowledged, WT delivers the reached set.

<a id="75-signing-and-completion"></a>
### 7.5 Signing and Completion

[Back to TOC](#table-of-contents)

27. Each peer hydrates the PSBT and receives a shared signing ticket.
28. Each peer sends `signed_psbt` to WT.
29. WT waits for all signatures and then emits `broadcast`.
30. Peers move to reset, and WT clears ceremony state.

<a id="8-conditions-that-block-progress"></a>
## 8. Conditions That Block Progress

[Back to TOC](#table-of-contents)

The spec intentionally makes progress conditional on many checks.

The ceremony does not advance if:
- the initiator does not first lock the session and tx
- a peer lacks a valid `txid_ack`
- approvals are stale
- a non-initiator receives a WT bundle that does not match the expected
  session, tx, signatures, or freshness window
- the initial duress transcript is missing
- a commit is not followed by the exact SAR ack for its placeholder
- a pong is stale or inconsistent with earlier reviewed ping history
- minimum ping/pong distance is not satisfied
- not all peers have reached
- latest placeholders are not settled by SAR
- any peer activates fallback before signing
- signed PSBT tickets do not agree

This is a protocol designed to fail closed rather than permissively continue.

<a id="9-security-and-consistency-properties-visible-in-the-spec"></a>
## 9. Security and Consistency Properties Visible in the Spec

[Back to TOC](#table-of-contents)

The invariants near the end of the file show what the model considers
important.

<a id="91-session-and-transaction-binding"></a>
### 9.1 Session and Transaction Binding

[Back to TOC](#table-of-contents)

The protocol tries hard to ensure that once a session is active:
- all artifacts stay attached to the same session id
- all artifacts stay attached to the same txid
- no stale local signer transcripts are accepted for another session

<a id="92-evidence-freshness"></a>
### 9.2 Evidence Freshness

[Back to TOC](#table-of-contents)

Accepted evidence must have been fresh at the height where it was accepted:
- approvals
- WT bundles
- commits
- pings
- pongs
- SAR acknowledgements
- local signer transcripts

<a id="93-placeholder-authenticity-and-replay-suppression"></a>
### 9.3 Placeholder Authenticity and Replay Suppression

[Back to TOC](#table-of-contents)

The model includes:
- monotone placeholder ownership and kind assignment
- SAR replay memory that only grows
- suppression of repeated SAR acknowledgement for the same placeholder id

<a id="94-no-early-signing"></a>
### 9.4 No Early Signing

[Back to TOC](#table-of-contents)

The model states several no-early-completion conditions:
- no boomerang signature before universal readiness
- one not-ready peer blocks broadcast
- broadcast only after all signed PSBTs are present

<a id="95-duress-persistence"></a>
### 9.5 Duress Persistence

[Back to TOC](#table-of-contents)

Once duress is latched, it never reverts during the ceremony:
- `PostDuressNoRevert`

That means a failed consent match permanently changes future placeholder
behavior for that peer in the current session path.

<a id="96-fallback-separation"></a>
### 9.6 Fallback Separation

[Back to TOC](#table-of-contents)

Fallback is constrained so that:
- it only happens after hardware loss or `Milestone1`
- it does not overlap with successful boomerang signing completion

<a id="10-interpretation-of-the-protocols-intent"></a>
## 10. Interpretation of the Protocol's Intent

[Back to TOC](#table-of-contents)

This section is interpretive but grounded in the state machine.

The likely intended shape of the protocol is:
- first, get every peer and the watchtower to agree on a single withdrawal
  transaction
- second, have every peer obtain local signer acknowledgement of that choice
- third, require placeholder publication and witnessing so the ceremony leaves
  externally attestable traces
- fourth, repeatedly exchange round information until each peer privately
  decides it has seen enough to mark itself as reached
- fifth, permit signing only after universal reach and witnessed latest state

The names `padding` and `doxing_key`, together with SAR escalation on
`doxing_key`, strongly suggest that the placeholder channel is not only a
progress mechanism but also a latent coercion- or duress-signalling channel.
The spec supports that reading, but it does not define the real-world semantics
of those payloads.

<a id="11-important-ambiguities-or-open-questions-for-a-human-reviewer"></a>
## 11. Important Ambiguities or Open Questions for a Human Reviewer

[Back to TOC](#table-of-contents)

These are not criticisms of the model. They are places where the code leaves
intent abstract or under-specified for an external reader.

<a id="111-what-exactly-is-sar"></a>
### 11.1 What exactly is SAR?

[Back to TOC](#table-of-contents)

The model makes SAR acknowledgements important, but does not explain:
- who operates SAR
- whether SAR is public, private, or append-only
- what it means to "acknowledge" a placeholder in real deployment terms

<a id="112-what-do-placeholders-represent-externally"></a>
### 11.2 What do placeholders represent externally?

[Back to TOC](#table-of-contents)

The spec defines placeholder ids and kinds but not:
- their serialized form
- whether they appear on chain, in PSBT metadata, or in an off-chain log
- how `padding` differs from `doxing_key` operationally

<a id="113-why-does-the-digging-game-require-a-private-mystery-threshold"></a>
### 11.3 Why does the digging game require a private mystery threshold?

[Back to TOC](#table-of-contents)

The mechanics are clear, but the rationale is not stated in the model:
- why each peer has a private threshold
- what security or privacy property that threshold is meant to encode
- whether different peers are expected to have distinct thresholds in practice

<a id="114-why-can-recurring-duress-checks-occur-on-some-rounds-but-not-others"></a>
### 11.4 Why can recurring duress checks occur on some rounds but not others?

[Back to TOC](#table-of-contents)

The peer has a nondeterministic choice between:
- sending the next ping directly
- or first running a recurring duress check

That means the model permits multiple valid operational policies, but does not
fix one.

<a id="115-what-is-the-exact-wire-protocol"></a>
### 11.5 What is the exact wire protocol?

[Back to TOC](#table-of-contents)

Several transfers are explicit messages, but some fanout steps are abstracted as
state delivery flags:
- `approval_collection_delivered`
- `commit_collection_delivered`
- `reached_collection_delivered`

So this is a protocol model, not a full network interface spec.

<a id="116-what-is-meant-by-hydrated-psbt"></a>
### 11.6 What is meant by "hydrated" PSBT?

[Back to TOC](#table-of-contents)

The peer moves from `psbt_i` to `hydrated_psbt_i` on readiness, but the model
does not describe what data hydration adds. The only enforced property is that
the hydrated PSBT still matches the locked txid.

<a id="12-suggested-human-review-checklist"></a>
## 12. Suggested Human Review Checklist

[Back to TOC](#table-of-contents)

A reviewer evaluating whether the spec matches intended protocol behavior should
ask at least the following:

- Does the initiator uniquely and correctly lock the session and tx?
- Are the freshness windows appropriate for the expected deployment?
- Is the WT bundle sufficient for non-initiators to safely adopt the PSBT?
- Is requiring local `txid_ack` before approval the right trust boundary?
- Is the initial duress check in the correct place relative to approvals and
  commits?
- Should non-initiators be blocked on both approval-bundle acceptance and
  initiator-commit acknowledgement?
- Is SAR intended to be authoritative, advisory, public, or deniable?
- Are placeholder kinds and SAR escalation semantics aligned with the real
  system's threat model?
- Is the `mystery` threshold logic actually the desired completion criterion?
- Is the minimum ping/pong distance sufficient to encode the intended time or
  block separation guarantee?
- Should fallback be allowed exactly under the modeled conditions?
- Is the no-signing-before-universal-ready rule too strict, too weak, or
  correct?

<a id="13-bottom-line-protocol-description"></a>
## 13. Bottom-Line Protocol Description

[Back to TOC](#table-of-contents)

In one sentence:

The protocol is a watchtower-coordinated, multi-peer withdrawal ceremony in
which the initiator fixes the transaction, all peers locally attest to that
choice, all peers commit with witnessable placeholders, the watchtower and SAR
jointly supervise a repeated ping/pong progress game until every peer has
reached its threshold, and only then may all peers sign and permit broadcast.

In slightly more operational language:

It is a fail-closed coordination protocol for a single withdrawal, with explicit
session locking, explicit freshness checks, placeholder witnessing, duress
signalling hooks, round-based progress exchange, universal readiness gating,
and an abstract fallback escape hatch.
