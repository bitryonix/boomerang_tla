---- MODULE BoomerangWithdrawalCore ----
EXTENDS Naturals, FiniteSets

(***************************************************************************)
(* First formal slice of Boomerang withdrawal core.                        *)
(*                                                                         *)
(* Boundary: start after setup, with inherited setup state fixed,          *)
(* milestone_block_0 already reached, and the initiator about to submit    *)
(* a PSBT. End at ReadyToSign.                                             *)
(*                                                                         *)
(* This draft intentionally abstracts cryptography, QR encoding, runtime,  *)
(* and byte-level message formats into symbolic records and guards.        *)
(* It keeps the protocol variables that the English specification marks as *)
(* load-bearing.                                                           *)
(***************************************************************************)

(***************************************************************************)
(* Provisional decision register for this withdrawal slice.                *)
(*                                                                         *)
(* PDR-01 / ACR-03: duress-bearing placeholders are modeled on commits,    *)
(* pings, and the SAR acknowledgment roundtrip, not on approval families.  *)
(* PDR-02 / ACR-05: positive duress latches for the remainder of the       *)
(* ceremony via duress_latched_i.                                          *)
(* PDR-03 / ACR-08: freshness and lag bounds remain symbolic parameters.   *)
(* PDR-04 / ACR-09: non-duress placeholder plaintext is modeled as         *)
(* ZeroPad.                                                                *)
(* PDR-05 / ACR-10: the WT approval uses a canonical initiator field name  *)
(* "initiator" in this abstraction.                                        *)
(* PDR-06 / ACR-12: malformed-SAR branches remain out of scope here.       *)
(* PDR-07 / ACR-14: ST-mediated local checks remain abstract environment   *)
(* choices constrained by the consent-set rule.                            *)
(* PDR-08 / MODEL-01: the default TLC cfg suppresses deadlock checking for *)
(* the bounded BlockHeights model so timeout-only stalls do not mask the   *)
(* safety slice; revisit deadlock/liveness on an explicit progress model.  *)
(***************************************************************************)

CONSTANTS
    Peers,
    INITIATOR,
    ConsentAtoms,
    PSBTs,
    TXIDs,
    BlockHeights,
    InitBoomerangParams,
    InitBoomerangDescriptor,
    InitMilestoneBlockCollection,
    InitDuressConsentSet,
    InitDoxingKey,
    InitMystery,
    InitLocalBlockHeight,
    InitWTBlockHeight,
    NoTx,
    NoPsbt,
    NoMessage,
    NoPlaceholder,
    NoSigner,
    ZeroPad,
    APPROVAL_FRESHNESS,
    COMMIT_FRESHNESS,
    PING_FRESHNESS,
    PONG_FRESHNESS,
    MAX_BLOCK_LAG_JUMP,
    TxOfPsbt

ASSUME
    /\ INITIATOR \in Peers
    /\ Cardinality(Peers) >= 2
    /\ IsFiniteSet(Peers)
    /\ IsFiniteSet(ConsentAtoms)
    /\ IsFiniteSet(PSBTs)
    /\ IsFiniteSet(TXIDs)
    /\ IsFiniteSet(BlockHeights)
    /\ BlockHeights \subseteq Nat
    /\ InitMilestoneBlockCollection \in [milestone0 : Nat]
    /\ InitLocalBlockHeight \in Nat
    /\ InitWTBlockHeight \in Nat
    /\ InitLocalBlockHeight >= InitMilestoneBlockCollection.milestone0
    /\ InitWTBlockHeight >= InitMilestoneBlockCollection.milestone0
    /\ InitDuressConsentSet \in [Peers -> SUBSET ConsentAtoms]
    /\ InitDoxingKey \in [Peers -> ConsentAtoms \cup {ZeroPad}]
    /\ InitMystery \in [Peers -> Nat]
    /\ TxOfPsbt \in [PSBTs -> TXIDs]
    /\ APPROVAL_FRESHNESS \in Nat
    /\ COMMIT_FRESHNESS \in Nat
    /\ PING_FRESHNESS \in Nat
    /\ PONG_FRESHNESS \in Nat
    /\ MAX_BLOCK_LAG_JUMP \in Nat

VARIABLES
    boomerang_params,
    boomerang_descriptor,
    milestone_block_collection,
    duress_consent_set_i,
    doxing_key_i,
    mystery_i,
    tx_id,
    psbt_i,
    hydrated_psbt_i,
    peer_state,
    wt_state,
    peer_tx_approval_collection,
    wt_tx_approval,
    approval_outbox,
    wt_bundle_inbox,
    approval_collection_delivered,
    duress_placeholder_plaintext_i,
    duress_latched_i,
    approval_bundle_outbox,
    approvals_bundle_accepted,
    commit_outbox,
    initiator_commit_acked,
    peer_tx_commit_collection,
    commit_collection_delivered,
    saved_placeholder_for_sar_comparison,
    sar_pending_placeholder,
    sar_ack_i,
    wt_round_pings,
    pong_i,
    reached_collection_delivered,
    reached_pings_collection,
    counter_i,
    ping_seq_num_i,
    reached_mystery_flag_i,
    reached_boomlets_collection_i,
    last_seen_block_i,
    niso_i_event_block_height,
    most_work_bitcoin_block_height

vars == <<
    boomerang_params,
    boomerang_descriptor,
    milestone_block_collection,
    duress_consent_set_i,
    doxing_key_i,
    mystery_i,
    tx_id,
    psbt_i,
    hydrated_psbt_i,
    peer_state,
    wt_state,
    peer_tx_approval_collection,
    wt_tx_approval,
    approval_outbox,
    wt_bundle_inbox,
    approval_collection_delivered,
    duress_placeholder_plaintext_i,
    duress_latched_i,
    approval_bundle_outbox,
    approvals_bundle_accepted,
    commit_outbox,
    initiator_commit_acked,
    peer_tx_commit_collection,
    commit_collection_delivered,
    saved_placeholder_for_sar_comparison,
    sar_pending_placeholder,
    sar_ack_i,
    wt_round_pings,
    pong_i,
    reached_collection_delivered,
    reached_pings_collection,
    counter_i,
    ping_seq_num_i,
    reached_mystery_flag_i,
    reached_boomlets_collection_i,
    last_seen_block_i,
    niso_i_event_block_height,
    most_work_bitcoin_block_height
>>

PeerStates == {
    "ActiveReady",
    "AwaitingPeerApprovals",
    "AwaitingInitialDuressResolution",
    "InitialDuressResolved",
    "AwaitingWTInitiatorCommit",
    "AwaitingCommitCollection",
    "DiggingGame",
    "ReadyToSign",
    "Terminal"
}

WTStates == {
    "AwaitingInitiatorApproval",
    "CollectingPeerApprovals",
    "CollectingCommitments",
    "CollectingPings",
    "DistributingPongs",
    "DistributingReachedPings"
}

WT_ID  == "WT"
SAR_ID == "SAR"

OtherPeers(i) == Peers \ {i}
Milestone0 == milestone_block_collection.milestone0

(***************************************************************************)
(* TLC constant-binding helpers.                                           *)
(*                                                                         *)
(* These are cfg-only constructors for complex constant values. They do    *)
(* not add hidden protocol state or alter the withdrawal slice semantics.  *)
(***************************************************************************)

FirstOtherPeer ==
    CHOOSE p \in OtherPeers(INITIATOR) : TRUE

SecondOtherPeer ==
    CHOOSE p \in (OtherPeers(INITIATOR) \ {FirstOtherPeer}) : TRUE

FirstConsentAtom ==
    CHOOSE c \in ConsentAtoms : TRUE

SecondConsentAtom ==
    CHOOSE c \in (ConsentAtoms \ {FirstConsentAtom}) : TRUE

ThirdConsentAtom ==
    CHOOSE c \in (ConsentAtoms \ {FirstConsentAtom, SecondConsentAtom}) : TRUE

AnyTxId ==
    CHOOSE t \in TXIDs : TRUE

ModelInitMilestoneBlockCollection ==
    [ milestone0 |-> 0 ]

ModelInitDuressConsentSet ==
    [ p \in Peers |->
        IF p = INITIATOR THEN {FirstConsentAtom}
        ELSE IF p = FirstOtherPeer THEN {SecondConsentAtom}
        ELSE {ThirdConsentAtom} ]

