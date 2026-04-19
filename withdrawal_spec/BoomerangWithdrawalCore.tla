---- MODULE BoomerangWithdrawalCore ----
EXTENDS Naturals, FiniteSets

(***************************************************************************)
(* Authoritative merged withdrawal model.                                  *)
(*                                                                         *)
(* This module replaces the earlier split between:                         *)
(* - the narrow PlusCal withdrawal-core slice, and                         *)
(* - the broader hand-written independent withdrawal model.                *)
(*                                                                         *)
(* Scope:                                                                  *)
(* - starts after setup has completed successfully                         *)
(* - models one boomerang-regime withdrawal ceremony                       *)
(* - keeps deterministic fallback only as an abstract boundary             *)
(* - signing export and WT broadcast are in abstract form                  *)
(*                                                                         *)
(* The design docs do not define one canonical withdrawal transcript id,   *)
(* one canonical SAR acknowledgement shape, or the exact MuSig2 export     *)
(* transcript. This model therefore makes those proof-boundary assumptions *)
(* explicit rather than silently relying on them.                          *)
(***************************************************************************)

CONSTANTS
    Peers,
    INITIATOR,
    Sessions,
    ChallengeNonces,
    PlaceholderIds,
    PSBTs,
    TXIDs,
    BlockHeights,
    DURESS_CHECK_INTERVAL_IN_BLOCKS,
    InitMystery,
    Milestone0,
    Milestone1,
    NoSession,
    NoTx,
    NoPsbt,
    NoMessage,
    NoPayload,
    NoSigner,
    ZeroPad,
    APPROVAL_FRESHNESS,
    COMMIT_FRESHNESS,
    PING_FRESHNESS,
    PONG_FRESHNESS,
    MIN_PING_PONG_DISTANCE,
    MAX_BLOCK_LAG_JUMP,
    TxOfPsbt

ASSUME
    /\ INITIATOR \in Peers
    /\ Cardinality(Peers) >= 2
    /\ IsFiniteSet(Peers)
    /\ IsFiniteSet(Sessions)
    /\ Sessions # {}
    /\ IsFiniteSet(ChallengeNonces)
    /\ ChallengeNonces # {}
    /\ IsFiniteSet(PlaceholderIds)
    /\ PlaceholderIds # {}
    /\ IsFiniteSet(PSBTs)
    /\ PSBTs # {}
    /\ IsFiniteSet(TXIDs)
    /\ TXIDs # {}
    /\ IsFiniteSet(BlockHeights)
    /\ BlockHeights # {}
    /\ BlockHeights \subseteq Nat
    /\ DURESS_CHECK_INTERVAL_IN_BLOCKS \in Nat
    /\ DURESS_CHECK_INTERVAL_IN_BLOCKS > 0
    /\ InitMystery \in [Peers -> Nat]
    /\ \A p \in Peers : InitMystery[p] > 0
    /\ Milestone0 \in BlockHeights
    /\ Milestone1 \in BlockHeights
    /\ Milestone0 <= Milestone1
    /\ APPROVAL_FRESHNESS \in Nat
    /\ COMMIT_FRESHNESS \in Nat
    /\ PING_FRESHNESS \in Nat
    /\ PONG_FRESHNESS \in Nat
    /\ MIN_PING_PONG_DISTANCE \in Nat
    /\ MAX_BLOCK_LAG_JUMP \in Nat
    /\ TxOfPsbt \in [PSBTs -> TXIDs]

WT_ID  == "WT"
SAR_ID == "SAR"
STSigner(i) == [kind |-> "st_signer", peer |-> i]
STSignerSet == {STSigner(i) : i \in Peers}

PeerStates == {
    "ActiveReady",
    "AwaitingNonInitiatorLocalApproval",
    "AwaitingInitialTxIdAck",
    "AwaitingPeerApprovals",
    "AwaitingInitialDuressAck",
    "InitialDuressResolved",
    "AwaitingWTInitiatorCommit",
    "AwaitingCommitCollection",
    "DiggingGame",
    "AwaitingRecurringDuressAck",
    "ReadyToSign",
    "Signed",
    "AwaitReset",
    "Fallback",
    "Terminal"
}

WTStates == {
    "AwaitingInitiatorApproval",
    "CollectingPeerApprovals",
    "CollectingCommitments",
    "CollectingPings",
    "CollectingSignatures",
    "Broadcasted"
}

PhaseKinds == {"commit", "ping"}
DuressStages == {"initial", "ping"}
PlaceholderKinds == {"unused", "padding", "doxing_key"}

SessionIds == Sessions \cup {NoSession}
TxDomain == TXIDs \cup {NoTx}
PlaceholderDomain == PlaceholderIds \cup {NoPayload}

OtherPeers(i) == Peers \ {i}

LowestBlock ==
    CHOOSE h \in BlockHeights : \A k \in BlockHeights : h <= k

(***************************************************************************)
(* TLC constant-binding helpers.                                           *)
(***************************************************************************)

FirstPsbt ==
    CHOOSE p \in PSBTs : TRUE

SecondPsbt ==
    IF Cardinality(PSBTs) > 1
    THEN CHOOSE p \in (PSBTs \ {FirstPsbt}) : TRUE
    ELSE FirstPsbt

FirstTxId ==
    CHOOSE t \in TXIDs : TRUE

SecondTxId ==
    IF Cardinality(TXIDs) > 1
    THEN CHOOSE t \in (TXIDs \ {FirstTxId}) : TRUE
    ELSE FirstTxId

ModelInitMysteryMain ==
    [ p \in Peers |-> IF p = INITIATOR THEN 1 ELSE 2 ]

ModelInitMysterySmall ==
    [ p \in Peers |-> 1 ]

ModelTxOfPsbt ==
    [ p \in PSBTs |->
        IF Cardinality(PSBTs) = 1 \/ Cardinality(TXIDs) = 1
        THEN FirstTxId
        ELSE IF p = FirstPsbt THEN FirstTxId ELSE SecondTxId ]

RecurringDuressPRNGDraws ==
    0..((2 * DURESS_CHECK_INTERVAL_IN_BLOCKS) - 1)

RecurringDuressCheckFires(draw) ==
    /\ draw \in RecurringDuressPRNGDraws
    /\ draw % DURESS_CHECK_INTERVAL_IN_BLOCKS = 0

(***************************************************************************)
(* Message constructors.                                                   *)
(***************************************************************************)

ApprovalMsgFor(sid0, txid0, i, h) ==
    [ kind      |-> "approved",
      sid       |-> sid0, (* session_id *)
      peer      |-> i,
      txid      |-> txid0,
      height    |-> h,
      signed_by |-> i ]

WTApprovalMsgFor(sid0, txid0, h) ==
    [ kind      |-> "wt_approved",
      sid       |-> sid0,
      initiator |-> INITIATOR,
      txid      |-> txid0,
      height    |-> h,
      signed_by |-> WT_ID ]

InitiatorSubmissionMsgFor(sid0, txid0, h, p) ==
    [ kind               |-> "initiator_submission",
      sid                |-> sid0,
      initiator_approval |-> ApprovalMsgFor(sid0, txid0, INITIATOR, h),
      psbt               |-> p ]

WTBundleMsgFor(sid0, p, initAppr, wtAppr) ==
    [ kind               |-> "wt_bundle",
      sid                |-> sid0,
      psbt               |-> p,
      initiator_approval |-> initAppr,
      wt_approval        |-> wtAppr,
      signed_by          |-> WT_ID ]

ApprovalsBundleMsgFor(sid0, i, approvals, wtAppr) ==
    [ kind        |-> "approvals_bundle",
      sid         |-> sid0,
      peer        |-> i,
      approvals   |-> approvals,
      wt_approval |-> wtAppr,
      signed_by   |-> i ]

CommitMsgFor(sid0, txid0, i, h, placeholder0) ==
    [ kind         |-> "commit",
      sid          |-> sid0,
      peer         |-> i,
      txid         |-> txid0,
      height       |-> h,
      placeholder  |-> placeholder0,
      signed_by    |-> i,
      wt_signed_by |-> NoSigner ]

SARAckMsgFor(sid0, txid0, i, phase0, seq0, placeholder0) ==
    [ kind      |-> "sar_ack",
      sid       |-> sid0,
      peer      |-> i,
      txid      |-> txid0,
      phase     |-> phase0,
      seq       |-> seq0,
      placeholder |-> placeholder0,
      signed_by |-> SAR_ID ]

PingMsgFor(sid0, txid0, i, lastSeen, seq0, reached0, placeholder0) ==
    [ kind            |-> "ping",
      sid             |-> sid0,
      peer            |-> i,
      txid            |-> txid0,
      last_seen_block |-> lastSeen,
      ping_seq_num    |-> seq0,
      reached         |-> reached0,
      placeholder     |-> placeholder0,
      signed_by       |-> i ]

PongMsgFor(sid0, txid0, i, wtHeight, roundPings, ack0) ==
    [ kind        |-> "pong",
      sid         |-> sid0,
      to          |-> i,
      txid        |-> txid0,
      wt_height   |-> wtHeight,
      other_pings |-> [j \in OtherPeers(i) |-> roundPings[j]],
      sar_ack     |-> ack0,
      signed_by   |-> WT_ID ]

SignedPsbtMsgFor(sid0, txid0, i, p, ticket0) ==
    [ kind      |-> "signed_psbt",
      sid       |-> sid0,
      peer      |-> i,
      txid      |-> txid0,
      psbt      |-> p,
      ticket    |-> ticket0,
      signed_by |-> i ]

BroadcastMsgFor(sid0, txid0, ticket0) ==
    [ kind      |-> "broadcast",
      sid       |-> sid0,
      txid      |-> txid0,
      ticket    |-> ticket0,
      signed_by |-> WT_ID ]

TxIdChallengeMsgFor(sid0, txid0, i, nonce0) ==
    [ kind      |-> "txid_challenge",
      sid       |-> sid0,
      peer      |-> i,
      txid      |-> txid0,
      nonce     |-> nonce0,
      signed_by |-> i ]

TxIdAckMsgFor(sid0, txid0, i, nonce0) ==
    [ kind      |-> "txid_ack",
      sid       |-> sid0,
      peer      |-> i,
      txid      |-> txid0,
      nonce     |-> nonce0,
      signed_by |-> STSigner(i) ]

DuressChallengeMsgFor(sid0, txid0, i, stage0, seq0, nonce0) ==
    [ kind      |-> "duress_challenge",
      sid       |-> sid0,
      peer      |-> i,
      txid      |-> txid0,
      stage     |-> stage0,
      seq       |-> seq0,
      nonce     |-> nonce0,
      signed_by |-> i ]

DuressAckMsgFor(sid0, txid0, i, stage0, seq0, nonce0, consentMatch0) ==
    [ kind          |-> "duress_ack",
      sid           |-> sid0,
      peer          |-> i,
      txid          |-> txid0,
      stage         |-> stage0,
      seq           |-> seq0,
      nonce         |-> nonce0,
      consent_match |-> consentMatch0,
      signed_by     |-> STSigner(i) ]

(***************************************************************************)
(* Structural helpers.                                                     *)
(***************************************************************************)

SameTxId(psbt, txid0) ==
    IF psbt \in PSBTs THEN TxOfPsbt[psbt] = txid0 ELSE FALSE

SigningTicketFor(sid0, txid0) ==
    [ kind      |-> "signing_ticket",
      sid       |-> sid0,
      txid      |-> txid0 ]

Fresh(sentHeight, observedHeight, limit) ==
    /\ sentHeight \in Nat
    /\ observedHeight \in Nat
    /\ sentHeight <= observedHeight
    /\ observedHeight - sentHeight <= limit

ApprovalWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "height", "signed_by"}
    /\ m.kind = "approved"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.height \in Nat
    /\ m.signed_by \in Peers

WTApprovalWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "initiator", "txid", "height", "signed_by"}
    /\ m.kind = "wt_approved"
    /\ m.sid \in SessionIds
    /\ m.initiator \in Peers
    /\ m.txid \in TxDomain
    /\ m.height \in Nat
    /\ m.signed_by = WT_ID

WTViewWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"sid", "txid", "initiator", "height"}
    /\ m.sid \in SessionIds
    /\ m.txid \in TxDomain
    /\ m.initiator \in Peers
    /\ m.height \in Nat

InitiatorSubmissionWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "initiator_approval", "psbt"}
    /\ m.kind = "initiator_submission"
    /\ m.sid \in SessionIds
    /\ m.initiator_approval # NoMessage
    /\ ApprovalWellFormed(m.initiator_approval)
    /\ m.psbt \in PSBTs

WTBundleWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "psbt", "initiator_approval", "wt_approval", "signed_by"}
    /\ m.kind = "wt_bundle"
    /\ m.sid \in SessionIds
    /\ m.psbt \in PSBTs
    /\ m.initiator_approval # NoMessage
    /\ ApprovalWellFormed(m.initiator_approval)
    /\ m.wt_approval # NoMessage
    /\ WTApprovalWellFormed(m.wt_approval)
    /\ m.signed_by = WT_ID

BundleWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "approvals", "wt_approval", "signed_by"}
    /\ m.kind = "approvals_bundle"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ DOMAIN m.approvals = Peers
    /\ \A p \in Peers : ApprovalWellFormed(m.approvals[p])
    /\ m.wt_approval # NoMessage
    /\ WTApprovalWellFormed(m.wt_approval)
    /\ m.signed_by \in Peers

CommitWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "height", "placeholder", "signed_by", "wt_signed_by"}
    /\ m.kind = "commit"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.height \in Nat
    /\ m.placeholder \in PlaceholderDomain
    /\ m.signed_by \in Peers
    /\ m.wt_signed_by \in {WT_ID, NoSigner}

SARAckWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "phase", "seq", "placeholder", "signed_by"}
    /\ m.kind = "sar_ack"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.phase \in PhaseKinds
    /\ m.seq \in Nat
    /\ m.placeholder \in PlaceholderDomain
    /\ m.signed_by = SAR_ID

PingWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "last_seen_block", "ping_seq_num", "reached", "placeholder", "signed_by"}
    /\ m.kind = "ping"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.last_seen_block \in Nat
    /\ m.ping_seq_num \in Nat
    /\ m.reached \in BOOLEAN
    /\ m.placeholder \in PlaceholderDomain
    /\ m.signed_by \in Peers

PongWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "to", "txid", "wt_height", "other_pings", "sar_ack", "signed_by"}
    /\ m.kind = "pong"
    /\ m.sid \in SessionIds
    /\ m.to \in Peers
    /\ m.txid \in TxDomain
    /\ m.wt_height \in Nat
    /\ DOMAIN m.other_pings = OtherPeers(m.to)
    /\ \A j \in OtherPeers(m.to) :
         /\ m.other_pings[j] # NoMessage
         /\ PingWellFormed(m.other_pings[j])
    /\ m.sar_ack # NoMessage
    /\ SARAckWellFormed(m.sar_ack)
    /\ m.signed_by = WT_ID

SigningTicketWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "txid"}
    /\ m.kind = "signing_ticket"
    /\ m.sid \in SessionIds
    /\ m.txid \in TxDomain

SignedPsbtWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "psbt", "ticket", "signed_by"}
    /\ m.kind = "signed_psbt"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.psbt \in PSBTs
    /\ SigningTicketWellFormed(m.ticket)
    /\ m.signed_by \in Peers

BroadcastWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "txid", "ticket", "signed_by"}
    /\ m.kind = "broadcast"
    /\ m.sid \in SessionIds
    /\ m.txid \in TxDomain
    /\ SigningTicketWellFormed(m.ticket)
    /\ m.signed_by = WT_ID

TxIdChallengeWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "nonce", "signed_by"}
    /\ m.kind = "txid_challenge"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.nonce \in ChallengeNonces
    /\ m.signed_by = m.peer

TxIdAckWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "nonce", "signed_by"}
    /\ m.kind = "txid_ack"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.nonce \in ChallengeNonces
    /\ m.signed_by = STSigner(m.peer)

DuressChallengeWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "stage", "seq", "nonce", "signed_by"}
    /\ m.kind = "duress_challenge"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.stage \in DuressStages
    /\ m.seq \in Nat
    /\ m.nonce \in ChallengeNonces
    /\ m.signed_by = m.peer

DuressAckWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "sid", "peer", "txid", "stage", "seq", "nonce", "consent_match", "signed_by"}
    /\ m.kind = "duress_ack"
    /\ m.sid \in SessionIds
    /\ m.peer \in Peers
    /\ m.txid \in TxDomain
    /\ m.stage \in DuressStages
    /\ m.seq \in Nat
    /\ m.nonce \in ChallengeNonces
    /\ m.consent_match \in BOOLEAN
    /\ m.signed_by = STSigner(m.peer)

SubmissionApproval(m) ==
    IF m # NoMessage /\ InitiatorSubmissionWellFormed(m) THEN m.initiator_approval ELSE NoMessage

SubmissionPsbt(m) ==
    IF m # NoMessage /\ InitiatorSubmissionWellFormed(m) THEN m.psbt ELSE NoPsbt

WTBundleApproval(m) ==
    IF m # NoMessage /\ WTBundleWellFormed(m) THEN m.initiator_approval ELSE NoMessage

WTBundleWTApproval(m) ==
    IF m # NoMessage /\ WTBundleWellFormed(m) THEN m.wt_approval ELSE NoMessage

WTBundlePsbt(m) ==
    IF m # NoMessage /\ WTBundleWellFormed(m) THEN m.psbt ELSE NoPsbt

ApprovalsBundleApprovals(m) ==
    IF m # NoMessage /\ BundleWellFormed(m) THEN m.approvals ELSE [i \in Peers |-> NoMessage]

ApprovalsBundleWTApproval(m) ==
    IF m # NoMessage /\ BundleWellFormed(m) THEN m.wt_approval ELSE NoMessage

CommitPlaceholder(m) ==
    IF m # NoMessage /\ CommitWellFormed(m) THEN m.placeholder ELSE NoPayload

PingPlaceholder(m) ==
    IF m # NoMessage /\ PingWellFormed(m) THEN m.placeholder ELSE NoPayload

PingReached(m) ==
    IF m # NoMessage /\ PingWellFormed(m) THEN m.reached ELSE FALSE

PingSeqNum(m) ==
    IF m # NoMessage /\ PingWellFormed(m) THEN m.ping_seq_num ELSE 0

SealCommit(m) ==
    IF m # NoMessage /\ CommitWellFormed(m)
    THEN [m EXCEPT !.wt_signed_by = WT_ID]
    ELSE m

SignedPsbtTicket(m) ==
    IF m # NoMessage /\ SignedPsbtWellFormed(m) THEN m.ticket ELSE NoMessage

BroadcastTicket(m) ==
    IF m # NoMessage /\ BroadcastWellFormed(m) THEN m.ticket ELSE NoMessage

TxIdAckMatchesChallenge(ack0, challenge0) ==
    /\ ack0 # NoMessage
    /\ challenge0 # NoMessage
    /\ TxIdAckWellFormed(ack0)
    /\ TxIdChallengeWellFormed(challenge0)
    /\ ack0 = TxIdAckMsgFor(
        challenge0.sid,
        challenge0.txid,
        challenge0.peer,
        challenge0.nonce)

DuressAckMatchesChallenge(ack0, challenge0) ==
    /\ ack0 # NoMessage
    /\ challenge0 # NoMessage
    /\ DuressAckWellFormed(ack0)
    /\ DuressChallengeWellFormed(challenge0)
    /\ ack0.sid = challenge0.sid
    /\ ack0.peer = challenge0.peer
    /\ ack0.txid = challenge0.txid
    /\ ack0.stage = challenge0.stage
    /\ ack0.seq = challenge0.seq
    /\ ack0.nonce = challenge0.nonce
    /\ ack0.signed_by = STSigner(challenge0.peer)

ValidSig(m, signer) ==
    IF m = NoMessage THEN FALSE ELSE m.signed_by = signer

WTSigned(m) ==
    IF m # NoMessage /\ CommitWellFormed(m) THEN m.wt_signed_by = WT_ID ELSE FALSE

MsgSessionMatches(m, sid0) ==
    IF m = NoMessage THEN TRUE
    ELSE CASE m.kind = "approved"     -> ApprovalWellFormed(m) /\ m.sid = sid0
         [] m.kind = "wt_approved"  -> WTApprovalWellFormed(m) /\ m.sid = sid0
         [] m.kind = "commit"       -> CommitWellFormed(m) /\ m.sid = sid0
         [] m.kind = "sar_ack"      -> SARAckWellFormed(m) /\ m.sid = sid0
         [] m.kind = "ping"         -> PingWellFormed(m) /\ m.sid = sid0
         [] m.kind = "pong"         -> PongWellFormed(m) /\ m.sid = sid0
         [] m.kind = "signed_psbt"  -> SignedPsbtWellFormed(m) /\ m.sid = sid0
         [] m.kind = "broadcast"    -> BroadcastWellFormed(m) /\ m.sid = sid0
         [] m.kind = "txid_challenge" -> TxIdChallengeWellFormed(m) /\ m.sid = sid0
         [] m.kind = "txid_ack"     -> TxIdAckWellFormed(m) /\ m.sid = sid0
         [] m.kind = "duress_challenge" -> DuressChallengeWellFormed(m) /\ m.sid = sid0
         [] m.kind = "duress_ack"   -> DuressAckWellFormed(m) /\ m.sid = sid0
         [] OTHER                   -> FALSE

MsgTxMatches(m, txid0) ==
    IF m = NoMessage THEN TRUE
    ELSE CASE m.kind = "approved"     -> ApprovalWellFormed(m) /\ m.txid = txid0
         [] m.kind = "wt_approved"  -> WTApprovalWellFormed(m) /\ m.txid = txid0
         [] m.kind = "commit"       -> CommitWellFormed(m) /\ m.txid = txid0
         [] m.kind = "sar_ack"      -> SARAckWellFormed(m) /\ m.txid = txid0
         [] m.kind = "ping"         -> PingWellFormed(m) /\ m.txid = txid0
         [] m.kind = "pong"         -> PongWellFormed(m) /\ m.txid = txid0
         [] m.kind = "signed_psbt"  -> SignedPsbtWellFormed(m) /\ m.txid = txid0
         [] m.kind = "broadcast"    -> BroadcastWellFormed(m) /\ m.txid = txid0
         [] m.kind = "txid_challenge" -> TxIdChallengeWellFormed(m) /\ m.txid = txid0
         [] m.kind = "txid_ack"     -> TxIdAckWellFormed(m) /\ m.txid = txid0
         [] m.kind = "duress_challenge" -> DuressChallengeWellFormed(m) /\ m.txid = txid0
         [] m.kind = "duress_ack"   -> DuressAckWellFormed(m) /\ m.txid = txid0
         [] OTHER                   -> FALSE

PsbtTxMatches(p, txid0) ==
    IF p = NoPsbt THEN TRUE ELSE SameTxId(p, txid0)

ApprovalFreshAtWT(m, wtHeight) ==
    IF m # NoMessage /\ ApprovalWellFormed(m)
    THEN Fresh(m.height, wtHeight, APPROVAL_FRESHNESS)
    ELSE FALSE

ApprovalFreshRelative(m, otherHeight) ==
    IF m # NoMessage /\ ApprovalWellFormed(m)
    THEN Fresh(m.height, otherHeight, APPROVAL_FRESHNESS)
    ELSE FALSE

WTApprovalFreshAtPeer(m, peerHeight) ==
    IF m # NoMessage /\ WTApprovalWellFormed(m)
    THEN Fresh(m.height, peerHeight, APPROVAL_FRESHNESS)
    ELSE FALSE

WTBundleApprovalWindowValid(initAppr, wtAppr, observerHeight) ==
    /\ initAppr # NoMessage
    /\ wtAppr # NoMessage
    /\ ApprovalWellFormed(initAppr)
    /\ WTApprovalWellFormed(wtAppr)
    /\ initAppr.height <= wtAppr.height
    /\ wtAppr.height <= observerHeight
    /\ wtAppr.height - initAppr.height <= APPROVAL_FRESHNESS
    /\ observerHeight - wtAppr.height <= APPROVAL_FRESHNESS

PostWTApprovalWindowValid(appr, wtAppr, observerHeight) ==
    /\ appr # NoMessage
    /\ wtAppr # NoMessage
    /\ ApprovalWellFormed(appr)
    /\ WTApprovalWellFormed(wtAppr)
    /\ wtAppr.height <= appr.height
    /\ appr.height <= observerHeight
    /\ appr.height - wtAppr.height <= APPROVAL_FRESHNESS
    /\ observerHeight - appr.height <= APPROVAL_FRESHNESS

CommitFreshAtWT(m, wtHeight) ==
    IF m # NoMessage /\ CommitWellFormed(m)
    THEN Fresh(m.height, wtHeight, COMMIT_FRESHNESS)
    ELSE FALSE

CommitFreshAtPeer(m, peerHeight) ==
    IF m # NoMessage /\ CommitWellFormed(m)
    THEN Fresh(m.height, peerHeight, COMMIT_FRESHNESS)
    ELSE FALSE

PingFreshAtWT(m, wtHeight) ==
    IF m # NoMessage /\ PingWellFormed(m)
    THEN Fresh(m.last_seen_block, wtHeight, PING_FRESHNESS)
    ELSE FALSE

PongFreshAtPeer(m, peerHeight) ==
    IF m # NoMessage /\ PongWellFormed(m)
    THEN Fresh(m.wt_height, peerHeight, PONG_FRESHNESS)
    ELSE FALSE

ApprovalFreshAtWitness(m, witnessHeight) ==
    IF m # NoMessage /\ ApprovalWellFormed(m)
    THEN Fresh(m.height, witnessHeight, APPROVAL_FRESHNESS)
    ELSE FALSE

WTBundleFreshAtWitness(m, witnessHeight) ==
    LET wtAppr == WTBundleWTApproval(m)
        initAppr == WTBundleApproval(m)
    IN /\ m # NoMessage
       /\ WTBundleWellFormed(m)
       /\ WTBundleApprovalWindowValid(initAppr, wtAppr, witnessHeight)

CommitFreshAtWitness(m, witnessHeight) ==
    IF m # NoMessage /\ CommitWellFormed(m)
    THEN Fresh(m.height, witnessHeight, COMMIT_FRESHNESS)
    ELSE FALSE

PingFreshAtWitness(m, witnessHeight) ==
    IF m # NoMessage /\ PingWellFormed(m)
    THEN Fresh(m.last_seen_block, witnessHeight, PING_FRESHNESS)
    ELSE FALSE

PongFreshAtWitness(m, witnessHeight) ==
    IF m # NoMessage /\ PongWellFormed(m)
    THEN Fresh(m.wt_height, witnessHeight, PONG_FRESHNESS)
    ELSE FALSE

ExpectedAck(sid0, txid0, i, phase0, seq0, payload0) ==
    SARAckMsgFor(sid0, txid0, i, phase0, seq0, payload0)

AckMatchesExpected(ack0, expected0) ==
    /\ ack0 # NoMessage
    /\ expected0 # NoMessage
    /\ SARAckWellFormed(ack0)
    /\ ack0 = expected0

NisoAcceptsWTBundle(i, m, sid0, txid0, peerHeight) ==
    LET wtAppr == WTBundleWTApproval(m)
        initAppr == WTBundleApproval(m)
        p == WTBundlePsbt(m)
    IN /\ m # NoMessage
       /\ WTBundleWellFormed(m)
       /\ m.sid = sid0
       /\ ValidSig(wtAppr, WT_ID)
       /\ ValidSig(initAppr, INITIATOR)
       /\ initAppr.peer = INITIATOR
       /\ wtAppr.initiator = initAppr.peer
       /\ MsgSessionMatches(initAppr, sid0)
       /\ MsgSessionMatches(wtAppr, sid0)
       /\ MsgTxMatches(initAppr, txid0)
       /\ MsgTxMatches(wtAppr, txid0)
       /\ SameTxId(p, txid0)
       /\ peerHeight >= Milestone0
       /\ WTBundleApprovalWindowValid(initAppr, wtAppr, peerHeight)

BoomletAcceptsWTBundle(i, m, sid0, txid0, peerHeight) ==
    NisoAcceptsWTBundle(i, m, sid0, txid0, peerHeight)

NisoValidApprovalCollectionForPeer(i, delivered, approvals, wtAppr, sid0, txid0, peerHeight) ==
    /\ delivered
    /\ wtAppr # NoMessage
    /\ WTApprovalWellFormed(wtAppr)
    /\ ValidSig(wtAppr, WT_ID)
    /\ wtAppr.sid = sid0
    /\ wtAppr.txid = txid0
    /\ WTApprovalFreshAtPeer(wtAppr, peerHeight)
    /\ \A p \in Peers :
         LET a == approvals[p] IN
         IF a # NoMessage /\ ApprovalWellFormed(a) THEN
             /\ ValidSig(a, p)
             /\ a.peer = p
             /\ a.sid = sid0
             /\ a.txid = txid0
             /\ IF p = INITIATOR
                   THEN WTBundleApprovalWindowValid(a, wtAppr, peerHeight)
                   ELSE PostWTApprovalWindowValid(a, wtAppr, peerHeight)
         ELSE FALSE

BoomletValidApprovalCollectionForPeer(i, delivered, approvals, wtAppr, sid0, txid0, peerHeight) ==
    NisoValidApprovalCollectionForPeer(
        i,
        delivered,
        approvals,
        wtAppr,
        sid0,
        txid0,
        peerHeight)

NisoValidCommitCollectionForPeer(i, delivered, commitCollection, sid0, txid0, peerHeight) ==
    /\ delivered
    /\ \A p \in Peers :
         LET c == commitCollection[p] IN
         IF c # NoMessage /\ CommitWellFormed(c) THEN
             /\ ValidSig(c, p)
             /\ c.peer = p
             /\ WTSigned(c)
             /\ c.sid = sid0
             /\ c.txid = txid0
             /\ CommitFreshAtPeer(c, peerHeight)
         ELSE FALSE

BoomletValidCommitCollectionForPeer(i, delivered, commitCollection, sid0, txid0, peerHeight, ack0, expected0) ==
    /\ NisoValidCommitCollectionForPeer(i, delivered, commitCollection, sid0, txid0, peerHeight)
    /\ AckMatchesExpected(ack0, expected0)

NisoValidInitiatorCommitForPeer(i, delivered, commit0, sid0, txid0, peerHeight, accepted0) ==
    /\ i \in OtherPeers(INITIATOR)
    /\ delivered
    /\ commit0 # NoMessage
    /\ accepted0 # NoMessage
    /\ CommitWellFormed(commit0)
    /\ CommitWellFormed(accepted0)
    /\ ValidSig(commit0, INITIATOR)
    /\ commit0.peer = INITIATOR
    /\ WTSigned(commit0)
    /\ commit0.sid = sid0
    /\ commit0.txid = txid0
    /\ CommitFreshAtPeer(commit0, peerHeight)
    /\ commit0 = accepted0

BoomletValidInitiatorCommitForPeer(i, delivered, commit0, sid0, txid0, peerHeight, accepted0) ==
    NisoValidInitiatorCommitForPeer(
        i,
        delivered,
        commit0,
        sid0,
        txid0,
        peerHeight,
        accepted0)

PingObservedWithinBoundary(lastSeen, observerHeight) ==
    /\ lastSeen \in Nat
    /\ observerHeight \in Nat
    /\ lastSeen <= observerHeight
    /\ observerHeight - lastSeen <= PING_FRESHNESS + MAX_BLOCK_LAG_JUMP

PingProgressesFrom(prev, next, observerHeight) ==
    /\ next # NoMessage
    /\ PingWellFormed(next)
    /\ PingObservedWithinBoundary(next.last_seen_block, observerHeight)
    /\ IF prev = NoMessage THEN
          /\ next.ping_seq_num = 0
          /\ ~next.reached
       ELSE
          /\ PingWellFormed(prev)
          /\ next.ping_seq_num > prev.ping_seq_num
          /\ next.last_seen_block >= prev.last_seen_block
          /\ PingObservedWithinBoundary(prev.last_seen_block, observerHeight)

RoundPingsSatisfyMinimumPongDistance(roundPings, wtHeight) ==
    \A i \in Peers :
        /\ roundPings[i] # NoMessage
        /\ PingWellFormed(roundPings[i])
        /\ roundPings[i].last_seen_block + MIN_PING_PONG_DISTANCE <= wtHeight

