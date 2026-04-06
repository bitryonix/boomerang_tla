# Boomerang Withdrawal Core: Human Evaluation Notes

This document is an English reconstruction of the protocol modeled in
`BoomerangWithdrawalCore.tla`.

Scope and method:
- This write-up is derived only from `spec/BoomerangWithdrawalCore.tla`.
- It does not rely on any external design docs or prior versions.
- Where the spec is explicit, this document states the behavior directly.
- Where the spec implies intent but does not define it in plain English, this
  document marks that as an interpretation or inference.

Primary source anchors:
- Message constructors: lines 160-289
- Validation and helper predicates: lines 292-851
- Peer state machine: lines 935-1489
- Watchtower state machine: lines 1491-1739
- SAR process: lines 1741-1757
- Fallback monitor: lines 1759-1780
- Invariants and temporal properties: lines 4145-4606

## 1. Executive Summary

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

## 2. Parties and Their Responsibilities

### 2.1 Peers

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

### 2.2 Watchtower

The watchtower is the global coordinator. It:
- accepts and validates the initiator's starting submission
- distributes the initial bundle to non-initiators
- collects peer approvals
- collects commits and waits for corresponding SAR acknowledgements
- collects pings and produces per-peer pongs
- records which peers have reached the threshold for completion
- collects final signed PSBTs
- emits the abstract broadcast event

### 2.3 SAR

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

### 2.4 Fallback Monitor

Fallback is not a detailed alternative protocol in this model. It is an
abstract boundary condition. The fallback monitor:
- can mark peer hardware as lost
- can activate fallback for a peer if hardware is lost or `Milestone1` is
  reached
- prevents coexistence of fallback activation with boomerang signing completion

## 3. Core State Concepts

### 3.1 Locked Session and Locked Transaction

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

### 3.2 Freshness

Freshness is modeled with heights and bounded lag:
- approvals use `APPROVAL_FRESHNESS`
- commits use `COMMIT_FRESHNESS`
- pings use `PING_FRESHNESS`
- pongs use `PONG_FRESHNESS`

The watchtower and peers reject stale material. This means the protocol is not
just agreement on content; it is agreement on content that is recent enough
relative to observed chain height.

### 3.3 Placeholders

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

### 3.4 Mystery Counter and Reached Condition

Each peer has a private `mystery_i[self]` threshold and a local `counter_i`.
During the digging game, successful rounds can increment the counter. Once the
counter reaches the mystery threshold, `reached_mystery_flag_i[self]` becomes
true, and the peer starts advertising `reached = TRUE` in pings.

This means the protocol's completion condition is not a fixed round count. It
is peer-local and threshold-based.

## 4. Peer State Machine in Plain English

Peer states are declared near the top of the module and exercised in the
PlusCal process.

### 4.1 `ActiveReady`

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

### 4.2 `AwaitingInitialTxIdAck`

The peer locally accepts the pending `txid_challenge` and materializes the
matching `txid_ack`.

After that:
- the initiator sends `initiator_submission` to the watchtower
- a non-initiator sends a plain `approved` message

Then the peer moves to `AwaitingPeerApprovals`.

Meaning:
- no approval leaves a peer until it has a local secure-signer transcript for
  the exact session and txid.

### 4.3 `AwaitingPeerApprovals`

The peer waits until the watchtower indicates that the full approval collection
has been delivered.

At that point the peer creates an initial `duress_challenge` with:
- stage = `initial`
- seq = 0

Then it moves to `AwaitingInitialDuressAck`.

### 4.4 `AwaitingInitialDuressAck`

The peer receives a `duress_ack` with a boolean `consent_match`.

Immediate consequences:
- if `consent_match = TRUE`, the peer's payload kind becomes `padding`
- if `consent_match = FALSE`, the payload kind becomes `doxing_key`
- a failed consent match latches duress forever for that session path
- the peer increments its duress check counter

Then the peer moves to `InitialDuressResolved`.

### 4.5 `InitialDuressResolved`

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

### 4.6 `AwaitingWTInitiatorCommit`

Only non-initiators use this state. They wait for two conditions:
- the watchtower has accepted their `approvals_bundle`
- the initiator's commit has been acknowledged

Then they:
- allocate their own fresh placeholder
- define the expected SAR ack for commit phase, sequence 0
- emit their own `commit`
- move to `AwaitingCommitCollection`

This enforces a start-of-commit ordering: initiator commit first, others after.

### 4.7 `AwaitingCommitCollection`

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

### 4.8 `DiggingGame`

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

### 4.9 `AwaitingRecurringDuressAck`

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

### 4.10 `ReadyToSign`

The peer may sign only if:
- fallback is not active
- it has a hydrated PSBT
- it has a signing ticket
- every peer is in `ReadyToSign`, `Signed`, or `AwaitReset`
- no peer has fallback active
- every peer has the same signing ticket
- every peer has the expected SAR ack for its latest placeholder

Then the peer signs and emits `signed_psbt`, moving to `Signed`.

### 4.11 `Signed` and `AwaitReset`

After signing, the peer waits for the watchtower's `broadcast` message that
contains the same signing ticket.

Then it moves to `AwaitReset`, and after the global reset conditions hold it
returns to `ActiveReady` with most session-specific state cleared.

## 5. Watchtower State Machine in Plain English

### 5.1 `AwaitingInitiatorApproval`

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

### 5.2 `CollectingPeerApprovals`

WT repeatedly accepts `approved` messages from non-initiators if they are:
- well-formed
- signed by the claimed peer
- for the current session and tx
- fresh

Once all approvals are present, WT marks approval collection as delivered to all
peers and moves to `CollectingCommitments`.