ModelInitDoxingKey ==
    [ p \in Peers |->
        IF p = INITIATOR THEN FirstConsentAtom
        ELSE IF p = FirstOtherPeer THEN SecondConsentAtom
        ELSE ThirdConsentAtom ]

ModelInitMystery ==
    [ p \in Peers |->
        IF p = INITIATOR THEN 1
        ELSE IF p = FirstOtherPeer THEN 1
        ELSE 2 ]

ModelTxOfPsbt ==
    [ p \in PSBTs |-> AnyTxId ]

PlaceholderValues == ConsentAtoms \cup {ZeroPad}

ApprovalRecord ==
    [ kind      : {"approved"},
      peer      : Peers,
      txid      : TXIDs \cup {NoTx},
      height    : Nat,
      signed_by : Peers ]

ApprovalCollectionType == [Peers -> ApprovalRecord \cup {NoMessage}]

WTApprovalRecord ==
    [ kind      : {"wt_approved"},
      initiator : Peers,
      txid      : TXIDs \cup {NoTx},
      height    : Nat,
      signed_by : {WT_ID} ]

InitiatorSubmissionRecord ==
    [ kind               : {"initiator_submission"},
      initiator_approval : ApprovalRecord,
      psbt               : PSBTs ]

WTBundleRecord ==
    [ kind               : {"wt_bundle"},
      psbt               : PSBTs,
      initiator_approval : ApprovalRecord,
      wt_approval        : WTApprovalRecord,
      signed_by          : {WT_ID} ]

ApprovalsBundleRecord ==
    [ kind       : {"approvals_bundle"},
      peer       : Peers,
      approvals  : ApprovalCollectionType,
      wt_approval: WTApprovalRecord,
      signed_by  : Peers ]

CommitRecord ==
    [ kind         : {"commit"},
      peer         : Peers,
      txid         : TXIDs \cup {NoTx},
      height       : Nat,
      placeholder  : PlaceholderValues,
      signed_by    : Peers,
      wt_signed_by : {WT_ID, NoSigner} ]

CommitCollectionType == [Peers -> CommitRecord \cup {NoMessage}]

PingRecord ==
    [ kind            : {"ping"},
      peer            : Peers,
      txid            : TXIDs \cup {NoTx},
      last_seen_block : Nat,
      ping_seq_num    : Nat,
      reached         : BOOLEAN,
      placeholder     : PlaceholderValues,
      signed_by       : Peers ]

PingCollectionType == [Peers -> PingRecord \cup {NoMessage}]

SARAckRecord ==
    [ kind        : {"sar_ack"},
      placeholder : PlaceholderValues,
      signed_by   : {SAR_ID} ]

SARAckCollectionType == [Peers -> SARAckRecord \cup {NoMessage}]

PongOtherPingsType == UNION { [OtherPeers(i) -> PingRecord] : i \in Peers }

PongRecord ==
    [ kind        : {"pong"},
      to          : Peers,
      txid        : TXIDs \cup {NoTx},
      wt_height   : Nat,
      other_pings : PongOtherPingsType,
      sar_ack     : SARAckRecord,
      signed_by   : {WT_ID} ]

PongCollectionType == [Peers -> PongRecord \cup {NoMessage}]

ApprovalOutboxType ==
    [Peers -> ApprovalRecord \cup InitiatorSubmissionRecord \cup {NoMessage}]

WTBundleInboxType == [Peers -> WTBundleRecord \cup {NoMessage}]

ApprovalsBundleOutboxType == [Peers -> ApprovalsBundleRecord \cup {NoMessage}]

PlaceholderStateType == [Peers -> PlaceholderValues]
PlaceholderStorageType == [Peers -> PlaceholderValues \cup {NoPlaceholder}]

TxTaggedMessageCarrier ==
    ApprovalRecord \cup WTApprovalRecord \cup CommitRecord \cup PingRecord \cup PongRecord

SignedMessageCarrier ==
    ApprovalRecord \cup
    WTApprovalRecord \cup
    WTBundleRecord \cup
    ApprovalsBundleRecord \cup
    CommitRecord \cup
    PingRecord \cup
    SARAckRecord \cup
    PongRecord

ApprovalMsg(i, h) ==
    [ kind      |-> "approved",
      peer      |-> i,
      txid      |-> tx_id,
      height    |-> h,
      signed_by |-> i ]

WTApprovalMsg(h) ==
    [ kind      |-> "wt_approved",
      initiator |-> INITIATOR,
      txid      |-> tx_id,
      height    |-> h,
      signed_by |-> WT_ID ]

ApprovalsBundleMsg(i) ==
    [ kind        |-> "approvals_bundle",
      peer        |-> i,
      approvals   |-> peer_tx_approval_collection,
      wt_approval |-> wt_tx_approval,
      signed_by   |-> i ]

CommitMsg(i, h, ph) ==
    [ kind         |-> "commit",
      peer         |-> i,
      txid         |-> tx_id,
      height       |-> h,
      placeholder  |-> ph,
      signed_by    |-> i,
      wt_signed_by |-> NoSigner ]

PingMsg(i, seq, reached, ph) ==
    [ kind            |-> "ping",
      peer            |-> i,
      txid            |-> tx_id,
      last_seen_block |-> last_seen_block_i[i],
      ping_seq_num    |-> seq,
      reached         |-> reached,
      placeholder     |-> ph,
      signed_by       |-> i ]

SARAck(ph) ==
    [ kind       |-> "sar_ack",
      placeholder|-> ph,
      signed_by  |-> SAR_ID ]

PongMsg(i) ==
    [ kind       |-> "pong",
      to         |-> i,
      txid       |-> tx_id,
      wt_height  |-> most_work_bitcoin_block_height,
      other_pings|-> [j \in OtherPeers(i) |-> wt_round_pings[j]],
      sar_ack    |-> sar_ack_i[i],
      signed_by  |-> WT_ID ]

SameTxId(psbt, txid0) ==
    IF psbt \in PSBTs THEN TxOfPsbt[psbt] = txid0 ELSE FALSE

DecryptsToExpected(cipher, recipient, expected) == cipher = expected
ConsentSetMatch(selection, expected) == selection = expected

Fresh(sentHeight, observedHeight, limit) ==
    /\ sentHeight \in Nat
    /\ observedHeight \in Nat
    /\ sentHeight <= observedHeight
    /\ observedHeight - sentHeight <= limit

ApprovalWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "peer", "txid", "height", "signed_by"}
    /\ m.kind = "approved"
    /\ m.peer \in Peers
    /\ m.txid \in TXIDs \cup {NoTx}
    /\ m.height \in Nat
    /\ m.signed_by \in Peers

WTApprovalWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "initiator", "txid", "height", "signed_by"}
    /\ m.kind = "wt_approved"
    /\ m.initiator \in Peers
    /\ m.txid \in TXIDs \cup {NoTx}
    /\ m.height \in Nat
    /\ m.signed_by = WT_ID

InitiatorSubmissionWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "initiator_approval", "psbt"}
    /\ m.kind = "initiator_submission"
    /\ m.initiator_approval # NoMessage
    /\ ApprovalWellFormed(m.initiator_approval)
    /\ m.psbt \in PSBTs

WTBundleWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "psbt", "initiator_approval", "wt_approval", "signed_by"}
    /\ m.kind = "wt_bundle"
    /\ m.psbt \in PSBTs
    /\ m.initiator_approval # NoMessage
    /\ ApprovalWellFormed(m.initiator_approval)
    /\ m.wt_approval # NoMessage
    /\ WTApprovalWellFormed(m.wt_approval)
    /\ m.signed_by = WT_ID

BundleWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "peer", "approvals", "wt_approval", "signed_by"}
    /\ m.kind = "approvals_bundle"
    /\ m.peer \in Peers
    /\ DOMAIN m.approvals = Peers
    /\ \A p \in Peers : ApprovalWellFormed(m.approvals[p])
    /\ m.wt_approval # NoMessage
    /\ WTApprovalWellFormed(m.wt_approval)
    /\ m.signed_by \in Peers

CommitWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "peer", "txid", "height", "placeholder", "signed_by", "wt_signed_by"}
    /\ m.kind = "commit"
    /\ m.peer \in Peers
    /\ m.txid \in TXIDs \cup {NoTx}
    /\ m.height \in Nat
    /\ m.placeholder \in PlaceholderValues
    /\ m.signed_by \in Peers
    /\ m.wt_signed_by \in {WT_ID, NoSigner}

PingWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "peer", "txid", "last_seen_block", "ping_seq_num", "reached", "placeholder", "signed_by"}
    /\ m.kind = "ping"
    /\ m.peer \in Peers
    /\ m.txid \in TXIDs \cup {NoTx}
    /\ m.last_seen_block \in Nat
    /\ m.ping_seq_num \in Nat
    /\ m.reached \in BOOLEAN
    /\ m.placeholder \in PlaceholderValues
    /\ m.signed_by \in Peers

SARAckWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "placeholder", "signed_by"}
    /\ m.kind = "sar_ack"
    /\ m.placeholder \in PlaceholderValues
    /\ m.signed_by = SAR_ID

PongWellFormed(m) ==
    IF m = NoMessage THEN TRUE ELSE
    /\ DOMAIN m = {"kind", "to", "txid", "wt_height", "other_pings", "sar_ack", "signed_by"}
    /\ m.kind = "pong"
    /\ m.to \in Peers
    /\ m.txid \in TXIDs \cup {NoTx}
    /\ m.wt_height \in Nat
    /\ DOMAIN m.other_pings = OtherPeers(m.to)
    /\ \A j \in OtherPeers(m.to) :
         /\ m.other_pings[j] # NoMessage
         /\ PingWellFormed(m.other_pings[j])
    /\ m.sar_ack # NoMessage
    /\ SARAckWellFormed(m.sar_ack)
    /\ m.signed_by = WT_ID

SubmissionApproval(m) == IF m # NoMessage /\ InitiatorSubmissionWellFormed(m) THEN m.initiator_approval ELSE NoMessage
SubmissionPsbt(m) == IF m # NoMessage /\ InitiatorSubmissionWellFormed(m) THEN m.psbt ELSE NoPsbt
WTBundleApproval(m) == IF m # NoMessage /\ WTBundleWellFormed(m) THEN m.initiator_approval ELSE NoMessage
WTBundleWTApproval(m) == IF m # NoMessage /\ WTBundleWellFormed(m) THEN m.wt_approval ELSE NoMessage
WTBundlePsbt(m) == IF m # NoMessage /\ WTBundleWellFormed(m) THEN m.psbt ELSE NoPsbt
ApprovalsBundleApprovals(m) == IF m # NoMessage /\ BundleWellFormed(m) THEN m.approvals ELSE [i \in Peers |-> NoMessage]
ApprovalsBundleWTApproval(m) == IF m # NoMessage /\ BundleWellFormed(m) THEN m.wt_approval ELSE NoMessage
CommitPlaceholder(m) == IF m # NoMessage /\ CommitWellFormed(m) THEN m.placeholder ELSE NoPlaceholder
PingPlaceholder(m) == IF m # NoMessage /\ PingWellFormed(m) THEN m.placeholder ELSE NoPlaceholder
PingReached(m) == IF m # NoMessage /\ PingWellFormed(m) THEN m.reached ELSE FALSE
PingSeqNum(m) == IF m # NoMessage /\ PingWellFormed(m) THEN m.ping_seq_num ELSE 0

SealCommit(m) ==
    IF m # NoMessage /\ CommitWellFormed(m)
    THEN [m EXCEPT !.wt_signed_by = WT_ID]
    ELSE m

ValidSig(m, signer) ==
    IF m = NoMessage THEN FALSE ELSE m.signed_by = signer

WTSigned(m) ==
    IF m # NoMessage /\ CommitWellFormed(m) THEN m.wt_signed_by = WT_ID ELSE FALSE

PlaceholderMatchesSent(local, acked) ==
    /\ acked # NoMessage
    /\ SARAckWellFormed(acked)
    /\ acked.placeholder = local

ApprovalFreshAtWT(m) ==
    IF m # NoMessage /\ ApprovalWellFormed(m)
    THEN Fresh(m.height, most_work_bitcoin_block_height, APPROVAL_FRESHNESS)
    ELSE FALSE

WTApprovalFreshAtPeer(i, m) ==
    IF m # NoMessage /\ WTApprovalWellFormed(m)
    THEN Fresh(m.height, niso_i_event_block_height[i], APPROVAL_FRESHNESS)
    ELSE FALSE

CommitFreshAtWT(m) ==
    IF m # NoMessage /\ CommitWellFormed(m)
    THEN Fresh(m.height, most_work_bitcoin_block_height, COMMIT_FRESHNESS)
    ELSE FALSE

CommitFreshAtPeer(i, m) ==
    IF m # NoMessage /\ CommitWellFormed(m)
    THEN Fresh(m.height, niso_i_event_block_height[i], COMMIT_FRESHNESS)
    ELSE FALSE

PingFreshAtWT(m) ==
    IF m # NoMessage /\ PingWellFormed(m)
    THEN Fresh(m.last_seen_block, most_work_bitcoin_block_height, PING_FRESHNESS)
    ELSE FALSE

PongFreshAtPeer(i,m) ==
    IF m # NoMessage /\ PongWellFormed(m)
    THEN Fresh(m.wt_height, niso_i_event_block_height[i], PONG_FRESHNESS)
    ELSE FALSE

MsgTxMatches(m) ==
    IF m = NoMessage THEN TRUE
    ELSE CASE m.kind = "approved" -> ApprovalWellFormed(m) /\ m.txid = tx_id
         [] m.kind = "wt_approved" -> WTApprovalWellFormed(m) /\ m.txid = tx_id
         [] m.kind = "commit" -> CommitWellFormed(m) /\ m.txid = tx_id
         [] m.kind = "ping" -> PingWellFormed(m) /\ m.txid = tx_id
         [] m.kind = "pong" -> PongWellFormed(m) /\ m.txid = tx_id
         [] OTHER -> FALSE

PsbtTxMatches(p) == IF p = NoPsbt THEN TRUE ELSE SameTxId(p, tx_id)

NisoAcceptsWTBundle(i, m) ==
    LET wtAppr == WTBundleWTApproval(m)
        initAppr == WTBundleApproval(m)
        p == WTBundlePsbt(m)
    IN /\ m # NoMessage
       /\ WTBundleWellFormed(m)
       /\ ValidSig(wtAppr, WT_ID)
       /\ ValidSig(initAppr, INITIATOR)
       /\ MsgTxMatches(initAppr)
       /\ MsgTxMatches(wtAppr)
       /\ SameTxId(p, tx_id)
       /\ WTApprovalFreshAtPeer(i, wtAppr)

BoomletAcceptsWTBundle(i, m) == NisoAcceptsWTBundle(i, m)

NisoValidCommitCollection(i) ==
    /\ commit_collection_delivered[i]
    /\ \A p \in Peers:
         LET c == peer_tx_commit_collection[p] IN
         IF c # NoMessage /\ CommitWellFormed(c) THEN
             /\ ValidSig(c, p)
             /\ WTSigned(c)
             /\ c.txid = tx_id
             /\ CommitFreshAtPeer(i, c)
         ELSE FALSE

BoomletValidCommitCollection(i) ==
    /\ NisoValidCommitCollection(i)
    /\ sar_ack_i[i] # NoMessage
    /\ ValidSig(sar_ack_i[i], SAR_ID)
    /\ PlaceholderMatchesSent(saved_placeholder_for_sar_comparison[i], sar_ack_i[i])

IncludedPingsConsistentFor(i, pong) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      /\ pong.to = i
      /\ DOMAIN(pong.other_pings) = OtherPeers(i)
      /\ \A j \in OtherPeers(i) :
           LET q == pong.other_pings[j] IN
           /\ ValidSig(q, j)
           /\ MsgTxMatches(q)
           /\ (j \in reached_boomlets_collection_i[i] => PingReached(q))
    ELSE FALSE

NisoValidPong(i, pong) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      /\ ValidSig(pong, WT_ID)
      /\ pong.to = i
      /\ pong.txid = tx_id
      /\ PongFreshAtPeer(i, pong)
      /\ IncludedPingsConsistentFor(i, pong)
    ELSE FALSE