IncludedPingsConsistentFor(i, pong, reachedSeen, sid0, txid0, peerHeight, reviewedHistory) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      /\ pong.to = i
      /\ DOMAIN(pong.other_pings) = OtherPeers(i)
      /\ \A j \in OtherPeers(i) :
           LET q == pong.other_pings[j] IN
           /\ ValidSig(q, j)
           /\ q.peer = j
           /\ q.sid = sid0
           /\ q.txid = txid0
           /\ PingFreshAtWitness(q, peerHeight)
           /\ PingProgressesFrom(reviewedHistory[j], q, peerHeight)
           /\ (j \in reachedSeen => PingReached(q))
           /\ q.last_seen_block + MIN_PING_PONG_DISTANCE <= pong.wt_height
    ELSE FALSE

NisoValidPongForPeer(i, pong, sid0, txid0, peerHeight, reachedSeen, reviewedHistory) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      /\ ValidSig(pong, WT_ID)
      /\ pong.to = i
      /\ pong.sid = sid0
      /\ pong.txid = txid0
      /\ PongFreshAtPeer(pong, peerHeight)
      /\ IncludedPingsConsistentFor(i, pong, reachedSeen, sid0, txid0, peerHeight, reviewedHistory)
    ELSE FALSE

BoomletValidPongForPeer(i, pong, sid0, txid0, peerHeight, reachedSeen, expected0, reviewedHistory) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      /\ NisoValidPongForPeer(i, pong, sid0, txid0, peerHeight, reachedSeen, reviewedHistory)
      /\ AckMatchesExpected(pong.sar_ack, expected0)
    ELSE FALSE

AllApprovalsPresent(approvals) ==
    \A i \in Peers : approvals[i] # NoMessage

AllCommitsPresent(commits) ==
    \A i \in Peers : commits[i] # NoMessage

AllRoundPingsPresent(roundPings) ==
    \A i \in Peers : roundPings[i] # NoMessage

AllRoundSARRepliesPresent(acks) ==
    \A i \in Peers : acks[i] # NoMessage

AllSignedPsbtsPresent(coll) ==
    \A i \in Peers : coll[i] # NoMessage

WTAllReached(reachedPings) ==
    \A i \in Peers : reachedPings[i] # NoMessage

ReachedPeersAdvertised(i, pong) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      IF /\ pong.to = i
         /\ DOMAIN(pong.other_pings) = OtherPeers(i)
      THEN {j \in OtherPeers(i) : pong.other_pings[j].reached}
      ELSE {}
    ELSE {}

ReachedPingMatchesSessionTx(m, sid0, txid0) ==
    IF m # NoMessage /\ PingWellFormed(m) THEN
      /\ m.reached
      /\ m.sid = sid0
      /\ m.txid = txid0
    ELSE FALSE

ReachedPingConsistentForPeer(i, j, q, sid0, txid0, peerHeight, reviewedHistory, reachedSeen) ==
    /\ q # NoMessage
    /\ PingWellFormed(q)
    /\ ValidSig(q, j)
    /\ q.peer = j
    /\ q.sid = sid0
    /\ q.txid = txid0
    /\ q.reached
    /\ PingFreshAtWitness(q, peerHeight)
    /\ IF j = i
          THEN TRUE
          ELSE PingProgressesFrom(reviewedHistory[j], q, peerHeight)
    /\ (j \in reachedSeen => q.reached)
    /\ (reviewedHistory[j] # NoMessage /\ PingReached(reviewedHistory[j]) => q.reached)

ReachedCollectionValidForPeer(i, delivered, coll, sid0, txid0, peerHeight, reviewedHistory, reachedSeen) ==
    /\ delivered
    /\ \A j \in Peers :
         ReachedPingConsistentForPeer(
             i,
             j,
             coll[j],
             sid0,
             txid0,
             peerHeight,
             reviewedHistory,
             reachedSeen)

HigherBlocks(b) == {h \in BlockHeights : h > b}

LeastHigher(b) ==
    CHOOSE h \in HigherBlocks(b) : \A k \in HigherBlocks(b) : h <= k

Min2(a, b) ==
    IF a <= b THEN a ELSE b

CanIncrement(lastSeen, localHeight, pong, reviewHistory, i, sid0, txid0, reachedSeen) ==
    /\ localHeight > lastSeen
    /\ localHeight - lastSeen <= MAX_BLOCK_LAG_JUMP
    /\ IncludedPingsConsistentFor(
        i,
        pong,
        reachedSeen,
        sid0,
        txid0,
        localHeight,
        reviewHistory)

NextCounter(counter, lastSeen, localHeight, pong, reviewHistory, i, sid0, txid0, reachedSeen) ==
    IF CanIncrement(lastSeen, localHeight, pong, reviewHistory, i, sid0, txid0, reachedSeen)
    THEN counter + 1
    ELSE counter

NextReached(reachedFlag, counter, lastSeen, localHeight, mystery, pong, reviewHistory, i, sid0, txid0, reachedSeen) ==
    reachedFlag \/
    (NextCounter(
        counter,
        lastSeen,
        localHeight,
        pong,
        reviewHistory,
        i,
        sid0,
        txid0,
        reachedSeen) >= mystery)

NextLastSeen(lastSeen, localHeight) ==
    IF /\ localHeight > lastSeen
       /\ localHeight - lastSeen <= MAX_BLOCK_LAG_JUMP
       THEN Min2(localHeight, lastSeen + MAX_BLOCK_LAG_JUMP)
       ELSE lastSeen

DiggingReplyKind(latched, currentKind, fireCheck, signal) ==
    IF latched \/ (fireCheck /\ signal)
       THEN "doxing_key"
       ELSE IF fireCheck THEN "padding" ELSE currentKind

DiggingReplyLatched(latched, fireCheck, signal) ==
    latched \/ (fireCheck /\ signal)

(***************************************************************************)
(* Merged PlusCal ceremony.                                                *)
(***************************************************************************)

(*--algorithm WithdrawalMerged
variables
    mystery_i = InitMystery,
    used_sessions = {},
    completed_withdrawals = 0,
    session_id = NoSession,
    tx_id = NoTx,
    current_placeholder_i = [i \in Peers |-> NoPayload],
    placeholder_owner = [pid \in PlaceholderIds |-> NoSigner],
    placeholder_kind = [pid \in PlaceholderIds |-> "unused"],
    psbt_i = [i \in Peers |-> NoPsbt],
    hydrated_psbt_i = [i \in Peers |-> NoPsbt],
    signed_psbt_i = [i \in Peers |-> NoPsbt],
    signing_ticket_i = [i \in Peers |-> NoMessage],
    local_psbt_reviewed_i = [i \in Peers |-> FALSE],
    pending_txid_challenge_i = [i \in Peers |-> NoMessage],
    accepted_txid_challenge_i = [i \in Peers |-> NoMessage],
    accepted_txid_ack_i = [i \in Peers |-> NoMessage],
    accepted_txid_ack_height_i = [i \in Peers |-> LowestBlock],
    pending_duress_challenge_i = [i \in Peers |-> NoMessage],
    accepted_duress_challenge_i = [i \in Peers |-> NoMessage],
    accepted_duress_ack_i = [i \in Peers |-> NoMessage],
    accepted_duress_ack_height_i = [i \in Peers |-> LowestBlock],
    current_ping_from_recurring_check_i = [i \in Peers |-> FALSE],
    peer_state = [i \in Peers |-> "ActiveReady"],
    wt_state = "AwaitingInitiatorApproval",
    wt_session_view = NoMessage,
    peer_tx_approval_collection = [i \in Peers |-> NoMessage],
    wt_tx_approval = NoMessage,
    approval_outbox = [i \in Peers |-> NoMessage],
    wt_bundle_inbox = [i \in Peers |-> NoMessage],
    approval_collection_delivered = [i \in Peers |-> FALSE],
    payload_kind_i = [i \in Peers |-> "none"],
    duress_latched_i = [i \in Peers |-> FALSE],
    duress_checks_i = [i \in Peers |-> 0],
    approval_bundle_outbox = [i \in Peers |-> NoMessage],
    approvals_bundle_accepted = [i \in Peers |-> FALSE],
    commit_outbox = [i \in Peers |-> NoMessage],
    initiator_commit_acked = [i \in Peers |-> FALSE],
    initiator_commit_inbox = [i \in Peers |-> NoMessage],
    peer_tx_commit_collection = [i \in Peers |-> NoMessage],
    commit_collection_delivered = [i \in Peers |-> FALSE],
    saved_expected_sar_ack = [i \in Peers |-> NoMessage],
    sar_pending_ack_request = [i \in Peers |-> NoMessage],
    sar_ack_i = [i \in Peers |-> NoMessage],
    sar_seen_placeholder_ids_i = [i \in Peers |-> {}],
    sar_escalated_i = [i \in Peers |-> FALSE],
    wt_round_pings = [i \in Peers |-> NoMessage],
    wt_last_accepted_ping = [i \in Peers |-> NoMessage],
    peer_reviewed_ping_history_i = [i \in Peers |-> [j \in Peers |-> NoMessage]],
    pong_i = [i \in Peers |-> NoMessage],
    reached_collection_delivered = [i \in Peers |-> FALSE],
    reached_pings_collection = [i \in Peers |-> NoMessage],
    counter_i = [i \in Peers |-> 0],
    ping_seq_num_i = [i \in Peers |-> 0],
    reached_mystery_flag_i = [i \in Peers |-> FALSE],
    reached_boomlets_collection_i = [i \in Peers |-> {}],
    signed_psbt_outbox = [i \in Peers |-> NoMessage],
    wt_signed_psbt_collection = [i \in Peers |-> NoMessage],
    broadcast_record = NoMessage,
    wt_accepted_approval = [i \in Peers |-> NoMessage],
    wt_accepted_approval_height = [i \in Peers |-> LowestBlock],
    peer_accepted_wt_bundle = [i \in Peers |-> NoMessage],
    peer_accepted_wt_bundle_height = [i \in Peers |-> LowestBlock],
    peer_accepted_initiator_commit = [i \in Peers |-> NoMessage],
    peer_accepted_initiator_commit_height = [i \in Peers |-> LowestBlock],
    wt_accepted_commit = [i \in Peers |-> NoMessage],
    wt_accepted_commit_height = [i \in Peers |-> LowestBlock],
    wt_accepted_ping = [i \in Peers |-> NoMessage],
    wt_accepted_ping_height = [i \in Peers |-> LowestBlock],
    peer_accepted_pong = [i \in Peers |-> NoMessage],
    peer_accepted_pong_height = [i \in Peers |-> LowestBlock],
    peer_accepted_sar_ack = [i \in Peers |-> NoMessage],
    peer_accepted_sar_ack_expected = [i \in Peers |-> NoMessage],
    peer_accepted_sar_ack_height = [i \in Peers |-> LowestBlock],
    hardware_lost = {},
    fallback_activated = [i \in Peers |-> FALSE],
    niso_i_event_block_height = [i \in Peers |-> LowestBlock],
    most_work_bitcoin_block_height = LowestBlock,
    last_seen_block_i = [i \in Peers |-> LowestBlock];

process Peer \in Peers
begin
PeerSessionLoop:
    while TRUE do
    ActiveReady:
        if self = INITIATOR then
            with sid \in Sessions \ used_sessions do
                with p \in PSBTs do
                    with nonce \in ChallengeNonces do
                        await peer_state[self] = "ActiveReady"
                           /\ session_id = NoSession
                           /\ tx_id = NoTx
                           /\ sid \notin used_sessions
                           /\ niso_i_event_block_height[self] >= Milestone0;
                        session_id := sid;
                        tx_id := TxOfPsbt[p];
                        psbt_i[self] := p;
                        pending_txid_challenge_i[self] := TxIdChallengeMsgFor(
                            sid,
                            TxOfPsbt[p],
                            self,
                            nonce);
                        peer_state[self] := "AwaitingInitialTxIdAck";
                    end with;
                end with;
            end with;
        else
            await peer_state[self] = "ActiveReady"
               /\ wt_bundle_inbox[self] # NoMessage
               /\ NisoAcceptsWTBundle(
                    self,
                    wt_bundle_inbox[self],
                    session_id,
                    tx_id,
                    niso_i_event_block_height[self])
               /\ BoomletAcceptsWTBundle(
                    self,
                    wt_bundle_inbox[self],
                    session_id,
                    tx_id,
                    niso_i_event_block_height[self]);
            psbt_i[self] := WTBundlePsbt(wt_bundle_inbox[self]);
            peer_accepted_wt_bundle[self] := wt_bundle_inbox[self];
            peer_accepted_wt_bundle_height[self] := niso_i_event_block_height[self];
            local_psbt_reviewed_i[self] := FALSE;
            peer_state[self] := "AwaitingNonInitiatorLocalApproval";
            wt_bundle_inbox[self] := NoMessage;
        end if;

    AwaitNonInitiatorLocalApproval:
        if self # INITIATOR then
            with nonce \in ChallengeNonces do
                await peer_state[self] = "AwaitingNonInitiatorLocalApproval"
                   /\ psbt_i[self] # NoPsbt
                   /\ SameTxId(psbt_i[self], tx_id);
                local_psbt_reviewed_i[self] := TRUE;
                pending_txid_challenge_i[self] := TxIdChallengeMsgFor(
                    session_id,
                    tx_id,
                    self,
                    nonce);
                peer_state[self] := "AwaitingInitialTxIdAck";
            end with;
        end if;

    AwaitInitialTxIdAck:
        await peer_state[self] = "AwaitingInitialTxIdAck"
           /\ pending_txid_challenge_i[self] # NoMessage;
        accepted_txid_challenge_i[self] := pending_txid_challenge_i[self];
        accepted_txid_ack_i[self] := TxIdAckMsgFor(
            pending_txid_challenge_i[self].sid,
            pending_txid_challenge_i[self].txid,
            self,
            pending_txid_challenge_i[self].nonce);
        accepted_txid_ack_height_i[self] := niso_i_event_block_height[self];
        pending_txid_challenge_i[self] := NoMessage;
        if self = INITIATOR then
            approval_outbox[self] := InitiatorSubmissionMsgFor(
                session_id,
                tx_id,
                niso_i_event_block_height[self],
                psbt_i[self]);
        else
            approval_outbox[self] := ApprovalMsgFor(
                session_id,
                tx_id,
                self,
                niso_i_event_block_height[self]);
        end if;
        peer_state[self] := "AwaitingPeerApprovals";

    AwaitApprovalCollection:
        with nonce \in ChallengeNonces do
            await peer_state[self] = "AwaitingPeerApprovals"
               /\ NisoValidApprovalCollectionForPeer(
                    self,
                    approval_collection_delivered[self],
                    peer_tx_approval_collection,
                    wt_tx_approval,
                    session_id,
                    tx_id,
                    niso_i_event_block_height[self])
               /\ BoomletValidApprovalCollectionForPeer(
                    self,
                    approval_collection_delivered[self],
                    peer_tx_approval_collection,
                    wt_tx_approval,
                    session_id,
                    tx_id,
                    niso_i_event_block_height[self]);
            pending_duress_challenge_i[self] := DuressChallengeMsgFor(
                session_id,
                tx_id,
                self,
                "initial",
                0,
                nonce);
            peer_state[self] := "AwaitingInitialDuressAck";
        end with;

    AwaitInitialDuressAck:
        await peer_state[self] = "AwaitingInitialDuressAck"
           /\ pending_duress_challenge_i[self] # NoMessage;
        with consent_match \in BOOLEAN do
            accepted_duress_challenge_i[self] := pending_duress_challenge_i[self];
            accepted_duress_ack_i[self] := DuressAckMsgFor(
                pending_duress_challenge_i[self].sid,
                pending_duress_challenge_i[self].txid,
                self,
                pending_duress_challenge_i[self].stage,
                pending_duress_challenge_i[self].seq,
                pending_duress_challenge_i[self].nonce,
                consent_match);
            accepted_duress_ack_height_i[self] := niso_i_event_block_height[self];
            pending_duress_challenge_i[self] := NoMessage;
            payload_kind_i[self] := IF consent_match THEN "padding" ELSE "doxing_key";
            duress_latched_i[self] := ~consent_match;
            duress_checks_i[self] := duress_checks_i[self] + 1;
            peer_state[self] := "InitialDuressResolved";
        end with;

    AfterInitialDuress:
        if self = INITIATOR then
            with pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner} do
                placeholder_owner[pid] := self;
                placeholder_kind[pid] := payload_kind_i[self];
                current_placeholder_i[self] := pid;
                saved_expected_sar_ack[self] := ExpectedAck(
                    session_id,
                    tx_id,
                    self,
                    "commit",
                    0,
                    pid);
                commit_outbox[self] := CommitMsgFor(
                    session_id,
                    tx_id,
                    self,
                    niso_i_event_block_height[self],
                    pid);
            end with;
            peer_state[self] := "AwaitingCommitCollection";
        else
            approval_bundle_outbox[self] := ApprovalsBundleMsgFor(
                session_id,
                self,
                peer_tx_approval_collection,
                wt_tx_approval);
            peer_state[self] := "AwaitingWTInitiatorCommit";
        end if;

    AwaitInitiatorCommitAck:
        if self # INITIATOR then
            await approvals_bundle_accepted[self]
               /\ initiator_commit_acked[self]
               /\ NisoValidInitiatorCommitForPeer(
                    self,
                    initiator_commit_inbox[self] # NoMessage,
                    initiator_commit_inbox[self],
                    session_id,
                    tx_id,
                    niso_i_event_block_height[self],
                    peer_tx_commit_collection[INITIATOR])
               /\ BoomletValidInitiatorCommitForPeer(
                    self,
                    initiator_commit_inbox[self] # NoMessage,
                    initiator_commit_inbox[self],
                    session_id,
                    tx_id,
                    niso_i_event_block_height[self],
                    peer_tx_commit_collection[INITIATOR]);
            peer_accepted_initiator_commit[self] := initiator_commit_inbox[self];
            peer_accepted_initiator_commit_height[self] := niso_i_event_block_height[self];
            initiator_commit_inbox[self] := NoMessage;
            with pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner} do
                placeholder_owner[pid] := self;
                placeholder_kind[pid] := payload_kind_i[self];
                current_placeholder_i[self] := pid;
                saved_expected_sar_ack[self] := ExpectedAck(
                    session_id,
                    tx_id,
                    self,
                    "commit",
                    0,
                    pid);
                commit_outbox[self] := CommitMsgFor(
                    session_id,
                    tx_id,
                    self,
                    niso_i_event_block_height[self],
                    pid);
            end with;
            peer_state[self] := "AwaitingCommitCollection";
        end if;

    EnterDiggingGame:
        await peer_state[self] = "AwaitingCommitCollection"
           /\ NisoValidCommitCollectionForPeer(
                self,
                commit_collection_delivered[self],
                peer_tx_commit_collection,
                session_id,
                tx_id,
                niso_i_event_block_height[self])
           /\ BoomletValidCommitCollectionForPeer(
                self,
                commit_collection_delivered[self],
                peer_tx_commit_collection,
                session_id,
                tx_id,
                niso_i_event_block_height[self],
                sar_ack_i[self],
                saved_expected_sar_ack[self]);

        peer_accepted_sar_ack[self] := sar_ack_i[self];
        peer_accepted_sar_ack_expected[self] := saved_expected_sar_ack[self];
        peer_accepted_sar_ack_height[self] := niso_i_event_block_height[self];
        sar_ack_i[self] := NoMessage;
        with pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner} do
            placeholder_owner[pid] := self;
            placeholder_kind[pid] := payload_kind_i[self];
            current_placeholder_i[self] := pid;
            saved_expected_sar_ack[self] := ExpectedAck(
                session_id,
                tx_id,
                self,
                "ping",
                0,
                pid);
            counter_i[self] := 0;
            ping_seq_num_i[self] := 0;
            reached_mystery_flag_i[self] := FALSE;
            reached_boomlets_collection_i[self] := {};
            last_seen_block_i[self] := niso_i_event_block_height[self];
            current_ping_from_recurring_check_i[self] := FALSE;
            wt_round_pings[self] := PingMsgFor(
                session_id,
                tx_id,
                self,
                niso_i_event_block_height[self],
                0,
                FALSE,
                pid);
        end with;
        peer_state[self] := "DiggingGame";

    DiggingLoop:
        while peer_state[self] \in {"DiggingGame", "AwaitingRecurringDuressAck"} do
            if peer_state[self] = "DiggingGame" then
                either
                    await reached_collection_delivered[self]
                       /\ AckMatchesExpected(sar_ack_i[self], saved_expected_sar_ack[self])
                       /\ SameTxId(psbt_i[self], tx_id)
                       /\ ReachedCollectionValidForPeer(
                            self,
                            reached_collection_delivered[self],
                            reached_pings_collection,
                            session_id,
                            tx_id,
                            niso_i_event_block_height[self],
                            peer_reviewed_ping_history_i[self],
                            reached_boomlets_collection_i[self]);
                    peer_accepted_sar_ack[self] := sar_ack_i[self];
                    peer_accepted_sar_ack_expected[self] := saved_expected_sar_ack[self];
                    peer_accepted_sar_ack_height[self] := niso_i_event_block_height[self];
                    hydrated_psbt_i[self] := psbt_i[self];
                    signing_ticket_i[self] := SigningTicketFor(session_id, tx_id);
                    current_ping_from_recurring_check_i[self] := FALSE;
                    peer_state[self] := "ReadyToSign";
                or
                    await ~reached_collection_delivered[self]
                       /\ pong_i[self] # NoMessage
                       /\ NisoValidPongForPeer(
                            self,
                            pong_i[self],
                            session_id,
                            tx_id,
                            niso_i_event_block_height[self],
                            reached_boomlets_collection_i[self],
                            peer_reviewed_ping_history_i[self])
                       /\ BoomletValidPongForPeer(
                            self,
                            pong_i[self],
                            session_id,
                            tx_id,
                            niso_i_event_block_height[self],
                            reached_boomlets_collection_i[self],
                            saved_expected_sar_ack[self],
                            peer_reviewed_ping_history_i[self]);

                    peer_accepted_pong[self] := pong_i[self];
                    peer_accepted_pong_height[self] := niso_i_event_block_height[self];
                    peer_accepted_sar_ack[self] := pong_i[self].sar_ack;
                    peer_accepted_sar_ack_expected[self] := saved_expected_sar_ack[self];
                    peer_accepted_sar_ack_height[self] := niso_i_event_block_height[self];

                    either
                        with pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner} do
                            placeholder_owner[pid] := self;
                            placeholder_kind[pid] := DiggingReplyKind(
                                duress_latched_i[self],
                                payload_kind_i[self],
                                FALSE,
                                FALSE);
                            current_placeholder_i[self] := pid;
                            saved_expected_sar_ack[self] := ExpectedAck(
                                session_id,
                                tx_id,
                                self,
                                "ping",
                                ping_seq_num_i[self] + 1,
                                pid);
                            wt_round_pings[self] := PingMsgFor(
                                session_id,
                                tx_id,
                                self,
                                NextLastSeen(
                                    last_seen_block_i[self],
                                    niso_i_event_block_height[self]),
                                ping_seq_num_i[self] + 1,
                                NextReached(
                                    reached_mystery_flag_i[self],
                                    counter_i[self],
                                    last_seen_block_i[self],
                                    niso_i_event_block_height[self],
                                    mystery_i[self],
                                    pong_i[self],
                                    peer_reviewed_ping_history_i[self],
                                    self,
                                    session_id,
                                    tx_id,
                                    reached_boomlets_collection_i[self]),
                                pid);
                        end with;
                        ping_seq_num_i[self] := ping_seq_num_i[self] + 1;
                        last_seen_block_i[self] := NextLastSeen(
                            last_seen_block_i[self],
                            niso_i_event_block_height[self]);
                        reached_mystery_flag_i[self] := NextReached(
                            reached_mystery_flag_i[self],
                            counter_i[self],
                            last_seen_block_i[self],
                            niso_i_event_block_height[self],
                            mystery_i[self],
                            pong_i[self],
                            peer_reviewed_ping_history_i[self],
                            self,
                            session_id,
                            tx_id,
                            reached_boomlets_collection_i[self]);
                        reached_boomlets_collection_i[self] := reached_boomlets_collection_i[self] \cup
                            ReachedPeersAdvertised(self, pong_i[self]);
                        counter_i[self] := NextCounter(
                            counter_i[self],
                            last_seen_block_i[self],
                            niso_i_event_block_height[self],
                            pong_i[self],
                            peer_reviewed_ping_history_i[self],
                            self,
                            session_id,
                            tx_id,
                            reached_boomlets_collection_i[self]);
                        duress_latched_i[self] := DiggingReplyLatched(
                            duress_latched_i[self],
                            FALSE,
                            FALSE);
                        payload_kind_i[self] := DiggingReplyKind(
                            duress_latched_i[self],
                            payload_kind_i[self],
                            FALSE,
                            FALSE);
                        current_ping_from_recurring_check_i[self] := FALSE;
                        peer_reviewed_ping_history_i[self] := [j \in Peers |->
                            IF j = self
                               THEN peer_reviewed_ping_history_i[self][j]
                               ELSE IF j \in OtherPeers(self)
                                       THEN pong_i[self].other_pings[j]
                                       ELSE peer_reviewed_ping_history_i[self][j]];
                        pong_i[self] := NoMessage;
                    or
                        with prng_draw \in RecurringDuressPRNGDraws do
                            if RecurringDuressCheckFires(prng_draw) then
                                with nonce \in ChallengeNonces do
                                    pending_duress_challenge_i[self] := DuressChallengeMsgFor(
                                        session_id,
                                        tx_id,
                                        self,
                                        "ping",
                                        ping_seq_num_i[self] + 1,
                                        nonce);
                                    peer_state[self] := "AwaitingRecurringDuressAck";
                                end with;
                            else
                                with pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner} do
                                    placeholder_owner[pid] := self;
                                    placeholder_kind[pid] := DiggingReplyKind(
                                        duress_latched_i[self],
                                        payload_kind_i[self],
                                        FALSE,
                                        FALSE);
                                    current_placeholder_i[self] := pid;
                                    saved_expected_sar_ack[self] := ExpectedAck(
                                        session_id,
                                        tx_id,
                                        self,
                                        "ping",
                                        ping_seq_num_i[self] + 1,
                                        pid);
                                    wt_round_pings[self] := PingMsgFor(
                                        session_id,
                                        tx_id,
                                        self,
                                        NextLastSeen(
                                            last_seen_block_i[self],
                                            niso_i_event_block_height[self]),
                                        ping_seq_num_i[self] + 1,
                                        NextReached(
                                            reached_mystery_flag_i[self],
                                            counter_i[self],
                                            last_seen_block_i[self],
                                            niso_i_event_block_height[self],
                                            mystery_i[self],
                                            pong_i[self],
                                            peer_reviewed_ping_history_i[self],
                                            self,
                                            session_id,
                                            tx_id,
                                            reached_boomlets_collection_i[self]),
                                        pid);
                                end with;
                                ping_seq_num_i[self] := ping_seq_num_i[self] + 1;
                                last_seen_block_i[self] := NextLastSeen(
                                    last_seen_block_i[self],
                                    niso_i_event_block_height[self]);
                                reached_mystery_flag_i[self] := NextReached(
                                    reached_mystery_flag_i[self],
                                    counter_i[self],
                                    last_seen_block_i[self],
                                    niso_i_event_block_height[self],
                                    mystery_i[self],
                                    pong_i[self],
                                    peer_reviewed_ping_history_i[self],
                                    self,
                                    session_id,
                                    tx_id,
                                    reached_boomlets_collection_i[self]);
                                reached_boomlets_collection_i[self] := reached_boomlets_collection_i[self] \cup
                                    ReachedPeersAdvertised(self, pong_i[self]);
                                counter_i[self] := NextCounter(
                                    counter_i[self],
                                    last_seen_block_i[self],
                                    niso_i_event_block_height[self],
                                    pong_i[self],
                                    peer_reviewed_ping_history_i[self],
                                    self,
                                    session_id,
                                    tx_id,
                                    reached_boomlets_collection_i[self]);
                                duress_latched_i[self] := DiggingReplyLatched(
                                    duress_latched_i[self],
                                    FALSE,
                                    FALSE);
                                payload_kind_i[self] := DiggingReplyKind(
                                    duress_latched_i[self],
                                    payload_kind_i[self],
                                    FALSE,
                                    FALSE);
                                current_ping_from_recurring_check_i[self] := FALSE;
                                peer_reviewed_ping_history_i[self] := [j \in Peers |->
                                    IF j = self
                                       THEN peer_reviewed_ping_history_i[self][j]
                                       ELSE IF j \in OtherPeers(self)
                                               THEN pong_i[self].other_pings[j]
                                               ELSE peer_reviewed_ping_history_i[self][j]];
                                pong_i[self] := NoMessage;
                            end if;
                        end with;
                    end either;
                end either;
            else
                await peer_state[self] = "AwaitingRecurringDuressAck"
                   /\ pending_duress_challenge_i[self] # NoMessage
                   /\ pong_i[self] # NoMessage;
                with consent_match \in BOOLEAN do
                    accepted_duress_challenge_i[self] := pending_duress_challenge_i[self];
                    accepted_duress_ack_i[self] := DuressAckMsgFor(
                        pending_duress_challenge_i[self].sid,
                        pending_duress_challenge_i[self].txid,
                        self,
                        pending_duress_challenge_i[self].stage,
                        pending_duress_challenge_i[self].seq,
                        pending_duress_challenge_i[self].nonce,
                        consent_match);
                    accepted_duress_ack_height_i[self] := niso_i_event_block_height[self];
                    pending_duress_challenge_i[self] := NoMessage;
                    with pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner} do
                        placeholder_owner[pid] := self;
                        placeholder_kind[pid] := DiggingReplyKind(
                            duress_latched_i[self],
                            payload_kind_i[self],
                            TRUE,
                            ~consent_match);
                        current_placeholder_i[self] := pid;
                        saved_expected_sar_ack[self] := ExpectedAck(
                            session_id,
                            tx_id,
                            self,
                            "ping",
                            ping_seq_num_i[self] + 1,
                            pid);
                        wt_round_pings[self] := PingMsgFor(
                            session_id,
                            tx_id,
                            self,
                            NextLastSeen(
                                last_seen_block_i[self],
                                niso_i_event_block_height[self]),
                            ping_seq_num_i[self] + 1,
                            NextReached(
                                reached_mystery_flag_i[self],
                                counter_i[self],
                                last_seen_block_i[self],
                                niso_i_event_block_height[self],
                                mystery_i[self],
                                pong_i[self],
                                peer_reviewed_ping_history_i[self],
                                self,
                                session_id,
                                tx_id,
                                reached_boomlets_collection_i[self]),
                            pid);
                    end with;
                    ping_seq_num_i[self] := ping_seq_num_i[self] + 1;
                    last_seen_block_i[self] := NextLastSeen(
                        last_seen_block_i[self],
                        niso_i_event_block_height[self]);
                    reached_mystery_flag_i[self] := NextReached(
                        reached_mystery_flag_i[self],
                        counter_i[self],
                        last_seen_block_i[self],
                        niso_i_event_block_height[self],
                        mystery_i[self],
                        pong_i[self],
                        peer_reviewed_ping_history_i[self],
                        self,
                        session_id,
                        tx_id,
                        reached_boomlets_collection_i[self]);
                    reached_boomlets_collection_i[self] := reached_boomlets_collection_i[self] \cup
                        ReachedPeersAdvertised(self, pong_i[self]);
                    counter_i[self] := NextCounter(
                        counter_i[self],
                        last_seen_block_i[self],
                        niso_i_event_block_height[self],
                        pong_i[self],
                        peer_reviewed_ping_history_i[self],
                        self,
                        session_id,
                        tx_id,
                        reached_boomlets_collection_i[self]);
                    duress_latched_i[self] := DiggingReplyLatched(
                        duress_latched_i[self],
                        TRUE,
                        ~consent_match);
                    payload_kind_i[self] := DiggingReplyKind(
                        duress_latched_i[self],
                        payload_kind_i[self],
                        TRUE,
                        ~consent_match);
                    duress_checks_i[self] := duress_checks_i[self] + 1;
                    current_ping_from_recurring_check_i[self] := TRUE;
                    peer_reviewed_ping_history_i[self] := [j \in Peers |->
                        IF j = self
                           THEN peer_reviewed_ping_history_i[self][j]
                           ELSE IF j \in OtherPeers(self)
                                   THEN pong_i[self].other_pings[j]
                                   ELSE peer_reviewed_ping_history_i[self][j]];
                    pong_i[self] := NoMessage;
                    peer_state[self] := "DiggingGame";
                end with;
            end if;
        end while;

    ReadyToSign:
        if ~fallback_activated[self] then
            await peer_state[self] = "ReadyToSign"
               /\ hydrated_psbt_i[self] # NoPsbt
               /\ signing_ticket_i[self] # NoMessage
               /\ \A j \in Peers :
                    /\ peer_state[j] \in {"ReadyToSign", "Signed", "AwaitReset"}
                    /\ ~fallback_activated[j]
                    /\ signing_ticket_i[j] = signing_ticket_i[self]
                    /\ saved_expected_sar_ack[j] # NoMessage
                    /\ AckMatchesExpected(sar_ack_i[j], saved_expected_sar_ack[j]);
            signed_psbt_i[self] := hydrated_psbt_i[self];
            signed_psbt_outbox[self] := SignedPsbtMsgFor(
                session_id,
                tx_id,
                self,
                hydrated_psbt_i[self],
                signing_ticket_i[self]);
            peer_state[self] := "Signed";
        end if;

    AwaitBroadcast:
        if ~fallback_activated[self] then
            await broadcast_record # NoMessage
               /\ BroadcastWellFormed(broadcast_record)
               /\ broadcast_record.sid = session_id
               /\ broadcast_record.txid = tx_id
               /\ BroadcastTicket(broadcast_record) = signing_ticket_i[self];
            peer_state[self] := "AwaitReset";
        end if;

    AfterSession:
        if fallback_activated[self] then
            await FALSE;
        else
            await peer_state[self] = "AwaitReset"
               /\ session_id = NoSession
               /\ tx_id = NoTx
               /\ broadcast_record = NoMessage
               /\ wt_state = "AwaitingInitiatorApproval";
            with regenerated_mystery \in {InitMystery[self], InitMystery[self] + 1} do
                mystery_i[self] := regenerated_mystery;
                current_placeholder_i[self] := NoPayload;
                psbt_i[self] := NoPsbt;
                hydrated_psbt_i[self] := NoPsbt;
                signed_psbt_i[self] := NoPsbt;
                signing_ticket_i[self] := NoMessage;
                local_psbt_reviewed_i[self] := FALSE;
                pending_txid_challenge_i[self] := NoMessage;
                accepted_txid_challenge_i[self] := NoMessage;
                accepted_txid_ack_i[self] := NoMessage;
                accepted_txid_ack_height_i[self] := LowestBlock;
                pending_duress_challenge_i[self] := NoMessage;
                accepted_duress_challenge_i[self] := NoMessage;
                accepted_duress_ack_i[self] := NoMessage;
                accepted_duress_ack_height_i[self] := LowestBlock;
                current_ping_from_recurring_check_i[self] := FALSE;
                payload_kind_i[self] := "none";
                duress_latched_i[self] := FALSE;
                duress_checks_i[self] := 0;
                approval_collection_delivered[self] := FALSE;
                approvals_bundle_accepted[self] := FALSE;
                initiator_commit_acked[self] := FALSE;
                initiator_commit_inbox[self] := NoMessage;
                commit_collection_delivered[self] := FALSE;
                saved_expected_sar_ack[self] := NoMessage;
                sar_pending_ack_request[self] := NoMessage;
                sar_ack_i[self] := NoMessage;
                sar_escalated_i[self] := FALSE;
                wt_round_pings[self] := NoMessage;
                wt_last_accepted_ping[self] := NoMessage;
                peer_reviewed_ping_history_i[self] := [j \in Peers |-> NoMessage];
                pong_i[self] := NoMessage;
                reached_collection_delivered[self] := FALSE;
                reached_pings_collection[self] := NoMessage;
                counter_i[self] := 0;
                ping_seq_num_i[self] := 0;
                reached_mystery_flag_i[self] := FALSE;
                reached_boomlets_collection_i[self] := {};
                signed_psbt_outbox[self] := NoMessage;
                wt_signed_psbt_collection[self] := NoMessage;
                peer_accepted_initiator_commit[self] := NoMessage;
                peer_accepted_initiator_commit_height[self] := LowestBlock;
                last_seen_block_i[self] := niso_i_event_block_height[self];
                peer_state[self] := "ActiveReady";
            end with;
        end if;
    end while;