### 5.3 `CollectingCommitments`

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

### 5.4 `CollectingPings`

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

### 5.5 `CollectingSignatures`

WT gathers one `signed_psbt` from each peer, checking:
- well-formedness
- peer signature
- session/tx binding
- ticket consistency with the peer's signing ticket
- PSBT-to-tx consistency

Once all signed PSBTs are present and the tickets agree, WT emits `broadcast`
and moves to `Broadcasted`.

### 5.6 `Broadcasted` and Reset

WT waits until all peers are in `AwaitReset`. It then:
- marks the session id as used
- increments completed withdrawals
- clears session-global volatile state
- returns to `AwaitingInitiatorApproval`

## 6. Message Catalogue

The following message shapes are explicit in the spec.

### 6.1 Approval and Session-Locking Messages

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

### 6.2 Local Signer Transcript Messages

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

### 6.3 Commit and Placeholder Witnessing Messages

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

### 6.4 Digging-Phase Messages

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

### 6.5 Signing and Broadcast Messages

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

## 7. End-to-End Message Passing Narrative

Below is the message flow in plain sequence form.

### 7.1 Session Start

1. Initiator locally forms `txid_challenge`.
2. Secure signer returns `txid_ack`.
3. Initiator sends `initiator_submission` to WT.
4. WT validates the submission and sends each non-initiator a `wt_bundle`.
5. Each non-initiator locally forms `txid_challenge`.
6. Secure signer returns `txid_ack`.
7. Each non-initiator sends `approved` to WT.

### 7.2 Approval Completion and Initial Duress

8. WT waits until all approvals are present.
9. Each peer performs an initial `duress_challenge`.
10. Secure signer returns `duress_ack`.
11. Each peer's payload kind becomes either `padding` or `doxing_key`.

### 7.3 Commit Phase

12. Initiator sends `commit` with its first placeholder.
13. SAR returns matching `sar_ack` for that placeholder.
14. Each non-initiator sends `approvals_bundle` to WT.
15. WT acknowledges the initiator commit to unlock the others.
16. Each non-initiator sends its own `commit`.
17. SAR returns matching `sar_ack` for each of those commits.
18. WT seals all commits and delivers the full commit collection.

### 7.4 Digging Rounds

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

### 7.5 Signing and Completion

27. Each peer hydrates the PSBT and receives a shared signing ticket.
28. Each peer sends `signed_psbt` to WT.
29. WT waits for all signatures and then emits `broadcast`.
30. Peers move to reset, and WT clears ceremony state.

## 8. Conditions That Block Progress

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

## 9. Security and Consistency Properties Visible in the Spec

The invariants near the end of the file show what the model considers
important.

### 9.1 Session and Transaction Binding

The protocol tries hard to ensure that once a session is active:
- all artifacts stay attached to the same session id
- all artifacts stay attached to the same txid
- no stale local signer transcripts are accepted for another session

### 9.2 Evidence Freshness

Accepted evidence must have been fresh at the height where it was accepted:
- approvals
- WT bundles
- commits
- pings
- pongs
- SAR acknowledgements
- local signer transcripts

### 9.3 Placeholder Authenticity and Replay Suppression

The model includes:
- monotone placeholder ownership and kind assignment
- SAR replay memory that only grows
- suppression of repeated SAR acknowledgement for the same placeholder id

### 9.4 No Early Signing

The model states several no-early-completion conditions:
- no boomerang signature before universal readiness
- one not-ready peer blocks broadcast
- broadcast only after all signed PSBTs are present

### 9.5 Duress Persistence

Once duress is latched, it never reverts during the ceremony:
- `PostDuressNoRevert`

That means a failed consent match permanently changes future placeholder
behavior for that peer in the current session path.

### 9.6 Fallback Separation

Fallback is constrained so that:
- it only happens after hardware loss or `Milestone1`
- it does not overlap with successful boomerang signing completion

## 10. Interpretation of the Protocol's Intent

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

## 11. Important Ambiguities or Open Questions for a Human Reviewer

These are not criticisms of the model. They are places where the code leaves
intent abstract or under-specified for an external reader.

### 11.1 What exactly is SAR?

The model makes SAR acknowledgements important, but does not explain:
- who operates SAR
- whether SAR is public, private, or append-only
- what it means to "acknowledge" a placeholder in real deployment terms

### 11.2 What do placeholders represent externally?

The spec defines placeholder ids and kinds but not:
- their serialized form
- whether they appear on chain, in PSBT metadata, or in an off-chain log
- how `padding` differs from `doxing_key` operationally

### 11.3 Why does the digging game require a private mystery threshold?

The mechanics are clear, but the rationale is not stated in the model:
- why each peer has a private threshold
- what security or privacy property that threshold is meant to encode
- whether different peers are expected to have distinct thresholds in practice

### 11.4 Why can recurring duress checks occur on some rounds but not others?

The peer has a nondeterministic choice between:
- sending the next ping directly
- or first running a recurring duress check

That means the model permits multiple valid operational policies, but does not
fix one.

### 11.5 What is the exact wire protocol?

Several transfers are explicit messages, but some fanout steps are abstracted as
state delivery flags:
- `approval_collection_delivered`
- `commit_collection_delivered`
- `reached_collection_delivered`

So this is a protocol model, not a full network interface spec.

### 11.6 What is meant by "hydrated" PSBT?

The peer moves from `psbt_i` to `hydrated_psbt_i` on readiness, but the model
does not describe what data hydration adds. The only enforced property is that
the hydrated PSBT still matches the locked txid.

## 12. Suggested Human Review Checklist

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

## 13. Bottom-Line Protocol Description

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