BoomletValidPong(i, pong) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      /\ NisoValidPong(i, pong)
      /\ ValidSig(pong.sar_ack, SAR_ID)
      /\ PlaceholderMatchesSent(saved_placeholder_for_sar_comparison[i], pong.sar_ack)
    ELSE FALSE

AllApprovalsPresent == \A i \in Peers : peer_tx_approval_collection[i] # NoMessage
AllCommitsPresent   == \A i \in Peers : peer_tx_commit_collection[i] # NoMessage
AllBundlesAccepted  == \A i \in OtherPeers(INITIATOR) : approvals_bundle_accepted[i]
AllRoundPingsPresent == \A i \in Peers : wt_round_pings[i] # NoMessage
AllRoundSARRepliesPresent == \A i \in Peers : sar_ack_i[i] # NoMessage
ReachedPeers == {i \in Peers : reached_pings_collection[i] # NoMessage}
WTAllReached == ReachedPeers = Peers

ReachedPeersAdvertised(i, pong) ==
    IF pong # NoMessage /\ PongWellFormed(pong) THEN
      IF /\ pong.to = i
         /\ DOMAIN(pong.other_pings) = OtherPeers(i)
      THEN {j \in OtherPeers(i) : pong.other_pings[j].reached}
      ELSE {}
    ELSE {}

ReachedPingMatchesTx(m) ==
    IF m # NoMessage /\ PingWellFormed(m) THEN
      /\ m.reached
      /\ m.txid = tx_id
    ELSE FALSE

HigherBlocks(b) == {h \in BlockHeights : h > b}
LeastHigher(b) == CHOOSE h \in HigherBlocks(b) : \A k \in HigherBlocks(b) : h <= k
Min2(a,b) == IF a <= b THEN a ELSE b

CanIncrement(i) == niso_i_event_block_height[i] > last_seen_block_i[i]

InitialDuressVisibleNext(i, signal) ==
    [ peer_state |-> IF i = INITIATOR THEN "AwaitingCommitCollection" ELSE "AwaitingWTInitiatorCommit",
      emits      |-> IF i = INITIATOR THEN "commit" ELSE "approvals_bundle",
      txid       |-> tx_id,
      counter    |-> counter_i[i],
      pingseq    |-> ping_seq_num_i[i],
      reached    |-> reached_mystery_flag_i[i] ]

PongVisibleNext(i, fireCheck, signal) ==
    LET nextCounter == IF CanIncrement(i) THEN counter_i[i] + 1 ELSE counter_i[i]
        nextReached == reached_mystery_flag_i[i] \/ (nextCounter >= mystery_i[i])
        nextLastSeen == IF CanIncrement(i)
                           THEN Min2(niso_i_event_block_height[i], last_seen_block_i[i] + MAX_BLOCK_LAG_JUMP)
                           ELSE last_seen_block_i[i]
    IN [ peer_state |-> "DiggingGame",
         emits      |-> "ping",
         txid       |-> tx_id,
         counter    |-> nextCounter,
         pingseq    |-> ping_seq_num_i[i] + 1,
         reached    |-> nextReached,
         last_seen  |-> nextLastSeen,
         seen       |-> reached_boomlets_collection_i[i] ]

ObservationalConsistencySurrogate ==
    /\ \A i \in Peers :
         peer_state[i] = "AwaitingInitialDuressResolution" =>
           InitialDuressVisibleNext(i, FALSE) = InitialDuressVisibleNext(i, TRUE)
    /\ \A i \in Peers :
         /\ peer_state[i] = "DiggingGame"
         /\ pong_i[i] # NoMessage
         => /\ PongVisibleNext(i, FALSE, FALSE) = PongVisibleNext(i, FALSE, TRUE)
            /\ PongVisibleNext(i, TRUE, FALSE)  = PongVisibleNext(i, TRUE, TRUE)

Init ==
    /\ boomerang_params = InitBoomerangParams
    /\ boomerang_descriptor = InitBoomerangDescriptor
    /\ milestone_block_collection = InitMilestoneBlockCollection
    /\ duress_consent_set_i = InitDuressConsentSet
    /\ doxing_key_i = InitDoxingKey
    /\ mystery_i = InitMystery
    /\ tx_id = NoTx
    /\ psbt_i = [i \in Peers |-> NoPsbt]
    /\ hydrated_psbt_i = [i \in Peers |-> NoPsbt]
    /\ peer_state = [i \in Peers |-> "ActiveReady"]
    /\ wt_state = "AwaitingInitiatorApproval"
    /\ peer_tx_approval_collection = [i \in Peers |-> NoMessage]
    /\ wt_tx_approval = NoMessage
    /\ approval_outbox = [i \in Peers |-> NoMessage]
    /\ wt_bundle_inbox = [i \in Peers |-> NoMessage]
    /\ approval_collection_delivered = [i \in Peers |-> FALSE]
    /\ duress_placeholder_plaintext_i = [i \in Peers |-> ZeroPad]
    /\ duress_latched_i = [i \in Peers |-> FALSE]
    /\ approval_bundle_outbox = [i \in Peers |-> NoMessage]
    /\ approvals_bundle_accepted = [i \in Peers |-> FALSE]
    /\ commit_outbox = [i \in Peers |-> NoMessage]
    /\ initiator_commit_acked = [i \in Peers |-> FALSE]
    /\ peer_tx_commit_collection = [i \in Peers |-> NoMessage]
    /\ commit_collection_delivered = [i \in Peers |-> FALSE]
    /\ saved_placeholder_for_sar_comparison = [i \in Peers |-> NoPlaceholder]
    /\ sar_pending_placeholder = [i \in Peers |-> NoPlaceholder]
    /\ sar_ack_i = [i \in Peers |-> NoMessage]
    /\ wt_round_pings = [i \in Peers |-> NoMessage]
    /\ pong_i = [i \in Peers |-> NoMessage]
    /\ reached_collection_delivered = [i \in Peers |-> FALSE]
    /\ reached_pings_collection = [i \in Peers |-> NoMessage]
    /\ counter_i = [i \in Peers |-> 0]
    /\ ping_seq_num_i = [i \in Peers |-> 0]
    /\ reached_mystery_flag_i = [i \in Peers |-> FALSE]
    /\ reached_boomlets_collection_i = [i \in Peers |-> {}]
    /\ last_seen_block_i = [i \in Peers |-> InitLocalBlockHeight]
    /\ niso_i_event_block_height = [i \in Peers |-> InitLocalBlockHeight]
    /\ most_work_bitcoin_block_height = InitWTBlockHeight

InitiatorBeginWithdrawal(p) ==
    /\ p \in PSBTs
    /\ peer_state[INITIATOR] = "ActiveReady"
    /\ tx_id = NoTx
    /\ InitLocalBlockHeight >= Milestone0
    /\ tx_id' = TxOfPsbt[p]
    /\ psbt_i' = [psbt_i EXCEPT ![INITIATOR] = p]
    /\ peer_state' = [peer_state EXCEPT
                         ![INITIATOR] = "AwaitingPeerApprovals"]
    /\ approval_outbox' = [approval_outbox EXCEPT
                             ![INITIATOR] =
                               [ kind             |-> "initiator_submission",
                                 initiator_approval|-> [ kind      |-> "approved",
                                                         peer      |-> INITIATOR,
                                                         txid      |-> TxOfPsbt[p],
                                                         height    |-> niso_i_event_block_height[INITIATOR],
                                                         signed_by |-> INITIATOR ],
                                 psbt            |-> p ]]
    /\ wt_state' = "AwaitingInitiatorApproval"
    /\ UNCHANGED <<
           boomerang_params, boomerang_descriptor, milestone_block_collection,
           duress_consent_set_i, doxing_key_i, mystery_i,
           hydrated_psbt_i, peer_tx_approval_collection, wt_tx_approval,
           wt_bundle_inbox, approval_collection_delivered,
           duress_placeholder_plaintext_i, duress_latched_i,
           approval_bundle_outbox, approvals_bundle_accepted,
           commit_outbox, initiator_commit_acked,
           peer_tx_commit_collection, commit_collection_delivered,
           saved_placeholder_for_sar_comparison, sar_pending_placeholder,
           sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
           reached_pings_collection, counter_i, ping_seq_num_i,
           reached_mystery_flag_i, reached_boomlets_collection_i,
           last_seen_block_i, niso_i_event_block_height,
           most_work_bitcoin_block_height >>