end process;

process Watchtower = WT_ID
begin
WatchtowerSessionLoop:
    while TRUE do
    AwaitInitiatorApproval:
        await approval_outbox[INITIATOR] # NoMessage
           /\ InitiatorSubmissionWellFormed(approval_outbox[INITIATOR])
           /\ ValidSig(SubmissionApproval(approval_outbox[INITIATOR]), INITIATOR)
           /\ MsgSessionMatches(SubmissionApproval(approval_outbox[INITIATOR]), session_id)
           /\ MsgTxMatches(SubmissionApproval(approval_outbox[INITIATOR]), tx_id)
           /\ ApprovalFreshAtWT(
                SubmissionApproval(approval_outbox[INITIATOR]),
                most_work_bitcoin_block_height);
        wt_session_view := [
            sid |-> session_id,
            txid |-> tx_id,
            initiator |-> INITIATOR,
            height |-> most_work_bitcoin_block_height ];
        peer_tx_approval_collection[INITIATOR] := SubmissionApproval(approval_outbox[INITIATOR]);
        wt_accepted_approval[INITIATOR] := SubmissionApproval(approval_outbox[INITIATOR]);
        wt_accepted_approval_height[INITIATOR] := most_work_bitcoin_block_height;
        wt_tx_approval := WTApprovalMsgFor(session_id, tx_id, most_work_bitcoin_block_height);
        wt_bundle_inbox := [i \in Peers |->
            IF i = INITIATOR
               THEN NoMessage
               ELSE WTBundleMsgFor(
                    session_id,
                    SubmissionPsbt(approval_outbox[INITIATOR]),
                    SubmissionApproval(approval_outbox[INITIATOR]),
                    WTApprovalMsgFor(session_id, tx_id, most_work_bitcoin_block_height))];
        approval_outbox[INITIATOR] := NoMessage;
        wt_state := "CollectingPeerApprovals";

    CollectPeerApprovals:
        while wt_state = "CollectingPeerApprovals" do
            either
                with i \in {p \in OtherPeers(INITIATOR) :
                                /\ approval_outbox[p] # NoMessage
                                /\ ApprovalWellFormed(approval_outbox[p])
                                /\ ValidSig(approval_outbox[p], p)
                                /\ approval_outbox[p].sid = session_id
                                /\ approval_outbox[p].txid = tx_id
                                /\ PostWTApprovalWindowValid(
                                    approval_outbox[p],
                                    wt_tx_approval,
                                    most_work_bitcoin_block_height)} do
                    peer_tx_approval_collection[i] := approval_outbox[i];
                    wt_accepted_approval[i] := approval_outbox[i];
                    wt_accepted_approval_height[i] := most_work_bitcoin_block_height;
                    approval_outbox[i] := NoMessage;
                end with;
            or
                await AllApprovalsPresent(peer_tx_approval_collection)
                   /\ \E i \in Peers : ~approval_collection_delivered[i];
                approval_collection_delivered := [i \in Peers |-> TRUE];
                wt_state := "CollectingCommitments";
            end either;
        end while;

    CollectCommitments:
        while wt_state = "CollectingCommitments" do
            either
                with i \in {p \in OtherPeers(INITIATOR) :
                                /\ approval_bundle_outbox[p] # NoMessage
                                /\ BundleWellFormed(approval_bundle_outbox[p])
                                /\ ValidSig(approval_bundle_outbox[p], p)
                                /\ approval_bundle_outbox[p].sid = session_id
                                /\ ApprovalsBundleApprovals(approval_bundle_outbox[p]) = peer_tx_approval_collection
                                /\ ApprovalsBundleWTApproval(approval_bundle_outbox[p]) = wt_tx_approval} do
                    approvals_bundle_accepted[i] := TRUE;
                    approval_bundle_outbox[i] := NoMessage;
                end with;
            or
                with i \in {p \in Peers :
                                /\ commit_outbox[p] # NoMessage
                                /\ peer_tx_commit_collection[p] = NoMessage
                                /\ sar_pending_ack_request[p] = NoMessage
                                /\ sar_ack_i[p] = NoMessage
                                /\ CommitWellFormed(commit_outbox[p])
                                /\ ValidSig(commit_outbox[p], p)
                                /\ commit_outbox[p].sid = session_id
                                /\ commit_outbox[p].txid = tx_id
                                /\ CommitFreshAtWT(
                                    commit_outbox[p],
                                    most_work_bitcoin_block_height)} do
                    wt_accepted_commit[i] := commit_outbox[i];
                    wt_accepted_commit_height[i] := most_work_bitcoin_block_height;
                    sar_pending_ack_request[i] := ExpectedAck(
                        session_id,
                        tx_id,
                        i,
                        "commit",
                        0,
                        CommitPlaceholder(commit_outbox[i]));
                end with;
            or
                with i \in {p \in Peers :
                                /\ commit_outbox[p] # NoMessage
                                /\ AckMatchesExpected(
                                    sar_ack_i[p],
                                    saved_expected_sar_ack[p])} do
                    peer_tx_commit_collection[i] := SealCommit(commit_outbox[i]);
                    if i = INITIATOR then
                        initiator_commit_acked := [j \in Peers |->
                            IF j = INITIATOR THEN initiator_commit_acked[j] ELSE TRUE];
                        initiator_commit_inbox := [j \in Peers |->
                            IF j = INITIATOR THEN initiator_commit_inbox[j]
                            ELSE SealCommit(commit_outbox[i])];
                    end if;
                    commit_outbox[i] := NoMessage;
                end with;
            or
                await AllCommitsPresent(peer_tx_commit_collection)
                   /\ \E i \in Peers : ~commit_collection_delivered[i];
                commit_collection_delivered := [i \in Peers |-> TRUE];
                wt_state := "CollectingPings";
            end either;
        end while;

    CollectPings:
        while wt_state = "CollectingPings" do
            either
                with i \in {p \in Peers :
                                /\ wt_round_pings[p] # NoMessage
                                /\ sar_pending_ack_request[p] = NoMessage
                                /\ sar_ack_i[p] = NoMessage
                                /\ PingWellFormed(wt_round_pings[p])
                                /\ ValidSig(wt_round_pings[p], p)
                                /\ wt_round_pings[p].sid = session_id
                                /\ wt_round_pings[p].txid = tx_id
                                /\ PingFreshAtWT(
                                    wt_round_pings[p],
                                    most_work_bitcoin_block_height)
                                /\ PingProgressesFrom(
                                    wt_last_accepted_ping[p],
                                    wt_round_pings[p],
                                    most_work_bitcoin_block_height)} do
                    wt_accepted_ping[i] := wt_round_pings[i];
                    wt_accepted_ping_height[i] := most_work_bitcoin_block_height;
                    wt_last_accepted_ping[i] := wt_round_pings[i];
                    sar_pending_ack_request[i] := ExpectedAck(
                        session_id,
                        tx_id,
                        i,
                        "ping",
                        PingSeqNum(wt_round_pings[i]),
                        PingPlaceholder(wt_round_pings[i]));
                    if PingReached(wt_round_pings[i]) /\ reached_pings_collection[i] = NoMessage then
                        reached_pings_collection[i] := wt_round_pings[i];
                    end if;
                end with;
            or
                await WTAllReached(reached_pings_collection)
                   /\ AllRoundPingsPresent(wt_round_pings)
                   /\ AllRoundSARRepliesPresent(sar_ack_i)
                   /\ RoundPingsSatisfyMinimumPongDistance(
                        wt_round_pings,
                        most_work_bitcoin_block_height);
                reached_collection_delivered := [i \in Peers |-> TRUE];
                wt_state := "CollectingSignatures";
            or
                await AllRoundPingsPresent(wt_round_pings)
                   /\ AllRoundSARRepliesPresent(sar_ack_i)
                   /\ ~WTAllReached(reached_pings_collection)
                   /\ RoundPingsSatisfyMinimumPongDistance(
                        wt_round_pings,
                        most_work_bitcoin_block_height);
                pong_i := [i \in Peers |->
                    PongMsgFor(
                        session_id,
                        tx_id,
                        i,
                        most_work_bitcoin_block_height,
                        wt_round_pings,
                        sar_ack_i[i])];
                wt_round_pings := [i \in Peers |-> NoMessage];
                sar_ack_i := [i \in Peers |-> NoMessage];
                wt_state := "CollectingPings";
            end either;
        end while;

    CollectSignatures:
        while wt_state = "CollectingSignatures" do
            either
                with i \in {p \in Peers :
                                /\ signed_psbt_outbox[p] # NoMessage
                                /\ wt_signed_psbt_collection[p] = NoMessage
                                /\ SignedPsbtWellFormed(signed_psbt_outbox[p])
                                /\ ValidSig(signed_psbt_outbox[p], p)
                                /\ signed_psbt_outbox[p].sid = session_id
                                /\ signed_psbt_outbox[p].txid = tx_id
                                /\ SignedPsbtTicket(signed_psbt_outbox[p]) = signing_ticket_i[p]
                                /\ SameTxId(signed_psbt_outbox[p].psbt, tx_id)} do
                    wt_signed_psbt_collection[i] := signed_psbt_outbox[i];
                    signed_psbt_outbox[i] := NoMessage;
                end with;
            or
                await AllSignedPsbtsPresent(wt_signed_psbt_collection)
                   /\ \A i \in Peers :
                        SignedPsbtTicket(wt_signed_psbt_collection[i]) = signing_ticket_i[i];
                broadcast_record := BroadcastMsgFor(
                    session_id,
                    tx_id,
                    SignedPsbtTicket(wt_signed_psbt_collection[INITIATOR]));
                wt_state := "Broadcasted";
            end either;
        end while;

    ResetAfterBroadcast:
        await wt_state = "Broadcasted"
           /\ \A i \in Peers : peer_state[i] = "AwaitReset";
        used_sessions := used_sessions \cup {session_id};
        completed_withdrawals := completed_withdrawals + 1;
        session_id := NoSession;
        tx_id := NoTx;
        wt_session_view := NoMessage;
        pending_txid_challenge_i := [i \in Peers |-> NoMessage];
        accepted_txid_challenge_i := [i \in Peers |-> NoMessage];
        accepted_txid_ack_i := [i \in Peers |-> NoMessage];
        accepted_txid_ack_height_i := [i \in Peers |-> LowestBlock];
        pending_duress_challenge_i := [i \in Peers |-> NoMessage];
        accepted_duress_challenge_i := [i \in Peers |-> NoMessage];
        accepted_duress_ack_i := [i \in Peers |-> NoMessage];
        accepted_duress_ack_height_i := [i \in Peers |-> LowestBlock];
        current_ping_from_recurring_check_i := [i \in Peers |-> FALSE];
        peer_tx_approval_collection := [i \in Peers |-> NoMessage];
        wt_tx_approval := NoMessage;
        peer_accepted_initiator_commit := [i \in Peers |-> NoMessage];
        peer_accepted_initiator_commit_height := [i \in Peers |-> LowestBlock];
        approval_outbox := [i \in Peers |-> NoMessage];
        wt_bundle_inbox := [i \in Peers |-> NoMessage];
        approval_collection_delivered := [i \in Peers |-> FALSE];
        approval_bundle_outbox := [i \in Peers |-> NoMessage];
        approvals_bundle_accepted := [i \in Peers |-> FALSE];
        commit_outbox := [i \in Peers |-> NoMessage];
        initiator_commit_acked := [i \in Peers |-> FALSE];
        initiator_commit_inbox := [i \in Peers |-> NoMessage];
        peer_tx_commit_collection := [i \in Peers |-> NoMessage];
        commit_collection_delivered := [i \in Peers |-> FALSE];
        saved_expected_sar_ack := [i \in Peers |-> NoMessage];
        sar_pending_ack_request := [i \in Peers |-> NoMessage];
        sar_ack_i := [i \in Peers |-> NoMessage];
        sar_escalated_i := [i \in Peers |-> FALSE];
        wt_round_pings := [i \in Peers |-> NoMessage];
        wt_last_accepted_ping := [i \in Peers |-> NoMessage];
        pong_i := [i \in Peers |-> NoMessage];
        reached_collection_delivered := [i \in Peers |-> FALSE];
        reached_pings_collection := [i \in Peers |-> NoMessage];
        signed_psbt_outbox := [i \in Peers |-> NoMessage];
        wt_signed_psbt_collection := [i \in Peers |-> NoMessage];
        broadcast_record := NoMessage;
        hardware_lost := {};
        fallback_activated := [i \in Peers |-> FALSE];
        wt_state := "AwaitingInitiatorApproval";
    end while;
end process;

process SAR = SAR_ID
begin
AckLoop:
    while TRUE do
        with i \in {p \in Peers :
                        /\ sar_pending_ack_request[p] # NoMessage
                        /\ SARAckWellFormed(sar_pending_ack_request[p])
                        /\ sar_pending_ack_request[p].placeholder \notin sar_seen_placeholder_ids_i[p]} do
            sar_seen_placeholder_ids_i[i] := sar_seen_placeholder_ids_i[i] \cup {sar_pending_ack_request[i].placeholder};
            sar_ack_i[i] := sar_pending_ack_request[i];
            if placeholder_kind[sar_pending_ack_request[i].placeholder] = "doxing_key" then
                sar_escalated_i[i] := TRUE;
            end if;
            sar_pending_ack_request[i] := NoMessage;
        end with;
    end while;
end process;

process FallbackMonitor = "FALLBACK"
begin
FallbackLoop:
    while TRUE do
        either
            with i \in {p \in Peers :
                            /\ p \notin hardware_lost
                            /\ peer_state[p] \notin {"Signed", "AwaitReset", "Fallback"}} do
                hardware_lost := hardware_lost \cup {i};
            end with;
        or
            with i \in {p \in Peers :
                            /\ ~fallback_activated[p]
                            /\ peer_state[p] \notin {"Signed", "AwaitReset", "Fallback"}
                            /\ \A j \in Peers : peer_state[j] # "Signed" /\ peer_state[j] # "AwaitReset"
                            /\ (p \in hardware_lost \/ most_work_bitcoin_block_height >= Milestone1)} do
                fallback_activated[i] := TRUE;
                peer_state[i] := "Fallback";
            end with;
        end either;
    end while;
end process;

process Environment = "ENV"
begin
AdvanceHeights:
    while TRUE do
        either
            with i \in {p \in Peers : HigherBlocks(niso_i_event_block_height[p]) # {}} do
                niso_i_event_block_height[i] := LeastHigher(niso_i_event_block_height[i]);
            end with;
        or
            await HigherBlocks(most_work_bitcoin_block_height) # {};
            most_work_bitcoin_block_height := LeastHigher(most_work_bitcoin_block_height);
        end either;
    end while;
end process;

end algorithm; *)

\* BEGIN TRANSLATION
VARIABLES mystery_i, used_sessions, completed_withdrawals, session_id, tx_id, 
          current_placeholder_i, placeholder_owner, placeholder_kind, psbt_i, 
          hydrated_psbt_i, signed_psbt_i, signing_ticket_i, 
          local_psbt_reviewed_i, pending_txid_challenge_i, 
          accepted_txid_challenge_i, accepted_txid_ack_i, 
          accepted_txid_ack_height_i, pending_duress_challenge_i, 
          accepted_duress_challenge_i, accepted_duress_ack_i, 
          accepted_duress_ack_height_i, current_ping_from_recurring_check_i, 
          peer_state, wt_state, wt_session_view, peer_tx_approval_collection, 
          wt_tx_approval, approval_outbox, wt_bundle_inbox, 
          approval_collection_delivered, payload_kind_i, duress_latched_i, 
          duress_checks_i, approval_bundle_outbox, approvals_bundle_accepted, 
          commit_outbox, initiator_commit_acked, initiator_commit_inbox, 
          peer_tx_commit_collection, commit_collection_delivered, 
          saved_expected_sar_ack, sar_pending_ack_request, sar_ack_i, 
          sar_seen_placeholder_ids_i, sar_escalated_i, wt_round_pings, 
          wt_last_accepted_ping, peer_reviewed_ping_history_i, pong_i, 
          reached_collection_delivered, reached_pings_collection, counter_i, 
          ping_seq_num_i, reached_mystery_flag_i, 
          reached_boomlets_collection_i, signed_psbt_outbox, 
          wt_signed_psbt_collection, broadcast_record, wt_accepted_approval, 
          wt_accepted_approval_height, peer_accepted_wt_bundle, 
          peer_accepted_wt_bundle_height, peer_accepted_initiator_commit, 
          peer_accepted_initiator_commit_height, wt_accepted_commit, 
          wt_accepted_commit_height, wt_accepted_ping, 
          wt_accepted_ping_height, peer_accepted_pong, 
          peer_accepted_pong_height, peer_accepted_sar_ack, 
          peer_accepted_sar_ack_expected, peer_accepted_sar_ack_height, 
          hardware_lost, fallback_activated, niso_i_event_block_height, 
          most_work_bitcoin_block_height, last_seen_block_i, pc

vars == << mystery_i, used_sessions, completed_withdrawals, session_id, tx_id, 
           current_placeholder_i, placeholder_owner, placeholder_kind, psbt_i, 
           hydrated_psbt_i, signed_psbt_i, signing_ticket_i, 
           local_psbt_reviewed_i, pending_txid_challenge_i, 
           accepted_txid_challenge_i, accepted_txid_ack_i, 
           accepted_txid_ack_height_i, pending_duress_challenge_i, 
           accepted_duress_challenge_i, accepted_duress_ack_i, 
           accepted_duress_ack_height_i, current_ping_from_recurring_check_i, 
           peer_state, wt_state, wt_session_view, peer_tx_approval_collection, 
           wt_tx_approval, approval_outbox, wt_bundle_inbox, 
           approval_collection_delivered, payload_kind_i, duress_latched_i, 
           duress_checks_i, approval_bundle_outbox, approvals_bundle_accepted, 
           commit_outbox, initiator_commit_acked, initiator_commit_inbox, 
           peer_tx_commit_collection, commit_collection_delivered, 
           saved_expected_sar_ack, sar_pending_ack_request, sar_ack_i, 
           sar_seen_placeholder_ids_i, sar_escalated_i, wt_round_pings, 
           wt_last_accepted_ping, peer_reviewed_ping_history_i, pong_i, 
           reached_collection_delivered, reached_pings_collection, counter_i, 
           ping_seq_num_i, reached_mystery_flag_i, 
           reached_boomlets_collection_i, signed_psbt_outbox, 
           wt_signed_psbt_collection, broadcast_record, wt_accepted_approval, 
           wt_accepted_approval_height, peer_accepted_wt_bundle, 
           peer_accepted_wt_bundle_height, peer_accepted_initiator_commit, 
           peer_accepted_initiator_commit_height, wt_accepted_commit, 
           wt_accepted_commit_height, wt_accepted_ping, 
           wt_accepted_ping_height, peer_accepted_pong, 
           peer_accepted_pong_height, peer_accepted_sar_ack, 
           peer_accepted_sar_ack_expected, peer_accepted_sar_ack_height, 
           hardware_lost, fallback_activated, niso_i_event_block_height, 
           most_work_bitcoin_block_height, last_seen_block_i, pc >>

ProcSet == (Peers) \cup {WT_ID} \cup {SAR_ID} \cup {"FALLBACK"} \cup {"ENV"}

Init == (* Global variables *)
        /\ mystery_i = InitMystery
        /\ used_sessions = {}
        /\ completed_withdrawals = 0
        /\ session_id = NoSession
        /\ tx_id = NoTx
        /\ current_placeholder_i = [i \in Peers |-> NoPayload]
        /\ placeholder_owner = [pid \in PlaceholderIds |-> NoSigner]
        /\ placeholder_kind = [pid \in PlaceholderIds |-> "unused"]
        /\ psbt_i = [i \in Peers |-> NoPsbt]
        /\ hydrated_psbt_i = [i \in Peers |-> NoPsbt]
        /\ signed_psbt_i = [i \in Peers |-> NoPsbt]
        /\ signing_ticket_i = [i \in Peers |-> NoMessage]
        /\ local_psbt_reviewed_i = [i \in Peers |-> FALSE]
        /\ pending_txid_challenge_i = [i \in Peers |-> NoMessage]
        /\ accepted_txid_challenge_i = [i \in Peers |-> NoMessage]
        /\ accepted_txid_ack_i = [i \in Peers |-> NoMessage]
        /\ accepted_txid_ack_height_i = [i \in Peers |-> LowestBlock]
        /\ pending_duress_challenge_i = [i \in Peers |-> NoMessage]
        /\ accepted_duress_challenge_i = [i \in Peers |-> NoMessage]
        /\ accepted_duress_ack_i = [i \in Peers |-> NoMessage]
        /\ accepted_duress_ack_height_i = [i \in Peers |-> LowestBlock]
        /\ current_ping_from_recurring_check_i = [i \in Peers |-> FALSE]
        /\ peer_state = [i \in Peers |-> "ActiveReady"]
        /\ wt_state = "AwaitingInitiatorApproval"
        /\ wt_session_view = NoMessage
        /\ peer_tx_approval_collection = [i \in Peers |-> NoMessage]
        /\ wt_tx_approval = NoMessage
        /\ approval_outbox = [i \in Peers |-> NoMessage]
        /\ wt_bundle_inbox = [i \in Peers |-> NoMessage]
        /\ approval_collection_delivered = [i \in Peers |-> FALSE]
        /\ payload_kind_i = [i \in Peers |-> "none"]
        /\ duress_latched_i = [i \in Peers |-> FALSE]
        /\ duress_checks_i = [i \in Peers |-> 0]
        /\ approval_bundle_outbox = [i \in Peers |-> NoMessage]
        /\ approvals_bundle_accepted = [i \in Peers |-> FALSE]
        /\ commit_outbox = [i \in Peers |-> NoMessage]
        /\ initiator_commit_acked = [i \in Peers |-> FALSE]
        /\ initiator_commit_inbox = [i \in Peers |-> NoMessage]
        /\ peer_tx_commit_collection = [i \in Peers |-> NoMessage]
        /\ commit_collection_delivered = [i \in Peers |-> FALSE]
        /\ saved_expected_sar_ack = [i \in Peers |-> NoMessage]
        /\ sar_pending_ack_request = [i \in Peers |-> NoMessage]
        /\ sar_ack_i = [i \in Peers |-> NoMessage]
        /\ sar_seen_placeholder_ids_i = [i \in Peers |-> {}]
        /\ sar_escalated_i = [i \in Peers |-> FALSE]
        /\ wt_round_pings = [i \in Peers |-> NoMessage]
        /\ wt_last_accepted_ping = [i \in Peers |-> NoMessage]
        /\ peer_reviewed_ping_history_i = [i \in Peers |-> [j \in Peers |-> NoMessage]]
        /\ pong_i = [i \in Peers |-> NoMessage]
        /\ reached_collection_delivered = [i \in Peers |-> FALSE]
        /\ reached_pings_collection = [i \in Peers |-> NoMessage]
        /\ counter_i = [i \in Peers |-> 0]
        /\ ping_seq_num_i = [i \in Peers |-> 0]
        /\ reached_mystery_flag_i = [i \in Peers |-> FALSE]
        /\ reached_boomlets_collection_i = [i \in Peers |-> {}]
        /\ signed_psbt_outbox = [i \in Peers |-> NoMessage]
        /\ wt_signed_psbt_collection = [i \in Peers |-> NoMessage]
        /\ broadcast_record = NoMessage
        /\ wt_accepted_approval = [i \in Peers |-> NoMessage]
        /\ wt_accepted_approval_height = [i \in Peers |-> LowestBlock]
        /\ peer_accepted_wt_bundle = [i \in Peers |-> NoMessage]
        /\ peer_accepted_wt_bundle_height = [i \in Peers |-> LowestBlock]
        /\ peer_accepted_initiator_commit = [i \in Peers |-> NoMessage]
        /\ peer_accepted_initiator_commit_height = [i \in Peers |-> LowestBlock]
        /\ wt_accepted_commit = [i \in Peers |-> NoMessage]
        /\ wt_accepted_commit_height = [i \in Peers |-> LowestBlock]
        /\ wt_accepted_ping = [i \in Peers |-> NoMessage]
        /\ wt_accepted_ping_height = [i \in Peers |-> LowestBlock]
        /\ peer_accepted_pong = [i \in Peers |-> NoMessage]
        /\ peer_accepted_pong_height = [i \in Peers |-> LowestBlock]
        /\ peer_accepted_sar_ack = [i \in Peers |-> NoMessage]
        /\ peer_accepted_sar_ack_expected = [i \in Peers |-> NoMessage]
        /\ peer_accepted_sar_ack_height = [i \in Peers |-> LowestBlock]
        /\ hardware_lost = {}
        /\ fallback_activated = [i \in Peers |-> FALSE]
        /\ niso_i_event_block_height = [i \in Peers |-> LowestBlock]
        /\ most_work_bitcoin_block_height = LowestBlock
        /\ last_seen_block_i = [i \in Peers |-> LowestBlock]
        /\ pc = [self \in ProcSet |-> CASE self \in Peers -> "PeerSessionLoop"
                                        [] self = WT_ID -> "WatchtowerSessionLoop"
                                        [] self = SAR_ID -> "AckLoop"
                                        [] self = "FALLBACK" -> "FallbackLoop"
                                        [] self = "ENV" -> "AdvanceHeights"]

PeerSessionLoop(self) == /\ pc[self] = "PeerSessionLoop"
                         /\ pc' = [pc EXCEPT ![self] = "ActiveReady"]
                         /\ UNCHANGED << mystery_i, used_sessions, 
                                         completed_withdrawals, session_id, 
                                         tx_id, current_placeholder_i, 
                                         placeholder_owner, placeholder_kind, 
                                         psbt_i, hydrated_psbt_i, 
                                         signed_psbt_i, signing_ticket_i, 
                                         local_psbt_reviewed_i, 
                                         pending_txid_challenge_i, 
                                         accepted_txid_challenge_i, 
                                         accepted_txid_ack_i, 
                                         accepted_txid_ack_height_i, 
                                         pending_duress_challenge_i, 
                                         accepted_duress_challenge_i, 
                                         accepted_duress_ack_i, 
                                         accepted_duress_ack_height_i, 
                                         current_ping_from_recurring_check_i, 
                                         peer_state, wt_state, wt_session_view, 
                                         peer_tx_approval_collection, 
                                         wt_tx_approval, approval_outbox, 
                                         wt_bundle_inbox, 
                                         approval_collection_delivered, 
                                         payload_kind_i, duress_latched_i, 
                                         duress_checks_i, 
                                         approval_bundle_outbox, 
                                         approvals_bundle_accepted, 
                                         commit_outbox, initiator_commit_acked, 
                                         initiator_commit_inbox, 
                                         peer_tx_commit_collection, 
                                         commit_collection_delivered, 
                                         saved_expected_sar_ack, 
                                         sar_pending_ack_request, sar_ack_i, 
                                         sar_seen_placeholder_ids_i, 
                                         sar_escalated_i, wt_round_pings, 
                                         wt_last_accepted_ping, 
                                         peer_reviewed_ping_history_i, pong_i, 
                                         reached_collection_delivered, 
                                         reached_pings_collection, counter_i, 
                                         ping_seq_num_i, 
                                         reached_mystery_flag_i, 
                                         reached_boomlets_collection_i, 
                                         signed_psbt_outbox, 
                                         wt_signed_psbt_collection, 
                                         broadcast_record, 
                                         wt_accepted_approval, 
                                         wt_accepted_approval_height, 
                                         peer_accepted_wt_bundle, 
                                         peer_accepted_wt_bundle_height, 
                                         peer_accepted_initiator_commit, 
                                         peer_accepted_initiator_commit_height, 
                                         wt_accepted_commit, 
                                         wt_accepted_commit_height, 
                                         wt_accepted_ping, 
                                         wt_accepted_ping_height, 
                                         peer_accepted_pong, 
                                         peer_accepted_pong_height, 
                                         peer_accepted_sar_ack, 
                                         peer_accepted_sar_ack_expected, 
                                         peer_accepted_sar_ack_height, 
                                         hardware_lost, fallback_activated, 
                                         niso_i_event_block_height, 
                                         most_work_bitcoin_block_height, 
                                         last_seen_block_i >>

ActiveReady(self) == /\ pc[self] = "ActiveReady"
                     /\ IF self = INITIATOR
                           THEN /\ \E sid \in Sessions \ used_sessions:
                                     \E p \in PSBTs:
                                       \E nonce \in ChallengeNonces:
                                         /\    peer_state[self] = "ActiveReady"
                                            /\ session_id = NoSession
                                            /\ tx_id = NoTx
                                            /\ sid \notin used_sessions
                                            /\ niso_i_event_block_height[self] >= Milestone0
                                         /\ session_id' = sid
                                         /\ tx_id' = TxOfPsbt[p]
                                         /\ psbt_i' = [psbt_i EXCEPT ![self] = p]
                                         /\ pending_txid_challenge_i' = [pending_txid_challenge_i EXCEPT ![self] =                               TxIdChallengeMsgFor(
                                                                                                                   sid,
                                                                                                                   TxOfPsbt[p],
                                                                                                                   self,
                                                                                                                   nonce)]
                                         /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingInitialTxIdAck"]
                                /\ UNCHANGED << local_psbt_reviewed_i, 
                                                wt_bundle_inbox, 
                                                peer_accepted_wt_bundle, 
                                                peer_accepted_wt_bundle_height >>
                           ELSE /\    peer_state[self] = "ActiveReady"
                                   /\ wt_bundle_inbox[self] # NoMessage
                                   /\ NisoAcceptsWTBundle(
                                        self,
                                        wt_bundle_inbox[self],
                                        session_id,
                                        tx_id,
                                        niso_i_event_block_height[self])
                                   /\ BoomletAcceptsWTBundle(
                                        self,
                                        wt_bundle_inbox[self],
                                        session_id,
                                        tx_id,
                                        niso_i_event_block_height[self])
                                /\ psbt_i' = [psbt_i EXCEPT ![self] = WTBundlePsbt(wt_bundle_inbox[self])]
                                /\ peer_accepted_wt_bundle' = [peer_accepted_wt_bundle EXCEPT ![self] = wt_bundle_inbox[self]]
                                /\ peer_accepted_wt_bundle_height' = [peer_accepted_wt_bundle_height EXCEPT ![self] = niso_i_event_block_height[self]]
                                /\ local_psbt_reviewed_i' = [local_psbt_reviewed_i EXCEPT ![self] = FALSE]
                                /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingNonInitiatorLocalApproval"]
                                /\ wt_bundle_inbox' = [wt_bundle_inbox EXCEPT ![self] = NoMessage]
                                /\ UNCHANGED << session_id, tx_id, 
                                                pending_txid_challenge_i >>
                     /\ pc' = [pc EXCEPT ![self] = "AwaitNonInitiatorLocalApproval"]
                     /\ UNCHANGED << mystery_i, used_sessions, 
                                     completed_withdrawals, 
                                     current_placeholder_i, placeholder_owner, 
                                     placeholder_kind, hydrated_psbt_i, 
                                     signed_psbt_i, signing_ticket_i, 
                                     accepted_txid_challenge_i, 
                                     accepted_txid_ack_i, 
                                     accepted_txid_ack_height_i, 
                                     pending_duress_challenge_i, 
                                     accepted_duress_challenge_i, 
                                     accepted_duress_ack_i, 
                                     accepted_duress_ack_height_i, 
                                     current_ping_from_recurring_check_i, 
                                     wt_state, wt_session_view, 
                                     peer_tx_approval_collection, 
                                     wt_tx_approval, approval_outbox, 
                                     approval_collection_delivered, 
                                     payload_kind_i, duress_latched_i, 
                                     duress_checks_i, approval_bundle_outbox, 
                                     approvals_bundle_accepted, commit_outbox, 
                                     initiator_commit_acked, 
                                     initiator_commit_inbox, 
                                     peer_tx_commit_collection, 
                                     commit_collection_delivered, 
                                     saved_expected_sar_ack, 
                                     sar_pending_ack_request, sar_ack_i, 
                                     sar_seen_placeholder_ids_i, 
                                     sar_escalated_i, wt_round_pings, 
                                     wt_last_accepted_ping, 
                                     peer_reviewed_ping_history_i, pong_i, 
                                     reached_collection_delivered, 
                                     reached_pings_collection, counter_i, 
                                     ping_seq_num_i, reached_mystery_flag_i, 
                                     reached_boomlets_collection_i, 
                                     signed_psbt_outbox, 
                                     wt_signed_psbt_collection, 
                                     broadcast_record, wt_accepted_approval, 
                                     wt_accepted_approval_height, 
                                     peer_accepted_initiator_commit, 
                                     peer_accepted_initiator_commit_height, 
                                     wt_accepted_commit, 
                                     wt_accepted_commit_height, 
                                     wt_accepted_ping, wt_accepted_ping_height, 
                                     peer_accepted_pong, 
                                     peer_accepted_pong_height, 
                                     peer_accepted_sar_ack, 
                                     peer_accepted_sar_ack_expected, 
                                     peer_accepted_sar_ack_height, 
                                     hardware_lost, fallback_activated, 
                                     niso_i_event_block_height, 
                                     most_work_bitcoin_block_height, 
                                     last_seen_block_i >>

AwaitNonInitiatorLocalApproval(self) == /\ pc[self] = "AwaitNonInitiatorLocalApproval"
                                        /\ IF self # INITIATOR
                                              THEN /\ \E nonce \in ChallengeNonces:
                                                        /\    peer_state[self] = "AwaitingNonInitiatorLocalApproval"
                                                           /\ psbt_i[self] # NoPsbt
                                                           /\ SameTxId(psbt_i[self], tx_id)
                                                        /\ local_psbt_reviewed_i' = [local_psbt_reviewed_i EXCEPT ![self] = TRUE]
                                                        /\ pending_txid_challenge_i' = [pending_txid_challenge_i EXCEPT ![self] =                               TxIdChallengeMsgFor(
                                                                                                                                  session_id,
                                                                                                                                  tx_id,
                                                                                                                                  self,
                                                                                                                                  nonce)]
                                                        /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingInitialTxIdAck"]
                                              ELSE /\ TRUE
                                                   /\ UNCHANGED << local_psbt_reviewed_i, 
                                                                   pending_txid_challenge_i, 
                                                                   peer_state >>
                                        /\ pc' = [pc EXCEPT ![self] = "AwaitInitialTxIdAck"]
                                        /\ UNCHANGED << mystery_i, 
                                                        used_sessions, 
                                                        completed_withdrawals, 
                                                        session_id, tx_id, 
                                                        current_placeholder_i, 
                                                        placeholder_owner, 
                                                        placeholder_kind, 
                                                        psbt_i, 
                                                        hydrated_psbt_i, 
                                                        signed_psbt_i, 
                                                        signing_ticket_i, 
                                                        accepted_txid_challenge_i, 
                                                        accepted_txid_ack_i, 
                                                        accepted_txid_ack_height_i, 
                                                        pending_duress_challenge_i, 
                                                        accepted_duress_challenge_i, 
                                                        accepted_duress_ack_i, 
                                                        accepted_duress_ack_height_i, 
                                                        current_ping_from_recurring_check_i, 
                                                        wt_state, 
                                                        wt_session_view, 
                                                        peer_tx_approval_collection, 
                                                        wt_tx_approval, 
                                                        approval_outbox, 
                                                        wt_bundle_inbox, 
                                                        approval_collection_delivered, 
                                                        payload_kind_i, 
                                                        duress_latched_i, 
                                                        duress_checks_i, 
                                                        approval_bundle_outbox, 
                                                        approvals_bundle_accepted, 
                                                        commit_outbox, 
                                                        initiator_commit_acked, 
                                                        initiator_commit_inbox, 
                                                        peer_tx_commit_collection, 
                                                        commit_collection_delivered, 
                                                        saved_expected_sar_ack, 
                                                        sar_pending_ack_request, 
                                                        sar_ack_i, 
                                                        sar_seen_placeholder_ids_i, 
                                                        sar_escalated_i, 
                                                        wt_round_pings, 
                                                        wt_last_accepted_ping, 
                                                        peer_reviewed_ping_history_i, 
                                                        pong_i, 
                                                        reached_collection_delivered, 
                                                        reached_pings_collection, 
                                                        counter_i, 
                                                        ping_seq_num_i, 
                                                        reached_mystery_flag_i, 
                                                        reached_boomlets_collection_i, 
                                                        signed_psbt_outbox, 
                                                        wt_signed_psbt_collection, 
                                                        broadcast_record, 
                                                        wt_accepted_approval, 
                                                        wt_accepted_approval_height, 
                                                        peer_accepted_wt_bundle, 
                                                        peer_accepted_wt_bundle_height, 
                                                        peer_accepted_initiator_commit, 
                                                        peer_accepted_initiator_commit_height, 
                                                        wt_accepted_commit, 
                                                        wt_accepted_commit_height, 
                                                        wt_accepted_ping, 
                                                        wt_accepted_ping_height, 
                                                        peer_accepted_pong, 
                                                        peer_accepted_pong_height, 
                                                        peer_accepted_sar_ack, 
                                                        peer_accepted_sar_ack_expected, 
                                                        peer_accepted_sar_ack_height, 
                                                        hardware_lost, 
                                                        fallback_activated, 
                                                        niso_i_event_block_height, 
                                                        most_work_bitcoin_block_height, 
                                                        last_seen_block_i >>

AwaitInitialTxIdAck(self) == /\ pc[self] = "AwaitInitialTxIdAck"
                             /\    peer_state[self] = "AwaitingInitialTxIdAck"
                                /\ pending_txid_challenge_i[self] # NoMessage
                             /\ accepted_txid_challenge_i' = [accepted_txid_challenge_i EXCEPT ![self] = pending_txid_challenge_i[self]]
                             /\ accepted_txid_ack_i' = [accepted_txid_ack_i EXCEPT ![self] =                          TxIdAckMsgFor(
                                                                                             pending_txid_challenge_i[self].sid,
                                                                                             pending_txid_challenge_i[self].txid,
                                                                                             self,
                                                                                             pending_txid_challenge_i[self].nonce)]
                             /\ accepted_txid_ack_height_i' = [accepted_txid_ack_height_i EXCEPT ![self] = niso_i_event_block_height[self]]
                             /\ pending_txid_challenge_i' = [pending_txid_challenge_i EXCEPT ![self] = NoMessage]
                             /\ IF self = INITIATOR
                                   THEN /\ approval_outbox' = [approval_outbox EXCEPT ![self] =                      InitiatorSubmissionMsgFor(
                                                                                                session_id,
                                                                                                tx_id,
                                                                                                niso_i_event_block_height[self],
                                                                                                psbt_i[self])]
                                   ELSE /\ approval_outbox' = [approval_outbox EXCEPT ![self] =                      ApprovalMsgFor(
                                                                                                session_id,
                                                                                                tx_id,
                                                                                                self,
                                                                                                niso_i_event_block_height[self])]
                             /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingPeerApprovals"]
                             /\ pc' = [pc EXCEPT ![self] = "AwaitApprovalCollection"]
                             /\ UNCHANGED << mystery_i, used_sessions, 
                                             completed_withdrawals, session_id, 
                                             tx_id, current_placeholder_i, 
                                             placeholder_owner, 
                                             placeholder_kind, psbt_i, 
                                             hydrated_psbt_i, signed_psbt_i, 
                                             signing_ticket_i, 
                                             local_psbt_reviewed_i, 
                                             pending_duress_challenge_i, 
                                             accepted_duress_challenge_i, 
                                             accepted_duress_ack_i, 
                                             accepted_duress_ack_height_i, 
                                             current_ping_from_recurring_check_i, 
                                             wt_state, wt_session_view, 
                                             peer_tx_approval_collection, 
                                             wt_tx_approval, wt_bundle_inbox, 
                                             approval_collection_delivered, 
                                             payload_kind_i, duress_latched_i, 
                                             duress_checks_i, 
                                             approval_bundle_outbox, 
                                             approvals_bundle_accepted, 
                                             commit_outbox, 
                                             initiator_commit_acked, 
                                             initiator_commit_inbox, 
                                             peer_tx_commit_collection, 
                                             commit_collection_delivered, 
                                             saved_expected_sar_ack, 
                                             sar_pending_ack_request, 
                                             sar_ack_i, 
                                             sar_seen_placeholder_ids_i, 
                                             sar_escalated_i, wt_round_pings, 
                                             wt_last_accepted_ping, 
                                             peer_reviewed_ping_history_i, 
                                             pong_i, 
                                             reached_collection_delivered, 
                                             reached_pings_collection, 
                                             counter_i, ping_seq_num_i, 
                                             reached_mystery_flag_i, 
                                             reached_boomlets_collection_i, 
                                             signed_psbt_outbox, 
                                             wt_signed_psbt_collection, 
                                             broadcast_record, 
                                             wt_accepted_approval, 
                                             wt_accepted_approval_height, 
                                             peer_accepted_wt_bundle, 
                                             peer_accepted_wt_bundle_height, 
                                             peer_accepted_initiator_commit, 
                                             peer_accepted_initiator_commit_height, 
                                             wt_accepted_commit, 
                                             wt_accepted_commit_height, 
                                             wt_accepted_ping, 
                                             wt_accepted_ping_height, 
                                             peer_accepted_pong, 
                                             peer_accepted_pong_height, 
                                             peer_accepted_sar_ack, 
                                             peer_accepted_sar_ack_expected, 
                                             peer_accepted_sar_ack_height, 
                                             hardware_lost, fallback_activated, 
                                             niso_i_event_block_height, 
                                             most_work_bitcoin_block_height, 
                                             last_seen_block_i >>

AwaitApprovalCollection(self) == /\ pc[self] = "AwaitApprovalCollection"
                                 /\ \E nonce \in ChallengeNonces:
                                      /\    peer_state[self] = "AwaitingPeerApprovals"
                                         /\ NisoValidApprovalCollectionForPeer(
                                              self,
                                              approval_collection_delivered[self],
                                              peer_tx_approval_collection,
                                              wt_tx_approval,
                                              session_id,
                                              tx_id,
                                              niso_i_event_block_height[self])
                                         /\ BoomletValidApprovalCollectionForPeer(
                                              self,
                                              approval_collection_delivered[self],
                                              peer_tx_approval_collection,
                                              wt_tx_approval,
                                              session_id,
                                              tx_id,
                                              niso_i_event_block_height[self])
                                      /\ pending_duress_challenge_i' = [pending_duress_challenge_i EXCEPT ![self] =                                 DuressChallengeMsgFor(
                                                                                                                    session_id,
                                                                                                                    tx_id,
                                                                                                                    self,
                                                                                                                    "initial",
                                                                                                                    0,
                                                                                                                    nonce)]
                                      /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingInitialDuressAck"]
                                 /\ pc' = [pc EXCEPT ![self] = "AwaitInitialDuressAck"]
                                 /\ UNCHANGED << mystery_i, used_sessions, 
                                                 completed_withdrawals, 
                                                 session_id, tx_id, 
                                                 current_placeholder_i, 
                                                 placeholder_owner, 
                                                 placeholder_kind, psbt_i, 
                                                 hydrated_psbt_i, 
                                                 signed_psbt_i, 
                                                 signing_ticket_i, 
                                                 local_psbt_reviewed_i, 
                                                 pending_txid_challenge_i, 
                                                 accepted_txid_challenge_i, 
                                                 accepted_txid_ack_i, 
                                                 accepted_txid_ack_height_i, 
                                                 accepted_duress_challenge_i, 
                                                 accepted_duress_ack_i, 
                                                 accepted_duress_ack_height_i, 
                                                 current_ping_from_recurring_check_i, 
                                                 wt_state, wt_session_view, 
                                                 peer_tx_approval_collection, 
                                                 wt_tx_approval, 
                                                 approval_outbox, 
                                                 wt_bundle_inbox, 
                                                 approval_collection_delivered, 
                                                 payload_kind_i, 
                                                 duress_latched_i, 
                                                 duress_checks_i, 
                                                 approval_bundle_outbox, 
                                                 approvals_bundle_accepted, 
                                                 commit_outbox, 
                                                 initiator_commit_acked, 
                                                 initiator_commit_inbox, 
                                                 peer_tx_commit_collection, 
                                                 commit_collection_delivered, 
                                                 saved_expected_sar_ack, 
                                                 sar_pending_ack_request, 
                                                 sar_ack_i, 
                                                 sar_seen_placeholder_ids_i, 
                                                 sar_escalated_i, 
                                                 wt_round_pings, 
                                                 wt_last_accepted_ping, 
                                                 peer_reviewed_ping_history_i, 
                                                 pong_i, 
                                                 reached_collection_delivered, 
                                                 reached_pings_collection, 
                                                 counter_i, ping_seq_num_i, 
                                                 reached_mystery_flag_i, 
                                                 reached_boomlets_collection_i, 
                                                 signed_psbt_outbox, 
                                                 wt_signed_psbt_collection, 
                                                 broadcast_record, 
                                                 wt_accepted_approval, 
                                                 wt_accepted_approval_height, 
                                                 peer_accepted_wt_bundle, 
                                                 peer_accepted_wt_bundle_height, 
                                                 peer_accepted_initiator_commit, 
                                                 peer_accepted_initiator_commit_height, 
                                                 wt_accepted_commit, 
                                                 wt_accepted_commit_height, 
                                                 wt_accepted_ping, 
                                                 wt_accepted_ping_height, 
                                                 peer_accepted_pong, 
                                                 peer_accepted_pong_height, 
                                                 peer_accepted_sar_ack, 
                                                 peer_accepted_sar_ack_expected, 
                                                 peer_accepted_sar_ack_height, 
                                                 hardware_lost, 
                                                 fallback_activated, 
                                                 niso_i_event_block_height, 
                                                 most_work_bitcoin_block_height, 
                                                 last_seen_block_i >>

AwaitInitialDuressAck(self) == /\ pc[self] = "AwaitInitialDuressAck"
                               /\    peer_state[self] = "AwaitingInitialDuressAck"
                                  /\ pending_duress_challenge_i[self] # NoMessage
                               /\ \E consent_match \in BOOLEAN:
                                    /\ accepted_duress_challenge_i' = [accepted_duress_challenge_i EXCEPT ![self] = pending_duress_challenge_i[self]]
                                    /\ accepted_duress_ack_i' = [accepted_duress_ack_i EXCEPT ![self] =                            DuressAckMsgFor(
                                                                                                        pending_duress_challenge_i[self].sid,
                                                                                                        pending_duress_challenge_i[self].txid,
                                                                                                        self,
                                                                                                        pending_duress_challenge_i[self].stage,
                                                                                                        pending_duress_challenge_i[self].seq,
                                                                                                        pending_duress_challenge_i[self].nonce,
                                                                                                        consent_match)]
                                    /\ accepted_duress_ack_height_i' = [accepted_duress_ack_height_i EXCEPT ![self] = niso_i_event_block_height[self]]
                                    /\ pending_duress_challenge_i' = [pending_duress_challenge_i EXCEPT ![self] = NoMessage]
                                    /\ payload_kind_i' = [payload_kind_i EXCEPT ![self] = IF consent_match THEN "padding" ELSE "doxing_key"]
                                    /\ duress_latched_i' = [duress_latched_i EXCEPT ![self] = ~consent_match]
                                    /\ duress_checks_i' = [duress_checks_i EXCEPT ![self] = duress_checks_i[self] + 1]
                                    /\ peer_state' = [peer_state EXCEPT ![self] = "InitialDuressResolved"]
                               /\ pc' = [pc EXCEPT ![self] = "AfterInitialDuress"]
                               /\ UNCHANGED << mystery_i, used_sessions, 
                                               completed_withdrawals, 
                                               session_id, tx_id, 
                                               current_placeholder_i, 
                                               placeholder_owner, 
                                               placeholder_kind, psbt_i, 
                                               hydrated_psbt_i, signed_psbt_i, 
                                               signing_ticket_i, 
                                               local_psbt_reviewed_i, 
                                               pending_txid_challenge_i, 
                                               accepted_txid_challenge_i, 
                                               accepted_txid_ack_i, 
                                               accepted_txid_ack_height_i, 
                                               current_ping_from_recurring_check_i, 
                                               wt_state, wt_session_view, 
                                               peer_tx_approval_collection, 
                                               wt_tx_approval, approval_outbox, 
                                               wt_bundle_inbox, 
                                               approval_collection_delivered, 
                                               approval_bundle_outbox, 
                                               approvals_bundle_accepted, 
                                               commit_outbox, 
                                               initiator_commit_acked, 
                                               initiator_commit_inbox, 
                                               peer_tx_commit_collection, 
                                               commit_collection_delivered, 
                                               saved_expected_sar_ack, 
                                               sar_pending_ack_request, 
                                               sar_ack_i, 
                                               sar_seen_placeholder_ids_i, 
                                               sar_escalated_i, wt_round_pings, 
                                               wt_last_accepted_ping, 
                                               peer_reviewed_ping_history_i, 
                                               pong_i, 
                                               reached_collection_delivered, 
                                               reached_pings_collection, 
                                               counter_i, ping_seq_num_i, 
                                               reached_mystery_flag_i, 
                                               reached_boomlets_collection_i, 
                                               signed_psbt_outbox, 
                                               wt_signed_psbt_collection, 
                                               broadcast_record, 
                                               wt_accepted_approval, 
                                               wt_accepted_approval_height, 
                                               peer_accepted_wt_bundle, 
                                               peer_accepted_wt_bundle_height, 
                                               peer_accepted_initiator_commit, 
                                               peer_accepted_initiator_commit_height, 
                                               wt_accepted_commit, 
                                               wt_accepted_commit_height, 
                                               wt_accepted_ping, 
                                               wt_accepted_ping_height, 
                                               peer_accepted_pong, 
                                               peer_accepted_pong_height, 
                                               peer_accepted_sar_ack, 
                                               peer_accepted_sar_ack_expected, 
                                               peer_accepted_sar_ack_height, 
                                               hardware_lost, 
                                               fallback_activated, 
                                               niso_i_event_block_height, 
                                               most_work_bitcoin_block_height, 
                                               last_seen_block_i >>

AfterInitialDuress(self) == /\ pc[self] = "AfterInitialDuress"
                            /\ IF self = INITIATOR
                                  THEN /\ \E pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner}:
                                            /\ placeholder_owner' = [placeholder_owner EXCEPT ![pid] = self]
                                            /\ placeholder_kind' = [placeholder_kind EXCEPT ![pid] = payload_kind_i[self]]
                                            /\ current_placeholder_i' = [current_placeholder_i EXCEPT ![self] = pid]
                                            /\ saved_expected_sar_ack' = [saved_expected_sar_ack EXCEPT ![self] =                             ExpectedAck(
                                                                                                                  session_id,
                                                                                                                  tx_id,
                                                                                                                  self,
                                                                                                                  "commit",
                                                                                                                  0,
                                                                                                                  pid)]
                                            /\ commit_outbox' = [commit_outbox EXCEPT ![self] =                    CommitMsgFor(
                                                                                                session_id,
                                                                                                tx_id,
                                                                                                self,
                                                                                                niso_i_event_block_height[self],
                                                                                                pid)]
                                       /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingCommitCollection"]
                                       /\ UNCHANGED approval_bundle_outbox
                                  ELSE /\ approval_bundle_outbox' = [approval_bundle_outbox EXCEPT ![self] =                             ApprovalsBundleMsgFor(
                                                                                                             session_id,
                                                                                                             self,
                                                                                                             peer_tx_approval_collection,
                                                                                                             wt_tx_approval)]
                                       /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingWTInitiatorCommit"]
                                       /\ UNCHANGED << current_placeholder_i, 
                                                       placeholder_owner, 
                                                       placeholder_kind, 
                                                       commit_outbox, 
                                                       saved_expected_sar_ack >>
                            /\ pc' = [pc EXCEPT ![self] = "AwaitInitiatorCommitAck"]
                            /\ UNCHANGED << mystery_i, used_sessions, 
                                            completed_withdrawals, session_id, 
                                            tx_id, psbt_i, hydrated_psbt_i, 
                                            signed_psbt_i, signing_ticket_i, 
                                            local_psbt_reviewed_i, 
                                            pending_txid_challenge_i, 
                                            accepted_txid_challenge_i, 
                                            accepted_txid_ack_i, 
                                            accepted_txid_ack_height_i, 
                                            pending_duress_challenge_i, 
                                            accepted_duress_challenge_i, 
                                            accepted_duress_ack_i, 
                                            accepted_duress_ack_height_i, 
                                            current_ping_from_recurring_check_i, 
                                            wt_state, wt_session_view, 
                                            peer_tx_approval_collection, 
                                            wt_tx_approval, approval_outbox, 
                                            wt_bundle_inbox, 
                                            approval_collection_delivered, 
                                            payload_kind_i, duress_latched_i, 
                                            duress_checks_i, 
                                            approvals_bundle_accepted, 
                                            initiator_commit_acked, 
                                            initiator_commit_inbox, 
                                            peer_tx_commit_collection, 
                                            commit_collection_delivered, 
                                            sar_pending_ack_request, sar_ack_i, 
                                            sar_seen_placeholder_ids_i, 
                                            sar_escalated_i, wt_round_pings, 
                                            wt_last_accepted_ping, 
                                            peer_reviewed_ping_history_i, 
                                            pong_i, 
                                            reached_collection_delivered, 
                                            reached_pings_collection, 
                                            counter_i, ping_seq_num_i, 
                                            reached_mystery_flag_i, 
                                            reached_boomlets_collection_i, 
                                            signed_psbt_outbox, 
                                            wt_signed_psbt_collection, 
                                            broadcast_record, 
                                            wt_accepted_approval, 
                                            wt_accepted_approval_height, 
                                            peer_accepted_wt_bundle, 
                                            peer_accepted_wt_bundle_height, 
                                            peer_accepted_initiator_commit, 
                                            peer_accepted_initiator_commit_height, 
                                            wt_accepted_commit, 
                                            wt_accepted_commit_height, 
                                            wt_accepted_ping, 
                                            wt_accepted_ping_height, 
                                            peer_accepted_pong, 
                                            peer_accepted_pong_height, 
                                            peer_accepted_sar_ack, 
                                            peer_accepted_sar_ack_expected, 
                                            peer_accepted_sar_ack_height, 
                                            hardware_lost, fallback_activated, 
                                            niso_i_event_block_height, 
                                            most_work_bitcoin_block_height, 
                                            last_seen_block_i >>

AwaitInitiatorCommitAck(self) == /\ pc[self] = "AwaitInitiatorCommitAck"
                                 /\ IF self # INITIATOR
                                       THEN /\    approvals_bundle_accepted[self]
                                               /\ initiator_commit_acked[self]
                                               /\ NisoValidInitiatorCommitForPeer(
                                                    self,
                                                    initiator_commit_inbox[self] # NoMessage,
                                                    initiator_commit_inbox[self],
                                                    session_id,
                                                    tx_id,
                                                    niso_i_event_block_height[self],
                                                    peer_tx_commit_collection[INITIATOR])
                                               /\ BoomletValidInitiatorCommitForPeer(
                                                    self,
                                                    initiator_commit_inbox[self] # NoMessage,
                                                    initiator_commit_inbox[self],
                                                    session_id,
                                                    tx_id,
                                                    niso_i_event_block_height[self],
                                                    peer_tx_commit_collection[INITIATOR])
                                            /\ peer_accepted_initiator_commit' = [peer_accepted_initiator_commit EXCEPT ![self] = initiator_commit_inbox[self]]
                                            /\ peer_accepted_initiator_commit_height' = [peer_accepted_initiator_commit_height EXCEPT ![self] = niso_i_event_block_height[self]]
                                            /\ initiator_commit_inbox' = [initiator_commit_inbox EXCEPT ![self] = NoMessage]
                                            /\ \E pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner}:
                                                 /\ placeholder_owner' = [placeholder_owner EXCEPT ![pid] = self]
                                                 /\ placeholder_kind' = [placeholder_kind EXCEPT ![pid] = payload_kind_i[self]]
                                                 /\ current_placeholder_i' = [current_placeholder_i EXCEPT ![self] = pid]
                                                 /\ saved_expected_sar_ack' = [saved_expected_sar_ack EXCEPT ![self] =                             ExpectedAck(
                                                                                                                       session_id,
                                                                                                                       tx_id,
                                                                                                                       self,
                                                                                                                       "commit",
                                                                                                                       0,
                                                                                                                       pid)]
                                                 /\ commit_outbox' = [commit_outbox EXCEPT ![self] =                    CommitMsgFor(
                                                                                                     session_id,
                                                                                                     tx_id,
                                                                                                     self,
                                                                                                     niso_i_event_block_height[self],
                                                                                                     pid)]
                                            /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingCommitCollection"]
                                       ELSE /\ TRUE
                                            /\ UNCHANGED << current_placeholder_i, 
                                                            placeholder_owner, 
                                                            placeholder_kind, 
                                                            peer_state, 
                                                            commit_outbox, 
                                                            initiator_commit_inbox, 
                                                            saved_expected_sar_ack, 
                                                            peer_accepted_initiator_commit, 
                                                            peer_accepted_initiator_commit_height >>
                                 /\ pc' = [pc EXCEPT ![self] = "EnterDiggingGame"]
                                 /\ UNCHANGED << mystery_i, used_sessions, 
                                                 completed_withdrawals, 
                                                 session_id, tx_id, psbt_i, 
                                                 hydrated_psbt_i, 
                                                 signed_psbt_i, 
                                                 signing_ticket_i, 
                                                 local_psbt_reviewed_i, 
                                                 pending_txid_challenge_i, 
                                                 accepted_txid_challenge_i, 
                                                 accepted_txid_ack_i, 
                                                 accepted_txid_ack_height_i, 
                                                 pending_duress_challenge_i, 
                                                 accepted_duress_challenge_i, 
                                                 accepted_duress_ack_i, 
                                                 accepted_duress_ack_height_i, 
                                                 current_ping_from_recurring_check_i, 
                                                 wt_state, wt_session_view, 
                                                 peer_tx_approval_collection, 
                                                 wt_tx_approval, 
                                                 approval_outbox, 
                                                 wt_bundle_inbox, 
                                                 approval_collection_delivered, 
                                                 payload_kind_i, 
                                                 duress_latched_i, 
                                                 duress_checks_i, 
                                                 approval_bundle_outbox, 
                                                 approvals_bundle_accepted, 
                                                 initiator_commit_acked, 
                                                 peer_tx_commit_collection, 
                                                 commit_collection_delivered, 
                                                 sar_pending_ack_request, 
                                                 sar_ack_i, 
                                                 sar_seen_placeholder_ids_i, 
                                                 sar_escalated_i, 
                                                 wt_round_pings, 
                                                 wt_last_accepted_ping, 
                                                 peer_reviewed_ping_history_i, 
                                                 pong_i, 
                                                 reached_collection_delivered, 
                                                 reached_pings_collection, 
                                                 counter_i, ping_seq_num_i, 
                                                 reached_mystery_flag_i, 
                                                 reached_boomlets_collection_i, 
                                                 signed_psbt_outbox, 
                                                 wt_signed_psbt_collection, 
                                                 broadcast_record, 
                                                 wt_accepted_approval, 
                                                 wt_accepted_approval_height, 
                                                 peer_accepted_wt_bundle, 
                                                 peer_accepted_wt_bundle_height, 
                                                 wt_accepted_commit, 
                                                 wt_accepted_commit_height, 
                                                 wt_accepted_ping, 
                                                 wt_accepted_ping_height, 
                                                 peer_accepted_pong, 
                                                 peer_accepted_pong_height, 
                                                 peer_accepted_sar_ack, 
                                                 peer_accepted_sar_ack_expected, 
                                                 peer_accepted_sar_ack_height, 
                                                 hardware_lost, 
                                                 fallback_activated, 
                                                 niso_i_event_block_height, 
                                                 most_work_bitcoin_block_height, 
                                                 last_seen_block_i >>