WTStoreInitiatorApprovalAndFanout ==
    LET sub == approval_outbox[INITIATOR]
        appr == SubmissionApproval(sub)
        p == SubmissionPsbt(sub)
    IN /\ approval_outbox[INITIATOR] # NoMessage
        /\ wt_state = "AwaitingInitiatorApproval"
        /\ InitiatorSubmissionWellFormed(sub)
        /\ ValidSig(appr, INITIATOR)
        /\ MsgTxMatches(appr)
        /\ ApprovalFreshAtWT(appr)
        /\ peer_tx_approval_collection' = [peer_tx_approval_collection EXCEPT ![INITIATOR] = appr]
        /\ wt_tx_approval' = WTApprovalMsg(most_work_bitcoin_block_height)
        /\ wt_bundle_inbox' = [i \in Peers |->
              IF i = INITIATOR THEN NoMessage ELSE
                 [ kind             |-> "wt_bundle",
                   psbt             |-> p,
                   initiator_approval|-> appr,
                   wt_approval      |-> WTApprovalMsg(most_work_bitcoin_block_height),
                   signed_by        |-> WT_ID ]]
        /\ approval_outbox' = [approval_outbox EXCEPT ![INITIATOR] = NoMessage]
        /\ wt_state' = "CollectingPeerApprovals"
        /\ UNCHANGED <<
              boomerang_params, boomerang_descriptor, milestone_block_collection,
              duress_consent_set_i, doxing_key_i, mystery_i,
              tx_id, psbt_i, hydrated_psbt_i, peer_state,
              approval_collection_delivered,
              duress_placeholder_plaintext_i, duress_latched_i,
              approval_bundle_outbox, approvals_bundle_accepted,
              commit_outbox, initiator_commit_acked,
              peer_tx_commit_collection, commit_collection_delivered,
              saved_placeholder_for_sar_comparison, sar_pending_placeholder,
              sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
              reached_pings_collection, counter_i, ping_seq_num_i,
              reached_mystery_flag_i, reached_boomlets_collection_i,
              last_seen_block_i, niso_i_event_block_height,
              most_work_bitcoin_block_height >>

NonInitiatorAcceptBundleAndApprove(i) ==
    /\ i \in OtherPeers(INITIATOR)
    /\ peer_state[i] = "ActiveReady"
    /\ wt_bundle_inbox[i] # NoMessage
    /\ NisoAcceptsWTBundle(i, wt_bundle_inbox[i])
    /\ BoomletAcceptsWTBundle(i, wt_bundle_inbox[i])
    /\ psbt_i' = [psbt_i EXCEPT ![i] = WTBundlePsbt(wt_bundle_inbox[i])]
    /\ peer_state' = [peer_state EXCEPT ![i] = "AwaitingPeerApprovals"]
    /\ approval_outbox' = [approval_outbox EXCEPT ![i] = ApprovalMsg(i, niso_i_event_block_height[i])]
    /\ wt_bundle_inbox' = [wt_bundle_inbox EXCEPT ![i] = NoMessage]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          hydrated_psbt_i, wt_state, peer_tx_approval_collection, wt_tx_approval,
          approval_collection_delivered, duress_placeholder_plaintext_i,
          duress_latched_i, approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

WTCollectPeerApproval(i) ==
    /\ i \in OtherPeers(INITIATOR)
    /\ wt_state = "CollectingPeerApprovals"
    /\ approval_outbox[i] # NoMessage
    /\ ApprovalWellFormed(approval_outbox[i])
    /\ ValidSig(approval_outbox[i], i)
    /\ MsgTxMatches(approval_outbox[i])
    /\ ApprovalFreshAtWT(approval_outbox[i])
    /\ peer_tx_approval_collection' = [peer_tx_approval_collection EXCEPT ![i] = approval_outbox[i]]
    /\ approval_outbox' = [approval_outbox EXCEPT ![i] = NoMessage]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state, wt_tx_approval,
          wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

WTDistributeApprovalCollections ==
    /\ wt_state = "CollectingPeerApprovals"
    /\ AllApprovalsPresent
    /\ \E i \in Peers : ~approval_collection_delivered[i]
    /\ approval_collection_delivered' = [i \in Peers |-> TRUE]
    /\ peer_state' = [i \in Peers |->
           IF peer_state[i] = "AwaitingPeerApprovals" THEN "AwaitingInitialDuressResolution"
           ELSE peer_state[i]]
    /\ wt_state' = "CollectingCommitments"
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

PeerResolveInitialDuress(i, signal) ==
    /\ i \in Peers
    /\ signal \in BOOLEAN
    /\ peer_state[i] = "AwaitingInitialDuressResolution"
    /\ approval_collection_delivered[i]
    /\ duress_placeholder_plaintext_i' = [duress_placeholder_plaintext_i EXCEPT
           ![i] = IF signal THEN doxing_key_i[i] ELSE ZeroPad]
    /\ duress_latched_i' = [duress_latched_i EXCEPT ![i] = duress_latched_i[i] \/ signal]
    /\ peer_state' = [peer_state EXCEPT ![i] = "InitialDuressResolved"]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

InitiatorCommit ==
    LET ph == duress_placeholder_plaintext_i[INITIATOR] IN
    /\ peer_state[INITIATOR] = "InitialDuressResolved"
    /\ saved_placeholder_for_sar_comparison' = [saved_placeholder_for_sar_comparison EXCEPT ![INITIATOR] = ph]
    /\ commit_outbox' = [commit_outbox EXCEPT ![INITIATOR] = CommitMsg(INITIATOR, niso_i_event_block_height[INITIATOR], ph)]
    /\ peer_state' = [peer_state EXCEPT ![INITIATOR] = "AwaitingCommitCollection"]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          sar_pending_placeholder, sar_ack_i, wt_round_pings, pong_i,
          reached_collection_delivered, reached_pings_collection,
          counter_i, ping_seq_num_i, reached_mystery_flag_i,
          reached_boomlets_collection_i, last_seen_block_i,
          niso_i_event_block_height, most_work_bitcoin_block_height >>

NonInitiatorSendApprovalsBundle(i) ==
    /\ i \in OtherPeers(INITIATOR)
    /\ peer_state[i] = "InitialDuressResolved"
    /\ approval_bundle_outbox' = [approval_bundle_outbox EXCEPT ![i] = ApprovalsBundleMsg(i)]
    /\ peer_state' = [peer_state EXCEPT ![i] = "AwaitingWTInitiatorCommit"]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

WTReceiveApprovalsBundle(i) ==
    /\ i \in OtherPeers(INITIATOR)
    /\ wt_state = "CollectingCommitments"
    /\ approval_bundle_outbox[i] # NoMessage
    /\ BundleWellFormed(approval_bundle_outbox[i])
    /\ ValidSig(approval_bundle_outbox[i], i)
    /\ ApprovalsBundleApprovals(approval_bundle_outbox[i]) = peer_tx_approval_collection
    /\ ApprovalsBundleWTApproval(approval_bundle_outbox[i]) = wt_tx_approval
    /\ approvals_bundle_accepted' = [approvals_bundle_accepted EXCEPT ![i] = TRUE]
    /\ approval_bundle_outbox' = [approval_bundle_outbox EXCEPT ![i] = NoMessage]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

WTReceiveCommit(i) ==
    /\ i \in Peers
    /\ wt_state = "CollectingCommitments"
    /\ commit_outbox[i] # NoMessage
    /\ peer_tx_commit_collection[i] = NoMessage
    /\ sar_pending_placeholder[i] = NoPlaceholder
    /\ sar_ack_i[i] = NoMessage
    /\ CommitWellFormed(commit_outbox[i])
    /\ ValidSig(commit_outbox[i], i)
    /\ MsgTxMatches(commit_outbox[i])
    /\ CommitFreshAtWT(commit_outbox[i])
    /\ sar_pending_placeholder' = [sar_pending_placeholder EXCEPT ![i] = CommitPlaceholder(commit_outbox[i])]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_ack_i,
          wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