EnterDiggingGame(self) == /\ pc[self] = "EnterDiggingGame"
                          /\    peer_state[self] = "AwaitingCommitCollection"
                             /\ NisoValidCommitCollectionForPeer(
                                  self,
                                  commit_collection_delivered[self],
                                  peer_tx_commit_collection,
                                  session_id,
                                  tx_id,
                                  niso_i_event_block_height[self])
                             /\ BoomletValidCommitCollectionForPeer(
                                  self,
                                  commit_collection_delivered[self],
                                  peer_tx_commit_collection,
                                  session_id,
                                  tx_id,
                                  niso_i_event_block_height[self],
                                  sar_ack_i[self],
                                  saved_expected_sar_ack[self])
                          /\ peer_accepted_sar_ack' = [peer_accepted_sar_ack EXCEPT ![self] = sar_ack_i[self]]
                          /\ peer_accepted_sar_ack_expected' = [peer_accepted_sar_ack_expected EXCEPT ![self] = saved_expected_sar_ack[self]]
                          /\ peer_accepted_sar_ack_height' = [peer_accepted_sar_ack_height EXCEPT ![self] = niso_i_event_block_height[self]]
                          /\ sar_ack_i' = [sar_ack_i EXCEPT ![self] = NoMessage]
                          /\ \E pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner}:
                               /\ placeholder_owner' = [placeholder_owner EXCEPT ![pid] = self]
                               /\ placeholder_kind' = [placeholder_kind EXCEPT ![pid] = payload_kind_i[self]]
                               /\ current_placeholder_i' = [current_placeholder_i EXCEPT ![self] = pid]
                               /\ saved_expected_sar_ack' = [saved_expected_sar_ack EXCEPT ![self] =                             ExpectedAck(
                                                                                                     session_id,
                                                                                                     tx_id,
                                                                                                     self,
                                                                                                     "ping",
                                                                                                     0,
                                                                                                     pid)]
                               /\ counter_i' = [counter_i EXCEPT ![self] = 0]
                               /\ ping_seq_num_i' = [ping_seq_num_i EXCEPT ![self] = 0]
                               /\ reached_mystery_flag_i' = [reached_mystery_flag_i EXCEPT ![self] = FALSE]
                               /\ reached_boomlets_collection_i' = [reached_boomlets_collection_i EXCEPT ![self] = {}]
                               /\ last_seen_block_i' = [last_seen_block_i EXCEPT ![self] = niso_i_event_block_height[self]]
                               /\ current_ping_from_recurring_check_i' = [current_ping_from_recurring_check_i EXCEPT ![self] = FALSE]
                               /\ wt_round_pings' = [wt_round_pings EXCEPT ![self] =                     PingMsgFor(
                                                                                     session_id,
                                                                                     tx_id,
                                                                                     self,
                                                                                     niso_i_event_block_height[self],
                                                                                     0,
                                                                                     FALSE,
                                                                                     pid)]
                          /\ peer_state' = [peer_state EXCEPT ![self] = "DiggingGame"]
                          /\ pc' = [pc EXCEPT ![self] = "DiggingLoop"]
                          /\ UNCHANGED << mystery_i, used_sessions, 
                                          completed_withdrawals, session_id, 
                                          tx_id, psbt_i, hydrated_psbt_i, 
                                          signed_psbt_i, signing_ticket_i, 
                                          local_psbt_reviewed_i, 
                                          pending_txid_challenge_i, 
                                          accepted_txid_challenge_i, 
                                          accepted_txid_ack_i, 
                                          accepted_txid_ack_height_i, 
                                          pending_duress_challenge_i, 
                                          accepted_duress_challenge_i, 
                                          accepted_duress_ack_i, 
                                          accepted_duress_ack_height_i, 
                                          wt_state, wt_session_view, 
                                          peer_tx_approval_collection, 
                                          wt_tx_approval, approval_outbox, 
                                          wt_bundle_inbox, 
                                          approval_collection_delivered, 
                                          payload_kind_i, duress_latched_i, 
                                          duress_checks_i, 
                                          approval_bundle_outbox, 
                                          approvals_bundle_accepted, 
                                          commit_outbox, 
                                          initiator_commit_acked, 
                                          initiator_commit_inbox, 
                                          peer_tx_commit_collection, 
                                          commit_collection_delivered, 
                                          sar_pending_ack_request, 
                                          sar_seen_placeholder_ids_i, 
                                          sar_escalated_i, 
                                          wt_last_accepted_ping, 
                                          peer_reviewed_ping_history_i, pong_i, 
                                          reached_collection_delivered, 
                                          reached_pings_collection, 
                                          signed_psbt_outbox, 
                                          wt_signed_psbt_collection, 
                                          broadcast_record, 
                                          wt_accepted_approval, 
                                          wt_accepted_approval_height, 
                                          peer_accepted_wt_bundle, 
                                          peer_accepted_wt_bundle_height, 
                                          peer_accepted_initiator_commit, 
                                          peer_accepted_initiator_commit_height, 
                                          wt_accepted_commit, 
                                          wt_accepted_commit_height, 
                                          wt_accepted_ping, 
                                          wt_accepted_ping_height, 
                                          peer_accepted_pong, 
                                          peer_accepted_pong_height, 
                                          hardware_lost, fallback_activated, 
                                          niso_i_event_block_height, 
                                          most_work_bitcoin_block_height >>

DiggingLoop(self) == /\ pc[self] = "DiggingLoop"
                     /\ IF peer_state[self] \in {"DiggingGame", "AwaitingRecurringDuressAck"}
                           THEN /\ IF peer_state[self] = "DiggingGame"
                                      THEN /\ \/ /\    reached_collection_delivered[self]
                                                    /\ AckMatchesExpected(sar_ack_i[self], saved_expected_sar_ack[self])
                                                    /\ SameTxId(psbt_i[self], tx_id)
                                                    /\ ReachedCollectionValidForPeer(
                                                         self,
                                                         reached_collection_delivered[self],
                                                         reached_pings_collection,
                                                         session_id,
                                                         tx_id,
                                                         niso_i_event_block_height[self],
                                                         peer_reviewed_ping_history_i[self],
                                                         reached_boomlets_collection_i[self])
                                                 /\ peer_accepted_sar_ack' = [peer_accepted_sar_ack EXCEPT ![self] = sar_ack_i[self]]
                                                 /\ peer_accepted_sar_ack_expected' = [peer_accepted_sar_ack_expected EXCEPT ![self] = saved_expected_sar_ack[self]]
                                                 /\ peer_accepted_sar_ack_height' = [peer_accepted_sar_ack_height EXCEPT ![self] = niso_i_event_block_height[self]]
                                                 /\ hydrated_psbt_i' = [hydrated_psbt_i EXCEPT ![self] = psbt_i[self]]
                                                 /\ signing_ticket_i' = [signing_ticket_i EXCEPT ![self] = SigningTicketFor(session_id, tx_id)]
                                                 /\ current_ping_from_recurring_check_i' = [current_ping_from_recurring_check_i EXCEPT ![self] = FALSE]
                                                 /\ peer_state' = [peer_state EXCEPT ![self] = "ReadyToSign"]
                                                 /\ UNCHANGED <<current_placeholder_i, placeholder_owner, placeholder_kind, pending_duress_challenge_i, payload_kind_i, duress_latched_i, saved_expected_sar_ack, wt_round_pings, peer_reviewed_ping_history_i, pong_i, counter_i, ping_seq_num_i, reached_mystery_flag_i, reached_boomlets_collection_i, peer_accepted_pong, peer_accepted_pong_height, last_seen_block_i>>
                                              \/ /\    ~reached_collection_delivered[self]
                                                    /\ pong_i[self] # NoMessage
                                                    /\ NisoValidPongForPeer(
                                                         self,
                                                         pong_i[self],
                                                         session_id,
                                                         tx_id,
                                                         niso_i_event_block_height[self],
                                                         reached_boomlets_collection_i[self],
                                                         peer_reviewed_ping_history_i[self])
                                                    /\ BoomletValidPongForPeer(
                                                         self,
                                                         pong_i[self],
                                                         session_id,
                                                         tx_id,
                                                         niso_i_event_block_height[self],
                                                         reached_boomlets_collection_i[self],
                                                         saved_expected_sar_ack[self],
                                                         peer_reviewed_ping_history_i[self])
                                                 /\ peer_accepted_pong' = [peer_accepted_pong EXCEPT ![self] = pong_i[self]]
                                                 /\ peer_accepted_pong_height' = [peer_accepted_pong_height EXCEPT ![self] = niso_i_event_block_height[self]]
                                                 /\ peer_accepted_sar_ack' = [peer_accepted_sar_ack EXCEPT ![self] = pong_i[self].sar_ack]
                                                 /\ peer_accepted_sar_ack_expected' = [peer_accepted_sar_ack_expected EXCEPT ![self] = saved_expected_sar_ack[self]]
                                                 /\ peer_accepted_sar_ack_height' = [peer_accepted_sar_ack_height EXCEPT ![self] = niso_i_event_block_height[self]]
                                                 /\ \/ /\ \E pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner}:
                                                            /\ placeholder_owner' = [placeholder_owner EXCEPT ![pid] = self]
                                                            /\ placeholder_kind' = [placeholder_kind EXCEPT ![pid] =                      DiggingReplyKind(
                                                                                                                     duress_latched_i[self],
                                                                                                                     payload_kind_i[self],
                                                                                                                     FALSE,
                                                                                                                     FALSE)]
                                                            /\ current_placeholder_i' = [current_placeholder_i EXCEPT ![self] = pid]
                                                            /\ saved_expected_sar_ack' = [saved_expected_sar_ack EXCEPT ![self] =                             ExpectedAck(
                                                                                                                                  session_id,
                                                                                                                                  tx_id,
                                                                                                                                  self,
                                                                                                                                  "ping",
                                                                                                                                  ping_seq_num_i[self] + 1,
                                                                                                                                  pid)]
                                                            /\ wt_round_pings' = [wt_round_pings EXCEPT ![self] =                     PingMsgFor(
                                                                                                                  session_id,
                                                                                                                  tx_id,
                                                                                                                  self,
                                                                                                                  NextLastSeen(
                                                                                                                      last_seen_block_i[self],
                                                                                                                      niso_i_event_block_height[self]),
                                                                                                                  ping_seq_num_i[self] + 1,
                                                                                                                  NextReached(
                                                                                                                      reached_mystery_flag_i[self],
                                                                                                                      counter_i[self],
                                                                                                                      last_seen_block_i[self],
                                                                                                                      niso_i_event_block_height[self],
                                                                                                                      mystery_i[self],
                                                                                                                      pong_i[self],
                                                                                                                      peer_reviewed_ping_history_i[self],
                                                                                                                      self,
                                                                                                                      session_id,
                                                                                                                      tx_id,
                                                                                                                      reached_boomlets_collection_i[self]),
                                                                                                                  pid)]
                                                       /\ ping_seq_num_i' = [ping_seq_num_i EXCEPT ![self] = ping_seq_num_i[self] + 1]
                                                       /\ last_seen_block_i' = [last_seen_block_i EXCEPT ![self] =                        NextLastSeen(
                                                                                                                   last_seen_block_i[self],
                                                                                                                   niso_i_event_block_height[self])]
                                                       /\ reached_mystery_flag_i' = [reached_mystery_flag_i EXCEPT ![self] =                             NextReached(
                                                                                                                             reached_mystery_flag_i[self],
                                                                                                                             counter_i[self],
                                                                                                                             last_seen_block_i'[self],
                                                                                                                             niso_i_event_block_height[self],
                                                                                                                             mystery_i[self],
                                                                                                                             pong_i[self],
                                                                                                                             peer_reviewed_ping_history_i[self],
                                                                                                                             self,
                                                                                                                             session_id,
                                                                                                                             tx_id,
                                                                                                                             reached_boomlets_collection_i[self])]
                                                       /\ reached_boomlets_collection_i' = [reached_boomlets_collection_i EXCEPT ![self] =                                    reached_boomlets_collection_i[self] \cup
                                                                                                                                           ReachedPeersAdvertised(self, pong_i[self])]
                                                       /\ counter_i' = [counter_i EXCEPT ![self] =                NextCounter(
                                                                                                   counter_i[self],
                                                                                                   last_seen_block_i'[self],
                                                                                                   niso_i_event_block_height[self],
                                                                                                   pong_i[self],
                                                                                                   peer_reviewed_ping_history_i[self],
                                                                                                   self,
                                                                                                   session_id,
                                                                                                   tx_id,
                                                                                                   reached_boomlets_collection_i'[self])]
                                                       /\ duress_latched_i' = [duress_latched_i EXCEPT ![self] =                       DiggingReplyLatched(
                                                                                                                 duress_latched_i[self],
                                                                                                                 FALSE,
                                                                                                                 FALSE)]
                                                       /\ payload_kind_i' = [payload_kind_i EXCEPT ![self] =                     DiggingReplyKind(
                                                                                                             duress_latched_i'[self],
                                                                                                             payload_kind_i[self],
                                                                                                             FALSE,
                                                                                                             FALSE)]
                                                       /\ current_ping_from_recurring_check_i' = [current_ping_from_recurring_check_i EXCEPT ![self] = FALSE]
                                                       /\ peer_reviewed_ping_history_i' = [peer_reviewed_ping_history_i EXCEPT ![self] =                                   [j \in Peers |->
                                                                                                                                         IF j = self
                                                                                                                                            THEN peer_reviewed_ping_history_i[self][j]
                                                                                                                                            ELSE IF j \in OtherPeers(self)
                                                                                                                                                    THEN pong_i[self].other_pings[j]
                                                                                                                                                    ELSE peer_reviewed_ping_history_i[self][j]]]
                                                       /\ pong_i' = [pong_i EXCEPT ![self] = NoMessage]
                                                       /\ UNCHANGED <<pending_duress_challenge_i, peer_state>>
                                                    \/ /\ \E prng_draw \in RecurringDuressPRNGDraws:
                                                            IF RecurringDuressCheckFires(prng_draw)
                                                               THEN /\ \E nonce \in ChallengeNonces:
                                                                         /\ pending_duress_challenge_i' = [pending_duress_challenge_i EXCEPT ![self] =                                 DuressChallengeMsgFor(
                                                                                                                                                       session_id,
                                                                                                                                                       tx_id,
                                                                                                                                                       self,
                                                                                                                                                       "ping",
                                                                                                                                                       ping_seq_num_i[self] + 1,
                                                                                                                                                       nonce)]
                                                                         /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitingRecurringDuressAck"]
                                                                    /\ UNCHANGED << current_placeholder_i, 
                                                                                    placeholder_owner, 
                                                                                    placeholder_kind, 
                                                                                    current_ping_from_recurring_check_i, 
                                                                                    payload_kind_i, 
                                                                                    duress_latched_i, 
                                                                                    saved_expected_sar_ack, 
                                                                                    wt_round_pings, 
                                                                                    peer_reviewed_ping_history_i, 
                                                                                    pong_i, 
                                                                                    counter_i, 
                                                                                    ping_seq_num_i, 
                                                                                    reached_mystery_flag_i, 
                                                                                    reached_boomlets_collection_i, 
                                                                                    last_seen_block_i >>
                                                               ELSE /\ \E pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner}:
                                                                         /\ placeholder_owner' = [placeholder_owner EXCEPT ![pid] = self]
                                                                         /\ placeholder_kind' = [placeholder_kind EXCEPT ![pid] =                      DiggingReplyKind(
                                                                                                                                  duress_latched_i[self],
                                                                                                                                  payload_kind_i[self],
                                                                                                                                  FALSE,
                                                                                                                                  FALSE)]
                                                                         /\ current_placeholder_i' = [current_placeholder_i EXCEPT ![self] = pid]
                                                                         /\ saved_expected_sar_ack' = [saved_expected_sar_ack EXCEPT ![self] =                             ExpectedAck(
                                                                                                                                               session_id,
                                                                                                                                               tx_id,
                                                                                                                                               self,
                                                                                                                                               "ping",
                                                                                                                                               ping_seq_num_i[self] + 1,
                                                                                                                                               pid)]
                                                                         /\ wt_round_pings' = [wt_round_pings EXCEPT ![self] =                     PingMsgFor(
                                                                                                                               session_id,
                                                                                                                               tx_id,
                                                                                                                               self,
                                                                                                                               NextLastSeen(
                                                                                                                                   last_seen_block_i[self],
                                                                                                                                   niso_i_event_block_height[self]),
                                                                                                                               ping_seq_num_i[self] + 1,
                                                                                                                               NextReached(
                                                                                                                                   reached_mystery_flag_i[self],
                                                                                                                                   counter_i[self],
                                                                                                                                   last_seen_block_i[self],
                                                                                                                                   niso_i_event_block_height[self],
                                                                                                                                   mystery_i[self],
                                                                                                                                   pong_i[self],
                                                                                                                                   peer_reviewed_ping_history_i[self],
                                                                                                                                   self,
                                                                                                                                   session_id,
                                                                                                                                   tx_id,
                                                                                                                                   reached_boomlets_collection_i[self]),
                                                                                                                               pid)]
                                                                    /\ ping_seq_num_i' = [ping_seq_num_i EXCEPT ![self] = ping_seq_num_i[self] + 1]
                                                                    /\ last_seen_block_i' = [last_seen_block_i EXCEPT ![self] =                        NextLastSeen(
                                                                                                                                last_seen_block_i[self],
                                                                                                                                niso_i_event_block_height[self])]
                                                                    /\ reached_mystery_flag_i' = [reached_mystery_flag_i EXCEPT ![self] =                             NextReached(
                                                                                                                                          reached_mystery_flag_i[self],
                                                                                                                                          counter_i[self],
                                                                                                                                          last_seen_block_i'[self],
                                                                                                                                          niso_i_event_block_height[self],
                                                                                                                                          mystery_i[self],
                                                                                                                                          pong_i[self],
                                                                                                                                          peer_reviewed_ping_history_i[self],
                                                                                                                                          self,
                                                                                                                                          session_id,
                                                                                                                                          tx_id,
                                                                                                                                          reached_boomlets_collection_i[self])]
                                                                    /\ reached_boomlets_collection_i' = [reached_boomlets_collection_i EXCEPT ![self] =                                    reached_boomlets_collection_i[self] \cup
                                                                                                                                                        ReachedPeersAdvertised(self, pong_i[self])]
                                                                    /\ counter_i' = [counter_i EXCEPT ![self] =                NextCounter(
                                                                                                                counter_i[self],
                                                                                                                last_seen_block_i'[self],
                                                                                                                niso_i_event_block_height[self],
                                                                                                                pong_i[self],
                                                                                                                peer_reviewed_ping_history_i[self],
                                                                                                                self,
                                                                                                                session_id,
                                                                                                                tx_id,
                                                                                                                reached_boomlets_collection_i'[self])]
                                                                    /\ duress_latched_i' = [duress_latched_i EXCEPT ![self] =                       DiggingReplyLatched(
                                                                                                                              duress_latched_i[self],
                                                                                                                              FALSE,
                                                                                                                              FALSE)]
                                                                    /\ payload_kind_i' = [payload_kind_i EXCEPT ![self] =                     DiggingReplyKind(
                                                                                                                          duress_latched_i'[self],
                                                                                                                          payload_kind_i[self],
                                                                                                                          FALSE,
                                                                                                                          FALSE)]
                                                                    /\ current_ping_from_recurring_check_i' = [current_ping_from_recurring_check_i EXCEPT ![self] = FALSE]
                                                                    /\ peer_reviewed_ping_history_i' = [peer_reviewed_ping_history_i EXCEPT ![self] =                                   [j \in Peers |->
                                                                                                                                                      IF j = self
                                                                                                                                                         THEN peer_reviewed_ping_history_i[self][j]
                                                                                                                                                         ELSE IF j \in OtherPeers(self)
                                                                                                                                                                 THEN pong_i[self].other_pings[j]
                                                                                                                                                                 ELSE peer_reviewed_ping_history_i[self][j]]]
                                                                    /\ pong_i' = [pong_i EXCEPT ![self] = NoMessage]
                                                                    /\ UNCHANGED << pending_duress_challenge_i, 
                                                                                    peer_state >>
                                                 /\ UNCHANGED <<hydrated_psbt_i, signing_ticket_i>>
                                           /\ UNCHANGED << accepted_duress_challenge_i, 
                                                           accepted_duress_ack_i, 
                                                           accepted_duress_ack_height_i, 
                                                           duress_checks_i >>
                                      ELSE /\    peer_state[self] = "AwaitingRecurringDuressAck"
                                              /\ pending_duress_challenge_i[self] # NoMessage
                                              /\ pong_i[self] # NoMessage
                                           /\ \E consent_match \in BOOLEAN:
                                                /\ accepted_duress_challenge_i' = [accepted_duress_challenge_i EXCEPT ![self] = pending_duress_challenge_i[self]]
                                                /\ accepted_duress_ack_i' = [accepted_duress_ack_i EXCEPT ![self] =                            DuressAckMsgFor(
                                                                                                                    pending_duress_challenge_i[self].sid,
                                                                                                                    pending_duress_challenge_i[self].txid,
                                                                                                                    self,
                                                                                                                    pending_duress_challenge_i[self].stage,
                                                                                                                    pending_duress_challenge_i[self].seq,
                                                                                                                    pending_duress_challenge_i[self].nonce,
                                                                                                                    consent_match)]
                                                /\ accepted_duress_ack_height_i' = [accepted_duress_ack_height_i EXCEPT ![self] = niso_i_event_block_height[self]]
                                                /\ pending_duress_challenge_i' = [pending_duress_challenge_i EXCEPT ![self] = NoMessage]
                                                /\ \E pid \in {q \in PlaceholderIds : placeholder_owner[q] = NoSigner}:
                                                     /\ placeholder_owner' = [placeholder_owner EXCEPT ![pid] = self]
                                                     /\ placeholder_kind' = [placeholder_kind EXCEPT ![pid] =                      DiggingReplyKind(
                                                                                                              duress_latched_i[self],
                                                                                                              payload_kind_i[self],
                                                                                                              TRUE,
                                                                                                              ~consent_match)]
                                                     /\ current_placeholder_i' = [current_placeholder_i EXCEPT ![self] = pid]
                                                     /\ saved_expected_sar_ack' = [saved_expected_sar_ack EXCEPT ![self] =                             ExpectedAck(
                                                                                                                           session_id,
                                                                                                                           tx_id,
                                                                                                                           self,
                                                                                                                           "ping",
                                                                                                                           ping_seq_num_i[self] + 1,
                                                                                                                           pid)]
                                                     /\ wt_round_pings' = [wt_round_pings EXCEPT ![self] =                     PingMsgFor(
                                                                                                           session_id,
                                                                                                           tx_id,
                                                                                                           self,
                                                                                                           NextLastSeen(
                                                                                                               last_seen_block_i[self],
                                                                                                               niso_i_event_block_height[self]),
                                                                                                           ping_seq_num_i[self] + 1,
                                                                                                           NextReached(
                                                                                                               reached_mystery_flag_i[self],
                                                                                                               counter_i[self],
                                                                                                               last_seen_block_i[self],
                                                                                                               niso_i_event_block_height[self],
                                                                                                               mystery_i[self],
                                                                                                               pong_i[self],
                                                                                                               peer_reviewed_ping_history_i[self],
                                                                                                               self,
                                                                                                               session_id,
                                                                                                               tx_id,
                                                                                                               reached_boomlets_collection_i[self]),
                                                                                                           pid)]
                                                /\ ping_seq_num_i' = [ping_seq_num_i EXCEPT ![self] = ping_seq_num_i[self] + 1]
                                                /\ last_seen_block_i' = [last_seen_block_i EXCEPT ![self] =                        NextLastSeen(
                                                                                                            last_seen_block_i[self],
                                                                                                            niso_i_event_block_height[self])]
                                                /\ reached_mystery_flag_i' = [reached_mystery_flag_i EXCEPT ![self] =                             NextReached(
                                                                                                                      reached_mystery_flag_i[self],
                                                                                                                      counter_i[self],
                                                                                                                      last_seen_block_i'[self],
                                                                                                                      niso_i_event_block_height[self],
                                                                                                                      mystery_i[self],
                                                                                                                      pong_i[self],
                                                                                                                      peer_reviewed_ping_history_i[self],
                                                                                                                      self,
                                                                                                                      session_id,
                                                                                                                      tx_id,
                                                                                                                      reached_boomlets_collection_i[self])]
                                                /\ reached_boomlets_collection_i' = [reached_boomlets_collection_i EXCEPT ![self] =                                    reached_boomlets_collection_i[self] \cup
                                                                                                                                    ReachedPeersAdvertised(self, pong_i[self])]
                                                /\ counter_i' = [counter_i EXCEPT ![self] =                NextCounter(
                                                                                            counter_i[self],
                                                                                            last_seen_block_i'[self],
                                                                                            niso_i_event_block_height[self],
                                                                                            pong_i[self],
                                                                                            peer_reviewed_ping_history_i[self],
                                                                                            self,
                                                                                            session_id,
                                                                                            tx_id,
                                                                                            reached_boomlets_collection_i'[self])]
                                                /\ duress_latched_i' = [duress_latched_i EXCEPT ![self] =                       DiggingReplyLatched(
                                                                                                          duress_latched_i[self],
                                                                                                          TRUE,
                                                                                                          ~consent_match)]
                                                /\ payload_kind_i' = [payload_kind_i EXCEPT ![self] =                     DiggingReplyKind(
                                                                                                      duress_latched_i'[self],
                                                                                                      payload_kind_i[self],
                                                                                                      TRUE,
                                                                                                      ~consent_match)]
                                                /\ duress_checks_i' = [duress_checks_i EXCEPT ![self] = duress_checks_i[self] + 1]
                                                /\ current_ping_from_recurring_check_i' = [current_ping_from_recurring_check_i EXCEPT ![self] = TRUE]
                                                /\ peer_reviewed_ping_history_i' = [peer_reviewed_ping_history_i EXCEPT ![self] =                                   [j \in Peers |->
                                                                                                                                  IF j = self
                                                                                                                                     THEN peer_reviewed_ping_history_i[self][j]
                                                                                                                                     ELSE IF j \in OtherPeers(self)
                                                                                                                                             THEN pong_i[self].other_pings[j]
                                                                                                                                             ELSE peer_reviewed_ping_history_i[self][j]]]
                                                /\ pong_i' = [pong_i EXCEPT ![self] = NoMessage]
                                                /\ peer_state' = [peer_state EXCEPT ![self] = "DiggingGame"]
                                           /\ UNCHANGED << hydrated_psbt_i, 
                                                           signing_ticket_i, 
                                                           peer_accepted_pong, 
                                                           peer_accepted_pong_height, 
                                                           peer_accepted_sar_ack, 
                                                           peer_accepted_sar_ack_expected, 
                                                           peer_accepted_sar_ack_height >>
                                /\ pc' = [pc EXCEPT ![self] = "DiggingLoop"]
                           ELSE /\ pc' = [pc EXCEPT ![self] = "ReadyToSign"]
                                /\ UNCHANGED << current_placeholder_i, 
                                                placeholder_owner, 
                                                placeholder_kind, 
                                                hydrated_psbt_i, 
                                                signing_ticket_i, 
                                                pending_duress_challenge_i, 
                                                accepted_duress_challenge_i, 
                                                accepted_duress_ack_i, 
                                                accepted_duress_ack_height_i, 
                                                current_ping_from_recurring_check_i, 
                                                peer_state, payload_kind_i, 
                                                duress_latched_i, 
                                                duress_checks_i, 
                                                saved_expected_sar_ack, 
                                                wt_round_pings, 
                                                peer_reviewed_ping_history_i, 
                                                pong_i, counter_i, 
                                                ping_seq_num_i, 
                                                reached_mystery_flag_i, 
                                                reached_boomlets_collection_i, 
                                                peer_accepted_pong, 
                                                peer_accepted_pong_height, 
                                                peer_accepted_sar_ack, 
                                                peer_accepted_sar_ack_expected, 
                                                peer_accepted_sar_ack_height, 
                                                last_seen_block_i >>
                     /\ UNCHANGED << mystery_i, used_sessions, 
                                     completed_withdrawals, session_id, tx_id, 
                                     psbt_i, signed_psbt_i, 
                                     local_psbt_reviewed_i, 
                                     pending_txid_challenge_i, 
                                     accepted_txid_challenge_i, 
                                     accepted_txid_ack_i, 
                                     accepted_txid_ack_height_i, wt_state, 
                                     wt_session_view, 
                                     peer_tx_approval_collection, 
                                     wt_tx_approval, approval_outbox, 
                                     wt_bundle_inbox, 
                                     approval_collection_delivered, 
                                     approval_bundle_outbox, 
                                     approvals_bundle_accepted, commit_outbox, 
                                     initiator_commit_acked, 
                                     initiator_commit_inbox, 
                                     peer_tx_commit_collection, 
                                     commit_collection_delivered, 
                                     sar_pending_ack_request, sar_ack_i, 
                                     sar_seen_placeholder_ids_i, 
                                     sar_escalated_i, wt_last_accepted_ping, 
                                     reached_collection_delivered, 
                                     reached_pings_collection, 
                                     signed_psbt_outbox, 
                                     wt_signed_psbt_collection, 
                                     broadcast_record, wt_accepted_approval, 
                                     wt_accepted_approval_height, 
                                     peer_accepted_wt_bundle, 
                                     peer_accepted_wt_bundle_height, 
                                     peer_accepted_initiator_commit, 
                                     peer_accepted_initiator_commit_height, 
                                     wt_accepted_commit, 
                                     wt_accepted_commit_height, 
                                     wt_accepted_ping, wt_accepted_ping_height, 
                                     hardware_lost, fallback_activated, 
                                     niso_i_event_block_height, 
                                     most_work_bitcoin_block_height >>

ReadyToSign(self) == /\ pc[self] = "ReadyToSign"
                     /\ IF ~fallback_activated[self]
                           THEN /\    peer_state[self] = "ReadyToSign"
                                   /\ hydrated_psbt_i[self] # NoPsbt
                                   /\ signing_ticket_i[self] # NoMessage
                                   /\ \A j \in Peers :
                                        /\ peer_state[j] \in {"ReadyToSign", "Signed", "AwaitReset"}
                                        /\ ~fallback_activated[j]
                                        /\ signing_ticket_i[j] = signing_ticket_i[self]
                                        /\ saved_expected_sar_ack[j] # NoMessage
                                        /\ AckMatchesExpected(sar_ack_i[j], saved_expected_sar_ack[j])
                                /\ signed_psbt_i' = [signed_psbt_i EXCEPT ![self] = hydrated_psbt_i[self]]
                                /\ signed_psbt_outbox' = [signed_psbt_outbox EXCEPT ![self] =                         SignedPsbtMsgFor(
                                                                                              session_id,
                                                                                              tx_id,
                                                                                              self,
                                                                                              hydrated_psbt_i[self],
                                                                                              signing_ticket_i[self])]
                                /\ peer_state' = [peer_state EXCEPT ![self] = "Signed"]
                           ELSE /\ TRUE
                                /\ UNCHANGED << signed_psbt_i, peer_state, 
                                                signed_psbt_outbox >>
                     /\ pc' = [pc EXCEPT ![self] = "AwaitBroadcast"]
                     /\ UNCHANGED << mystery_i, used_sessions, 
                                     completed_withdrawals, session_id, tx_id, 
                                     current_placeholder_i, placeholder_owner, 
                                     placeholder_kind, psbt_i, hydrated_psbt_i, 
                                     signing_ticket_i, local_psbt_reviewed_i, 
                                     pending_txid_challenge_i, 
                                     accepted_txid_challenge_i, 
                                     accepted_txid_ack_i, 
                                     accepted_txid_ack_height_i, 
                                     pending_duress_challenge_i, 
                                     accepted_duress_challenge_i, 
                                     accepted_duress_ack_i, 
                                     accepted_duress_ack_height_i, 
                                     current_ping_from_recurring_check_i, 
                                     wt_state, wt_session_view, 
                                     peer_tx_approval_collection, 
                                     wt_tx_approval, approval_outbox, 
                                     wt_bundle_inbox, 
                                     approval_collection_delivered, 
                                     payload_kind_i, duress_latched_i, 
                                     duress_checks_i, approval_bundle_outbox, 
                                     approvals_bundle_accepted, commit_outbox, 
                                     initiator_commit_acked, 
                                     initiator_commit_inbox, 
                                     peer_tx_commit_collection, 
                                     commit_collection_delivered, 
                                     saved_expected_sar_ack, 
                                     sar_pending_ack_request, sar_ack_i, 
                                     sar_seen_placeholder_ids_i, 
                                     sar_escalated_i, wt_round_pings, 
                                     wt_last_accepted_ping, 
                                     peer_reviewed_ping_history_i, pong_i, 
                                     reached_collection_delivered, 
                                     reached_pings_collection, counter_i, 
                                     ping_seq_num_i, reached_mystery_flag_i, 
                                     reached_boomlets_collection_i, 
                                     wt_signed_psbt_collection, 
                                     broadcast_record, wt_accepted_approval, 
                                     wt_accepted_approval_height, 
                                     peer_accepted_wt_bundle, 
                                     peer_accepted_wt_bundle_height, 
                                     peer_accepted_initiator_commit, 
                                     peer_accepted_initiator_commit_height, 
                                     wt_accepted_commit, 
                                     wt_accepted_commit_height, 
                                     wt_accepted_ping, wt_accepted_ping_height, 
                                     peer_accepted_pong, 
                                     peer_accepted_pong_height, 
                                     peer_accepted_sar_ack, 
                                     peer_accepted_sar_ack_expected, 
                                     peer_accepted_sar_ack_height, 
                                     hardware_lost, fallback_activated, 
                                     niso_i_event_block_height, 
                                     most_work_bitcoin_block_height, 
                                     last_seen_block_i >>