SARAcknowledgePlaceholder(i) ==
    /\ i \in Peers
    /\ sar_pending_placeholder[i] # NoPlaceholder
    /\ sar_ack_i' = [sar_ack_i EXCEPT ![i] = SARAck(sar_pending_placeholder[i])]
    /\ sar_pending_placeholder' = [sar_pending_placeholder EXCEPT ![i] = NoPlaceholder]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, wt_round_pings, pong_i,
          reached_collection_delivered, reached_pings_collection,
          counter_i, ping_seq_num_i, reached_mystery_flag_i,
          reached_boomlets_collection_i, last_seen_block_i,
          niso_i_event_block_height, most_work_bitcoin_block_height >>

WTSealInitiatorCommit ==
    /\ wt_state = "CollectingCommitments"
    /\ commit_outbox[INITIATOR] # NoMessage
    /\ sar_ack_i[INITIATOR] # NoMessage
    /\ ValidSig(sar_ack_i[INITIATOR], SAR_ID)
    /\ PlaceholderMatchesSent(saved_placeholder_for_sar_comparison[INITIATOR], sar_ack_i[INITIATOR])
    /\ peer_tx_commit_collection' = [peer_tx_commit_collection EXCEPT
           ![INITIATOR] = SealCommit(commit_outbox[INITIATOR])]
    /\ initiator_commit_acked' = [i \in Peers |-> IF i = INITIATOR THEN initiator_commit_acked[i] ELSE TRUE]
    /\ commit_outbox' = [commit_outbox EXCEPT ![INITIATOR] = NoMessage]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_collection_delivered, saved_placeholder_for_sar_comparison,
          sar_pending_placeholder, sar_ack_i,
          wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

NonInitiatorCommitAfterInitiatorAck(i) ==
    LET ph == IF duress_latched_i[i] THEN doxing_key_i[i] ELSE duress_placeholder_plaintext_i[i]
    IN /\ i \in OtherPeers(INITIATOR)
       /\ peer_state[i] = "AwaitingWTInitiatorCommit"
       /\ approvals_bundle_accepted[i]
       /\ initiator_commit_acked[i]
       /\ saved_placeholder_for_sar_comparison' = [saved_placeholder_for_sar_comparison EXCEPT ![i] = ph]
       /\ commit_outbox' = [commit_outbox EXCEPT ![i] = CommitMsg(i, niso_i_event_block_height[i], ph)]
       /\ peer_state' = [peer_state EXCEPT ![i] = "AwaitingCommitCollection"]
       /\ UNCHANGED <<
             boomerang_params, boomerang_descriptor, milestone_block_collection,
             duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
             psbt_i, hydrated_psbt_i, wt_state,
             peer_tx_approval_collection, wt_tx_approval,
             approval_outbox, wt_bundle_inbox, approval_collection_delivered,
             duress_placeholder_plaintext_i, duress_latched_i,
             approval_bundle_outbox, approvals_bundle_accepted,
             initiator_commit_acked,
             peer_tx_commit_collection, commit_collection_delivered,
             sar_pending_placeholder, sar_ack_i, wt_round_pings, pong_i,
             reached_collection_delivered, reached_pings_collection,
             counter_i, ping_seq_num_i, reached_mystery_flag_i,
             reached_boomlets_collection_i, last_seen_block_i,
             niso_i_event_block_height, most_work_bitcoin_block_height >>

WTSealNonInitiatorCommit(i) ==
    /\ i \in OtherPeers(INITIATOR)
    /\ wt_state = "CollectingCommitments"
    /\ commit_outbox[i] # NoMessage
    /\ sar_ack_i[i] # NoMessage
    /\ ValidSig(sar_ack_i[i], SAR_ID)
    /\ PlaceholderMatchesSent(saved_placeholder_for_sar_comparison[i], sar_ack_i[i])
    /\ peer_tx_commit_collection' = [peer_tx_commit_collection EXCEPT ![i] = SealCommit(commit_outbox[i])]
    /\ commit_outbox' = [commit_outbox EXCEPT ![i] = NoMessage]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          initiator_commit_acked,
          commit_collection_delivered, saved_placeholder_for_sar_comparison,
          sar_pending_placeholder, sar_ack_i,
          wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

WTCollectAndRedistributeCommitCollection ==
    /\ wt_state = "CollectingCommitments"
    /\ AllCommitsPresent
    /\ \E i \in Peers : ~commit_collection_delivered[i]
    /\ commit_collection_delivered' = [i \in Peers |-> TRUE]
    /\ wt_state' = "CollectingPings"
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

PeerEnterDiggingGame(i) ==
    LET ph == IF duress_latched_i[i] THEN doxing_key_i[i] ELSE duress_placeholder_plaintext_i[i]
    IN /\ i \in Peers
       /\ peer_state[i] = "AwaitingCommitCollection"
       /\ NisoValidCommitCollection(i)
       /\ BoomletValidCommitCollection(i)
       /\ counter_i' = [counter_i EXCEPT ![i] = 0]
       /\ ping_seq_num_i' = [ping_seq_num_i EXCEPT ![i] = 0]
       /\ reached_mystery_flag_i' = [reached_mystery_flag_i EXCEPT ![i] = FALSE]
       /\ reached_boomlets_collection_i' = [reached_boomlets_collection_i EXCEPT ![i] = {}]
       /\ last_seen_block_i' = [last_seen_block_i EXCEPT ![i] = niso_i_event_block_height[i]]
       /\ saved_placeholder_for_sar_comparison' = [saved_placeholder_for_sar_comparison EXCEPT ![i] = ph]
       /\ wt_round_pings' = [wt_round_pings EXCEPT ![i] = PingMsg(i, 0, FALSE, ph)]
       /\ sar_ack_i' = [sar_ack_i EXCEPT ![i] = NoMessage]
       /\ peer_state' = [peer_state EXCEPT ![i] = "DiggingGame"]
       /\ UNCHANGED <<
             boomerang_params, boomerang_descriptor, milestone_block_collection,
             duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
             psbt_i, hydrated_psbt_i, wt_state,
             peer_tx_approval_collection, wt_tx_approval,
             approval_outbox, wt_bundle_inbox, approval_collection_delivered,
             duress_placeholder_plaintext_i, duress_latched_i,
             approval_bundle_outbox, approvals_bundle_accepted,
             commit_outbox, initiator_commit_acked,
             peer_tx_commit_collection, commit_collection_delivered,
             sar_pending_placeholder,
             pong_i, reached_collection_delivered, reached_pings_collection,
             niso_i_event_block_height, most_work_bitcoin_block_height >>

WTCollectPingAndForwardPlaceholder(i) ==
    /\ i \in Peers
    /\ wt_state = "CollectingPings"
    /\ wt_round_pings[i] # NoMessage
    /\ sar_pending_placeholder[i] = NoPlaceholder
    /\ sar_ack_i[i] = NoMessage
    /\ PingWellFormed(wt_round_pings[i])
    /\ ValidSig(wt_round_pings[i], i)
    /\ MsgTxMatches(wt_round_pings[i])
    /\ PingFreshAtWT(wt_round_pings[i])
    /\ (PingSeqNum(wt_round_pings[i]) = 0 => ~PingReached(wt_round_pings[i]))
    /\ sar_pending_placeholder' = [sar_pending_placeholder EXCEPT ![i] = PingPlaceholder(wt_round_pings[i])]
    /\ reached_pings_collection' = [reached_pings_collection EXCEPT
           ![i] = IF PingReached(wt_round_pings[i]) /\ reached_pings_collection[i] = NoMessage
                    THEN wt_round_pings[i]
                    ELSE reached_pings_collection[i]]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_ack_i,
          wt_round_pings, pong_i, reached_collection_delivered,
          counter_i, ping_seq_num_i, reached_mystery_flag_i,
          reached_boomlets_collection_i, last_seen_block_i,
          niso_i_event_block_height, most_work_bitcoin_block_height >>

WTDistributePong ==
    /\ wt_state = "CollectingPings"
    /\ AllRoundPingsPresent
    /\ AllRoundSARRepliesPresent
    /\ ~WTAllReached
    /\ pong_i' = [i \in Peers |-> PongMsg(i)]
    /\ sar_ack_i' = [i \in Peers |-> NoMessage]
    /\ wt_round_pings' = [i \in Peers |-> NoMessage]
    /\ wt_state' = "CollectingPings"
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