AwaitBroadcast(self) == /\ pc[self] = "AwaitBroadcast"
                        /\ IF ~fallback_activated[self]
                              THEN /\    broadcast_record # NoMessage
                                      /\ BroadcastWellFormed(broadcast_record)
                                      /\ broadcast_record.sid = session_id
                                      /\ broadcast_record.txid = tx_id
                                      /\ BroadcastTicket(broadcast_record) = signing_ticket_i[self]
                                   /\ peer_state' = [peer_state EXCEPT ![self] = "AwaitReset"]
                              ELSE /\ TRUE
                                   /\ UNCHANGED peer_state
                        /\ pc' = [pc EXCEPT ![self] = "AfterSession"]
                        /\ UNCHANGED << mystery_i, used_sessions, 
                                        completed_withdrawals, session_id, 
                                        tx_id, current_placeholder_i, 
                                        placeholder_owner, placeholder_kind, 
                                        psbt_i, hydrated_psbt_i, signed_psbt_i, 
                                        signing_ticket_i, 
                                        local_psbt_reviewed_i, 
                                        pending_txid_challenge_i, 
                                        accepted_txid_challenge_i, 
                                        accepted_txid_ack_i, 
                                        accepted_txid_ack_height_i, 
                                        pending_duress_challenge_i, 
                                        accepted_duress_challenge_i, 
                                        accepted_duress_ack_i, 
                                        accepted_duress_ack_height_i, 
                                        current_ping_from_recurring_check_i, 
                                        wt_state, wt_session_view, 
                                        peer_tx_approval_collection, 
                                        wt_tx_approval, approval_outbox, 
                                        wt_bundle_inbox, 
                                        approval_collection_delivered, 
                                        payload_kind_i, duress_latched_i, 
                                        duress_checks_i, 
                                        approval_bundle_outbox, 
                                        approvals_bundle_accepted, 
                                        commit_outbox, initiator_commit_acked, 
                                        initiator_commit_inbox, 
                                        peer_tx_commit_collection, 
                                        commit_collection_delivered, 
                                        saved_expected_sar_ack, 
                                        sar_pending_ack_request, sar_ack_i, 
                                        sar_seen_placeholder_ids_i, 
                                        sar_escalated_i, wt_round_pings, 
                                        wt_last_accepted_ping, 
                                        peer_reviewed_ping_history_i, pong_i, 
                                        reached_collection_delivered, 
                                        reached_pings_collection, counter_i, 
                                        ping_seq_num_i, reached_mystery_flag_i, 
                                        reached_boomlets_collection_i, 
                                        signed_psbt_outbox, 
                                        wt_signed_psbt_collection, 
                                        broadcast_record, wt_accepted_approval, 
                                        wt_accepted_approval_height, 
                                        peer_accepted_wt_bundle, 
                                        peer_accepted_wt_bundle_height, 
                                        peer_accepted_initiator_commit, 
                                        peer_accepted_initiator_commit_height, 
                                        wt_accepted_commit, 
                                        wt_accepted_commit_height, 
                                        wt_accepted_ping, 
                                        wt_accepted_ping_height, 
                                        peer_accepted_pong, 
                                        peer_accepted_pong_height, 
                                        peer_accepted_sar_ack, 
                                        peer_accepted_sar_ack_expected, 
                                        peer_accepted_sar_ack_height, 
                                        hardware_lost, fallback_activated, 
                                        niso_i_event_block_height, 
                                        most_work_bitcoin_block_height, 
                                        last_seen_block_i >>

AfterSession(self) == /\ pc[self] = "AfterSession"
                      /\ IF fallback_activated[self]
                            THEN /\ FALSE
                                 /\ UNCHANGED << mystery_i, 
                                                 current_placeholder_i, psbt_i, 
                                                 hydrated_psbt_i, 
                                                 signed_psbt_i, 
                                                 signing_ticket_i, 
                                                 local_psbt_reviewed_i, 
                                                 pending_txid_challenge_i, 
                                                 accepted_txid_challenge_i, 
                                                 accepted_txid_ack_i, 
                                                 accepted_txid_ack_height_i, 
                                                 pending_duress_challenge_i, 
                                                 accepted_duress_challenge_i, 
                                                 accepted_duress_ack_i, 
                                                 accepted_duress_ack_height_i, 
                                                 current_ping_from_recurring_check_i, 
                                                 peer_state, 
                                                 approval_collection_delivered, 
                                                 payload_kind_i, 
                                                 duress_latched_i, 
                                                 duress_checks_i, 
                                                 approvals_bundle_accepted, 
                                                 initiator_commit_acked, 
                                                 initiator_commit_inbox, 
                                                 commit_collection_delivered, 
                                                 saved_expected_sar_ack, 
                                                 sar_pending_ack_request, 
                                                 sar_ack_i, sar_escalated_i, 
                                                 wt_round_pings, 
                                                 wt_last_accepted_ping, 
                                                 peer_reviewed_ping_history_i, 
                                                 pong_i, 
                                                 reached_collection_delivered, 
                                                 reached_pings_collection, 
                                                 counter_i, ping_seq_num_i, 
                                                 reached_mystery_flag_i, 
                                                 reached_boomlets_collection_i, 
                                                 signed_psbt_outbox, 
                                                 wt_signed_psbt_collection, 
                                                 peer_accepted_initiator_commit, 
                                                 peer_accepted_initiator_commit_height, 
                                                 last_seen_block_i >>
                            ELSE /\    peer_state[self] = "AwaitReset"
                                    /\ session_id = NoSession
                                    /\ tx_id = NoTx
                                    /\ broadcast_record = NoMessage
                                    /\ wt_state = "AwaitingInitiatorApproval"
                                 /\ \E regenerated_mystery \in {InitMystery[self], InitMystery[self] + 1}:
                                      /\ mystery_i' = [mystery_i EXCEPT ![self] = regenerated_mystery]
                                      /\ current_placeholder_i' = [current_placeholder_i EXCEPT ![self] = NoPayload]
                                      /\ psbt_i' = [psbt_i EXCEPT ![self] = NoPsbt]
                                      /\ hydrated_psbt_i' = [hydrated_psbt_i EXCEPT ![self] = NoPsbt]
                                      /\ signed_psbt_i' = [signed_psbt_i EXCEPT ![self] = NoPsbt]
                                      /\ signing_ticket_i' = [signing_ticket_i EXCEPT ![self] = NoMessage]
                                      /\ local_psbt_reviewed_i' = [local_psbt_reviewed_i EXCEPT ![self] = FALSE]
                                      /\ pending_txid_challenge_i' = [pending_txid_challenge_i EXCEPT ![self] = NoMessage]
                                      /\ accepted_txid_challenge_i' = [accepted_txid_challenge_i EXCEPT ![self] = NoMessage]
                                      /\ accepted_txid_ack_i' = [accepted_txid_ack_i EXCEPT ![self] = NoMessage]
                                      /\ accepted_txid_ack_height_i' = [accepted_txid_ack_height_i EXCEPT ![self] = LowestBlock]
                                      /\ pending_duress_challenge_i' = [pending_duress_challenge_i EXCEPT ![self] = NoMessage]
                                      /\ accepted_duress_challenge_i' = [accepted_duress_challenge_i EXCEPT ![self] = NoMessage]
                                      /\ accepted_duress_ack_i' = [accepted_duress_ack_i EXCEPT ![self] = NoMessage]
                                      /\ accepted_duress_ack_height_i' = [accepted_duress_ack_height_i EXCEPT ![self] = LowestBlock]
                                      /\ current_ping_from_recurring_check_i' = [current_ping_from_recurring_check_i EXCEPT ![self] = FALSE]
                                      /\ payload_kind_i' = [payload_kind_i EXCEPT ![self] = "none"]
                                      /\ duress_latched_i' = [duress_latched_i EXCEPT ![self] = FALSE]
                                      /\ duress_checks_i' = [duress_checks_i EXCEPT ![self] = 0]
                                      /\ approval_collection_delivered' = [approval_collection_delivered EXCEPT ![self] = FALSE]
                                      /\ approvals_bundle_accepted' = [approvals_bundle_accepted EXCEPT ![self] = FALSE]
                                      /\ initiator_commit_acked' = [initiator_commit_acked EXCEPT ![self] = FALSE]
                                      /\ initiator_commit_inbox' = [initiator_commit_inbox EXCEPT ![self] = NoMessage]
                                      /\ commit_collection_delivered' = [commit_collection_delivered EXCEPT ![self] = FALSE]
                                      /\ saved_expected_sar_ack' = [saved_expected_sar_ack EXCEPT ![self] = NoMessage]
                                      /\ sar_pending_ack_request' = [sar_pending_ack_request EXCEPT ![self] = NoMessage]
                                      /\ sar_ack_i' = [sar_ack_i EXCEPT ![self] = NoMessage]
                                      /\ sar_escalated_i' = [sar_escalated_i EXCEPT ![self] = FALSE]
                                      /\ wt_round_pings' = [wt_round_pings EXCEPT ![self] = NoMessage]
                                      /\ wt_last_accepted_ping' = [wt_last_accepted_ping EXCEPT ![self] = NoMessage]
                                      /\ peer_reviewed_ping_history_i' = [peer_reviewed_ping_history_i EXCEPT ![self] = [j \in Peers |-> NoMessage]]
                                      /\ pong_i' = [pong_i EXCEPT ![self] = NoMessage]
                                      /\ reached_collection_delivered' = [reached_collection_delivered EXCEPT ![self] = FALSE]
                                      /\ reached_pings_collection' = [reached_pings_collection EXCEPT ![self] = NoMessage]
                                      /\ counter_i' = [counter_i EXCEPT ![self] = 0]
                                      /\ ping_seq_num_i' = [ping_seq_num_i EXCEPT ![self] = 0]
                                      /\ reached_mystery_flag_i' = [reached_mystery_flag_i EXCEPT ![self] = FALSE]
                                      /\ reached_boomlets_collection_i' = [reached_boomlets_collection_i EXCEPT ![self] = {}]
                                      /\ signed_psbt_outbox' = [signed_psbt_outbox EXCEPT ![self] = NoMessage]
                                      /\ wt_signed_psbt_collection' = [wt_signed_psbt_collection EXCEPT ![self] = NoMessage]
                                      /\ peer_accepted_initiator_commit' = [peer_accepted_initiator_commit EXCEPT ![self] = NoMessage]
                                      /\ peer_accepted_initiator_commit_height' = [peer_accepted_initiator_commit_height EXCEPT ![self] = LowestBlock]
                                      /\ last_seen_block_i' = [last_seen_block_i EXCEPT ![self] = niso_i_event_block_height[self]]
                                      /\ peer_state' = [peer_state EXCEPT ![self] = "ActiveReady"]
                      /\ pc' = [pc EXCEPT ![self] = "PeerSessionLoop"]
                      /\ UNCHANGED << used_sessions, completed_withdrawals, 
                                      session_id, tx_id, placeholder_owner, 
                                      placeholder_kind, wt_state, 
                                      wt_session_view, 
                                      peer_tx_approval_collection, 
                                      wt_tx_approval, approval_outbox, 
                                      wt_bundle_inbox, approval_bundle_outbox, 
                                      commit_outbox, peer_tx_commit_collection, 
                                      sar_seen_placeholder_ids_i, 
                                      broadcast_record, wt_accepted_approval, 
                                      wt_accepted_approval_height, 
                                      peer_accepted_wt_bundle, 
                                      peer_accepted_wt_bundle_height, 
                                      wt_accepted_commit, 
                                      wt_accepted_commit_height, 
                                      wt_accepted_ping, 
                                      wt_accepted_ping_height, 
                                      peer_accepted_pong, 
                                      peer_accepted_pong_height, 
                                      peer_accepted_sar_ack, 
                                      peer_accepted_sar_ack_expected, 
                                      peer_accepted_sar_ack_height, 
                                      hardware_lost, fallback_activated, 
                                      niso_i_event_block_height, 
                                      most_work_bitcoin_block_height >>

Peer(self) == PeerSessionLoop(self) \/ ActiveReady(self)
                 \/ AwaitNonInitiatorLocalApproval(self)
                 \/ AwaitInitialTxIdAck(self)
                 \/ AwaitApprovalCollection(self)
                 \/ AwaitInitialDuressAck(self) \/ AfterInitialDuress(self)
                 \/ AwaitInitiatorCommitAck(self) \/ EnterDiggingGame(self)
                 \/ DiggingLoop(self) \/ ReadyToSign(self)
                 \/ AwaitBroadcast(self) \/ AfterSession(self)

WatchtowerSessionLoop == /\ pc[WT_ID] = "WatchtowerSessionLoop"
                         /\ pc' = [pc EXCEPT ![WT_ID] = "AwaitInitiatorApproval"]
                         /\ UNCHANGED << mystery_i, used_sessions, 
                                         completed_withdrawals, session_id, 
                                         tx_id, current_placeholder_i, 
                                         placeholder_owner, placeholder_kind, 
                                         psbt_i, hydrated_psbt_i, 
                                         signed_psbt_i, signing_ticket_i, 
                                         local_psbt_reviewed_i, 
                                         pending_txid_challenge_i, 
                                         accepted_txid_challenge_i, 
                                         accepted_txid_ack_i, 
                                         accepted_txid_ack_height_i, 
                                         pending_duress_challenge_i, 
                                         accepted_duress_challenge_i, 
                                         accepted_duress_ack_i, 
                                         accepted_duress_ack_height_i, 
                                         current_ping_from_recurring_check_i, 
                                         peer_state, wt_state, wt_session_view, 
                                         peer_tx_approval_collection, 
                                         wt_tx_approval, approval_outbox, 
                                         wt_bundle_inbox, 
                                         approval_collection_delivered, 
                                         payload_kind_i, duress_latched_i, 
                                         duress_checks_i, 
                                         approval_bundle_outbox, 
                                         approvals_bundle_accepted, 
                                         commit_outbox, initiator_commit_acked, 
                                         initiator_commit_inbox, 
                                         peer_tx_commit_collection, 
                                         commit_collection_delivered, 
                                         saved_expected_sar_ack, 
                                         sar_pending_ack_request, sar_ack_i, 
                                         sar_seen_placeholder_ids_i, 
                                         sar_escalated_i, wt_round_pings, 
                                         wt_last_accepted_ping, 
                                         peer_reviewed_ping_history_i, pong_i, 
                                         reached_collection_delivered, 
                                         reached_pings_collection, counter_i, 
                                         ping_seq_num_i, 
                                         reached_mystery_flag_i, 
                                         reached_boomlets_collection_i, 
                                         signed_psbt_outbox, 
                                         wt_signed_psbt_collection, 
                                         broadcast_record, 
                                         wt_accepted_approval, 
                                         wt_accepted_approval_height, 
                                         peer_accepted_wt_bundle, 
                                         peer_accepted_wt_bundle_height, 
                                         peer_accepted_initiator_commit, 
                                         peer_accepted_initiator_commit_height, 
                                         wt_accepted_commit, 
                                         wt_accepted_commit_height, 
                                         wt_accepted_ping, 
                                         wt_accepted_ping_height, 
                                         peer_accepted_pong, 
                                         peer_accepted_pong_height, 
                                         peer_accepted_sar_ack, 
                                         peer_accepted_sar_ack_expected, 
                                         peer_accepted_sar_ack_height, 
                                         hardware_lost, fallback_activated, 
                                         niso_i_event_block_height, 
                                         most_work_bitcoin_block_height, 
                                         last_seen_block_i >>

AwaitInitiatorApproval == /\ pc[WT_ID] = "AwaitInitiatorApproval"
                          /\    approval_outbox[INITIATOR] # NoMessage
                             /\ InitiatorSubmissionWellFormed(approval_outbox[INITIATOR])
                             /\ ValidSig(SubmissionApproval(approval_outbox[INITIATOR]), INITIATOR)
                             /\ MsgSessionMatches(SubmissionApproval(approval_outbox[INITIATOR]), session_id)
                             /\ MsgTxMatches(SubmissionApproval(approval_outbox[INITIATOR]), tx_id)
                             /\ ApprovalFreshAtWT(
                                  SubmissionApproval(approval_outbox[INITIATOR]),
                                  most_work_bitcoin_block_height)
                          /\ wt_session_view' =                [
                                                sid |-> session_id,
                                                txid |-> tx_id,
                                                initiator |-> INITIATOR,
                                                height |-> most_work_bitcoin_block_height ]
                          /\ peer_tx_approval_collection' = [peer_tx_approval_collection EXCEPT ![INITIATOR] = SubmissionApproval(approval_outbox[INITIATOR])]
                          /\ wt_accepted_approval' = [wt_accepted_approval EXCEPT ![INITIATOR] = SubmissionApproval(approval_outbox[INITIATOR])]
                          /\ wt_accepted_approval_height' = [wt_accepted_approval_height EXCEPT ![INITIATOR] = most_work_bitcoin_block_height]
                          /\ wt_tx_approval' = WTApprovalMsgFor(session_id, tx_id, most_work_bitcoin_block_height)
                          /\ wt_bundle_inbox' =                [i \in Peers |->
                                                IF i = INITIATOR
                                                   THEN NoMessage
                                                   ELSE WTBundleMsgFor(
                                                        session_id,
                                                        SubmissionPsbt(approval_outbox[INITIATOR]),
                                                        SubmissionApproval(approval_outbox[INITIATOR]),
                                                        WTApprovalMsgFor(session_id, tx_id, most_work_bitcoin_block_height))]
                          /\ approval_outbox' = [approval_outbox EXCEPT ![INITIATOR] = NoMessage]
                          /\ wt_state' = "CollectingPeerApprovals"
                          /\ pc' = [pc EXCEPT ![WT_ID] = "CollectPeerApprovals"]
                          /\ UNCHANGED << mystery_i, used_sessions, 
                                          completed_withdrawals, session_id, 
                                          tx_id, current_placeholder_i, 
                                          placeholder_owner, placeholder_kind, 
                                          psbt_i, hydrated_psbt_i, 
                                          signed_psbt_i, signing_ticket_i, 
                                          local_psbt_reviewed_i, 
                                          pending_txid_challenge_i, 
                                          accepted_txid_challenge_i, 
                                          accepted_txid_ack_i, 
                                          accepted_txid_ack_height_i, 
                                          pending_duress_challenge_i, 
                                          accepted_duress_challenge_i, 
                                          accepted_duress_ack_i, 
                                          accepted_duress_ack_height_i, 
                                          current_ping_from_recurring_check_i, 
                                          peer_state, 
                                          approval_collection_delivered, 
                                          payload_kind_i, duress_latched_i, 
                                          duress_checks_i, 
                                          approval_bundle_outbox, 
                                          approvals_bundle_accepted, 
                                          commit_outbox, 
                                          initiator_commit_acked, 
                                          initiator_commit_inbox, 
                                          peer_tx_commit_collection, 
                                          commit_collection_delivered, 
                                          saved_expected_sar_ack, 
                                          sar_pending_ack_request, sar_ack_i, 
                                          sar_seen_placeholder_ids_i, 
                                          sar_escalated_i, wt_round_pings, 
                                          wt_last_accepted_ping, 
                                          peer_reviewed_ping_history_i, pong_i, 
                                          reached_collection_delivered, 
                                          reached_pings_collection, counter_i, 
                                          ping_seq_num_i, 
                                          reached_mystery_flag_i, 
                                          reached_boomlets_collection_i, 
                                          signed_psbt_outbox, 
                                          wt_signed_psbt_collection, 
                                          broadcast_record, 
                                          peer_accepted_wt_bundle, 
                                          peer_accepted_wt_bundle_height, 
                                          peer_accepted_initiator_commit, 
                                          peer_accepted_initiator_commit_height, 
                                          wt_accepted_commit, 
                                          wt_accepted_commit_height, 
                                          wt_accepted_ping, 
                                          wt_accepted_ping_height, 
                                          peer_accepted_pong, 
                                          peer_accepted_pong_height, 
                                          peer_accepted_sar_ack, 
                                          peer_accepted_sar_ack_expected, 
                                          peer_accepted_sar_ack_height, 
                                          hardware_lost, fallback_activated, 
                                          niso_i_event_block_height, 
                                          most_work_bitcoin_block_height, 
                                          last_seen_block_i >>

CollectPeerApprovals == /\ pc[WT_ID] = "CollectPeerApprovals"
                        /\ IF wt_state = "CollectingPeerApprovals"
                              THEN /\ \/ /\ \E i \in {p \in OtherPeers(INITIATOR) :
                                                          /\ approval_outbox[p] # NoMessage
                                                          /\ ApprovalWellFormed(approval_outbox[p])
                                                          /\ ValidSig(approval_outbox[p], p)
                                                          /\ approval_outbox[p].sid = session_id
                                                          /\ approval_outbox[p].txid = tx_id
                                                          /\ PostWTApprovalWindowValid(
                                                              approval_outbox[p],
                                                              wt_tx_approval,
                                                              most_work_bitcoin_block_height)}:
                                              /\ peer_tx_approval_collection' = [peer_tx_approval_collection EXCEPT ![i] = approval_outbox[i]]
                                              /\ wt_accepted_approval' = [wt_accepted_approval EXCEPT ![i] = approval_outbox[i]]
                                              /\ wt_accepted_approval_height' = [wt_accepted_approval_height EXCEPT ![i] = most_work_bitcoin_block_height]
                                              /\ approval_outbox' = [approval_outbox EXCEPT ![i] = NoMessage]
                                         /\ UNCHANGED <<wt_state, approval_collection_delivered>>
                                      \/ /\    AllApprovalsPresent(peer_tx_approval_collection)
                                            /\ \E i \in Peers : ~approval_collection_delivered[i]
                                         /\ approval_collection_delivered' = [i \in Peers |-> TRUE]
                                         /\ wt_state' = "CollectingCommitments"
                                         /\ UNCHANGED <<peer_tx_approval_collection, approval_outbox, wt_accepted_approval, wt_accepted_approval_height>>
                                   /\ pc' = [pc EXCEPT ![WT_ID] = "CollectPeerApprovals"]
                              ELSE /\ pc' = [pc EXCEPT ![WT_ID] = "CollectCommitments"]
                                   /\ UNCHANGED << wt_state, 
                                                   peer_tx_approval_collection, 
                                                   approval_outbox, 
                                                   approval_collection_delivered, 
                                                   wt_accepted_approval, 
                                                   wt_accepted_approval_height >>
                        /\ UNCHANGED << mystery_i, used_sessions, 
                                        completed_withdrawals, session_id, 
                                        tx_id, current_placeholder_i, 
                                        placeholder_owner, placeholder_kind, 
                                        psbt_i, hydrated_psbt_i, signed_psbt_i, 
                                        signing_ticket_i, 
                                        local_psbt_reviewed_i, 
                                        pending_txid_challenge_i, 
                                        accepted_txid_challenge_i, 
                                        accepted_txid_ack_i, 
                                        accepted_txid_ack_height_i, 
                                        pending_duress_challenge_i, 
                                        accepted_duress_challenge_i, 
                                        accepted_duress_ack_i, 
                                        accepted_duress_ack_height_i, 
                                        current_ping_from_recurring_check_i, 
                                        peer_state, wt_session_view, 
                                        wt_tx_approval, wt_bundle_inbox, 
                                        payload_kind_i, duress_latched_i, 
                                        duress_checks_i, 
                                        approval_bundle_outbox, 
                                        approvals_bundle_accepted, 
                                        commit_outbox, initiator_commit_acked, 
                                        initiator_commit_inbox, 
                                        peer_tx_commit_collection, 
                                        commit_collection_delivered, 
                                        saved_expected_sar_ack, 
                                        sar_pending_ack_request, sar_ack_i, 
                                        sar_seen_placeholder_ids_i, 
                                        sar_escalated_i, wt_round_pings, 
                                        wt_last_accepted_ping, 
                                        peer_reviewed_ping_history_i, pong_i, 
                                        reached_collection_delivered, 
                                        reached_pings_collection, counter_i, 
                                        ping_seq_num_i, reached_mystery_flag_i, 
                                        reached_boomlets_collection_i, 
                                        signed_psbt_outbox, 
                                        wt_signed_psbt_collection, 
                                        broadcast_record, 
                                        peer_accepted_wt_bundle, 
                                        peer_accepted_wt_bundle_height, 
                                        peer_accepted_initiator_commit, 
                                        peer_accepted_initiator_commit_height, 
                                        wt_accepted_commit, 
                                        wt_accepted_commit_height, 
                                        wt_accepted_ping, 
                                        wt_accepted_ping_height, 
                                        peer_accepted_pong, 
                                        peer_accepted_pong_height, 
                                        peer_accepted_sar_ack, 
                                        peer_accepted_sar_ack_expected, 
                                        peer_accepted_sar_ack_height, 
                                        hardware_lost, fallback_activated, 
                                        niso_i_event_block_height, 
                                        most_work_bitcoin_block_height, 
                                        last_seen_block_i >>

CollectCommitments == /\ pc[WT_ID] = "CollectCommitments"
                      /\ IF wt_state = "CollectingCommitments"
                            THEN /\ \/ /\ \E i \in {p \in OtherPeers(INITIATOR) :
                                                        /\ approval_bundle_outbox[p] # NoMessage
                                                        /\ BundleWellFormed(approval_bundle_outbox[p])
                                                        /\ ValidSig(approval_bundle_outbox[p], p)
                                                        /\ approval_bundle_outbox[p].sid = session_id
                                                        /\ ApprovalsBundleApprovals(approval_bundle_outbox[p]) = peer_tx_approval_collection
                                                        /\ ApprovalsBundleWTApproval(approval_bundle_outbox[p]) = wt_tx_approval}:
                                            /\ approvals_bundle_accepted' = [approvals_bundle_accepted EXCEPT ![i] = TRUE]
                                            /\ approval_bundle_outbox' = [approval_bundle_outbox EXCEPT ![i] = NoMessage]
                                       /\ UNCHANGED <<wt_state, commit_outbox, initiator_commit_acked, initiator_commit_inbox, peer_tx_commit_collection, commit_collection_delivered, sar_pending_ack_request, wt_accepted_commit, wt_accepted_commit_height>>
                                    \/ /\ \E i \in {p \in Peers :
                                                        /\ commit_outbox[p] # NoMessage
                                                        /\ peer_tx_commit_collection[p] = NoMessage
                                                        /\ sar_pending_ack_request[p] = NoMessage
                                                        /\ sar_ack_i[p] = NoMessage
                                                        /\ CommitWellFormed(commit_outbox[p])
                                                        /\ ValidSig(commit_outbox[p], p)
                                                        /\ commit_outbox[p].sid = session_id
                                                        /\ commit_outbox[p].txid = tx_id
                                                        /\ CommitFreshAtWT(
                                                            commit_outbox[p],
                                                            most_work_bitcoin_block_height)}:
                                            /\ wt_accepted_commit' = [wt_accepted_commit EXCEPT ![i] = commit_outbox[i]]
                                            /\ wt_accepted_commit_height' = [wt_accepted_commit_height EXCEPT ![i] = most_work_bitcoin_block_height]
                                            /\ sar_pending_ack_request' = [sar_pending_ack_request EXCEPT ![i] =                           ExpectedAck(
                                                                                                                 session_id,
                                                                                                                 tx_id,
                                                                                                                 i,
                                                                                                                 "commit",
                                                                                                                 0,
                                                                                                                 CommitPlaceholder(commit_outbox[i]))]
                                       /\ UNCHANGED <<wt_state, approval_bundle_outbox, approvals_bundle_accepted, commit_outbox, initiator_commit_acked, initiator_commit_inbox, peer_tx_commit_collection, commit_collection_delivered>>
                                    \/ /\ \E i \in {p \in Peers :
                                                        /\ commit_outbox[p] # NoMessage
                                                        /\ AckMatchesExpected(
                                                            sar_ack_i[p],
                                                            saved_expected_sar_ack[p])}:
                                            /\ peer_tx_commit_collection' = [peer_tx_commit_collection EXCEPT ![i] = SealCommit(commit_outbox[i])]
                                            /\ IF i = INITIATOR
                                                  THEN /\ initiator_commit_acked' =                       [j \in Peers |->
                                                                                    IF j = INITIATOR THEN initiator_commit_acked[j] ELSE TRUE]
                                                       /\ initiator_commit_inbox' =                       [j \in Peers |->
                                                                                    IF j = INITIATOR THEN initiator_commit_inbox[j]
                                                                                    ELSE SealCommit(commit_outbox[i])]
                                                  ELSE /\ TRUE
                                                       /\ UNCHANGED << initiator_commit_acked, 
                                                                       initiator_commit_inbox >>
                                            /\ commit_outbox' = [commit_outbox EXCEPT ![i] = NoMessage]
                                       /\ UNCHANGED <<wt_state, approval_bundle_outbox, approvals_bundle_accepted, commit_collection_delivered, sar_pending_ack_request, wt_accepted_commit, wt_accepted_commit_height>>
                                    \/ /\    AllCommitsPresent(peer_tx_commit_collection)
                                          /\ \E i \in Peers : ~commit_collection_delivered[i]
                                       /\ commit_collection_delivered' = [i \in Peers |-> TRUE]
                                       /\ wt_state' = "CollectingPings"
                                       /\ UNCHANGED <<approval_bundle_outbox, approvals_bundle_accepted, commit_outbox, initiator_commit_acked, initiator_commit_inbox, peer_tx_commit_collection, sar_pending_ack_request, wt_accepted_commit, wt_accepted_commit_height>>
                                 /\ pc' = [pc EXCEPT ![WT_ID] = "CollectCommitments"]
                            ELSE /\ pc' = [pc EXCEPT ![WT_ID] = "CollectPings"]
                                 /\ UNCHANGED << wt_state, 
                                                 approval_bundle_outbox, 
                                                 approvals_bundle_accepted, 
                                                 commit_outbox, 
                                                 initiator_commit_acked, 
                                                 initiator_commit_inbox, 
                                                 peer_tx_commit_collection, 
                                                 commit_collection_delivered, 
                                                 sar_pending_ack_request, 
                                                 wt_accepted_commit, 
                                                 wt_accepted_commit_height >>
                      /\ UNCHANGED << mystery_i, used_sessions, 
                                      completed_withdrawals, session_id, tx_id, 
                                      current_placeholder_i, placeholder_owner, 
                                      placeholder_kind, psbt_i, 
                                      hydrated_psbt_i, signed_psbt_i, 
                                      signing_ticket_i, local_psbt_reviewed_i, 
                                      pending_txid_challenge_i, 
                                      accepted_txid_challenge_i, 
                                      accepted_txid_ack_i, 
                                      accepted_txid_ack_height_i, 
                                      pending_duress_challenge_i, 
                                      accepted_duress_challenge_i, 
                                      accepted_duress_ack_i, 
                                      accepted_duress_ack_height_i, 
                                      current_ping_from_recurring_check_i, 
                                      peer_state, wt_session_view, 
                                      peer_tx_approval_collection, 
                                      wt_tx_approval, approval_outbox, 
                                      wt_bundle_inbox, 
                                      approval_collection_delivered, 
                                      payload_kind_i, duress_latched_i, 
                                      duress_checks_i, saved_expected_sar_ack, 
                                      sar_ack_i, sar_seen_placeholder_ids_i, 
                                      sar_escalated_i, wt_round_pings, 
                                      wt_last_accepted_ping, 
                                      peer_reviewed_ping_history_i, pong_i, 
                                      reached_collection_delivered, 
                                      reached_pings_collection, counter_i, 
                                      ping_seq_num_i, reached_mystery_flag_i, 
                                      reached_boomlets_collection_i, 
                                      signed_psbt_outbox, 
                                      wt_signed_psbt_collection, 
                                      broadcast_record, wt_accepted_approval, 
                                      wt_accepted_approval_height, 
                                      peer_accepted_wt_bundle, 
                                      peer_accepted_wt_bundle_height, 
                                      peer_accepted_initiator_commit, 
                                      peer_accepted_initiator_commit_height, 
                                      wt_accepted_ping, 
                                      wt_accepted_ping_height, 
                                      peer_accepted_pong, 
                                      peer_accepted_pong_height, 
                                      peer_accepted_sar_ack, 
                                      peer_accepted_sar_ack_expected, 
                                      peer_accepted_sar_ack_height, 
                                      hardware_lost, fallback_activated, 
                                      niso_i_event_block_height, 
                                      most_work_bitcoin_block_height, 
                                      last_seen_block_i >>

CollectPings == /\ pc[WT_ID] = "CollectPings"
                /\ IF wt_state = "CollectingPings"
                      THEN /\ \/ /\ \E i \in {p \in Peers :
                                                  /\ wt_round_pings[p] # NoMessage
                                                  /\ sar_pending_ack_request[p] = NoMessage
                                                  /\ sar_ack_i[p] = NoMessage
                                                  /\ PingWellFormed(wt_round_pings[p])
                                                  /\ ValidSig(wt_round_pings[p], p)
                                                  /\ wt_round_pings[p].sid = session_id
                                                  /\ wt_round_pings[p].txid = tx_id
                                                  /\ PingFreshAtWT(
                                                      wt_round_pings[p],
                                                      most_work_bitcoin_block_height)
                                                  /\ PingProgressesFrom(
                                                      wt_last_accepted_ping[p],
                                                      wt_round_pings[p],
                                                      most_work_bitcoin_block_height)}:
                                      /\ wt_accepted_ping' = [wt_accepted_ping EXCEPT ![i] = wt_round_pings[i]]
                                      /\ wt_accepted_ping_height' = [wt_accepted_ping_height EXCEPT ![i] = most_work_bitcoin_block_height]
                                      /\ wt_last_accepted_ping' = [wt_last_accepted_ping EXCEPT ![i] = wt_round_pings[i]]
                                      /\ sar_pending_ack_request' = [sar_pending_ack_request EXCEPT ![i] =                           ExpectedAck(
                                                                                                           session_id,
                                                                                                           tx_id,
                                                                                                           i,
                                                                                                           "ping",
                                                                                                           PingSeqNum(wt_round_pings[i]),
                                                                                                           PingPlaceholder(wt_round_pings[i]))]
                                      /\ IF PingReached(wt_round_pings[i]) /\ reached_pings_collection[i] = NoMessage
                                            THEN /\ reached_pings_collection' = [reached_pings_collection EXCEPT ![i] = wt_round_pings[i]]
                                            ELSE /\ TRUE
                                                 /\ UNCHANGED reached_pings_collection
                                 /\ UNCHANGED <<wt_state, sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered>>
                              \/ /\    WTAllReached(reached_pings_collection)
                                    /\ AllRoundPingsPresent(wt_round_pings)
                                    /\ AllRoundSARRepliesPresent(sar_ack_i)
                                    /\ RoundPingsSatisfyMinimumPongDistance(
                                         wt_round_pings,
                                         most_work_bitcoin_block_height)
                                 /\ reached_collection_delivered' = [i \in Peers |-> TRUE]
                                 /\ wt_state' = "CollectingSignatures"
                                 /\ UNCHANGED <<sar_pending_ack_request, sar_ack_i, wt_round_pings, wt_last_accepted_ping, pong_i, reached_pings_collection, wt_accepted_ping, wt_accepted_ping_height>>
                              \/ /\    AllRoundPingsPresent(wt_round_pings)
                                    /\ AllRoundSARRepliesPresent(sar_ack_i)
                                    /\ ~WTAllReached(reached_pings_collection)
                                    /\ RoundPingsSatisfyMinimumPongDistance(
                                         wt_round_pings,
                                         most_work_bitcoin_block_height)
                                 /\ pong_i' =       [i \in Peers |->
                                              PongMsgFor(
                                                  session_id,
                                                  tx_id,
                                                  i,
                                                  most_work_bitcoin_block_height,
                                                  wt_round_pings,
                                                  sar_ack_i[i])]
                                 /\ wt_round_pings' = [i \in Peers |-> NoMessage]
                                 /\ sar_ack_i' = [i \in Peers |-> NoMessage]
                                 /\ wt_state' = "CollectingPings"
                                 /\ UNCHANGED <<sar_pending_ack_request, wt_last_accepted_ping, reached_collection_delivered, reached_pings_collection, wt_accepted_ping, wt_accepted_ping_height>>
                           /\ pc' = [pc EXCEPT ![WT_ID] = "CollectPings"]
                      ELSE /\ pc' = [pc EXCEPT ![WT_ID] = "CollectSignatures"]
                           /\ UNCHANGED << wt_state, sar_pending_ack_request, 
                                           sar_ack_i, wt_round_pings, 
                                           wt_last_accepted_ping, pong_i, 
                                           reached_collection_delivered, 
                                           reached_pings_collection, 
                                           wt_accepted_ping, 
                                           wt_accepted_ping_height >>
                /\ UNCHANGED << mystery_i, used_sessions, 
                                completed_withdrawals, session_id, tx_id, 
                                current_placeholder_i, placeholder_owner, 
                                placeholder_kind, psbt_i, hydrated_psbt_i, 
                                signed_psbt_i, signing_ticket_i, 
                                local_psbt_reviewed_i, 
                                pending_txid_challenge_i, 
                                accepted_txid_challenge_i, accepted_txid_ack_i, 
                                accepted_txid_ack_height_i, 
                                pending_duress_challenge_i, 
                                accepted_duress_challenge_i, 
                                accepted_duress_ack_i, 
                                accepted_duress_ack_height_i, 
                                current_ping_from_recurring_check_i, 
                                peer_state, wt_session_view, 
                                peer_tx_approval_collection, wt_tx_approval, 
                                approval_outbox, wt_bundle_inbox, 
                                approval_collection_delivered, payload_kind_i, 
                                duress_latched_i, duress_checks_i, 
                                approval_bundle_outbox, 
                                approvals_bundle_accepted, commit_outbox, 
                                initiator_commit_acked, initiator_commit_inbox, 
                                peer_tx_commit_collection, 
                                commit_collection_delivered, 
                                saved_expected_sar_ack, 
                                sar_seen_placeholder_ids_i, sar_escalated_i, 
                                peer_reviewed_ping_history_i, counter_i, 
                                ping_seq_num_i, reached_mystery_flag_i, 
                                reached_boomlets_collection_i, 
                                signed_psbt_outbox, wt_signed_psbt_collection, 
                                broadcast_record, wt_accepted_approval, 
                                wt_accepted_approval_height, 
                                peer_accepted_wt_bundle, 
                                peer_accepted_wt_bundle_height, 
                                peer_accepted_initiator_commit, 
                                peer_accepted_initiator_commit_height, 
                                wt_accepted_commit, wt_accepted_commit_height, 
                                peer_accepted_pong, peer_accepted_pong_height, 
                                peer_accepted_sar_ack, 
                                peer_accepted_sar_ack_expected, 
                                peer_accepted_sar_ack_height, hardware_lost, 
                                fallback_activated, niso_i_event_block_height, 
                                most_work_bitcoin_block_height, 
                                last_seen_block_i >>

CollectSignatures == /\ pc[WT_ID] = "CollectSignatures"
                     /\ IF wt_state = "CollectingSignatures"
                           THEN /\ \/ /\ \E i \in {p \in Peers :
                                                       /\ signed_psbt_outbox[p] # NoMessage
                                                       /\ wt_signed_psbt_collection[p] = NoMessage
                                                       /\ SignedPsbtWellFormed(signed_psbt_outbox[p])
                                                       /\ ValidSig(signed_psbt_outbox[p], p)
                                                       /\ signed_psbt_outbox[p].sid = session_id
                                                       /\ signed_psbt_outbox[p].txid = tx_id
                                                       /\ SignedPsbtTicket(signed_psbt_outbox[p]) = signing_ticket_i[p]
                                                       /\ SameTxId(signed_psbt_outbox[p].psbt, tx_id)}:
                                           /\ wt_signed_psbt_collection' = [wt_signed_psbt_collection EXCEPT ![i] = signed_psbt_outbox[i]]
                                           /\ signed_psbt_outbox' = [signed_psbt_outbox EXCEPT ![i] = NoMessage]
                                      /\ UNCHANGED <<wt_state, broadcast_record>>
                                   \/ /\    AllSignedPsbtsPresent(wt_signed_psbt_collection)
                                         /\ \A i \in Peers :
                                              SignedPsbtTicket(wt_signed_psbt_collection[i]) = signing_ticket_i[i]
                                      /\ broadcast_record' =                 BroadcastMsgFor(
                                                             session_id,
                                                             tx_id,
                                                             SignedPsbtTicket(wt_signed_psbt_collection[INITIATOR]))
                                      /\ wt_state' = "Broadcasted"
                                      /\ UNCHANGED <<signed_psbt_outbox, wt_signed_psbt_collection>>
                                /\ pc' = [pc EXCEPT ![WT_ID] = "CollectSignatures"]
                           ELSE /\ pc' = [pc EXCEPT ![WT_ID] = "ResetAfterBroadcast"]
                                /\ UNCHANGED << wt_state, signed_psbt_outbox, 
                                                wt_signed_psbt_collection, 
                                                broadcast_record >>
                     /\ UNCHANGED << mystery_i, used_sessions, 
                                     completed_withdrawals, session_id, tx_id, 
                                     current_placeholder_i, placeholder_owner, 
                                     placeholder_kind, psbt_i, hydrated_psbt_i, 
                                     signed_psbt_i, signing_ticket_i, 
                                     local_psbt_reviewed_i, 
                                     pending_txid_challenge_i, 
                                     accepted_txid_challenge_i, 
                                     accepted_txid_ack_i, 
                                     accepted_txid_ack_height_i, 
                                     pending_duress_challenge_i, 
                                     accepted_duress_challenge_i, 
                                     accepted_duress_ack_i, 
                                     accepted_duress_ack_height_i, 
                                     current_ping_from_recurring_check_i, 
                                     peer_state, wt_session_view, 
                                     peer_tx_approval_collection, 
                                     wt_tx_approval, approval_outbox, 
                                     wt_bundle_inbox, 
                                     approval_collection_delivered, 
                                     payload_kind_i, duress_latched_i, 
                                     duress_checks_i, approval_bundle_outbox, 
                                     approvals_bundle_accepted, commit_outbox, 
                                     initiator_commit_acked, 
                                     initiator_commit_inbox, 
                                     peer_tx_commit_collection, 
                                     commit_collection_delivered, 
                                     saved_expected_sar_ack, 
                                     sar_pending_ack_request, sar_ack_i, 
                                     sar_seen_placeholder_ids_i, 
                                     sar_escalated_i, wt_round_pings, 
                                     wt_last_accepted_ping, 
                                     peer_reviewed_ping_history_i, pong_i, 
                                     reached_collection_delivered, 
                                     reached_pings_collection, counter_i, 
                                     ping_seq_num_i, reached_mystery_flag_i, 
                                     reached_boomlets_collection_i, 
                                     wt_accepted_approval, 
                                     wt_accepted_approval_height, 
                                     peer_accepted_wt_bundle, 
                                     peer_accepted_wt_bundle_height, 
                                     peer_accepted_initiator_commit, 
                                     peer_accepted_initiator_commit_height, 
                                     wt_accepted_commit, 
                                     wt_accepted_commit_height, 
                                     wt_accepted_ping, wt_accepted_ping_height, 
                                     peer_accepted_pong, 
                                     peer_accepted_pong_height, 
                                     peer_accepted_sar_ack, 
                                     peer_accepted_sar_ack_expected, 
                                     peer_accepted_sar_ack_height, 
                                     hardware_lost, fallback_activated, 
                                     niso_i_event_block_height, 
                                     most_work_bitcoin_block_height, 
                                     last_seen_block_i >>

ResetAfterBroadcast == /\ pc[WT_ID] = "ResetAfterBroadcast"
                       /\    wt_state = "Broadcasted"
                          /\ \A i \in Peers : peer_state[i] = "AwaitReset"
                       /\ used_sessions' = (used_sessions \cup {session_id})
                       /\ completed_withdrawals' = completed_withdrawals + 1
                       /\ session_id' = NoSession
                       /\ tx_id' = NoTx
                       /\ wt_session_view' = NoMessage
                       /\ pending_txid_challenge_i' = [i \in Peers |-> NoMessage]
                       /\ accepted_txid_challenge_i' = [i \in Peers |-> NoMessage]
                       /\ accepted_txid_ack_i' = [i \in Peers |-> NoMessage]
                       /\ accepted_txid_ack_height_i' = [i \in Peers |-> LowestBlock]
                       /\ pending_duress_challenge_i' = [i \in Peers |-> NoMessage]
                       /\ accepted_duress_challenge_i' = [i \in Peers |-> NoMessage]
                       /\ accepted_duress_ack_i' = [i \in Peers |-> NoMessage]
                       /\ accepted_duress_ack_height_i' = [i \in Peers |-> LowestBlock]
                       /\ current_ping_from_recurring_check_i' = [i \in Peers |-> FALSE]
                       /\ peer_tx_approval_collection' = [i \in Peers |-> NoMessage]
                       /\ wt_tx_approval' = NoMessage
                       /\ peer_accepted_initiator_commit' = [i \in Peers |-> NoMessage]
                       /\ peer_accepted_initiator_commit_height' = [i \in Peers |-> LowestBlock]
                       /\ approval_outbox' = [i \in Peers |-> NoMessage]
                       /\ wt_bundle_inbox' = [i \in Peers |-> NoMessage]
                       /\ approval_collection_delivered' = [i \in Peers |-> FALSE]
                       /\ approval_bundle_outbox' = [i \in Peers |-> NoMessage]
                       /\ approvals_bundle_accepted' = [i \in Peers |-> FALSE]
                       /\ commit_outbox' = [i \in Peers |-> NoMessage]
                       /\ initiator_commit_acked' = [i \in Peers |-> FALSE]
                       /\ initiator_commit_inbox' = [i \in Peers |-> NoMessage]
                       /\ peer_tx_commit_collection' = [i \in Peers |-> NoMessage]
                       /\ commit_collection_delivered' = [i \in Peers |-> FALSE]
                       /\ saved_expected_sar_ack' = [i \in Peers |-> NoMessage]
                       /\ sar_pending_ack_request' = [i \in Peers |-> NoMessage]
                       /\ sar_ack_i' = [i \in Peers |-> NoMessage]
                       /\ sar_escalated_i' = [i \in Peers |-> FALSE]
                       /\ wt_round_pings' = [i \in Peers |-> NoMessage]
                       /\ wt_last_accepted_ping' = [i \in Peers |-> NoMessage]
                       /\ pong_i' = [i \in Peers |-> NoMessage]
                       /\ reached_collection_delivered' = [i \in Peers |-> FALSE]
                       /\ reached_pings_collection' = [i \in Peers |-> NoMessage]
                       /\ signed_psbt_outbox' = [i \in Peers |-> NoMessage]
                       /\ wt_signed_psbt_collection' = [i \in Peers |-> NoMessage]
                       /\ broadcast_record' = NoMessage
                       /\ hardware_lost' = {}
                       /\ fallback_activated' = [i \in Peers |-> FALSE]
                       /\ wt_state' = "AwaitingInitiatorApproval"
                       /\ pc' = [pc EXCEPT ![WT_ID] = "WatchtowerSessionLoop"]
                       /\ UNCHANGED << mystery_i, current_placeholder_i, 
                                       placeholder_owner, placeholder_kind, 
                                       psbt_i, hydrated_psbt_i, signed_psbt_i, 
                                       signing_ticket_i, local_psbt_reviewed_i, 
                                       peer_state, payload_kind_i, 
                                       duress_latched_i, duress_checks_i, 
                                       sar_seen_placeholder_ids_i, 
                                       peer_reviewed_ping_history_i, counter_i, 
                                       ping_seq_num_i, reached_mystery_flag_i, 
                                       reached_boomlets_collection_i, 
                                       wt_accepted_approval, 
                                       wt_accepted_approval_height, 
                                       peer_accepted_wt_bundle, 
                                       peer_accepted_wt_bundle_height, 
                                       wt_accepted_commit, 
                                       wt_accepted_commit_height, 
                                       wt_accepted_ping, 
                                       wt_accepted_ping_height, 
                                       peer_accepted_pong, 
                                       peer_accepted_pong_height, 
                                       peer_accepted_sar_ack, 
                                       peer_accepted_sar_ack_expected, 
                                       peer_accepted_sar_ack_height, 
                                       niso_i_event_block_height, 
                                       most_work_bitcoin_block_height, 
                                       last_seen_block_i >>

Watchtower == WatchtowerSessionLoop \/ AwaitInitiatorApproval
                 \/ CollectPeerApprovals \/ CollectCommitments
                 \/ CollectPings \/ CollectSignatures
                 \/ ResetAfterBroadcast

AckLoop == /\ pc[SAR_ID] = "AckLoop"
           /\ \E i \in {p \in Peers :
                            /\ sar_pending_ack_request[p] # NoMessage
                            /\ SARAckWellFormed(sar_pending_ack_request[p])
                            /\ sar_pending_ack_request[p].placeholder \notin sar_seen_placeholder_ids_i[p]}:
                /\ sar_seen_placeholder_ids_i' = [sar_seen_placeholder_ids_i EXCEPT ![i] = sar_seen_placeholder_ids_i[i] \cup {sar_pending_ack_request[i].placeholder}]
                /\ sar_ack_i' = [sar_ack_i EXCEPT ![i] = sar_pending_ack_request[i]]
                /\ IF placeholder_kind[sar_pending_ack_request[i].placeholder] = "doxing_key"
                      THEN /\ sar_escalated_i' = [sar_escalated_i EXCEPT ![i] = TRUE]
                      ELSE /\ TRUE
                           /\ UNCHANGED sar_escalated_i
                /\ sar_pending_ack_request' = [sar_pending_ack_request EXCEPT ![i] = NoMessage]
           /\ pc' = [pc EXCEPT ![SAR_ID] = "AckLoop"]
           /\ UNCHANGED << mystery_i, used_sessions, completed_withdrawals, 
                           session_id, tx_id, current_placeholder_i, 
                           placeholder_owner, placeholder_kind, psbt_i, 
                           hydrated_psbt_i, signed_psbt_i, signing_ticket_i, 
                           local_psbt_reviewed_i, pending_txid_challenge_i, 
                           accepted_txid_challenge_i, accepted_txid_ack_i, 
                           accepted_txid_ack_height_i, 
                           pending_duress_challenge_i, 
                           accepted_duress_challenge_i, accepted_duress_ack_i, 
                           accepted_duress_ack_height_i, 
                           current_ping_from_recurring_check_i, peer_state, 
                           wt_state, wt_session_view, 
                           peer_tx_approval_collection, wt_tx_approval, 
                           approval_outbox, wt_bundle_inbox, 
                           approval_collection_delivered, payload_kind_i, 
                           duress_latched_i, duress_checks_i, 
                           approval_bundle_outbox, approvals_bundle_accepted, 
                           commit_outbox, initiator_commit_acked, 
                           initiator_commit_inbox, peer_tx_commit_collection, 
                           commit_collection_delivered, saved_expected_sar_ack, 
                           wt_round_pings, wt_last_accepted_ping, 
                           peer_reviewed_ping_history_i, pong_i, 
                           reached_collection_delivered, 
                           reached_pings_collection, counter_i, ping_seq_num_i, 
                           reached_mystery_flag_i, 
                           reached_boomlets_collection_i, signed_psbt_outbox, 
                           wt_signed_psbt_collection, broadcast_record, 
                           wt_accepted_approval, wt_accepted_approval_height, 
                           peer_accepted_wt_bundle, 
                           peer_accepted_wt_bundle_height, 
                           peer_accepted_initiator_commit, 
                           peer_accepted_initiator_commit_height, 
                           wt_accepted_commit, wt_accepted_commit_height, 
                           wt_accepted_ping, wt_accepted_ping_height, 
                           peer_accepted_pong, peer_accepted_pong_height, 
                           peer_accepted_sar_ack, 
                           peer_accepted_sar_ack_expected, 
                           peer_accepted_sar_ack_height, hardware_lost, 
                           fallback_activated, niso_i_event_block_height, 
                           most_work_bitcoin_block_height, last_seen_block_i >>

SAR == AckLoop

FallbackLoop == /\ pc["FALLBACK"] = "FallbackLoop"
                /\ \/ /\ \E i \in {p \in Peers :
                                       /\ p \notin hardware_lost
                                       /\ peer_state[p] \notin {"Signed", "AwaitReset", "Fallback"}}:
                           hardware_lost' = (hardware_lost \cup {i})
                      /\ UNCHANGED <<peer_state, fallback_activated>>
                   \/ /\ \E i \in {p \in Peers :
                                       /\ ~fallback_activated[p]
                                       /\ peer_state[p] \notin {"Signed", "AwaitReset", "Fallback"}
                                       /\ \A j \in Peers : peer_state[j] # "Signed" /\ peer_state[j] # "AwaitReset"
                                       /\ (p \in hardware_lost \/ most_work_bitcoin_block_height >= Milestone1)}:
                           /\ fallback_activated' = [fallback_activated EXCEPT ![i] = TRUE]
                           /\ peer_state' = [peer_state EXCEPT ![i] = "Fallback"]
                      /\ UNCHANGED hardware_lost
                /\ pc' = [pc EXCEPT !["FALLBACK"] = "FallbackLoop"]
                /\ UNCHANGED << mystery_i, used_sessions, 
                                completed_withdrawals, session_id, tx_id, 
                                current_placeholder_i, placeholder_owner, 
                                placeholder_kind, psbt_i, hydrated_psbt_i, 
                                signed_psbt_i, signing_ticket_i, 
                                local_psbt_reviewed_i, 
                                pending_txid_challenge_i, 
                                accepted_txid_challenge_i, accepted_txid_ack_i, 
                                accepted_txid_ack_height_i, 
                                pending_duress_challenge_i, 
                                accepted_duress_challenge_i, 
                                accepted_duress_ack_i, 
                                accepted_duress_ack_height_i, 
                                current_ping_from_recurring_check_i, wt_state, 
                                wt_session_view, peer_tx_approval_collection, 
                                wt_tx_approval, approval_outbox, 
                                wt_bundle_inbox, approval_collection_delivered, 
                                payload_kind_i, duress_latched_i, 
                                duress_checks_i, approval_bundle_outbox, 
                                approvals_bundle_accepted, commit_outbox, 
                                initiator_commit_acked, initiator_commit_inbox, 
                                peer_tx_commit_collection, 
                                commit_collection_delivered, 
                                saved_expected_sar_ack, 
                                sar_pending_ack_request, sar_ack_i, 
                                sar_seen_placeholder_ids_i, sar_escalated_i, 
                                wt_round_pings, wt_last_accepted_ping, 
                                peer_reviewed_ping_history_i, pong_i, 
                                reached_collection_delivered, 
                                reached_pings_collection, counter_i, 
                                ping_seq_num_i, reached_mystery_flag_i, 
                                reached_boomlets_collection_i, 
                                signed_psbt_outbox, wt_signed_psbt_collection, 
                                broadcast_record, wt_accepted_approval, 
                                wt_accepted_approval_height, 
                                peer_accepted_wt_bundle, 
                                peer_accepted_wt_bundle_height, 
                                peer_accepted_initiator_commit, 
                                peer_accepted_initiator_commit_height, 
                                wt_accepted_commit, wt_accepted_commit_height, 
                                wt_accepted_ping, wt_accepted_ping_height, 
                                peer_accepted_pong, peer_accepted_pong_height, 
                                peer_accepted_sar_ack, 
                                peer_accepted_sar_ack_expected, 
                                peer_accepted_sar_ack_height, 
                                niso_i_event_block_height, 
                                most_work_bitcoin_block_height, 
                                last_seen_block_i >>

FallbackMonitor == FallbackLoop