PeerProcessPongAndUpdateDiggingState(i, fireCheck, signal) ==
    LET nextPlain ==
            IF duress_latched_i[i] \/ (fireCheck /\ signal)
               THEN doxing_key_i[i]
               ELSE IF fireCheck THEN ZeroPad ELSE duress_placeholder_plaintext_i[i]
        nextLatched == duress_latched_i[i] \/ (fireCheck /\ signal)
        nextCounter == IF CanIncrement(i) THEN counter_i[i] + 1 ELSE counter_i[i]
        nextReached == reached_mystery_flag_i[i] \/ (nextCounter >= mystery_i[i])
        newlyReached == ReachedPeersAdvertised(i, pong_i[i])
        nextSeen == reached_boomlets_collection_i[i] \cup newlyReached
        nextLastSeen == IF CanIncrement(i)
                           THEN Min2(niso_i_event_block_height[i], last_seen_block_i[i] + MAX_BLOCK_LAG_JUMP)
                           ELSE last_seen_block_i[i]
    IN /\ i \in Peers
       /\ fireCheck \in BOOLEAN
       /\ signal \in BOOLEAN
       /\ peer_state[i] = "DiggingGame"
       /\ pong_i[i] # NoMessage
       /\ NisoValidPong(i, pong_i[i])
       /\ BoomletValidPong(i, pong_i[i])
       /\ duress_placeholder_plaintext_i' = [duress_placeholder_plaintext_i EXCEPT ![i] = nextPlain]
       /\ duress_latched_i' = [duress_latched_i EXCEPT ![i] = nextLatched]
       /\ counter_i' = [counter_i EXCEPT ![i] = nextCounter]
       /\ reached_boomlets_collection_i' = [reached_boomlets_collection_i EXCEPT ![i] = nextSeen]
       /\ reached_mystery_flag_i' = [reached_mystery_flag_i EXCEPT ![i] = nextReached]
       /\ last_seen_block_i' = [last_seen_block_i EXCEPT ![i] = nextLastSeen]
       /\ ping_seq_num_i' = [ping_seq_num_i EXCEPT ![i] = ping_seq_num_i[i] + 1]
       /\ saved_placeholder_for_sar_comparison' = [saved_placeholder_for_sar_comparison EXCEPT ![i] = nextPlain]
       /\ wt_round_pings' = [wt_round_pings EXCEPT ![i] = PingMsg(i, ping_seq_num_i[i] + 1, nextReached, nextPlain)]
       /\ pong_i' = [pong_i EXCEPT ![i] = NoMessage]
       /\ UNCHANGED <<
             boomerang_params, boomerang_descriptor, milestone_block_collection,
             duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
             psbt_i, hydrated_psbt_i, peer_state, wt_state,
             peer_tx_approval_collection, wt_tx_approval,
             approval_outbox, wt_bundle_inbox, approval_collection_delivered,
             approval_bundle_outbox, approvals_bundle_accepted,
             commit_outbox, initiator_commit_acked,
             peer_tx_commit_collection, commit_collection_delivered,
             sar_pending_placeholder, sar_ack_i, reached_collection_delivered,
             reached_pings_collection, niso_i_event_block_height,
             most_work_bitcoin_block_height >>

WTBreakWhenAllReached ==
    /\ wt_state \in {"CollectingPings", "DistributingPongs"}
    /\ WTAllReached
    /\ reached_collection_delivered' = [i \in Peers |-> TRUE]
    /\ wt_state' = "DistributingReachedPings"
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_pings_collection,
          counter_i, ping_seq_num_i, reached_mystery_flag_i,
          reached_boomlets_collection_i, last_seen_block_i,
          niso_i_event_block_height, most_work_bitcoin_block_height >>

PeerAcceptReachedPingsAndBecomeReadyToSign(i) ==
    /\ i \in Peers
    /\ peer_state[i] = "DiggingGame"
    /\ reached_collection_delivered[i]
    /\ \A j \in Peers : reached_pings_collection[j] # NoMessage
    /\ \A j \in Peers :
          /\ ValidSig(reached_pings_collection[j], j)
          /\ ReachedPingMatchesTx(reached_pings_collection[j])
    /\ hydrated_psbt_i' = [hydrated_psbt_i EXCEPT ![i] = psbt_i[i]]
    /\ SameTxId(psbt_i[i], tx_id)
    /\ peer_state' = [peer_state EXCEPT ![i] = "ReadyToSign"]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height,
          most_work_bitcoin_block_height >>

AdvanceNisoHeight(i) ==
    /\ i \in Peers
    /\ HigherBlocks(niso_i_event_block_height[i]) # {}
    /\ niso_i_event_block_height' = [niso_i_event_block_height EXCEPT ![i] = LeastHigher(niso_i_event_block_height[i])]
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, most_work_bitcoin_block_height >>

AdvanceWTHeight ==
    /\ HigherBlocks(most_work_bitcoin_block_height) # {}
    /\ most_work_bitcoin_block_height' = LeastHigher(most_work_bitcoin_block_height)
    /\ UNCHANGED <<
          boomerang_params, boomerang_descriptor, milestone_block_collection,
          duress_consent_set_i, doxing_key_i, mystery_i, tx_id,
          psbt_i, hydrated_psbt_i, peer_state, wt_state,
          peer_tx_approval_collection, wt_tx_approval,
          approval_outbox, wt_bundle_inbox, approval_collection_delivered,
          duress_placeholder_plaintext_i, duress_latched_i,
          approval_bundle_outbox, approvals_bundle_accepted,
          commit_outbox, initiator_commit_acked,
          peer_tx_commit_collection, commit_collection_delivered,
          saved_placeholder_for_sar_comparison, sar_pending_placeholder,
          sar_ack_i, wt_round_pings, pong_i, reached_collection_delivered,
          reached_pings_collection, counter_i, ping_seq_num_i,
          reached_mystery_flag_i, reached_boomlets_collection_i,
          last_seen_block_i, niso_i_event_block_height >>

PeerSendPing(i) ==
    PeerEnterDiggingGame(i) \/
    (\E fireCheck \in BOOLEAN, signal \in BOOLEAN : PeerProcessPongAndUpdateDiggingState(i, fireCheck, signal))

Next ==
    \/ \E p \in PSBTs : InitiatorBeginWithdrawal(p)
    \/ WTStoreInitiatorApprovalAndFanout
    \/ \E i \in OtherPeers(INITIATOR) : NonInitiatorAcceptBundleAndApprove(i)
    \/ \E i \in OtherPeers(INITIATOR) : WTCollectPeerApproval(i)
    \/ WTDistributeApprovalCollections
    \/ \E i \in Peers : PeerResolveInitialDuress(i, FALSE)
    \/ \E i \in Peers : PeerResolveInitialDuress(i, TRUE)
    \/ InitiatorCommit
    \/ \E i \in OtherPeers(INITIATOR) : NonInitiatorSendApprovalsBundle(i)
    \/ \E i \in OtherPeers(INITIATOR) : WTReceiveApprovalsBundle(i)
    \/ WTReceiveCommit(INITIATOR)
    \/ SARAcknowledgePlaceholder(INITIATOR)
    \/ WTSealInitiatorCommit
    \/ \E i \in OtherPeers(INITIATOR) : NonInitiatorCommitAfterInitiatorAck(i)
    \/ \E i \in OtherPeers(INITIATOR) : WTReceiveCommit(i)
    \/ \E i \in OtherPeers(INITIATOR) : SARAcknowledgePlaceholder(i)
    \/ \E i \in OtherPeers(INITIATOR) : WTSealNonInitiatorCommit(i)
    \/ WTCollectAndRedistributeCommitCollection
    \/ \E i \in Peers : PeerEnterDiggingGame(i)
    \/ \E i \in Peers : WTCollectPingAndForwardPlaceholder(i)
    \/ WTDistributePong
    \/ \E i \in Peers : PeerProcessPongAndUpdateDiggingState(i, FALSE, FALSE)
    \/ \E i \in Peers : PeerProcessPongAndUpdateDiggingState(i, TRUE, FALSE)
    \/ \E i \in Peers : PeerProcessPongAndUpdateDiggingState(i, TRUE, TRUE)
    \/ WTBreakWhenAllReached
    \/ \E i \in Peers : PeerAcceptReachedPingsAndBecomeReadyToSign(i)
    \/ \E i \in Peers : AdvanceNisoHeight(i)
    \/ AdvanceWTHeight

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* State predicates / invariants                                            *)
(***************************************************************************)

TypeOK ==
    /\ duress_consent_set_i \in [Peers -> SUBSET ConsentAtoms]
    /\ doxing_key_i \in PlaceholderStateType
    /\ mystery_i \in [Peers -> Nat]
    /\ peer_state \in [Peers -> PeerStates]
    /\ wt_state \in WTStates
    /\ tx_id \in TXIDs \cup {NoTx}
    /\ psbt_i \in [Peers -> PSBTs \cup {NoPsbt}]
    /\ hydrated_psbt_i \in [Peers -> PSBTs \cup {NoPsbt}]
    /\ approval_collection_delivered \in [Peers -> BOOLEAN]
    /\ duress_placeholder_plaintext_i \in PlaceholderStateType
    /\ duress_latched_i \in [Peers -> BOOLEAN]
    /\ approvals_bundle_accepted \in [Peers -> BOOLEAN]
    /\ initiator_commit_acked \in [Peers -> BOOLEAN]
    /\ commit_collection_delivered \in [Peers -> BOOLEAN]
    /\ saved_placeholder_for_sar_comparison \in PlaceholderStorageType
    /\ sar_pending_placeholder \in PlaceholderStorageType
    /\ reached_collection_delivered \in [Peers -> BOOLEAN]
    /\ counter_i \in [Peers -> Nat]
    /\ ping_seq_num_i \in [Peers -> Nat]
    /\ reached_mystery_flag_i \in [Peers -> BOOLEAN]
    /\ reached_boomlets_collection_i \in [Peers -> SUBSET Peers]
    /\ last_seen_block_i \in [Peers -> Nat]
    /\ niso_i_event_block_height \in [Peers -> Nat]
    /\ most_work_bitcoin_block_height \in Nat
    /\ \A i \in Peers : ApprovalWellFormed(peer_tx_approval_collection[i])
    /\ WTApprovalWellFormed(wt_tx_approval)
    /\ \A i \in Peers : ApprovalWellFormed(approval_outbox[i]) \/ InitiatorSubmissionWellFormed(approval_outbox[i])
    /\ \A i \in Peers : BundleWellFormed(approval_bundle_outbox[i])
    /\ \A i \in Peers : WTBundleWellFormed(wt_bundle_inbox[i])
    /\ \A i \in Peers : CommitWellFormed(commit_outbox[i])
    /\ \A i \in Peers : CommitWellFormed(peer_tx_commit_collection[i])
    /\ \A i \in Peers : PingWellFormed(wt_round_pings[i])
    /\ \A i \in Peers : PongWellFormed(pong_i[i])
    /\ \A i \in Peers : SARAckWellFormed(sar_ack_i[i])
    /\ \A i \in Peers : PingWellFormed(reached_pings_collection[i])
    /\ boomerang_params = InitBoomerangParams
    /\ boomerang_descriptor = InitBoomerangDescriptor
    /\ milestone_block_collection = InitMilestoneBlockCollection

TxIdFrozen ==
    tx_id = NoTx \/
    (/\ \A i \in Peers :
          /\ MsgTxMatches(peer_tx_approval_collection[i])
          /\ MsgTxMatches(peer_tx_commit_collection[i])
          /\ MsgTxMatches(wt_round_pings[i])
          /\ MsgTxMatches(pong_i[i])
          /\ MsgTxMatches(reached_pings_collection[i])
          /\ PsbtTxMatches(hydrated_psbt_i[i])
          /\ PsbtTxMatches(psbt_i[i])
     /\ MsgTxMatches(wt_tx_approval))

NoEarlySigning ==
    \A i \in Peers :
      peer_state[i] = "ReadyToSign" =>
        /\ AllApprovalsPresent
        /\ AllCommitsPresent
        /\ WTAllReached
        /\ hydrated_psbt_i[i] # NoPsbt
        /\ SameTxId(hydrated_psbt_i[i], tx_id)

PlaceholderAuthentic ==
    \A i \in Peers :
      sar_ack_i[i] # NoMessage =>
        /\ ValidSig(sar_ack_i[i], SAR_ID)
        /\ saved_placeholder_for_sar_comparison[i] # NoPlaceholder
        /\ PlaceholderMatchesSent(saved_placeholder_for_sar_comparison[i], sar_ack_i[i])

WTBreakConditionCorrect ==
    wt_state = "DistributingReachedPings" => WTAllReached

PostDuressNoRevert ==
    \A i \in Peers : duress_latched_i[i] => duress_placeholder_plaintext_i[i] = doxing_key_i[i]

NormalRegimeNonInterference ==
    /\ peer_state \in [Peers -> PeerStates]
    /\ wt_state \in WTStates

ReachedFlagsMonotoneStep ==
    \A i \in Peers : reached_mystery_flag_i[i] => reached_mystery_flag_i'[i]

ReachedFlagsMonotone ==
    [] [ReachedFlagsMonotoneStep]_vars

ReachedBoomletsCollectionsMonotoneStep ==
    \A i \in Peers : reached_boomlets_collection_i[i] \subseteq reached_boomlets_collection_i'[i]

ReachedPingsCollectionMonotoneStep ==
    {i \in Peers : reached_pings_collection[i] # NoMessage}
      \subseteq
    {i \in Peers : reached_pings_collection'[i] # NoMessage}

ReachedCollectionsMonotone ==
    /\ [] [ReachedBoomletsCollectionsMonotoneStep]_vars
    /\ [] [ReachedPingsCollectionMonotoneStep]_vars

CounterMonotoneStep ==
    \A i \in Peers : counter_i[i] <= counter_i'[i]

CounterMonotone ==
    [] [CounterMonotoneStep]_vars

PingSeqStrictAfterFirstStep ==
    \A i \in Peers :
      /\ wt_round_pings'[i] # wt_round_pings[i]
      /\ wt_round_pings'[i] # NoMessage
      /\ ping_seq_num_i[i] > 0
      => ping_seq_num_i'[i] = ping_seq_num_i[i] + 1

PingSeqStrictAfterFirst ==
    [] [PingSeqStrictAfterFirstStep]_vars

(***************************************************************************)
(* Optional fairness assumptions. Kept separate from safety model.         *)
(***************************************************************************)

PeerProgress(i) ==
    \/ NonInitiatorAcceptBundleAndApprove(i)
    \/ PeerResolveInitialDuress(i, FALSE)
    \/ PeerResolveInitialDuress(i, TRUE)
    \/ (i \in OtherPeers(INITIATOR) /\ NonInitiatorSendApprovalsBundle(i))
    \/ (i \in OtherPeers(INITIATOR) /\ NonInitiatorCommitAfterInitiatorAck(i))
    \/ PeerEnterDiggingGame(i)
    \/ PeerProcessPongAndUpdateDiggingState(i, FALSE, FALSE)
    \/ PeerProcessPongAndUpdateDiggingState(i, TRUE, FALSE)
    \/ PeerProcessPongAndUpdateDiggingState(i, TRUE, TRUE)
    \/ PeerAcceptReachedPingsAndBecomeReadyToSign(i)
    \/ AdvanceNisoHeight(i)

WTProgress ==
    \/ WTStoreInitiatorApprovalAndFanout
    \/ (\E i \in OtherPeers(INITIATOR) : WTCollectPeerApproval(i))
    \/ WTDistributeApprovalCollections
    \/ (\E i \in OtherPeers(INITIATOR) : WTReceiveApprovalsBundle(i))
    \/ WTReceiveCommit(INITIATOR)
    \/ WTSealInitiatorCommit
    \/ (\E i \in OtherPeers(INITIATOR) : WTReceiveCommit(i))
    \/ (\E i \in OtherPeers(INITIATOR) : WTSealNonInitiatorCommit(i))
    \/ WTCollectAndRedistributeCommitCollection
    \/ (\E i \in Peers : WTCollectPingAndForwardPlaceholder(i))
    \/ WTDistributePong
    \/ WTBreakWhenAllReached
    \/ AdvanceWTHeight

SARProgress == \E i \in Peers : SARAcknowledgePlaceholder(i)

Fairness ==
    /\ WF_vars(WTProgress)
    /\ WF_vars(SARProgress)
    /\ \A i \in Peers : WF_vars(PeerProgress(i))

SpecWF == Spec /\ Fairness

====