AdvanceHeights == /\ pc["ENV"] = "AdvanceHeights"
                  /\ \/ /\ \E i \in {p \in Peers : HigherBlocks(niso_i_event_block_height[p]) # {}}:
                             niso_i_event_block_height' = [niso_i_event_block_height EXCEPT ![i] = LeastHigher(niso_i_event_block_height[i])]
                        /\ UNCHANGED most_work_bitcoin_block_height
                     \/ /\ HigherBlocks(most_work_bitcoin_block_height) # {}
                        /\ most_work_bitcoin_block_height' = LeastHigher(most_work_bitcoin_block_height)
                        /\ UNCHANGED niso_i_event_block_height
                  /\ pc' = [pc EXCEPT !["ENV"] = "AdvanceHeights"]
                  /\ UNCHANGED << mystery_i, used_sessions, 
                                  completed_withdrawals, session_id, tx_id, 
                                  current_placeholder_i, placeholder_owner, 
                                  placeholder_kind, psbt_i, hydrated_psbt_i, 
                                  signed_psbt_i, signing_ticket_i, 
                                  local_psbt_reviewed_i, 
                                  pending_txid_challenge_i, 
                                  accepted_txid_challenge_i, 
                                  accepted_txid_ack_i, 
                                  accepted_txid_ack_height_i, 
                                  pending_duress_challenge_i, 
                                  accepted_duress_challenge_i, 
                                  accepted_duress_ack_i, 
                                  accepted_duress_ack_height_i, 
                                  current_ping_from_recurring_check_i, 
                                  peer_state, wt_state, wt_session_view, 
                                  peer_tx_approval_collection, wt_tx_approval, 
                                  approval_outbox, wt_bundle_inbox, 
                                  approval_collection_delivered, 
                                  payload_kind_i, duress_latched_i, 
                                  duress_checks_i, approval_bundle_outbox, 
                                  approvals_bundle_accepted, commit_outbox, 
                                  initiator_commit_acked, 
                                  initiator_commit_inbox, 
                                  peer_tx_commit_collection, 
                                  commit_collection_delivered, 
                                  saved_expected_sar_ack, 
                                  sar_pending_ack_request, sar_ack_i, 
                                  sar_seen_placeholder_ids_i, sar_escalated_i, 
                                  wt_round_pings, wt_last_accepted_ping, 
                                  peer_reviewed_ping_history_i, pong_i, 
                                  reached_collection_delivered, 
                                  reached_pings_collection, counter_i, 
                                  ping_seq_num_i, reached_mystery_flag_i, 
                                  reached_boomlets_collection_i, 
                                  signed_psbt_outbox, 
                                  wt_signed_psbt_collection, broadcast_record, 
                                  wt_accepted_approval, 
                                  wt_accepted_approval_height, 
                                  peer_accepted_wt_bundle, 
                                  peer_accepted_wt_bundle_height, 
                                  peer_accepted_initiator_commit, 
                                  peer_accepted_initiator_commit_height, 
                                  wt_accepted_commit, 
                                  wt_accepted_commit_height, wt_accepted_ping, 
                                  wt_accepted_ping_height, peer_accepted_pong, 
                                  peer_accepted_pong_height, 
                                  peer_accepted_sar_ack, 
                                  peer_accepted_sar_ack_expected, 
                                  peer_accepted_sar_ack_height, hardware_lost, 
                                  fallback_activated, last_seen_block_i >>

Environment == AdvanceHeights

Next == Watchtower \/ SAR \/ FallbackMonitor \/ Environment
           \/ (\E self \in Peers: Peer(self))

Spec == Init /\ [][Next]_vars

\* END TRANSLATION

(***************************************************************************)
(* State predicates and safety properties.                                 *)
(***************************************************************************)

AllReady ==
    \A i \in Peers : peer_state[i] \in {"ReadyToSign", "Signed", "AwaitReset"}

AllLatestPlaceholdersSettled ==
    \A i \in Peers :
        /\ saved_expected_sar_ack[i] # NoMessage
        /\ AckMatchesExpected(sar_ack_i[i], saved_expected_sar_ack[i])

SignedPeers == {i \in Peers : peer_state[i] = "Signed"}

ReadyOrSignedPeers == {i \in Peers : peer_state[i] \in {"ReadyToSign", "Signed", "AwaitReset"}}

PlaceholderInstanceAuthenticForPeer(i, pid) ==
    /\ pid \in PlaceholderIds
    /\ placeholder_owner[pid] = i
    /\ placeholder_kind[pid] \in {"padding", "doxing_key"}

AckAuthenticForPeer(i, ack0, expected0) ==
    /\ ack0 # NoMessage
    /\ expected0 # NoMessage
    /\ ValidSig(ack0, SAR_ID)
    /\ AckMatchesExpected(ack0, expected0)
    /\ PlaceholderInstanceAuthenticForPeer(i, ack0.placeholder)

AcceptedTxIdTranscriptForPeer(i) ==
    /\ accepted_txid_challenge_i[i] # NoMessage
    /\ accepted_txid_ack_i[i] # NoMessage
    /\ TxIdChallengeWellFormed(accepted_txid_challenge_i[i])
    /\ TxIdAckMatchesChallenge(
        accepted_txid_ack_i[i],
        accepted_txid_challenge_i[i])

AcceptedInitialDuressTranscriptForPeer(i) ==
    /\ accepted_duress_challenge_i[i] # NoMessage
    /\ accepted_duress_ack_i[i] # NoMessage
    /\ DuressChallengeWellFormed(accepted_duress_challenge_i[i])
    /\ accepted_duress_challenge_i[i].stage = "initial"
    /\ accepted_duress_challenge_i[i].seq = 0
    /\ DuressAckMatchesChallenge(
        accepted_duress_ack_i[i],
        accepted_duress_challenge_i[i])

AcceptedRecurringDuressTranscriptForPeer(i, seq0) ==
    /\ accepted_duress_challenge_i[i] # NoMessage
    /\ accepted_duress_ack_i[i] # NoMessage
    /\ DuressChallengeWellFormed(accepted_duress_challenge_i[i])
    /\ accepted_duress_challenge_i[i].stage = "ping"
    /\ accepted_duress_challenge_i[i].seq = seq0
    /\ DuressAckMatchesChallenge(
        accepted_duress_ack_i[i],
        accepted_duress_challenge_i[i])

InitialInternalOutcome(i, consentMatch) ==
    LET ch == pending_duress_challenge_i[i]
        ack == DuressAckMsgFor(
            ch.sid,
            ch.txid,
            i,
            ch.stage,
            ch.seq,
            ch.nonce,
            consentMatch)
    IN [ public      |->
            [ peer_state |-> IF i = INITIATOR THEN "AwaitingCommitCollection" ELSE "AwaitingWTInitiatorCommit",
              emits      |-> IF i = INITIATOR THEN "commit" ELSE "approvals_bundle",
              sid        |-> ch.sid,
              txid       |-> ch.txid,
              ack_stage  |-> ack.stage,
              ack_seq    |-> ack.seq,
              ack_nonce  |-> ack.nonce,
              counter    |-> counter_i[i],
              pingseq    |-> ping_seq_num_i[i],
              reached    |-> reached_mystery_flag_i[i] ],
         hidden_kind |-> IF ack.consent_match THEN "padding" ELSE "doxing_key" ]

DiggingInternalOutcome(i, consentMatch) ==
    LET ch == pending_duress_challenge_i[i]
        nextCounter ==
            NextCounter(
                counter_i[i],
                last_seen_block_i[i],
                niso_i_event_block_height[i],
                pong_i[i],
                peer_reviewed_ping_history_i[i],
                i,
                session_id,
                tx_id,
                reached_boomlets_collection_i[i])
        nextReached ==
            NextReached(
                reached_mystery_flag_i[i],
                counter_i[i],
                last_seen_block_i[i],
                niso_i_event_block_height[i],
                mystery_i[i],
                pong_i[i],
                peer_reviewed_ping_history_i[i],
                i,
                session_id,
                tx_id,
                reached_boomlets_collection_i[i])
        nextLastSeen ==
            NextLastSeen(
                last_seen_block_i[i],
                niso_i_event_block_height[i])
        signal == ~consentMatch
    IN [ public        |->
            [ peer_state |-> "DiggingGame",
              emits      |-> "ping",
              sid        |-> ch.sid,
              txid       |-> ch.txid,
              ack_stage  |-> ch.stage,
              ack_seq    |-> ch.seq,
              ack_nonce  |-> ch.nonce,
              counter    |-> nextCounter,
              pingseq    |-> ch.seq,
              reached    |-> nextReached,
              last_seen  |-> nextLastSeen,
              seen       |-> reached_boomlets_collection_i[i] \cup ReachedPeersAdvertised(i, pong_i[i]),
              did_check  |-> TRUE ],
         hidden_kind  |->
            DiggingReplyKind(
                duress_latched_i[i],
                payload_kind_i[i],
                TRUE,
                signal),
         hidden_latch |->
            DiggingReplyLatched(
                duress_latched_i[i],
                TRUE,
                signal) ]

ObservableEnvelopeConsistentUnderPrivateDuress ==
    /\ \A i \in Peers :
         /\ peer_state[i] = "AwaitingInitialDuressAck"
         /\ pending_duress_challenge_i[i] # NoMessage
         /\ pending_duress_challenge_i[i].stage = "initial"
         => /\ InitialInternalOutcome(i, FALSE).hidden_kind # InitialInternalOutcome(i, TRUE).hidden_kind
            /\ InitialInternalOutcome(i, FALSE).public = InitialInternalOutcome(i, TRUE).public
    /\ \A i \in Peers :
         /\ peer_state[i] = "AwaitingRecurringDuressAck"
         /\ pending_duress_challenge_i[i] # NoMessage
         /\ pending_duress_challenge_i[i].stage = "ping"
         /\ pong_i[i] # NoMessage
         => /\ DiggingInternalOutcome(i, FALSE).public =
               DiggingInternalOutcome(i, TRUE).public
            /\ (~duress_latched_i[i] /\ payload_kind_i[i] = "padding") =>
               DiggingInternalOutcome(i, FALSE).hidden_kind #
               DiggingInternalOutcome(i, TRUE).hidden_kind

ClassifiedDeadlockState ==
    \/ /\ \A i \in Peers : peer_state[i] = "Fallback"
       /\ session_id = NoSession
    \/ /\ session_id = NoSession
       /\ used_sessions = Sessions
       /\ \A i \in Peers : peer_state[i] = "ActiveReady"

TypeOK ==
    /\ mystery_i \in [Peers -> Nat]
    /\ used_sessions \subseteq Sessions
    /\ completed_withdrawals \in Nat
    /\ session_id \in SessionIds
    /\ tx_id \in TxDomain
    /\ current_placeholder_i \in [Peers -> PlaceholderDomain]
    /\ placeholder_owner \in [PlaceholderIds -> Peers \cup {NoSigner}]
    /\ placeholder_kind \in [PlaceholderIds -> PlaceholderKinds]
    /\ peer_state \in [Peers -> PeerStates]
    /\ wt_state \in WTStates
    /\ hardware_lost \subseteq Peers
    /\ fallback_activated \in [Peers -> BOOLEAN]
    /\ psbt_i \in [Peers -> PSBTs \cup {NoPsbt}]
    /\ hydrated_psbt_i \in [Peers -> PSBTs \cup {NoPsbt}]
    /\ signed_psbt_i \in [Peers -> PSBTs \cup {NoPsbt}]
    /\ local_psbt_reviewed_i \in [Peers -> BOOLEAN]
    /\ current_ping_from_recurring_check_i \in [Peers -> BOOLEAN]
    /\ payload_kind_i \in [Peers -> {"none", "padding", "doxing_key"}]
    /\ duress_latched_i \in [Peers -> BOOLEAN]
    /\ duress_checks_i \in [Peers -> Nat]
    /\ approval_collection_delivered \in [Peers -> BOOLEAN]
    /\ approvals_bundle_accepted \in [Peers -> BOOLEAN]
    /\ initiator_commit_acked \in [Peers -> BOOLEAN]
    /\ commit_collection_delivered \in [Peers -> BOOLEAN]
    /\ reached_collection_delivered \in [Peers -> BOOLEAN]
    /\ counter_i \in [Peers -> Nat]
    /\ ping_seq_num_i \in [Peers -> Nat]
    /\ reached_mystery_flag_i \in [Peers -> BOOLEAN]
    /\ reached_boomlets_collection_i \in [Peers -> SUBSET Peers]
    /\ sar_seen_placeholder_ids_i \in [Peers -> SUBSET PlaceholderIds]
    /\ accepted_txid_ack_height_i \in [Peers -> Nat]
    /\ accepted_duress_ack_height_i \in [Peers -> Nat]
    /\ wt_accepted_approval_height \in [Peers -> Nat]
    /\ peer_accepted_wt_bundle_height \in [Peers -> Nat]
    /\ wt_accepted_commit_height \in [Peers -> Nat]
    /\ wt_accepted_ping_height \in [Peers -> Nat]
    /\ peer_accepted_pong_height \in [Peers -> Nat]
    /\ peer_accepted_sar_ack_height \in [Peers -> Nat]
    /\ niso_i_event_block_height \in [Peers -> Nat]
    /\ last_seen_block_i \in [Peers -> Nat]
    /\ most_work_bitcoin_block_height \in Nat
    /\ WTViewWellFormed(wt_session_view)
    /\ \A i \in Peers : ApprovalWellFormed(peer_tx_approval_collection[i])
    /\ WTApprovalWellFormed(wt_tx_approval)
    /\ \A i \in Peers :
         ApprovalWellFormed(approval_outbox[i]) \/ InitiatorSubmissionWellFormed(approval_outbox[i])
    /\ \A i \in Peers : WTBundleWellFormed(wt_bundle_inbox[i])
    /\ \A i \in Peers : BundleWellFormed(approval_bundle_outbox[i])
    /\ \A i \in Peers : CommitWellFormed(commit_outbox[i])
    /\ \A i \in Peers : CommitWellFormed(initiator_commit_inbox[i])
    /\ \A i \in Peers : CommitWellFormed(peer_tx_commit_collection[i])
    /\ \A i \in Peers : TxIdChallengeWellFormed(pending_txid_challenge_i[i])
    /\ \A i \in Peers : TxIdChallengeWellFormed(accepted_txid_challenge_i[i])
    /\ \A i \in Peers : TxIdAckWellFormed(accepted_txid_ack_i[i])
    /\ \A i \in Peers : DuressChallengeWellFormed(pending_duress_challenge_i[i])
    /\ \A i \in Peers : DuressChallengeWellFormed(accepted_duress_challenge_i[i])
    /\ \A i \in Peers : DuressAckWellFormed(accepted_duress_ack_i[i])
    /\ \A i \in Peers : SARAckWellFormed(saved_expected_sar_ack[i])
    /\ \A i \in Peers : SARAckWellFormed(sar_pending_ack_request[i])
    /\ \A i \in Peers : SARAckWellFormed(sar_ack_i[i])
    /\ \A i \in Peers : SigningTicketWellFormed(signing_ticket_i[i])
    /\ \A i \in Peers : PingWellFormed(wt_round_pings[i])
    /\ \A i \in Peers : PingWellFormed(wt_last_accepted_ping[i])
    /\ \A i \in Peers : \A j \in Peers : PingWellFormed(peer_reviewed_ping_history_i[i][j])
    /\ \A i \in Peers : PongWellFormed(pong_i[i])
    /\ \A i \in Peers : PingWellFormed(reached_pings_collection[i])
    /\ \A i \in Peers : SignedPsbtWellFormed(signed_psbt_outbox[i])
    /\ \A i \in Peers : SignedPsbtWellFormed(wt_signed_psbt_collection[i])
    /\ \A i \in Peers : ApprovalWellFormed(wt_accepted_approval[i])
    /\ \A i \in Peers : WTBundleWellFormed(peer_accepted_wt_bundle[i])
    /\ \A i \in Peers : CommitWellFormed(peer_accepted_initiator_commit[i])
    /\ \A i \in Peers : CommitWellFormed(wt_accepted_commit[i])
    /\ \A i \in Peers : PingWellFormed(wt_accepted_ping[i])
    /\ \A i \in Peers : PongWellFormed(peer_accepted_pong[i])
    /\ \A i \in Peers : SARAckWellFormed(peer_accepted_sar_ack[i])
    /\ \A i \in Peers : SARAckWellFormed(peer_accepted_sar_ack_expected[i])
    /\ peer_accepted_initiator_commit_height \in [Peers -> Nat]
    /\ BroadcastWellFormed(broadcast_record)
    /\ \A pid \in PlaceholderIds :
         (placeholder_owner[pid] = NoSigner) = (placeholder_kind[pid] = "unused")

CounterBounded ==
    \A i \in Peers : counter_i[i] <= mystery_i[i]

WithdrawalOnlyAfterMilestone0 ==
    /\ session_id = NoSession
       \/ niso_i_event_block_height[INITIATOR] >= Milestone0
    /\ \A i \in OtherPeers(INITIATOR) :
         peer_accepted_wt_bundle[i] # NoMessage =>
             peer_accepted_wt_bundle_height[i] >= Milestone0

InitiatorStartsTheSession ==
    session_id = NoSession
    \/ \/ /\ pending_txid_challenge_i[INITIATOR] # NoMessage
          /\ pending_txid_challenge_i[INITIATOR].peer = INITIATOR
          /\ pending_txid_challenge_i[INITIATOR].sid = session_id
          /\ pending_txid_challenge_i[INITIATOR].txid = tx_id
       \/ /\ accepted_txid_challenge_i[INITIATOR] # NoMessage
          /\ accepted_txid_challenge_i[INITIATOR].peer = INITIATOR
          /\ accepted_txid_challenge_i[INITIATOR].sid = session_id
          /\ accepted_txid_challenge_i[INITIATOR].txid = tx_id
       \/ LET initAppr ==
               IF peer_tx_approval_collection[INITIATOR] # NoMessage
               THEN peer_tx_approval_collection[INITIATOR]
               ELSE SubmissionApproval(approval_outbox[INITIATOR])
          IN /\ initAppr # NoMessage
             /\ initAppr.peer = INITIATOR
             /\ initAppr.sid = session_id
             /\ initAppr.txid = tx_id

WTSessionViewMatchesLockedSession ==
    wt_session_view = NoMessage
    \/ /\ wt_session_view.sid = session_id
       /\ wt_session_view.txid = tx_id
       /\ wt_session_view.initiator = INITIATOR

UsedSessionsNeverCurrent ==
    session_id = NoSession \/ session_id \notin used_sessions

ApprovalsBoundToLockedSession ==
    \A i \in Peers :
        /\ MsgSessionMatches(peer_tx_approval_collection[i], session_id)
        /\ MsgTxMatches(peer_tx_approval_collection[i], tx_id)
        /\ IF approval_outbox[i] = NoMessage THEN TRUE
           ELSE IF ApprovalWellFormed(approval_outbox[i]) THEN
                /\ approval_outbox[i].sid = session_id
                /\ approval_outbox[i].txid = tx_id
           ELSE /\ InitiatorSubmissionWellFormed(approval_outbox[i])
                /\ approval_outbox[i].sid = session_id
                /\ SubmissionApproval(approval_outbox[i]).sid = session_id
                /\ SubmissionApproval(approval_outbox[i]).txid = tx_id

CommitmentsBoundToLockedSession ==
    \A i \in Peers :
        /\ MsgSessionMatches(peer_tx_commit_collection[i], session_id)
        /\ MsgTxMatches(peer_tx_commit_collection[i], tx_id)
        /\ MsgSessionMatches(commit_outbox[i], session_id)
        /\ MsgTxMatches(commit_outbox[i], tx_id)

PingsBoundToLockedSession ==
    \A i \in Peers :
        /\ MsgSessionMatches(wt_round_pings[i], session_id)
        /\ MsgTxMatches(wt_round_pings[i], tx_id)
        /\ MsgSessionMatches(pong_i[i], session_id)
        /\ MsgTxMatches(pong_i[i], tx_id)
        /\ MsgSessionMatches(reached_pings_collection[i], session_id)
        /\ MsgTxMatches(reached_pings_collection[i], tx_id)

SignedPsbtsBoundToLockedSession ==
    \A i \in Peers :
        /\ MsgSessionMatches(signed_psbt_outbox[i], session_id)
        /\ MsgTxMatches(signed_psbt_outbox[i], tx_id)
        /\ MsgSessionMatches(wt_signed_psbt_collection[i], session_id)
        /\ MsgTxMatches(wt_signed_psbt_collection[i], tx_id)
    /\ MsgSessionMatches(broadcast_record, session_id)
    /\ MsgTxMatches(broadcast_record, tx_id)

HydrationMatchesLockedTx ==
    \A i \in Peers :
        /\ PsbtTxMatches(hydrated_psbt_i[i], tx_id)
        /\ PsbtTxMatches(signed_psbt_i[i], tx_id)

AcceptedEvidenceWasFresh ==
    /\ \A i \in Peers :
         wt_accepted_approval[i] # NoMessage =>
             IF i = INITIATOR
             THEN ApprovalFreshAtWitness(
                      wt_accepted_approval[i],
                      wt_accepted_approval_height[i])
             ELSE PostWTApprovalWindowValid(
                      wt_accepted_approval[i],
                      wt_tx_approval,
                      wt_accepted_approval_height[i])
    /\ \A i \in Peers :
         peer_accepted_wt_bundle[i] # NoMessage =>
             WTBundleFreshAtWitness(
                 peer_accepted_wt_bundle[i],
                 peer_accepted_wt_bundle_height[i])
    /\ \A i \in OtherPeers(INITIATOR) :
         peer_accepted_initiator_commit[i] # NoMessage =>
             CommitFreshAtWitness(
                 peer_accepted_initiator_commit[i],
                 peer_accepted_initiator_commit_height[i])
    /\ \A i \in Peers :
         wt_accepted_commit[i] # NoMessage =>
             CommitFreshAtWitness(
                 wt_accepted_commit[i],
                 wt_accepted_commit_height[i])
    /\ \A i \in Peers :
         wt_accepted_ping[i] # NoMessage =>
             PingFreshAtWitness(
                 wt_accepted_ping[i],
                 wt_accepted_ping_height[i])
    /\ \A i \in Peers :
         peer_accepted_pong[i] # NoMessage =>
             PongFreshAtWitness(
                 peer_accepted_pong[i],
                 peer_accepted_pong_height[i])
    /\ \A i \in Peers :
         peer_accepted_sar_ack[i] # NoMessage =>
             AckMatchesExpected(
                 peer_accepted_sar_ack[i],
                 peer_accepted_sar_ack_expected[i])
    /\ \A i \in Peers :
         accepted_txid_ack_i[i] # NoMessage =>
             /\ AcceptedTxIdTranscriptForPeer(i)
             /\ accepted_txid_ack_height_i[i] <= niso_i_event_block_height[i]
    /\ \A i \in Peers :
         accepted_duress_ack_i[i] # NoMessage =>
             /\ DuressAckMatchesChallenge(
                 accepted_duress_ack_i[i],
                 accepted_duress_challenge_i[i])
             /\ accepted_duress_ack_height_i[i] <= niso_i_event_block_height[i]

ApprovalsRequireAcceptedTxIdTranscript ==
    \A i \in Peers :
        approval_outbox[i] # NoMessage =>
            /\ AcceptedTxIdTranscriptForPeer(i)
            /\ accepted_txid_challenge_i[i].sid = session_id
            /\ accepted_txid_challenge_i[i].txid = tx_id

NonInitiatorTxIdPathRequiresLocalPsbtReview ==
    \A i \in OtherPeers(INITIATOR) :
        (pending_txid_challenge_i[i] # NoMessage
         \/ accepted_txid_challenge_i[i] # NoMessage
         \/ accepted_txid_ack_i[i] # NoMessage
         \/ approval_outbox[i] # NoMessage)
        => /\ local_psbt_reviewed_i[i]
           /\ peer_accepted_wt_bundle[i] # NoMessage
           /\ SameTxId(psbt_i[i], tx_id)

CommitsRequireAcceptedInitialDuressTranscript ==
    \A i \in Peers :
        commit_outbox[i] # NoMessage =>
            /\ AcceptedInitialDuressTranscriptForPeer(i)
            /\ accepted_duress_challenge_i[i].sid = session_id
            /\ accepted_duress_challenge_i[i].txid = tx_id

RecurringChecksRequireAcceptedTranscript ==
    \A i \in Peers :
        /\ current_ping_from_recurring_check_i[i]
        /\ wt_round_pings[i] # NoMessage
        => /\ AcceptedRecurringDuressTranscriptForPeer(
                i,
                PingSeqNum(wt_round_pings[i]))
           /\ accepted_duress_challenge_i[i].sid = session_id
           /\ accepted_duress_challenge_i[i].txid = tx_id

PendingSTTranscriptsBoundToCurrentSession ==
    \A i \in Peers :
        /\ MsgSessionMatches(pending_txid_challenge_i[i], session_id)
        /\ MsgTxMatches(pending_txid_challenge_i[i], tx_id)
        /\ MsgSessionMatches(pending_duress_challenge_i[i], session_id)
        /\ MsgTxMatches(pending_duress_challenge_i[i], tx_id)

NoStaleSTTranscriptAcceptance ==
    \A i \in Peers :
        /\ (accepted_txid_ack_i[i] = NoMessage
            \/ /\ AcceptedTxIdTranscriptForPeer(i)
               /\ accepted_txid_challenge_i[i].peer = i
               /\ accepted_txid_challenge_i[i].sid = session_id
               /\ accepted_txid_challenge_i[i].txid = tx_id)
        /\ (accepted_duress_ack_i[i] = NoMessage
            \/ /\ DuressAckMatchesChallenge(
                     accepted_duress_ack_i[i],
                     accepted_duress_challenge_i[i])
               /\ accepted_duress_challenge_i[i].peer = i
               /\ accepted_duress_challenge_i[i].sid = session_id
               /\ accepted_duress_challenge_i[i].txid = tx_id)

CommitRequiresUniversalApproval ==
    \A i \in Peers :
        commit_outbox[i] # NoMessage \/ peer_tx_commit_collection[i] # NoMessage =>
            AllApprovalsPresent(peer_tx_approval_collection)

NonInitiatorCommitsRequireVerifiedInitiatorCommit ==
    \A i \in OtherPeers(INITIATOR) :
        commit_outbox[i] # NoMessage \/ peer_tx_commit_collection[i] # NoMessage =>
            /\ peer_accepted_initiator_commit[i] # NoMessage
            /\ peer_accepted_initiator_commit[i] = peer_tx_commit_collection[INITIATOR]
            /\ CommitFreshAtWitness(
                peer_accepted_initiator_commit[i],
                peer_accepted_initiator_commit_height[i])

PlaceholderKindPresentFromCommitOnward ==
    \A i \in Peers :
        peer_state[i] \in {
            "InitialDuressResolved",
            "AwaitingWTInitiatorCommit",
            "AwaitingCommitCollection",
            "DiggingGame",
            "AwaitingRecurringDuressAck",
            "ReadyToSign",
            "Signed" } =>
            payload_kind_i[i] \in {"padding", "doxing_key"}

ReachedFlagsAgreeWithCounters ==
    \A i \in Peers :
        /\ reached_mystery_flag_i[i] => counter_i[i] >= mystery_i[i]
        /\ reached_pings_collection[i] # NoMessage =>
             reached_pings_collection[i].reached

ReadyRequiresHydratedTx ==
    \A i \in Peers :
        peer_state[i] \in {"ReadyToSign", "Signed", "AwaitReset"} =>
            /\ hydrated_psbt_i[i] # NoPsbt
            /\ SameTxId(hydrated_psbt_i[i], tx_id)

ReadyRequiresUniversalReach ==
    \A i \in Peers :
        peer_state[i] \in {"ReadyToSign", "Signed", "AwaitReset"} =>
            /\ WTAllReached(reached_pings_collection)
            /\ AllLatestPlaceholdersSettled

ReadyStatesRequireValidReachedCollection ==
    \A i \in Peers :
        peer_state[i] \in {"ReadyToSign", "Signed", "AwaitReset"} =>
            ReachedCollectionValidForPeer(
                i,
                reached_collection_delivered[i],
                reached_pings_collection,
                session_id,
                tx_id,
                niso_i_event_block_height[i],
                peer_reviewed_ping_history_i[i],
                reached_boomlets_collection_i[i])

ReadyRequiresAtLeastOneDuressCheck ==
    \A i \in Peers :
        peer_state[i] \in {"ReadyToSign", "Signed", "AwaitReset"} =>
            duress_checks_i[i] >= 1

NoBoomerangSignatureBeforeUniversalReady ==
    SignedPeers # {} =>
        /\ AllReady
        /\ \A i \in Peers : ~fallback_activated[i]

OneNotReadyPeerBlocksBroadcast ==
    \A i \in Peers :
        ~(peer_state[i] \in {"ReadyToSign", "Signed", "AwaitReset"}) =>
            broadcast_record = NoMessage

AcceptedPlaceholderAcksAreAuthentic ==
    /\ \A i \in Peers :
         sar_ack_i[i] # NoMessage =>
            AckAuthenticForPeer(i, sar_ack_i[i], saved_expected_sar_ack[i])
    /\ \A i \in Peers :
         pong_i[i] # NoMessage =>
            AckAuthenticForPeer(i, pong_i[i].sar_ack, saved_expected_sar_ack[i])
    /\ \A i \in Peers :
         peer_accepted_sar_ack[i] # NoMessage =>
            AckAuthenticForPeer(
                i,
                peer_accepted_sar_ack[i],
                peer_accepted_sar_ack_expected[i])

WTBreakConditionCorrect ==
    wt_state \in {"CollectingSignatures", "Broadcasted"} =>
        /\ WTAllReached(reached_pings_collection)
        /\ AllLatestPlaceholdersSettled

PostDuressNoRevert ==
    \A i \in Peers :
        duress_latched_i[i] =>
            /\ payload_kind_i[i] = "doxing_key"

PlaceholderReplaySuppressionStateSound ==
    \A i \in Peers :
        \A pid \in sar_seen_placeholder_ids_i[i] :
            PlaceholderInstanceAuthenticForPeer(i, pid)

CurrentSessionSarEscalationRequiresDuress ==
    \A i \in Peers :
        sar_escalated_i[i] =>
            \E pid \in sar_seen_placeholder_ids_i[i] :
                placeholder_kind[pid] = "doxing_key"

FallbackOnlyAfterLossOrMilestone ==
    \A i \in Peers :
        fallback_activated[i] =>
            \/ i \in hardware_lost
            \/ most_work_bitcoin_block_height >= Milestone1

FallbackSeparateFromBoomerangSigning ==
    \A i \in Peers, j \in Peers :
        ~(fallback_activated[i] /\ peer_state[j] \in {"Signed", "AwaitReset"})

NoBroadcastBeforeAllSigned ==
    broadcast_record = NoMessage
    \/ /\ AllSignedPsbtsPresent(wt_signed_psbt_collection)
       /\ \A i \in Peers :
            /\ wt_signed_psbt_collection[i].sid = session_id
            /\ wt_signed_psbt_collection[i].txid = tx_id
            /\ SignedPsbtTicket(wt_signed_psbt_collection[i]) = BroadcastTicket(broadcast_record)
            /\ SameTxId(wt_signed_psbt_collection[i].psbt, tx_id)

CurrentSessionBindingsFrozen ==
    /\ session_id = NoSession \/ tx_id # NoTx
    /\ session_id = NoSession
       \/ /\ ApprovalsBoundToLockedSession
          /\ CommitmentsBoundToLockedSession
          /\ PingsBoundToLockedSession
          /\ SignedPsbtsBoundToLockedSession
          /\ PendingSTTranscriptsBoundToCurrentSession
          /\ NoStaleSTTranscriptAcceptance
          /\ \A i \in Peers :
               /\ PsbtTxMatches(psbt_i[i], tx_id)
               /\ PsbtTxMatches(hydrated_psbt_i[i], tx_id)
               /\ PsbtTxMatches(signed_psbt_i[i], tx_id)
          /\ MsgSessionMatches(wt_tx_approval, session_id)
          /\ MsgTxMatches(wt_tx_approval, tx_id)

CurrentSessionSigningWitnessAligned ==
    session_id = NoSession
    \/ /\ \A i \in ReadyOrSignedPeers :
             /\ signing_ticket_i[i] = SigningTicketFor(session_id, tx_id)
             /\ hydrated_psbt_i[i] # NoPsbt
             /\ SameTxId(hydrated_psbt_i[i], tx_id)
       /\ \A i \in Peers :
             signed_psbt_outbox[i] # NoMessage =>
                SignedPsbtTicket(signed_psbt_outbox[i]) = SigningTicketFor(session_id, tx_id)
       /\ (broadcast_record = NoMessage
           \/ BroadcastTicket(broadcast_record) = SigningTicketFor(session_id, tx_id))

SenderFieldsMatchSlots ==
    /\ IF wt_tx_approval = NoMessage
          THEN TRUE
          ELSE wt_tx_approval.initiator = INITIATOR
    /\ \A i \in Peers :
         /\ IF peer_tx_approval_collection[i] = NoMessage
               THEN TRUE
               ELSE peer_tx_approval_collection[i].peer = i
         /\ IF wt_accepted_approval[i] = NoMessage
               THEN TRUE
               ELSE wt_accepted_approval[i].peer = i
         /\ IF wt_bundle_inbox[i] = NoMessage
               THEN TRUE
               ELSE /\ WTBundleApproval(wt_bundle_inbox[i]).peer = INITIATOR
                    /\ WTBundleWTApproval(wt_bundle_inbox[i]).initiator = INITIATOR
         /\ IF peer_accepted_wt_bundle[i] = NoMessage
               THEN TRUE
               ELSE /\ WTBundleApproval(peer_accepted_wt_bundle[i]).peer = INITIATOR
                    /\ WTBundleWTApproval(peer_accepted_wt_bundle[i]).initiator = INITIATOR
         /\ IF peer_tx_commit_collection[i] = NoMessage
               THEN TRUE
               ELSE peer_tx_commit_collection[i].peer = i
         /\ IF wt_accepted_commit[i] = NoMessage
               THEN TRUE
               ELSE wt_accepted_commit[i].peer = i
         /\ IF initiator_commit_inbox[i] = NoMessage
               THEN TRUE
               ELSE initiator_commit_inbox[i].peer = INITIATOR
         /\ IF peer_accepted_initiator_commit[i] = NoMessage
               THEN TRUE
               ELSE peer_accepted_initiator_commit[i].peer = INITIATOR
         /\ IF wt_round_pings[i] = NoMessage
               THEN TRUE
               ELSE wt_round_pings[i].peer = i
         /\ IF wt_last_accepted_ping[i] = NoMessage
               THEN TRUE
               ELSE wt_last_accepted_ping[i].peer = i
         /\ IF reached_pings_collection[i] = NoMessage
               THEN TRUE
               ELSE reached_pings_collection[i].peer = i
         /\ (IF approval_outbox[i] # NoMessage /\ ApprovalWellFormed(approval_outbox[i])
                THEN approval_outbox[i].peer = i
                ELSE TRUE)
         /\ (IF approval_outbox[i] # NoMessage /\ InitiatorSubmissionWellFormed(approval_outbox[i])
                THEN SubmissionApproval(approval_outbox[i]).peer = INITIATOR
                ELSE TRUE)
         /\ (IF commit_outbox[i] # NoMessage /\ CommitWellFormed(commit_outbox[i])
                THEN commit_outbox[i].peer = i
                ELSE TRUE)
         /\ \A j \in Peers :
                IF peer_reviewed_ping_history_i[j][i] = NoMessage
                THEN TRUE
                ELSE peer_reviewed_ping_history_i[j][i].peer = i

UnlockedStateIsClean ==
    session_id # NoSession
    \/ /\ tx_id = NoTx
       /\ wt_state = "AwaitingInitiatorApproval"
       /\ wt_session_view = NoMessage
       /\ wt_tx_approval = NoMessage
       /\ broadcast_record = NoMessage
       /\ \A i \in Peers :
            /\ peer_tx_approval_collection[i] = NoMessage
            /\ approval_outbox[i] = NoMessage
            /\ wt_bundle_inbox[i] = NoMessage
            /\ approval_bundle_outbox[i] = NoMessage
            /\ commit_outbox[i] = NoMessage
            /\ initiator_commit_inbox[i] = NoMessage
            /\ peer_tx_commit_collection[i] = NoMessage
            /\ pending_txid_challenge_i[i] = NoMessage
            /\ accepted_txid_challenge_i[i] = NoMessage
            /\ accepted_txid_ack_i[i] = NoMessage
            /\ ~local_psbt_reviewed_i[i]
            /\ pending_duress_challenge_i[i] = NoMessage
            /\ accepted_duress_challenge_i[i] = NoMessage
            /\ accepted_duress_ack_i[i] = NoMessage
            /\ peer_accepted_initiator_commit[i] = NoMessage
            /\ saved_expected_sar_ack[i] = NoMessage
            /\ sar_pending_ack_request[i] = NoMessage
            /\ sar_ack_i[i] = NoMessage
            /\ wt_round_pings[i] = NoMessage
            /\ pong_i[i] = NoMessage
            /\ reached_pings_collection[i] = NoMessage
            /\ signed_psbt_outbox[i] = NoMessage
            /\ wt_signed_psbt_collection[i] = NoMessage
            /\ ~current_ping_from_recurring_check_i[i]

DeadlockStatesAreClassified ==
    []((~ENABLED Next) => ClassifiedDeadlockState)

(***************************************************************************)
(* Temporal and liveness checks.                                           *)
(***************************************************************************)

UsedSessionsMonotoneStep ==
    used_sessions \subseteq used_sessions'

CompletedWithdrawalsMonotoneStep ==
    completed_withdrawals <= completed_withdrawals'

PlaceholderLedgerMonotoneStep ==
    /\ \A pid \in PlaceholderIds :
         placeholder_owner[pid] # NoSigner =>
             placeholder_owner'[pid] = placeholder_owner[pid]
    /\ \A pid \in PlaceholderIds :
         placeholder_kind[pid] # "unused" =>
             placeholder_kind'[pid] = placeholder_kind[pid]

SARReplayMemoryMonotoneStep ==
    \A i \in Peers :
        sar_seen_placeholder_ids_i[i] \subseteq sar_seen_placeholder_ids_i'[i]

UsedSessionsMonotone ==
    [] [UsedSessionsMonotoneStep]_vars

CompletedWithdrawalsMonotone ==
    [] [CompletedWithdrawalsMonotoneStep]_vars

PlaceholderLedgerMonotone ==
    [] [PlaceholderLedgerMonotoneStep]_vars

SARReplayMemoryMonotone ==
    [] [SARReplayMemoryMonotoneStep]_vars

SpecWithFairness ==
    Spec
    /\ WF_vars(Watchtower)
    /\ WF_vars(SAR)
    /\ WF_vars(FallbackMonitor)
    /\ WF_vars(Environment)
    /\ \A i \in Peers : WF_vars(Peer(i))

FreshPendingSARAckEventuallyDelivered ==
    \A i \in Peers :
        []((sar_pending_ack_request[i] # NoMessage
            /\ SARAckWellFormed(sar_pending_ack_request[i])
            /\ sar_pending_ack_request[i].placeholder \notin sar_seen_placeholder_ids_i[i])
           => <>(sar_ack_i[i] # NoMessage))

LossEventuallyTriggersFallback ==
    \A i \in Peers :
        []((i \in hardware_lost
            /\ peer_state[i] \notin {"Signed", "AwaitReset", "Fallback"}
            /\ \A j \in Peers : peer_state[j] \notin {"Signed", "AwaitReset"})
           => <> fallback_activated[i])

====
