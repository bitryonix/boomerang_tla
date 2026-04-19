---- MODULE BoomerangWithdrawalWire ----
EXTENDS Naturals, Sequences, FiniteSets, TLC

(***************************************************************************)
(* Wire-faithful symbolic withdrawal model derived from BD.zip.            *)
(* Canonical sources for this module:                                      *)
(* - withdrawal/README.md                                                  *)
(* - withdrawal/initiator_withdrawal_diagram_without_states.puml           *)
(* - withdrawal/non_initiator_withdrawal_diagram_without_states.puml       *)
(*                                                                         *)
(* Scope:                                                                  *)
(* - post-setup only                                                       *)
(* - one active withdrawal ceremony                                        *)
(* - fixed 5-peer profile                                                  *)
(* - full withdrawal flow through WT relay                                 *)
(* - symbolic crypto only, with explicit wrapper layering                  *)
(*                                                                         *)
(* Design notes:                                                           *)
(* - every actor is a separate PlusCal process                             *)
(* - every actor hop uses an explicit mailbox                              *)
(* - exact canonical wrapper names are used on actor-to-actor messages     *)
(* - helper crypto/value constructors below are off-wire symbolic records   *)
(***************************************************************************)

CONSTANTS
    Peers,
    INITIATOR,
    PSBTs,
    TXIDs,
    InitDoxingKey,
    InitConsentSet,
    InitMystery,
    TxOfPsbt,
    Milestone0,
    DURESS_VALUE_CARDINALITY,
    DURESS_CHECK_INTERVAL_IN_BLOCKS,
    TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT,
    TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS,
    TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEER_TO_RECEIVING_NON_INITIATOR_PEERS_TX_APPROVAL_BY_WT,
    TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS,
    TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS,
    TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER,
    TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER,
    REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER,
    TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_SAR_RESPONSE_BY_WT,
    TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS,
    TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_NON_INITIATOR_PEER_TO_RECEIVING_NON_INITIATOR_PEERS_TX_COMMITMENT_BY_WT_HAVING_SAR_RESPONSE_BACK_TO_WT,
    TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS,
    REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS,
    TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_TO_RECEIVING_ALL_PINGS_BY_WT_AND_HAVING_SAR_RESPONSE_BACK_TO_WT,
    TOLERANCE_IN_BLOCKS_FROM_CREATING_PONG_BY_WT_TO_REVIEWING_THE_PONG_IN_PEERS_BOOMLET,
    TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_BY_OTHER_PEERS_TO_REVIEWING_THE_PING_IN_PEER_BOOMLET,
    JUMP_IN_BLOCKS_IF_LAST_SEEN_BLOCK_LAGS_BEHIND_NISO_EVENT_BLOCK_HEIGHT_IN_BOOMLET,
    REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PING_AND_PONG

ASSUME
    /\ INITIATOR \in Peers
    /\ Cardinality(Peers) = 5
    /\ IsFiniteSet(Peers)
    /\ IsFiniteSet(PSBTs)
    /\ PSBTs # {}
    /\ IsFiniteSet(TXIDs)
    /\ TXIDs # {}
    /\ TxOfPsbt \in [PSBTs -> TXIDs]
    /\ InitDoxingKey \in [Peers -> STRING]
    /\ DURESS_VALUE_CARDINALITY \in Nat
    /\ DURESS_VALUE_CARDINALITY >= 2
    /\ InitConsentSet \in [Peers -> [1..5 -> 1..DURESS_VALUE_CARDINALITY]]
    /\ InitMystery \in [Peers -> Nat]
    /\ \A i \in Peers : InitMystery[i] > 0
    /\ Milestone0 \in Nat
    /\ DURESS_CHECK_INTERVAL_IN_BLOCKS \in Nat
    /\ DURESS_CHECK_INTERVAL_IN_BLOCKS > 0
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEER_TO_RECEIVING_NON_INITIATOR_PEERS_TX_APPROVAL_BY_WT \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER \in Nat
    /\ REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_SAR_RESPONSE_BY_WT \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_NON_INITIATOR_PEER_TO_RECEIVING_NON_INITIATOR_PEERS_TX_COMMITMENT_BY_WT_HAVING_SAR_RESPONSE_BACK_TO_WT \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS \in Nat
    /\ REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_TO_RECEIVING_ALL_PINGS_BY_WT_AND_HAVING_SAR_RESPONSE_BACK_TO_WT \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_CREATING_PONG_BY_WT_TO_REVIEWING_THE_PONG_IN_PEERS_BOOMLET \in Nat
    /\ TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_BY_OTHER_PEERS_TO_REVIEWING_THE_PING_IN_PEER_BOOMLET \in Nat
    /\ JUMP_IN_BLOCKS_IF_LAST_SEEN_BLOCK_LAGS_BEHIND_NISO_EVENT_BLOCK_HEIGHT_IN_BOOMLET \in Nat
    /\ REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PING_AND_PONG \in Nat

CanonicalPsbt ==
    CHOOSE p \in PSBTs : TRUE

CanonicalTxId ==
    TxOfPsbt[CanonicalPsbt]

DuressValues ==
    1..DURESS_VALUE_CARDINALITY

RecurringDuressPRNGDraws ==
    0..((2 * DURESS_CHECK_INTERVAL_IN_BLOCKS) - 1)

RecurringDuressCheckFires(draw) ==
    /\ draw \in RecurringDuressPRNGDraws
    /\ draw % DURESS_CHECK_INTERVAL_IN_BLOCKS = 0

FirstDuressValue ==
    CHOOSE v \in DuressValues : TRUE

SecondDuressValue ==
    CHOOSE v \in (DuressValues \ {FirstDuressValue}) : TRUE

ModelInitDoxingKeyDistinct ==
    CHOOSE f \in [Peers -> {"DK0", "DK1", "DK2", "DK3", "DK4"}] :
        \A p, q \in Peers : p # q => f[p] # f[q]

ModelInitConsentSetAlternating ==
    [ p \in Peers |->
        [ c \in 1..5 |->
            IF c \in {1, 3, 5} THEN FirstDuressValue ELSE SecondDuressValue ] ]

ModelInitMysterySmall ==
    [ p \in Peers |-> 1 ]

ModelTxOfPsbtSingle ==
    [ p \in PSBTs |-> CHOOSE t \in TXIDs : TRUE ]

NonInitiators ==
    Peers \ {INITIATOR}

NoValue ==
    "NO_VALUE"

WT_ID ==
    "WT"

UserActor(i)    == [kind |-> "User", peer |-> i]
NisoActor(i)    == [kind |-> "Niso", peer |-> i]
BoomletActor(i) == [kind |-> "Boomlet", peer |-> i]
STActor(i)      == [kind |-> "ST", peer |-> i]
IsoActor(i)     == [kind |-> "Iso", peer |-> i]
SARActor(i)     == [kind |-> "SAR", peer |-> i]
WTActor         == [kind |-> "WT"]

WireHop(sender, receiver, message) ==
    [ sender |-> sender,
      receiver |-> receiver,
      message |-> message ]

MessageWithNonce(content, nonce) ==
    [ kind    |-> "MessageWithNonce",
      content |-> content,
      nonce   |-> nonce ]

SignatureOnMessage(signer, content) ==
    [ kind    |-> "SignatureOnMessage",
      signer  |-> signer,
      content |-> content ]

PaddedMessage(content, padding) ==
    [ kind    |-> "PaddedMessage",
      content |-> content,
      padding |-> padding ]

EncryptedFor(recipient, sender, iv, payload) ==
    [ kind      |-> "EncryptedFor",
      recipient |-> recipient,
      sender    |-> sender,
      iv        |-> iv,
      payload   |-> payload ]

Collection(items) ==
    [ kind  |-> "Collection",
      items |-> items ]

SignedContent(sig) ==
    sig.content

CipherPayload(cipher) ==
    cipher.payload

PaddedContent(padded) ==
    padded.content

PaddedPadding(padded) ==
    padded.padding

CanDecrypt(cipher, actor) ==
    /\ cipher # NoValue
    /\ cipher.kind = "EncryptedFor"
    /\ cipher.recipient = actor

Decrypt(cipher, actor) ==
    IF CanDecrypt(cipher, actor) THEN cipher.payload ELSE NoValue

ValidSig(sig, signer) ==
    /\ sig # NoValue
    /\ sig.kind = "SignatureOnMessage"
    /\ sig.signer = signer

NonceValue(peer, phase, seq) ==
    [ kind  |-> "Nonce",
      peer  |-> peer,
      phase |-> phase,
      seq   |-> seq ]

SafePaddingPlaintext(peer, stage, seq) ==
    [ kind  |-> "SafePaddingPlaintext",
      peer  |-> peer,
      stage |-> stage,
      seq   |-> seq ]

IsSafePaddingPlaintextForPeer(peer, plaintext) ==
    /\ plaintext # NoValue
    /\ plaintext.kind = "SafePaddingPlaintext"
    /\ plaintext.peer = peer

DuressColumnValueFunctions ==
    { values \in [DuressValues -> DuressValues] :
        \A value \in DuressValues :
            \E index \in DuressValues : values[index] = value }

MakeDuressCheckSpace(peer, stage, seq, spaceMap) ==
    [ kind  |-> "DuressCheckSpace",
      peer  |-> peer,
      stage |-> stage,
      seq   |-> seq,
      space |-> spaceMap ]

DuressCheckSpaces(peer, stage, seq) ==
    { MakeDuressCheckSpace(peer, stage, seq, spaceMap) :
        spaceMap \in [1..5 -> DuressColumnValueFunctions] }

DuressSignalIndex(peer, stage, seq, selectedIndices) ==
    [ kind             |-> "DuressSignalIndex",
      peer             |-> peer,
      stage            |-> stage,
      seq              |-> seq,
      selected_indices |-> selectedIndices ]

IndexOfValueInSpace(space, column, value) ==
    CHOOSE index \in DuressValues : space.space[column][index] = value

BuildDuressSignalIndex(space, honest, consentSet) ==
    DuressSignalIndex(
        space.peer,
        space.stage,
        space.seq,
        [column \in 1..5 |->
            IF honest
            THEN IndexOfValueInSpace(space, column, consentSet[column])
            ELSE CHOOSE index \in DuressValues : space.space[column][index] # consentSet[column]])

DuressSignalIndexMatchesSpace(space, signalIndex) ==
    /\ space.kind = "DuressCheckSpace"
    /\ signalIndex.kind = "DuressSignalIndex"
    /\ signalIndex.peer = space.peer
    /\ signalIndex.stage = space.stage
    /\ signalIndex.seq = space.seq
    /\ signalIndex.selected_indices \in [1..5 -> DuressValues]

DerivedDuressSignal(space, signalIndex) ==
    [column \in 1..5 |-> space.space[column][signalIndex.selected_indices[column]]]

FreshWithin(sentHeight, observedHeight, tolerance) ==
    /\ sentHeight \in Nat
    /\ observedHeight \in Nat
    /\ sentHeight <= observedHeight
    /\ observedHeight <= sentHeight + tolerance

Max2(a, b) ==
    IF a >= b THEN a ELSE b

Min2(a, b) ==
    IF a <= b THEN a ELSE b

BasePsbtOf(psbtLike) ==
    IF psbtLike = NoValue
    THEN NoValue
    ELSE IF psbtLike.kind = "HydratedPsbt"
         THEN psbtLike.base_psbt
         ELSE psbtLike

HydratedPsbt(basePsbt, txid) ==
    [ kind     |-> "HydratedPsbt",
      base_psbt |-> basePsbt,
      tx_id    |-> txid ]

HydratePsbt(psbtLike) ==
    IF BasePsbtOf(psbtLike) \in PSBTs
    THEN HydratedPsbt(BasePsbtOf(psbtLike), TxOfPsbt[BasePsbtOf(psbtLike)])
    ELSE NoValue

PsbtSatisfiable(psbtLike) ==
    HydratePsbt(psbtLike) # NoValue

HydratedPsbtMatchesCommittedTx(psbtLike, txid) ==
    LET hydrated == HydratePsbt(psbtLike) IN
        /\ hydrated # NoValue
        /\ hydrated.tx_id = txid
        /\ TxOfPsbt[hydrated.base_psbt] = txid

TxApproval(txid, eventHeight) ==
    [ kind               |-> "TxApproval",
      magic              |-> "approved",
      tx_id              |-> txid,
      event_block_height |-> eventHeight ]

WTTxApproval(txid, eventHeight, initiatorIdentity) ==
    [ kind               |-> "WTTxApproval",
      magic              |-> "approved",
      tx_id              |-> txid,
      event_block_height |-> eventHeight,
      initiator_id       |-> initiatorIdentity ]

TxCommit(txid, eventHeight) ==
    [ kind               |-> "TxCommit",
      magic              |-> "commit",
      tx_id              |-> txid,
      event_block_height |-> eventHeight ]

Ping(txid, lastSeenBlock, seq, reachedFlag) ==
    [ kind                 |-> "Ping",
      magic                |-> "ping",
      tx_id                |-> txid,
      last_seen_block      |-> lastSeenBlock,
      ping_seq_num         |-> seq,
      reached_mystery_flag |-> reachedFlag ]

Pong(txid, eventHeight, prevPings) ==
    [ kind               |-> "Pong",
      magic              |-> "pong",
      tx_id              |-> txid,
      event_block_height |-> eventHeight,
      prev_pings         |-> prevPings ]

PubnonceBoom(peer, txid) ==
    [ kind  |-> "PubnonceBoom",
      peer  |-> peer,
      tx_id |-> txid ]

PubnonceNormal(peer, txid) ==
    [ kind  |-> "PubnonceNormal",
      peer  |-> peer,
      tx_id |-> txid ]

PartialSigNormal(peer, txid) ==
    [ kind  |-> "PartialSigNormal",
      peer  |-> peer,
      tx_id |-> txid ]

PartialSigBoom(peer, txid) ==
    [ kind  |-> "PartialSigBoom",
      peer  |-> peer,
      tx_id |-> txid ]

PsbtSigned(peer, txid, psbt) ==
    [ kind  |-> "PsbtSigned",
      peer  |-> peer,
      tx_id |-> txid,
      psbt  |-> psbt ]

Broadcast(txid, signedPsbtCollection) ==
    [ kind               |-> "Broadcast",
      tx_id              |-> txid,
      signed_psbt_bundle |-> signedPsbtCollection ]

ApprovalsBundle(allPeerApprovals, wtApproval) ==
    [ kind                        |-> "ApprovalsBundle",
      all_peer_tx_approvals       |-> Collection(allPeerApprovals),
      wt_tx_approval_signed_by_wt |-> wtApproval ]

ReachedPingsCollection(items) ==
    [ kind  |-> "ReachedPingsCollection",
      items |-> items ]

DoxingDataIdentifier(duressPlaceholderPlaintext) ==
    [ kind                       |-> "DoxingDataIdentifier",
      duress_placeholder_payload |-> duressPlaceholderPlaintext ]

TxIdChallengeCipher(peer, txid, nonce) ==
    EncryptedFor(
        STActor(peer),
        BoomletActor(peer),
        [phase |-> "txid_challenge", peer |-> peer, nonce |-> nonce],
        MessageWithNonce(txid, nonce))

TxIdAckCipher(peer, txid, nonce) ==
    EncryptedFor(
        BoomletActor(peer),
        STActor(peer),
        [phase |-> "txid_ack", peer |-> peer, nonce |-> nonce],
        SignatureOnMessage(STActor(peer), MessageWithNonce(txid, nonce)))

DuressCheckCipher(space, nonce) ==
    EncryptedFor(
        STActor(space.peer),
        BoomletActor(space.peer),
        [phase |-> "duress_check", stage |-> space.stage, peer |-> space.peer, seq |-> space.seq, nonce |-> nonce],
        MessageWithNonce(space, nonce))

DuressReplyCipher(peer, stage, seq, nonce, signalIndex) ==
    EncryptedFor(
        BoomletActor(peer),
        STActor(peer),
        [phase |-> "duress_reply", stage |-> stage, peer |-> peer, seq |-> seq, nonce |-> nonce],
        MessageWithNonce(signalIndex, nonce))

SignedTxApproval(peer, txid, height) ==
    SignatureOnMessage(BoomletActor(peer), TxApproval(txid, height))

SignedWTTxApproval(txid, height, initiator) ==
    SignatureOnMessage(WTActor, WTTxApproval(txid, height, BoomletActor(initiator)))

ApprovalCipherForWT(peer, txid, height) ==
    EncryptedFor(
        WTActor,
        BoomletActor(peer),
        [phase |-> "tx_approval", peer |-> peer, tx_id |-> txid],
        SignedTxApproval(peer, txid, height))

PsbtCipherForPeer(fromPeer, toPeer, psbt, txid) ==
    EncryptedFor(
        BoomletActor(toPeer),
        BoomletActor(fromPeer),
        [phase |-> "psbt_fanout", from |-> fromPeer, to |-> toPeer, tx_id |-> txid],
        psbt)

PlaceholderCipherForSAR(peer, stage, seq, plaintext) ==
    EncryptedFor(
        SARActor(peer),
        BoomletActor(peer),
        [phase |-> stage, seq |-> seq, peer |-> peer],
        plaintext)

SignedCommitInner(peer, txid, height) ==
    SignatureOnMessage(BoomletActor(peer), TxCommit(txid, height))

CommitCipherForWT(peer, txid, height, placeholderCipher) ==
    EncryptedFor(
        WTActor,
        BoomletActor(peer),
        [phase |-> "commit", peer |-> peer, tx_id |-> txid],
        SignatureOnMessage(
            BoomletActor(peer),
            PaddedMessage(SignedCommitInner(peer, txid, height), placeholderCipher)))

SignedPingInner(peer, txid, lastSeenBlock, seq, reachedFlag) ==
    SignatureOnMessage(BoomletActor(peer), Ping(txid, lastSeenBlock, seq, reachedFlag))

PingCipherForWT(peer, txid, lastSeenBlock, seq, reachedFlag, placeholderCipher) ==
    EncryptedFor(
        WTActor,
        BoomletActor(peer),
        [phase |-> "ping", peer |-> peer, seq |-> seq, tx_id |-> txid],
        SignatureOnMessage(
            BoomletActor(peer),
            PaddedMessage(SignedPingInner(peer, txid, lastSeenBlock, seq, reachedFlag), placeholderCipher)))

PongCipherForPeer(peer, txid, wtHeight, prevPings) ==
    EncryptedFor(
        BoomletActor(peer),
        WTActor,
        [phase |-> "pong", peer |-> peer, tx_id |-> txid, height |-> wtHeight],
        SignatureOnMessage(
            WTActor,
            Pong(txid, wtHeight, Collection(prevPings))))

SARReplyCipher(peer, placeholderCipher) ==
    EncryptedFor(
        BoomletActor(peer),
        SARActor(peer),
        [phase |-> "sar_reply", peer |-> peer, iv |-> placeholderCipher.iv],
        SignatureOnMessage(SARActor(peer), placeholderCipher))

TxIdAckValid(peer, txid, nonce, ackCipher) ==
    /\ CanDecrypt(ackCipher, BoomletActor(peer))
    /\ LET signedAck == Decrypt(ackCipher, BoomletActor(peer)) IN
       /\ ValidSig(signedAck, STActor(peer))
       /\ SignedContent(signedAck) = MessageWithNonce(txid, nonce)

DuressReplyMatchesSpace(peer, space, stage, seq, nonce, replyCipher) ==
    /\ CanDecrypt(replyCipher, BoomletActor(peer))
    /\ LET reply == Decrypt(replyCipher, BoomletActor(peer)) IN
       /\ reply.kind = "MessageWithNonce"
       /\ reply.nonce = nonce
       /\ reply.content.kind = "DuressSignalIndex"
       /\ reply.content.peer = peer
       /\ reply.content.stage = stage
       /\ reply.content.seq = seq
       /\ DuressSignalIndexMatchesSpace(space, reply.content)

TxApprovalSigValid(sig, peer, txid, lower, upper) ==
    /\ ValidSig(sig, BoomletActor(peer))
    /\ SignedContent(sig).kind = "TxApproval"
    /\ SignedContent(sig).magic = "approved"
    /\ SignedContent(sig).tx_id = txid
    /\ lower <= SignedContent(sig).event_block_height
    /\ SignedContent(sig).event_block_height <= upper

WTTxApprovalSigValid(sig, txid, initiator, lower, upper) ==
    /\ ValidSig(sig, WTActor)
    /\ SignedContent(sig).kind = "WTTxApproval"
    /\ SignedContent(sig).magic = "approved"
    /\ SignedContent(sig).tx_id = txid
    /\ SignedContent(sig).initiator_id = BoomletActor(initiator)
    /\ lower <= SignedContent(sig).event_block_height
    /\ SignedContent(sig).event_block_height <= upper

CommitSigValid(sig, peer, txid, lower, upper) ==
    /\ ValidSig(sig, BoomletActor(peer))
    /\ SignedContent(sig).kind = "TxCommit"
    /\ SignedContent(sig).magic = "commit"
    /\ SignedContent(sig).tx_id = txid
    /\ lower <= SignedContent(sig).event_block_height
    /\ SignedContent(sig).event_block_height <= upper

WTSignedCommitValid(sig, peer, txid, lower, upper) ==
    /\ ValidSig(sig, WTActor)
    /\ CommitSigValid(SignedContent(sig), peer, txid, lower, upper)

ReachedPingSigValid(sig, peer, txid) ==
    /\ ValidSig(sig, BoomletActor(peer))
    /\ SignedContent(sig).kind = "Ping"
    /\ SignedContent(sig).magic = "ping"
    /\ SignedContent(sig).tx_id = txid
    /\ SignedContent(sig).reached_mystery_flag

PingSigValid(sig, peer, txid, lower, upper) ==
    /\ ValidSig(sig, BoomletActor(peer))
    /\ SignedContent(sig).kind = "Ping"
    /\ SignedContent(sig).magic = "ping"
    /\ SignedContent(sig).tx_id = txid
    /\ lower <= SignedContent(sig).last_seen_block
    /\ SignedContent(sig).last_seen_block <= upper

PrevPingSeqMonotoneForPeer(prevPings, peer, priorPrevPings) ==
    priorPrevPings = NoValue
    \/ \A j \in (Peers \ {peer}) :
           SignedContent(prevPings[j]).ping_seq_num
           > SignedContent(priorPrevPings[j]).ping_seq_num

ReachedPrevPingsStickyForPeer(prevPings, peer, knownReached) ==
    \A j \in (Peers \ {peer}) :
        ~(j \in knownReached)
        \/ SignedContent(prevPings[j]).reached_mystery_flag

PrevPingsValidForPeer(prevPings, peer, txid, upperHeight, priorPrevPings, knownReached) ==
    /\ \A j \in (Peers \ {peer}) :
         PingSigValid(
             prevPings[j],
             j,
             txid,
             IF upperHeight >= TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_BY_OTHER_PEERS_TO_REVIEWING_THE_PING_IN_PEER_BOOMLET
             THEN upperHeight - TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_BY_OTHER_PEERS_TO_REVIEWING_THE_PING_IN_PEER_BOOMLET
             ELSE 0,
             upperHeight)
    /\ PrevPingSeqMonotoneForPeer(prevPings, peer, priorPrevPings)
    /\ ReachedPrevPingsStickyForPeer(prevPings, peer, knownReached)

PongDeliveryValidForPeer(delivery, peer, txid, upperHeight, priorPrevPings, knownReached) ==
    /\ CanDecrypt(delivery.pong_signed_by_wt_encrypted_by_wt_for_boomlet, BoomletActor(peer))
    /\ LET signedPong == Decrypt(delivery.pong_signed_by_wt_encrypted_by_wt_for_boomlet, BoomletActor(peer)) IN
       /\ ValidSig(signedPong, WTActor)
       /\ SignedContent(signedPong).kind = "Pong"
       /\ SignedContent(signedPong).magic = "pong"
       /\ SignedContent(signedPong).tx_id = txid
       /\ FreshWithin(
            SignedContent(signedPong).event_block_height,
            upperHeight,
            TOLERANCE_IN_BLOCKS_FROM_CREATING_PONG_BY_WT_TO_REVIEWING_THE_PONG_IN_PEERS_BOOMLET)
       /\ PrevPingsValidForPeer(
            SignedContent(signedPong).prev_pings.items,
            peer,
            txid,
            upperHeight,
            priorPrevPings,
            knownReached)

SARReplyValidForPeer(peer, expectedPlaceholderCipher, replyCipher) ==
    /\ CanDecrypt(replyCipher, BoomletActor(peer))
    /\ LET signedPlaceholder == Decrypt(replyCipher, BoomletActor(peer)) IN
       /\ ValidSig(signedPlaceholder, SARActor(peer))
       /\ SignedContent(signedPlaceholder) = expectedPlaceholderCipher

ApprovalsBundleSigValid(sig, peer, allPeerApprovals, wtApproval) ==
    /\ ValidSig(sig, BoomletActor(peer))
    /\ SignedContent(sig) = ApprovalsBundle(allPeerApprovals, wtApproval)

CanIncrementCounter(peer, peerHeight, prevPings, lastSeenBlock) ==
    /\ peerHeight \in Nat
    /\ lastSeenBlock \in Nat
    /\ lastSeenBlock # peerHeight
    /\ \A j \in (Peers \ {peer}) :
         LET pingMsg == SignedContent(prevPings[j]) IN
         /\ pingMsg.kind = "Ping"
         /\ pingMsg.last_seen_block + TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_BY_OTHER_PEERS_TO_REVIEWING_THE_PING_IN_PEER_BOOMLET >= peerHeight
         /\ pingMsg.last_seen_block <= peerHeight

AllReached(reachedPings) ==
    \A i \in Peers : reachedPings[i] # NoValue

AllPeerSignedPsbtsPresent(signeds) ==
    \A i \in Peers : signeds[i] # NoValue

TxIdOutputKind(peer) ==
    IF peer = INITIATOR THEN "WithdrawalStOutput1" ELSE "WithdrawalNonInitiatorStOutput1"

TxIdAckInputKind(peer) ==
    IF peer = INITIATOR THEN "WithdrawalStInput1" ELSE "WithdrawalNonInitiatorStInput1"

InitialDuressOutputKind(peer) ==
    IF peer = INITIATOR THEN "WithdrawalStOutput2" ELSE "WithdrawalNonInitiatorStOutput2"

InitialDuressInputKind(peer) ==
    IF peer = INITIATOR THEN "WithdrawalStInput2" ELSE "WithdrawalNonInitiatorStInput2"

RecurringDuressOutputKind ==
    "WithdrawalStOutput3"

RecurringDuressInputKind ==
    "WithdrawalStInput3"

TxIdUserAckMessage(peer) ==
    IF peer = INITIATOR
    THEN [ kind  |-> "WithdrawalStInput1",
           magic |-> "withdrawal_initiator_peer_approved_that_txid_received_is_the_same_as_the_one_derived_from_withdrawal_psbt" ]
    ELSE [ kind  |-> "WithdrawalNonInitiatorStInput1",
           magic |-> "withdrawal_non_initiator_peer_approved_that_txid_received_is_the_same_as_the_one_derived_from_withdrawal_psbt" ]

WithdrawalNisoInput1(psbt) ==
    [ kind |-> "WithdrawalNisoInput1", psbt |-> psbt ]

WithdrawalNonInitiatorNisoInput1 ==
    [ kind |-> "WithdrawalNonInitiatorNisoInput1",
      magic |-> "withdrawal_non_initiator_peer_approved_the_withdrawal_psbt" ]

WithdrawalNisoInput2 ==
    [ kind |-> "WithdrawalNisoInput2",
      magic |-> "withdrawal_peer_is_informed_that_boomlet_should_be_connected_to_niso" ]

WithdrawalNonInitiatorNisoOutput1(psbt, initiatorPeerId) ==
    [ kind |-> "WithdrawalNonInitiatorNisoOutput1",
      psbt |-> psbt,
      initiator_peer_id |-> initiatorPeerId ]

WithdrawalNisoOutput1 ==
    [ kind |-> "WithdrawalNisoOutput1",
      magic |-> "withdrawal_ready_to_sign_received_connect_boomlet_to_iso" ]

WithdrawalIsoInput1 ==
    [ kind |-> "WithdrawalIsoInput1",
      network |-> "network",
      mnemonic |-> "mnemonic",
      passphrase |-> "passphrase" ]

WithdrawalIsoOutput1 ==
    [ kind |-> "WithdrawalIsoOutput1",
      magic |-> "withdrawal_psbt_signature_created_connect_boomlet_to_niso" ]

WithdrawalNisoBoomletMessage1(psbt, nisoHeight) ==
    [ kind |-> "WithdrawalNisoBoomletMessage1",
      psbt |-> psbt,
      niso_0_event_block_height |-> nisoHeight ]

WithdrawalBoomletNisoMessage1(cipher) ==
    [ kind |-> "WithdrawalBoomletNisoMessage1",
      tx_id_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalNisoStMessage1(peer, cipher) ==
    [ kind |-> IF peer = INITIATOR THEN "WithdrawalNisoStMessage1" ELSE "WithdrawalNonInitiatorNisoStMessage1",
      tx_id_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalStOutput1(peer, txid) ==
    [ kind |-> TxIdOutputKind(peer),
      tx_id |-> txid ]

WithdrawalStNisoMessage1(peer, ackCipher) ==
    [ kind |-> IF peer = INITIATOR THEN "WithdrawalStNisoMessage1" ELSE "WithdrawalNonInitiatorStNisoMessage1",
      tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet |-> ackCipher ]

WithdrawalNisoBoomletMessage2(ackCipher) ==
    [ kind |-> "WithdrawalNisoBoomletMessage2",
      tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet |-> ackCipher ]

WithdrawalBoomletNisoMessage2(approvalCipher, psbtCollection) ==
    [ kind |-> "WithdrawalBoomletNisoMessage2",
      initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt |-> approvalCipher,
      psbt_encrypted_collection |-> psbtCollection ]

WithdrawalNisoWtMessage1(approvalCipher, psbtCollection) ==
    [ kind |-> "WithdrawalNisoWtMessage1",
      initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt |-> approvalCipher,
      psbt_encrypted_collection |-> psbtCollection ]

WithdrawalWtNonInitiatorNisoMessage1(wtApproval, initiatorApproval, psbtCipher) ==
    [ kind |-> "WithdrawalWtNonInitiatorNisoMessage1",
      wt_tx_approval_signed_by_wt |-> wtApproval,
      peer_0_tx_approval_signed_by_boomlet_0 |-> initiatorApproval,
      psbt_encrypted_by_boomlet_0_for_boomlet_i |-> psbtCipher ]

WithdrawalNonInitiatorNisoBoomletMessage1(wtApproval, initiatorApproval, psbtCipher, nisoHeight) ==
    [ kind |-> "WithdrawalNonInitiatorNisoBoomletMessage1",
      wt_tx_approval_signed_by_wt |-> wtApproval,
      peer_0_tx_approval_signed_by_boomlet_0 |-> initiatorApproval,
      psbt_encrypted_by_boomlet_0_for_boomlet_i |-> psbtCipher,
      niso_1_event_block_height |-> nisoHeight ]

WithdrawalNonInitiatorBoomletNisoMessage1(psbt) ==
    [ kind |-> "WithdrawalNonInitiatorBoomletNisoMessage1",
      psbt |-> psbt ]

WithdrawalNonInitiatorNisoBoomletMessage2 ==
    [ kind |-> "WithdrawalNonInitiatorNisoBoomletMessage2",
      magic |-> "withdrawal_peer_agreement_with_psbt_received" ]

WithdrawalNonInitiatorBoomletNisoMessage2(cipher) ==
    [ kind |-> "WithdrawalNonInitiatorBoomletNisoMessage2",
      tx_id_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalNonInitiatorNisoBoomletMessage3(ackCipher, nisoHeight) ==
    [ kind |-> "WithdrawalNonInitiatorNisoBoomletMessage3",
      tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet |-> ackCipher,
      niso_1_event_block_height |-> nisoHeight ]

WithdrawalNonInitiatorBoomletNisoMessage3(approvalCipher) ==
    [ kind |-> "WithdrawalNonInitiatorBoomletNisoMessage3",
      peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt |-> approvalCipher ]

WithdrawalNonInitiatorNisoWtMessage1(approvalCipher) ==
    [ kind |-> "WithdrawalNonInitiatorNisoWtMessage1",
      peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt |-> approvalCipher ]

WithdrawalWtNisoMessage1(allPeerApprovals, wtApproval) ==
    [ kind |-> "WithdrawalWtNisoMessage1",
      all_peer_tx_approvals |-> allPeerApprovals,
      wt_tx_approval_signed_by_wt |-> wtApproval ]

WithdrawalWtNonInitiatorNisoMessage2(nonInitiatorApprovals) ==
    [ kind |-> "WithdrawalWtNonInitiatorNisoMessage2",
      non_initiator_tx_approvals |-> nonInitiatorApprovals ]

WithdrawalNisoBoomletMessage3(allPeerApprovals, wtApproval, nisoHeight) ==
    [ kind |-> "WithdrawalNisoBoomletMessage3",
      all_peer_tx_approvals |-> allPeerApprovals,
      wt_tx_approval_signed_by_wt |-> wtApproval,
      niso_0_event_block_height |-> nisoHeight ]

WithdrawalNonInitiatorNisoBoomletMessage4(nonInitiatorApprovals, nisoHeight) ==
    [ kind |-> "WithdrawalNonInitiatorNisoBoomletMessage4",
      non_initiator_tx_approvals |-> nonInitiatorApprovals,
      niso_1_event_block_height |-> nisoHeight ]

WithdrawalBoomletNisoMessage3(cipher) ==
    [ kind |-> "WithdrawalBoomletNisoMessage3",
      duress_check_space_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalNonInitiatorBoomletNisoMessage4(cipher) ==
    [ kind |-> "WithdrawalNonInitiatorBoomletNisoMessage4",
      duress_check_space_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalNisoStMessage2(peer, cipher) ==
    [ kind |-> IF peer = INITIATOR THEN "WithdrawalNisoStMessage2" ELSE "WithdrawalNonInitiatorNisoStMessage2",
      duress_check_space_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalStOutput2(peer, space, stage, seq) ==
    [ kind |-> InitialDuressOutputKind(peer),
      duress_check_space |-> space,
      stage |-> stage,
      seq |-> seq ]

WithdrawalStOutput3(space, stage, seq) ==
    [ kind |-> "WithdrawalStOutput3",
      duress_check_space |-> space,
      stage |-> stage,
      seq |-> seq ]

WithdrawalStNisoMessage2(peer, replyCipher) ==
    [ kind |-> IF peer = INITIATOR THEN "WithdrawalStNisoMessage2" ELSE "WithdrawalNonInitiatorStNisoMessage2",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet |-> replyCipher ]

WithdrawalStNisoMessage3(replyCipher) ==
    [ kind |-> "WithdrawalStNisoMessage3",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet |-> replyCipher ]

WithdrawalNisoBoomletMessage4(replyCipher) ==
    [ kind |-> "WithdrawalNisoBoomletMessage4",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet |-> replyCipher ]

WithdrawalNonInitiatorNisoBoomletMessage5(replyCipher) ==
    [ kind |-> "WithdrawalNonInitiatorNisoBoomletMessage5",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet |-> replyCipher ]

WithdrawalBoomletNisoMessage4(commitCipher) ==
    [ kind |-> "WithdrawalBoomletNisoMessage4",
      peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt |-> commitCipher ]

WithdrawalNisoWtMessage2(commitCipher) ==
    [ kind |-> "WithdrawalNisoWtMessage2",
      peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt |-> commitCipher ]

WithdrawalNonInitiatorBoomletNisoMessage5(approvalsSigned) ==
    [ kind |-> "WithdrawalNonInitiatorBoomletNisoMessage5",
      approvals_signed_by_boomlet_i |-> approvalsSigned ]

WithdrawalNonInitiatorNisoWtMessage2(approvalsSigned) ==
    [ kind |-> "WithdrawalNonInitiatorNisoWtMessage2",
      approvals_signed_by_boomlet_i |-> approvalsSigned ]

WithdrawalWtSarsMessage1(placeholderCipher, boomletIdentity) ==
    [ kind |-> "WithdrawalWtSarsMessage1",
      duress_placeholder |-> placeholderCipher,
      boomlet_identity_pubkey |-> boomletIdentity ]

WithdrawalNonInitiatorWtSarsMessage1(placeholderCipher, boomletIdentity) ==
    [ kind |-> "WithdrawalNonInitiatorWtSarsMessage1",
      duress_placeholder |-> placeholderCipher,
      boomlet_identity_pubkey |-> boomletIdentity ]

WithdrawalWtSarsMessage2(placeholderCipher, boomletIdentity) ==
    [ kind |-> "WithdrawalWtSarsMessage2",
      duress_placeholder |-> placeholderCipher,
      boomlet_identity_pubkey |-> boomletIdentity ]

WithdrawalSarsWtMessage1(replyCipher) ==
    [ kind |-> "WithdrawalSarsWtMessage1",
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> replyCipher ]

WithdrawalNonInitiatorSarsWtMessage1(replyCipher) ==
    [ kind |-> "WithdrawalNonInitiatorSarsWtMessage1",
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> replyCipher ]

WithdrawalSarsWtMessage2(replyCipher) ==
    [ kind |-> "WithdrawalSarsWtMessage2",
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> replyCipher ]

WithdrawalWtNonInitiatorNisoMessage3(initiatorCommitSignedByWT) ==
    [ kind |-> "WithdrawalWtNonInitiatorNisoMessage3",
      peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt |-> initiatorCommitSignedByWT ]

WithdrawalNonInitiatorNisoBoomletMessage6(initiatorCommitSignedByWT, nisoHeight) ==
    [ kind |-> "WithdrawalNonInitiatorNisoBoomletMessage6",
      peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt |-> initiatorCommitSignedByWT,
      niso_1_event_block_height |-> nisoHeight ]

WithdrawalNonInitiatorBoomletNisoMessage6(commitCipher) ==
    [ kind |-> "WithdrawalNonInitiatorBoomletNisoMessage6",
      peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt |-> commitCipher ]

WithdrawalNonInitiatorNisoWtMessage3(commitCipher) ==
    [ kind |-> "WithdrawalNonInitiatorNisoWtMessage3",
      peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt |-> commitCipher ]

WithdrawalWtNisoMessage2(commitCollection, sarReply) ==
    [ kind |-> "WithdrawalWtNisoMessage2",
      all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt |-> commitCollection,
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> sarReply ]

WithdrawalWtNonInitiatorNisoMessage4(commitCollection, sarReply) ==
    [ kind |-> "WithdrawalWtNonInitiatorNisoMessage4",
      all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt |-> commitCollection,
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> sarReply ]

WithdrawalNisoBoomletMessage5(commitCollection, sarReply, nisoHeight) ==
    [ kind |-> "WithdrawalNisoBoomletMessage5",
      all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt |-> commitCollection,
      niso_0_event_block_height |-> nisoHeight,
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> sarReply ]

WithdrawalBoomletNisoMessage5(pingCipher) ==
    [ kind |-> "WithdrawalBoomletNisoMessage5",
      peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt |-> pingCipher ]

WithdrawalBoomletNisoMessage6(cipher) ==
    [ kind |-> "WithdrawalBoomletNisoMessage6",
      duress_check_space_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalNisoStMessage3(cipher) ==
    [ kind |-> "WithdrawalNisoStMessage3",
      duress_check_space_with_nonce_encrypted_by_boomlet_for_st |-> cipher ]

WithdrawalNisoBoomletMessage6(pongCipher, sarReply, nisoHeight) ==
    [ kind |-> "WithdrawalNisoBoomletMessage6",
      pong_signed_by_wt_encrypted_by_wt_for_boomlet |-> pongCipher,
      niso_0_event_block_height |-> nisoHeight,
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> sarReply ]

WithdrawalNisoBoomletMessage7(replyCipher) ==
    [ kind |-> "WithdrawalNisoBoomletMessage7",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet |-> replyCipher ]

WithdrawalBoomletNisoMessage7(pingCipher) ==
    [ kind |-> "WithdrawalBoomletNisoMessage7",
      peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt |-> pingCipher ]

PingToWTMessage(peer, recurring, pingCipher) ==
    [ kind |->
          IF peer = INITIATOR
          THEN IF recurring THEN "WithdrawalNisoWtMessage4" ELSE "WithdrawalNisoWtMessage3"
          ELSE "WithdrawalNonInitiatorNisoWtMessage4",
      peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt |-> pingCipher ]

WithdrawalWtNisoMessage3(pongCipher, sarReply) ==
    [ kind |-> "WithdrawalWtNisoMessage3",
      pong_signed_by_wt_encrypted_by_wt_for_boomlet |-> pongCipher,
      duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet |-> sarReply ]

WithdrawalWtNisoMessage4(reachedCollection) ==
    [ kind |-> "WithdrawalWtNisoMessage4",
      reached_pings_collection |-> reachedCollection ]

WithdrawalNisoBoomletMessage8(reachedCollection, hydratedPsbt) ==
    [ kind |-> "WithdrawalNisoBoomletMessage8",
      reached_pings_collection |-> reachedCollection,
      hydrated_psbt |-> hydratedPsbt ]

WithdrawalBoomletNisoMessage8 ==
    [ kind |-> "WithdrawalBoomletNisoMessage8",
      magic |-> "withdrawal_ready_to_sign" ]

WithdrawalNisoBoomletMessage9 ==
    [ kind |-> "WithdrawalNisoBoomletMessage9",
      magic |-> "withdrawal_signing_finished_export_signed_psbt" ]

WithdrawalBoomletNisoMessage9(psbtSigned) ==
    [ kind |-> "WithdrawalBoomletNisoMessage9",
      psbt_signed_i |-> psbtSigned ]

WithdrawalNisoWtMessage5(psbtSigned) ==
    [ kind |-> "WithdrawalNisoWtMessage5",
      psbt_signed_i |-> psbtSigned ]

WithdrawalIsoBoomletMessage1 ==
    [ kind |-> "WithdrawalIsoBoomletMessage1",
      magic |-> "withdrawal_initialized_start_signing" ]

WithdrawalBoomletIsoMessage1(psbt, descriptor, pubkeyShare, pubnonceBoom) ==
    [ kind |-> "WithdrawalBoomletIsoMessage1",
      psbt |-> psbt,
      boomerang_descriptor |-> descriptor,
      boomlet_boom_musig2_pubkey_share |-> pubkeyShare,
      pubnonce_boom |-> pubnonceBoom ]

WithdrawalIsoBoomletMessage2(pubnonceNormal, partialsigNormal) ==
    [ kind |-> "WithdrawalIsoBoomletMessage2",
      pubnonce_normal |-> pubnonceNormal,
      partialsig_normal |-> partialsigNormal ]

WithdrawalBoomletIsoMessage2(partialsigBoom) ==
    [ kind |-> "WithdrawalBoomletIsoMessage2",
      partialsig_boom |-> partialsigBoom ]

CanonicalWireMessageKinds ==
    {
      "WithdrawalNisoInput1",
      "WithdrawalNonInitiatorNisoInput1",
      "WithdrawalNisoInput2",
      "WithdrawalNonInitiatorNisoOutput1",
      "WithdrawalNisoOutput1",
      "WithdrawalIsoInput1",
      "WithdrawalIsoOutput1",
      "WithdrawalNisoBoomletMessage1",
      "WithdrawalBoomletNisoMessage1",
      "WithdrawalNisoStMessage1",
      "WithdrawalNonInitiatorNisoStMessage1",
      "WithdrawalStOutput1",
      "WithdrawalNonInitiatorStOutput1",
      "WithdrawalStInput1",
      "WithdrawalNonInitiatorStInput1",
      "WithdrawalStNisoMessage1",
      "WithdrawalNonInitiatorStNisoMessage1",
      "WithdrawalNisoBoomletMessage2",
      "WithdrawalBoomletNisoMessage2",
      "WithdrawalNisoWtMessage1",
      "WithdrawalWtNonInitiatorNisoMessage1",
      "WithdrawalNonInitiatorNisoBoomletMessage1",
      "WithdrawalNonInitiatorBoomletNisoMessage1",
      "WithdrawalNonInitiatorNisoBoomletMessage2",
      "WithdrawalNonInitiatorBoomletNisoMessage2",
      "WithdrawalNonInitiatorNisoBoomletMessage3",
      "WithdrawalNonInitiatorBoomletNisoMessage3",
      "WithdrawalNonInitiatorNisoWtMessage1",
      "WithdrawalWtNisoMessage1",
      "WithdrawalWtNonInitiatorNisoMessage2",
      "WithdrawalNisoBoomletMessage3",
      "WithdrawalNonInitiatorNisoBoomletMessage4",
      "WithdrawalBoomletNisoMessage3",
      "WithdrawalNonInitiatorBoomletNisoMessage4",
      "WithdrawalNisoStMessage2",
      "WithdrawalNonInitiatorNisoStMessage2",
      "WithdrawalStOutput2",
      "WithdrawalNonInitiatorStOutput2",
      "WithdrawalStOutput3",
      "WithdrawalStInput2",
      "WithdrawalNonInitiatorStInput2",
      "WithdrawalStInput3",
      "WithdrawalStNisoMessage2",
      "WithdrawalNonInitiatorStNisoMessage2",
      "WithdrawalStNisoMessage3",
      "WithdrawalNisoBoomletMessage4",
      "WithdrawalNonInitiatorNisoBoomletMessage5",
      "WithdrawalBoomletNisoMessage4",
      "WithdrawalNisoWtMessage2",
      "WithdrawalNonInitiatorBoomletNisoMessage5",
      "WithdrawalNonInitiatorNisoWtMessage2",
      "WithdrawalWtSarsMessage1",
      "WithdrawalNonInitiatorWtSarsMessage1",
      "WithdrawalWtSarsMessage2",
      "WithdrawalSarsWtMessage1",
      "WithdrawalNonInitiatorSarsWtMessage1",
      "WithdrawalSarsWtMessage2",
      "WithdrawalWtNonInitiatorNisoMessage3",
      "WithdrawalNonInitiatorNisoBoomletMessage6",
      "WithdrawalNonInitiatorBoomletNisoMessage6",
      "WithdrawalNonInitiatorNisoWtMessage3",
      "WithdrawalWtNisoMessage2",
      "WithdrawalWtNonInitiatorNisoMessage4",
      "WithdrawalNisoBoomletMessage5",
      "WithdrawalBoomletNisoMessage5",
      "WithdrawalBoomletNisoMessage6",
      "WithdrawalNisoStMessage3",
      "WithdrawalNisoBoomletMessage6",
      "WithdrawalNisoBoomletMessage7",
      "WithdrawalBoomletNisoMessage7",
      "WithdrawalNisoWtMessage3",
      "WithdrawalNisoWtMessage4",
      "WithdrawalNonInitiatorNisoWtMessage4",
      "WithdrawalWtNisoMessage3",
      "WithdrawalWtNisoMessage4",
      "WithdrawalNisoBoomletMessage8",
      "WithdrawalBoomletNisoMessage8",
      "WithdrawalNisoBoomletMessage9",
      "WithdrawalBoomletNisoMessage9",
      "WithdrawalNisoWtMessage5",
      "WithdrawalIsoBoomletMessage1",
      "WithdrawalBoomletIsoMessage1",
      "WithdrawalIsoBoomletMessage2",
      "WithdrawalBoomletIsoMessage2"
    }

(*--algorithm WithdrawalWireFaithful
variables
    wire_trace = {},
    boomerang_descriptor = [milestone_block_0 |-> Milestone0],
    peer_id_collection = { BoomletActor(i) : i \in Peers },
    st_identity_pubkey_i = [i \in Peers |-> STActor(i)],
    sar_pubkey_i = [i \in Peers |-> SARActor(i)],
    doxing_key_i = InitDoxingKey,
    duress_consent_set_i = InitConsentSet,
    boomlet_mystery_i = InitMystery,
    most_work_bitcoin_block_height = Milestone0,

    user_saved_psbt_i = [i \in Peers |-> IF i = INITIATOR THEN CanonicalPsbt ELSE NoValue],
    user_initiator_peer_id_i = [i \in Peers |-> NoValue],
    user_last_duress_space_i = [i \in Peers |-> NoValue],
    user_sent_initial_psbt_i = [i \in Peers |-> FALSE],
    user_sent_psbt_agreement_i = [i \in Peers |-> FALSE],
    user_sent_iso_credentials_i = [i \in Peers |-> FALSE],
    user_sent_connect_back_to_niso_i = [i \in Peers |-> FALSE],

    niso_saved_psbt_i = [i \in Peers |-> NoValue],
    niso_saved_tx_id_i = [i \in Peers |-> NoValue],
    niso_event_block_height_i = [i \in Peers |-> Milestone0],
    niso_initiator_peer_id_i = [i \in Peers |-> NoValue],
    niso_saved_wt_tx_approval_i = [i \in Peers |-> NoValue],
    niso_hydrated_psbt_i = [i \in Peers |-> NoValue],
    niso_reached_pings_collection_i = [i \in Peers |-> NoValue],

    boomlet_saved_psbt_i = [i \in Peers |-> NoValue],
    boomlet_committed_tx_id_i = [i \in Peers |-> NoValue],
    boomlet_pending_txid_nonce_i = [i \in Peers |-> NoValue],
    boomlet_saved_duress_space_i = [i \in Peers |-> NoValue],
    boomlet_saved_duress_stage_i = [i \in Peers |-> NoValue],
    boomlet_saved_duress_seq_i = [i \in Peers |-> 0],
    boomlet_pending_duress_nonce_i = [i \in Peers |-> NoValue],
    boomlet_duress_placeholder_plaintext_i = [i \in Peers |-> NoValue],
    boomlet_duress_placeholder_cipher_i = [i \in Peers |-> NoValue],
    boomlet_signed_tx_approval_i = [i \in Peers |-> NoValue],
    boomlet_saved_wt_tx_approval_i = [i \in Peers |-> NoValue],
    boomlet_all_peer_approvals_i = [i \in Peers |-> NoValue],
    boomlet_approvals_bundle_i = [i \in Peers |-> NoValue],
    boomlet_signed_commit_inner_i = [i \in Peers |-> NoValue],
    boomlet_commit_collection_i = [i \in Peers |-> NoValue],
    boomlet_counter_i = [i \in Peers |-> 0],
    boomlet_last_seen_block_i = [i \in Peers |-> Milestone0],
    boomlet_ping_seq_num_i = [i \in Peers |-> 0],
    boomlet_reached_mystery_flag_i = [i \in Peers |-> FALSE],
    boomlet_known_reached_i = [i \in Peers |-> {}],
    boomlet_prev_pings_i = [i \in Peers |-> NoValue],
    boomlet_ready_to_sign_i = [i \in Peers |-> FALSE],
    boomlet_signed_psbt_i = [i \in Peers |-> NoValue],
    boomlet_pubnonce_boom_i = [i \in Peers |-> NoValue],
    boomlet_partialsig_boom_i = [i \in Peers |-> NoValue],

    st_last_txid_with_nonce_i = [i \in Peers |-> NoValue],
    st_last_duress_check_i = [i \in Peers |-> NoValue],

    iso_pubnonce_normal_i = [i \in Peers |-> NoValue],
    iso_partialsig_normal_i = [i \in Peers |-> NoValue],
    iso_signed_psbt_i = [i \in Peers |-> NoValue],

    sar_seen_placeholder_iv_i = [i \in Peers |-> {}],
    sar_escalated_i = [i \in Peers |-> FALSE],
    sar_last_doxing_identifier_i = [i \in Peers |-> NoValue],

    wt_saved_tx_id = NoValue,
    wt_saved_wt_tx_approval = NoValue,
    wt_initiator_tx_approval = NoValue,
    wt_noninitiator_tx_approval_i = [i \in Peers |-> NoValue],
    wt_approvals_bundle_i = [i \in Peers |-> NoValue],
    wt_pending_sar_stage_i = [i \in Peers |-> NoValue],
    wt_pending_placeholder_i = [i \in Peers |-> NoValue],
    wt_pending_signed_inner_i = [i \in Peers |-> NoValue],
    wt_commit_sar_reply_i = [i \in Peers |-> NoValue],
    wt_ping_sar_reply_i = [i \in Peers |-> NoValue],
    wt_signed_commit_i = [i \in Peers |-> NoValue],
    wt_last_accepted_ping_i = [i \in Peers |-> NoValue],
    wt_reached_pings_collection = [i \in Peers |-> NoValue],
    wt_last_pong_height = NoValue,
    wt_relayed_all_approvals = FALSE,
    wt_relayed_all_commits = FALSE,
    wt_signed_psbt_i = [i \in Peers |-> NoValue],
    wt_broadcast = NoValue,

    user_to_niso = [i \in Peers |-> NoValue],
    niso_to_user = [i \in Peers |-> NoValue],
    user_to_st = [i \in Peers |-> NoValue],
    st_to_user = [i \in Peers |-> NoValue],
    boomlet_to_niso = [i \in Peers |-> NoValue],
    niso_to_boomlet = [i \in Peers |-> NoValue],
    niso_to_st = [i \in Peers |-> NoValue],
    st_to_niso = [i \in Peers |-> NoValue],
    user_to_iso = [i \in Peers |-> NoValue],
    iso_to_user = [i \in Peers |-> NoValue],
    boomlet_to_iso = [i \in Peers |-> NoValue],
    iso_to_boomlet = [i \in Peers |-> NoValue],
    niso_to_wt = [i \in Peers |-> NoValue],
    wt_to_niso = [i \in Peers |-> NoValue],
    wt_to_sar = [i \in Peers |-> NoValue],
    sar_to_wt = [i \in Peers |-> NoValue];

process UserFlow \in Peers
variables msg = NoValue,
          signalIndex = NoValue;
begin
UserLoop:
    await (self = INITIATOR /\ ~user_sent_initial_psbt_i[self] /\ user_to_niso[self] = NoValue)
       \/ st_to_user[self] # NoValue
       \/ niso_to_user[self] # NoValue
       \/ iso_to_user[self] # NoValue;
    if self = INITIATOR /\ ~user_sent_initial_psbt_i[self] /\ user_to_niso[self] = NoValue then
        user_to_niso[self] := WithdrawalNisoInput1(CanonicalPsbt);
        user_sent_initial_psbt_i[self] := TRUE;
        wire_trace := wire_trace \cup { WireHop(UserActor(self), NisoActor(self), WithdrawalNisoInput1(CanonicalPsbt)) };
    elsif st_to_user[self] # NoValue then
        msg := st_to_user[self];
        st_to_user[self] := NoValue;
        if msg.kind = TxIdOutputKind(self) then
            assert msg.tx_id = TxOfPsbt[user_saved_psbt_i[self]];
            assert user_to_st[self] = NoValue;
            user_to_st[self] := TxIdUserAckMessage(self);
            wire_trace := wire_trace \cup { WireHop(UserActor(self), STActor(self), TxIdUserAckMessage(self)) };
        elsif msg.kind \in {InitialDuressOutputKind(self), RecurringDuressOutputKind} then
            user_last_duress_space_i[self] := msg.duress_check_space;
            signalIndex := BuildDuressSignalIndex(msg.duress_check_space, TRUE, duress_consent_set_i[self]);
            assert user_to_st[self] = NoValue;
            user_to_st[self] :=
                [ kind |-> IF msg.kind = RecurringDuressOutputKind THEN RecurringDuressInputKind ELSE InitialDuressInputKind(self),
                  duress_signal_index |-> signalIndex,
                  stage |-> msg.stage,
                  seq |-> msg.seq ];
            wire_trace := wire_trace \cup
                { WireHop(UserActor(self), STActor(self),
                    [ kind |-> IF msg.kind = RecurringDuressOutputKind THEN RecurringDuressInputKind ELSE InitialDuressInputKind(self),
                      duress_signal_index |-> signalIndex,
                      stage |-> msg.stage,
                      seq |-> msg.seq ]) };
        end if;
    elsif niso_to_user[self] # NoValue then
        msg := niso_to_user[self];
        niso_to_user[self] := NoValue;
        if msg.kind = "WithdrawalNonInitiatorNisoOutput1" then
            user_saved_psbt_i[self] := msg.psbt;
            user_initiator_peer_id_i[self] := msg.initiator_peer_id;
            assert user_to_niso[self] = NoValue;
            user_to_niso[self] := WithdrawalNonInitiatorNisoInput1;
            user_sent_psbt_agreement_i[self] := TRUE;
            wire_trace := wire_trace \cup { WireHop(UserActor(self), NisoActor(self), WithdrawalNonInitiatorNisoInput1) };
        elsif msg.kind = "WithdrawalNisoOutput1" then
            assert user_to_iso[self] = NoValue;
            user_to_iso[self] := WithdrawalIsoInput1;
            user_sent_iso_credentials_i[self] := TRUE;
            wire_trace := wire_trace \cup { WireHop(UserActor(self), IsoActor(self), WithdrawalIsoInput1) };
        end if;
    else
        msg := iso_to_user[self];
        iso_to_user[self] := NoValue;
        if msg.kind = "WithdrawalIsoOutput1" then
            assert user_to_niso[self] = NoValue;
            user_to_niso[self] := WithdrawalNisoInput2;
            user_sent_connect_back_to_niso_i[self] := TRUE;
            wire_trace := wire_trace \cup { WireHop(UserActor(self), NisoActor(self), WithdrawalNisoInput2) };
        end if;
    end if;
    goto UserLoop;
end process;

process STFlow \in Peers
variables msg = NoValue,
          nonceWrapped = NoValue,
          signalIndex = NoValue;
begin
STLoop:
    await niso_to_st[self] # NoValue \/ user_to_st[self] # NoValue;
    if niso_to_st[self] # NoValue then
        msg := niso_to_st[self];
        niso_to_st[self] := NoValue;
        if msg.kind \in {"WithdrawalNisoStMessage1", "WithdrawalNonInitiatorNisoStMessage1"} then
            nonceWrapped := Decrypt(msg.tx_id_with_nonce_encrypted_by_boomlet_for_st, STActor(self));
            assert nonceWrapped # NoValue;
            st_last_txid_with_nonce_i[self] := nonceWrapped;
            assert st_to_user[self] = NoValue;
            st_to_user[self] := WithdrawalStOutput1(self, nonceWrapped.content);
            wire_trace := wire_trace \cup { WireHop(STActor(self), UserActor(self), WithdrawalStOutput1(self, nonceWrapped.content)) };
        else
            nonceWrapped := Decrypt(msg.duress_check_space_with_nonce_encrypted_by_boomlet_for_st, STActor(self));
            assert nonceWrapped # NoValue;
            st_last_duress_check_i[self] := nonceWrapped;
            assert st_to_user[self] = NoValue;
            if msg.kind = "WithdrawalNisoStMessage3" then
                st_to_user[self] := WithdrawalStOutput3(nonceWrapped.content, nonceWrapped.content.stage, nonceWrapped.content.seq);
                wire_trace := wire_trace \cup
                    { WireHop(STActor(self), UserActor(self), WithdrawalStOutput3(nonceWrapped.content, nonceWrapped.content.stage, nonceWrapped.content.seq)) };
            else
                st_to_user[self] := WithdrawalStOutput2(self, nonceWrapped.content, nonceWrapped.content.stage, nonceWrapped.content.seq);
                wire_trace := wire_trace \cup
                    { WireHop(STActor(self), UserActor(self), WithdrawalStOutput2(self, nonceWrapped.content, nonceWrapped.content.stage, nonceWrapped.content.seq)) };
            end if;
        end if;
    else
        msg := user_to_st[self];
        user_to_st[self] := NoValue;
        if msg.kind \in {"WithdrawalStInput1", "WithdrawalNonInitiatorStInput1"} then
            assert st_last_txid_with_nonce_i[self] # NoValue;
            assert st_to_niso[self] = NoValue;
            st_to_niso[self] := WithdrawalStNisoMessage1(self, TxIdAckCipher(self, st_last_txid_with_nonce_i[self].content, st_last_txid_with_nonce_i[self].nonce));
            wire_trace := wire_trace \cup
                { WireHop(STActor(self), NisoActor(self), WithdrawalStNisoMessage1(self, TxIdAckCipher(self, st_last_txid_with_nonce_i[self].content, st_last_txid_with_nonce_i[self].nonce))) };
        else
            assert st_last_duress_check_i[self] # NoValue;
            signalIndex := msg.duress_signal_index;
            assert st_to_niso[self] = NoValue;
            if msg.kind = "WithdrawalStInput3" then
                st_to_niso[self] := WithdrawalStNisoMessage3(
                    DuressReplyCipher(self, msg.stage, msg.seq, st_last_duress_check_i[self].nonce, signalIndex));
                wire_trace := wire_trace \cup
                    { WireHop(STActor(self), NisoActor(self),
                        WithdrawalStNisoMessage3(DuressReplyCipher(self, msg.stage, msg.seq, st_last_duress_check_i[self].nonce, signalIndex))) };
            else
                st_to_niso[self] := WithdrawalStNisoMessage2(
                    self,
                    DuressReplyCipher(self, msg.stage, msg.seq, st_last_duress_check_i[self].nonce, signalIndex));
                wire_trace := wire_trace \cup
                    { WireHop(STActor(self), NisoActor(self),
                        WithdrawalStNisoMessage2(self, DuressReplyCipher(self, msg.stage, msg.seq, st_last_duress_check_i[self].nonce, signalIndex))) };
            end if;
        end if;
    end if;
    goto STLoop;
end process;

process NisoFlow \in Peers
variables msg = NoValue,
          approvalSig = NoValue,
          wtSig = NoValue,
          commitSig = NoValue,
          signedPing = NoValue;
begin
NisoLoop:
    await user_to_niso[self] # NoValue
       \/ boomlet_to_niso[self] # NoValue
       \/ st_to_niso[self] # NoValue
       \/ wt_to_niso[self] # NoValue;
    if user_to_niso[self] # NoValue then
        msg := user_to_niso[self];
        user_to_niso[self] := NoValue;
        if msg.kind = "WithdrawalNisoInput1" then
            assert self = INITIATOR;
            assert most_work_bitcoin_block_height >= boomerang_descriptor.milestone_block_0;
            assert PsbtSatisfiable(msg.psbt);
            niso_saved_psbt_i[self] := msg.psbt;
            niso_saved_tx_id_i[self] := TxOfPsbt[msg.psbt];
            niso_event_block_height_i[self] := most_work_bitcoin_block_height;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNisoBoomletMessage1(msg.psbt, niso_event_block_height_i[self]);
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage1(msg.psbt, niso_event_block_height_i[self])) };
        elsif msg.kind = "WithdrawalNonInitiatorNisoInput1" then
            assert self # INITIATOR;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNonInitiatorNisoBoomletMessage2;
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage2) };
        else
            assert msg.kind = "WithdrawalNisoInput2";
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNisoBoomletMessage9;
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage9) };
        end if;
    elsif boomlet_to_niso[self] # NoValue then
        msg := boomlet_to_niso[self];
        boomlet_to_niso[self] := NoValue;
        if msg.kind = "WithdrawalBoomletNisoMessage1" then
            assert niso_to_st[self] = NoValue;
            niso_to_st[self] := WithdrawalNisoStMessage1(self, msg.tx_id_with_nonce_encrypted_by_boomlet_for_st);
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage1(self, msg.tx_id_with_nonce_encrypted_by_boomlet_for_st)) };
        elsif msg.kind = "WithdrawalNonInitiatorBoomletNisoMessage1" then
            assert PsbtSatisfiable(msg.psbt);
            assert TxOfPsbt[msg.psbt] = niso_saved_tx_id_i[self];
            niso_saved_psbt_i[self] := msg.psbt;
            assert niso_to_user[self] = NoValue;
            niso_to_user[self] := WithdrawalNonInitiatorNisoOutput1(msg.psbt, niso_initiator_peer_id_i[self]);
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), UserActor(self), WithdrawalNonInitiatorNisoOutput1(msg.psbt, niso_initiator_peer_id_i[self])) };
        elsif msg.kind = "WithdrawalNonInitiatorBoomletNisoMessage2" then
            assert niso_to_st[self] = NoValue;
            niso_to_st[self] := WithdrawalNisoStMessage1(self, msg.tx_id_with_nonce_encrypted_by_boomlet_for_st);
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage1(self, msg.tx_id_with_nonce_encrypted_by_boomlet_for_st)) };
        elsif msg.kind = "WithdrawalBoomletNisoMessage2" then
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := WithdrawalNisoWtMessage1(
                msg.initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt,
                msg.psbt_encrypted_collection);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), WTActor, WithdrawalNisoWtMessage1(
                    msg.initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt,
                    msg.psbt_encrypted_collection)) };
        elsif msg.kind = "WithdrawalNonInitiatorBoomletNisoMessage3" then
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := WithdrawalNonInitiatorNisoWtMessage1(msg.peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), WTActor, WithdrawalNonInitiatorNisoWtMessage1(msg.peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) };
        elsif msg.kind = "WithdrawalBoomletNisoMessage3" then
            assert niso_to_st[self] = NoValue;
            niso_to_st[self] := WithdrawalNisoStMessage2(self, msg.duress_check_space_with_nonce_encrypted_by_boomlet_for_st);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage2(self, msg.duress_check_space_with_nonce_encrypted_by_boomlet_for_st)) };
        elsif msg.kind = "WithdrawalNonInitiatorBoomletNisoMessage4" then
            assert niso_to_st[self] = NoValue;
            niso_to_st[self] := WithdrawalNisoStMessage2(self, msg.duress_check_space_with_nonce_encrypted_by_boomlet_for_st);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage2(self, msg.duress_check_space_with_nonce_encrypted_by_boomlet_for_st)) };
        elsif msg.kind = "WithdrawalBoomletNisoMessage4" then
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := WithdrawalNisoWtMessage2(msg.peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), WTActor, WithdrawalNisoWtMessage2(msg.peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt)) };
        elsif msg.kind = "WithdrawalNonInitiatorBoomletNisoMessage5" then
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := WithdrawalNonInitiatorNisoWtMessage2(msg.approvals_signed_by_boomlet_i);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), WTActor, WithdrawalNonInitiatorNisoWtMessage2(msg.approvals_signed_by_boomlet_i)) };
        elsif msg.kind = "WithdrawalNonInitiatorBoomletNisoMessage6" then
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := WithdrawalNonInitiatorNisoWtMessage3(msg.peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), WTActor, WithdrawalNonInitiatorNisoWtMessage3(msg.peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) };
        elsif msg.kind = "WithdrawalBoomletNisoMessage5" then
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := PingToWTMessage(self, FALSE, msg.peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), WTActor, PingToWTMessage(self, FALSE, msg.peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) };
        elsif msg.kind = "WithdrawalBoomletNisoMessage6" then
            assert niso_to_st[self] = NoValue;
            niso_to_st[self] := WithdrawalNisoStMessage3(msg.duress_check_space_with_nonce_encrypted_by_boomlet_for_st);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage3(msg.duress_check_space_with_nonce_encrypted_by_boomlet_for_st)) };
        elsif msg.kind = "WithdrawalBoomletNisoMessage7" then
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := PingToWTMessage(self, TRUE, msg.peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), WTActor, PingToWTMessage(self, TRUE, msg.peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) };
        elsif msg.kind = "WithdrawalBoomletNisoMessage8" then
            assert niso_to_user[self] = NoValue;
            niso_to_user[self] := WithdrawalNisoOutput1;
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), UserActor(self), WithdrawalNisoOutput1) };
        else
            assert msg.kind = "WithdrawalBoomletNisoMessage9";
            assert niso_to_wt[self] = NoValue;
            niso_to_wt[self] := WithdrawalNisoWtMessage5(msg.psbt_signed_i);
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), WTActor, WithdrawalNisoWtMessage5(msg.psbt_signed_i)) };
        end if;
    elsif st_to_niso[self] # NoValue then
        msg := st_to_niso[self];
        st_to_niso[self] := NoValue;
        if msg.kind \in {"WithdrawalStNisoMessage1", "WithdrawalNonInitiatorStNisoMessage1"} then
            assert niso_to_boomlet[self] = NoValue;
            if self = INITIATOR then
                niso_to_boomlet[self] := WithdrawalNisoBoomletMessage2(msg.tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet);
                wire_trace := wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage2(msg.tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet)) };
            else
                niso_event_block_height_i[self] := most_work_bitcoin_block_height;
                niso_to_boomlet[self] := WithdrawalNonInitiatorNisoBoomletMessage3(msg.tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet, niso_event_block_height_i[self]);
                wire_trace := wire_trace \cup
                    { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage3(msg.tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet, niso_event_block_height_i[self])) };
            end if;
        elsif msg.kind \in {"WithdrawalStNisoMessage2", "WithdrawalNonInitiatorStNisoMessage2"} then
            assert niso_to_boomlet[self] = NoValue;
            if self = INITIATOR then
                niso_to_boomlet[self] := WithdrawalNisoBoomletMessage4(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet);
                wire_trace := wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage4(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)) };
            else
                niso_to_boomlet[self] := WithdrawalNonInitiatorNisoBoomletMessage5(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet);
                wire_trace := wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage5(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)) };
            end if;
        else
            assert msg.kind = "WithdrawalStNisoMessage3";
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNisoBoomletMessage7(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet);
            wire_trace := wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage7(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)) };
        end if;
    else
        msg := wt_to_niso[self];
        wt_to_niso[self] := NoValue;
        if msg.kind = "WithdrawalWtNonInitiatorNisoMessage1" then
            wtSig := msg.wt_tx_approval_signed_by_wt;
            approvalSig := msg.peer_0_tx_approval_signed_by_boomlet_0;
            assert WTTxApprovalSigValid(
                wtSig,
                SignedContent(approvalSig).tx_id,
                INITIATOR,
                SignedContent(approvalSig).event_block_height,
                most_work_bitcoin_block_height);
            assert ValidSig(approvalSig, BoomletActor(INITIATOR));
            assert SignedContent(wtSig).initiator_id \in peer_id_collection;
            assert SignedContent(approvalSig).magic = "approved";
            assert SignedContent(wtSig).magic = "approved";
            assert SignedContent(approvalSig).tx_id = SignedContent(wtSig).tx_id;
            assert SignedContent(wtSig).event_block_height >=
                Max2(
                    SignedContent(approvalSig).event_block_height,
                    IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                    THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                    ELSE 0);
            niso_saved_tx_id_i[self] := SignedContent(wtSig).tx_id;
            niso_initiator_peer_id_i[self] := SignedContent(wtSig).initiator_id;
            niso_saved_wt_tx_approval_i[self] := wtSig;
            niso_event_block_height_i[self] := most_work_bitcoin_block_height;
            assert most_work_bitcoin_block_height >= boomerang_descriptor.milestone_block_0;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNonInitiatorNisoBoomletMessage1(
                wtSig,
                approvalSig,
                msg.psbt_encrypted_by_boomlet_0_for_boomlet_i,
                niso_event_block_height_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage1(
                    wtSig,
                    approvalSig,
                    msg.psbt_encrypted_by_boomlet_0_for_boomlet_i,
                    niso_event_block_height_i[self])) };
        elsif msg.kind = "WithdrawalWtNisoMessage1" then
            wtSig := msg.wt_tx_approval_signed_by_wt;
            assert WTTxApprovalSigValid(
                wtSig,
                SignedContent(msg.all_peer_tx_approvals[INITIATOR]).tx_id,
                INITIATOR,
                SignedContent(msg.all_peer_tx_approvals[INITIATOR]).event_block_height,
                most_work_bitcoin_block_height);
            assert ValidSig(msg.all_peer_tx_approvals[INITIATOR], BoomletActor(INITIATOR));
            assert SignedContent(msg.all_peer_tx_approvals[INITIATOR]).magic = "approved";
            assert SignedContent(msg.all_peer_tx_approvals[INITIATOR]).tx_id = niso_saved_tx_id_i[self];
            assert SignedContent(wtSig).magic = "approved";
            assert SignedContent(wtSig).tx_id = niso_saved_tx_id_i[self];
            assert SignedContent(wtSig).event_block_height >= SignedContent(msg.all_peer_tx_approvals[INITIATOR]).event_block_height;
            assert SignedContent(wtSig).event_block_height <=
                Min2(
                    SignedContent(msg.all_peer_tx_approvals[INITIATOR]).event_block_height
                        + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT,
                    most_work_bitcoin_block_height);
            assert SignedContent(msg.all_peer_tx_approvals[INITIATOR]).event_block_height >=
                Max2(
                    IF SignedContent(wtSig).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                    THEN SignedContent(wtSig).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                    ELSE 0,
                    IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                    THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                    ELSE 0);
            assert SignedContent(msg.all_peer_tx_approvals[INITIATOR]).event_block_height <= SignedContent(wtSig).event_block_height;
            assert most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER;
            assert \A j \in NonInitiators :
                /\ ValidSig(msg.all_peer_tx_approvals[j], BoomletActor(j))
                /\ SignedContent(msg.all_peer_tx_approvals[j]).magic = "approved"
                /\ SignedContent(msg.all_peer_tx_approvals[j]).tx_id = niso_saved_tx_id_i[self]
                /\ SignedContent(msg.all_peer_tx_approvals[j]).event_block_height >=
                    Max2(
                        SignedContent(wtSig).event_block_height,
                        IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                        THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                        ELSE 0)
                /\ SignedContent(msg.all_peer_tx_approvals[j]).event_block_height <=
                    most_work_bitcoin_block_height
                        - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER;
            niso_saved_wt_tx_approval_i[self] := wtSig;
            niso_event_block_height_i[self] := most_work_bitcoin_block_height;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNisoBoomletMessage3(
                [j \in NonInitiators |-> msg.all_peer_tx_approvals[j]],
                wtSig,
                niso_event_block_height_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage3(
                    [j \in NonInitiators |-> msg.all_peer_tx_approvals[j]],
                    wtSig,
                    niso_event_block_height_i[self])) };
        elsif msg.kind = "WithdrawalWtNonInitiatorNisoMessage2" then
            niso_event_block_height_i[self] := most_work_bitcoin_block_height;
            assert niso_saved_wt_tx_approval_i[self] # NoValue;
            assert \A j \in NonInitiators :
                /\ ValidSig(msg.non_initiator_tx_approvals[j], BoomletActor(j))
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).magic = "approved"
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).tx_id = niso_saved_tx_id_i[self]
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).event_block_height >=
                    Max2(
                        SignedContent(niso_saved_wt_tx_approval_i[self]).event_block_height,
                        IF niso_event_block_height_i[self] >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                        THEN niso_event_block_height_i[self] - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                        ELSE 0)
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).event_block_height <=
                    Min2(
                        niso_event_block_height_i[self],
                        SignedContent(niso_saved_wt_tx_approval_i[self]).event_block_height
                            + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS);
            assert SignedContent(niso_saved_wt_tx_approval_i[self]).event_block_height >=
                IF niso_event_block_height_i[self] >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                THEN niso_event_block_height_i[self] - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                ELSE 0;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNonInitiatorNisoBoomletMessage4(
                msg.non_initiator_tx_approvals,
                niso_event_block_height_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage4(
                    msg.non_initiator_tx_approvals,
                    niso_event_block_height_i[self])) };
        elsif msg.kind = "WithdrawalWtNonInitiatorNisoMessage3" then
            commitSig := msg.peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt;
            assert WTSignedCommitValid(
                commitSig,
                INITIATOR,
                SignedContent(SignedContent(commitSig)).tx_id,
                IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                ELSE 0,
                most_work_bitcoin_block_height);
            niso_event_block_height_i[self] := most_work_bitcoin_block_height;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNonInitiatorNisoBoomletMessage6(commitSig, niso_event_block_height_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage6(commitSig, niso_event_block_height_i[self])) };
        elsif msg.kind \in {"WithdrawalWtNisoMessage2", "WithdrawalWtNonInitiatorNisoMessage4"} then
            niso_event_block_height_i[self] := most_work_bitcoin_block_height;
            assert niso_event_block_height_i[self] >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS;
            assert \A j \in Peers :
                WTSignedCommitValid(
                    msg.all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt[j],
                    j,
                    niso_saved_tx_id_i[self],
                    IF niso_event_block_height_i[self] >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                    THEN niso_event_block_height_i[self] - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                    ELSE 0,
                    niso_event_block_height_i[self]
                        - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS);
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNisoBoomletMessage5(
                msg.all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt,
                msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                niso_event_block_height_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage5(
                    msg.all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt,
                    msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                    niso_event_block_height_i[self])) };
        elsif msg.kind = "WithdrawalWtNisoMessage3" then
            niso_event_block_height_i[self] := most_work_bitcoin_block_height;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNisoBoomletMessage6(
                msg.pong_signed_by_wt_encrypted_by_wt_for_boomlet,
                msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                niso_event_block_height_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage6(
                    msg.pong_signed_by_wt_encrypted_by_wt_for_boomlet,
                    msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                    niso_event_block_height_i[self])) };
        else
            assert msg.kind = "WithdrawalWtNisoMessage4";
            assert msg.reached_pings_collection.kind = "ReachedPingsCollection";
            assert \A j \in Peers :
                ReachedPingSigValid(msg.reached_pings_collection.items[j], j, niso_saved_tx_id_i[self]);
            niso_reached_pings_collection_i[self] := msg.reached_pings_collection;
            niso_hydrated_psbt_i[self] := HydratePsbt(niso_saved_psbt_i[self]);
            assert niso_hydrated_psbt_i[self] # NoValue;
            assert niso_to_boomlet[self] = NoValue;
            niso_to_boomlet[self] := WithdrawalNisoBoomletMessage8(msg.reached_pings_collection, niso_hydrated_psbt_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage8(msg.reached_pings_collection, niso_hydrated_psbt_i[self])) };
        end if;
    end if;
    goto NisoLoop;
end process;

process BoomletFlow \in Peers
variables msg = NoValue,
          signedAck = NoValue,
          duressSignal = NoValue,
          hydrated = NoValue,
          signedPong = NoValue,
          prevPings = NoValue;
begin
BoomletLoop:
    await niso_to_boomlet[self] # NoValue \/ iso_to_boomlet[self] # NoValue;
    if niso_to_boomlet[self] # NoValue then
        msg := niso_to_boomlet[self];
        niso_to_boomlet[self] := NoValue;
        if msg.kind = "WithdrawalNisoBoomletMessage1" then
            assert self = INITIATOR;
            assert msg.niso_0_event_block_height >= boomerang_descriptor.milestone_block_0;
            boomlet_saved_psbt_i[self] := msg.psbt;
            boomlet_committed_tx_id_i[self] := TxOfPsbt[msg.psbt];
            boomlet_pending_txid_nonce_i[self] := NonceValue(self, "txid", 0);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalBoomletNisoMessage1(
                TxIdChallengeCipher(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self]));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage1(
                    TxIdChallengeCipher(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self]))) };
        elsif msg.kind = "WithdrawalNisoBoomletMessage2" then
            assert TxIdAckValid(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self], msg.tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet);
            boomlet_signed_tx_approval_i[self] := SignedTxApproval(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self]);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalBoomletNisoMessage2(
                ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self]),
                Collection([j \in NonInitiators |-> PsbtCipherForPeer(self, j, boomlet_saved_psbt_i[self], boomlet_committed_tx_id_i[self]) ]));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage2(
                    ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self]),
                    Collection([j \in NonInitiators |-> PsbtCipherForPeer(self, j, boomlet_saved_psbt_i[self], boomlet_committed_tx_id_i[self]) ]))) };
        elsif msg.kind = "WithdrawalNonInitiatorNisoBoomletMessage1" then
            assert self # INITIATOR;
            assert ValidSig(msg.wt_tx_approval_signed_by_wt, WTActor);
            assert ValidSig(msg.peer_0_tx_approval_signed_by_boomlet_0, BoomletActor(INITIATOR));
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).initiator_id \in peer_id_collection;
            assert SignedContent(msg.peer_0_tx_approval_signed_by_boomlet_0).magic = "approved";
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).magic = "approved";
            boomlet_saved_wt_tx_approval_i[self] := msg.wt_tx_approval_signed_by_wt;
            boomlet_signed_tx_approval_i[INITIATOR] := msg.peer_0_tx_approval_signed_by_boomlet_0;
            boomlet_saved_psbt_i[self] := Decrypt(msg.psbt_encrypted_by_boomlet_0_for_boomlet_i, BoomletActor(self));
            assert boomlet_saved_psbt_i[self] # NoValue;
            boomlet_committed_tx_id_i[self] := TxOfPsbt[boomlet_saved_psbt_i[self]];
            assert boomlet_committed_tx_id_i[self] = SignedContent(msg.peer_0_tx_approval_signed_by_boomlet_0).tx_id;
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).tx_id = boomlet_committed_tx_id_i[self];
            assert SignedContent(msg.peer_0_tx_approval_signed_by_boomlet_0).event_block_height >=
                IF SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                THEN SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                ELSE 0;
            assert SignedContent(msg.peer_0_tx_approval_signed_by_boomlet_0).event_block_height <=
                Min2(
                    msg.niso_1_event_block_height,
                    SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height);
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height >=
                Max2(
                    SignedContent(msg.peer_0_tx_approval_signed_by_boomlet_0).event_block_height,
                    IF msg.niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                    THEN msg.niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                    ELSE 0);
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height <=
                Min2(
                    SignedContent(msg.peer_0_tx_approval_signed_by_boomlet_0).event_block_height
                        + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT,
                    msg.niso_1_event_block_height);
            assert msg.niso_1_event_block_height >= boomerang_descriptor.milestone_block_0;
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalNonInitiatorBoomletNisoMessage1(boomlet_saved_psbt_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage1(boomlet_saved_psbt_i[self])) };
        elsif msg.kind = "WithdrawalNonInitiatorNisoBoomletMessage2" then
            boomlet_pending_txid_nonce_i[self] := NonceValue(self, "txid", 0);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalNonInitiatorBoomletNisoMessage2(
                TxIdChallengeCipher(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self]));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage2(
                    TxIdChallengeCipher(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self]))) };
        elsif msg.kind = "WithdrawalNonInitiatorNisoBoomletMessage3" then
            assert TxIdAckValid(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self], msg.tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet);
            boomlet_signed_tx_approval_i[self] := SignedTxApproval(self, boomlet_committed_tx_id_i[self], msg.niso_1_event_block_height);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalNonInitiatorBoomletNisoMessage3(
                ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], msg.niso_1_event_block_height));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage3(
                    ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], msg.niso_1_event_block_height))) };
        elsif msg.kind = "WithdrawalNisoBoomletMessage3" then
            assert ValidSig(msg.wt_tx_approval_signed_by_wt, WTActor);
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).magic = "approved";
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).tx_id = boomlet_committed_tx_id_i[self];
            assert \A j \in NonInitiators :
                /\ ValidSig(msg.all_peer_tx_approvals[j], BoomletActor(j))
                /\ SignedContent(msg.all_peer_tx_approvals[j]).magic = "approved"
                /\ SignedContent(msg.all_peer_tx_approvals[j]).tx_id = boomlet_committed_tx_id_i[self]
                /\ SignedContent(msg.all_peer_tx_approvals[j]).event_block_height >=
                    Max2(
                        SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height,
                        IF msg.niso_0_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                        THEN msg.niso_0_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                        ELSE 0)
                /\ msg.niso_0_event_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                /\ SignedContent(msg.all_peer_tx_approvals[j]).event_block_height <=
                    msg.niso_0_event_block_height
                        - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER;
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height >= SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height;
            assert SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height <=
                Min2(
                    SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height
                        + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT,
                    msg.niso_0_event_block_height);
            assert SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height >=
                Max2(
                    IF SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                    THEN SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                    ELSE 0,
                    IF msg.niso_0_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                    THEN msg.niso_0_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                    ELSE 0);
            assert SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height <= SignedContent(msg.wt_tx_approval_signed_by_wt).event_block_height;
            boomlet_all_peer_approvals_i[self] := msg.all_peer_tx_approvals;
            boomlet_saved_wt_tx_approval_i[self] := msg.wt_tx_approval_signed_by_wt;
            boomlet_saved_duress_stage_i[self] := "initial";
            boomlet_saved_duress_seq_i[self] := 1;
            with space \in DuressCheckSpaces(self, "initial", 1) do
                boomlet_saved_duress_space_i[self] := space;
                boomlet_pending_duress_nonce_i[self] := NonceValue(self, "initial_duress", 1);
                assert boomlet_to_niso[self] = NoValue;
                boomlet_to_niso[self] := WithdrawalBoomletNisoMessage3(DuressCheckCipher(space, boomlet_pending_duress_nonce_i[self]));
                wire_trace := wire_trace \cup
                    { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage3(DuressCheckCipher(space, boomlet_pending_duress_nonce_i[self]))) };
            end with;
        elsif msg.kind = "WithdrawalNonInitiatorNisoBoomletMessage4" then
            assert boomlet_saved_wt_tx_approval_i[self] # NoValue;
            assert \A j \in NonInitiators :
                /\ ValidSig(msg.non_initiator_tx_approvals[j], BoomletActor(j))
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).magic = "approved"
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).tx_id = boomlet_committed_tx_id_i[self]
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).event_block_height >=
                    Max2(
                        SignedContent(boomlet_saved_wt_tx_approval_i[self]).event_block_height,
                        IF msg.niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                        THEN msg.niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                        ELSE 0)
                /\ SignedContent(msg.non_initiator_tx_approvals[j]).event_block_height <=
                    Min2(
                        msg.niso_1_event_block_height,
                        SignedContent(boomlet_saved_wt_tx_approval_i[self]).event_block_height
                            + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS);
            assert SignedContent(boomlet_saved_wt_tx_approval_i[self]).event_block_height >=
                IF msg.niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                THEN msg.niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                ELSE 0;
            boomlet_all_peer_approvals_i[self] := msg.non_initiator_tx_approvals;
            boomlet_saved_duress_stage_i[self] := "initial";
            boomlet_saved_duress_seq_i[self] := 1;
            with space \in DuressCheckSpaces(self, "initial", 1) do
                boomlet_saved_duress_space_i[self] := space;
                boomlet_pending_duress_nonce_i[self] := NonceValue(self, "initial_duress", 1);
                assert boomlet_to_niso[self] = NoValue;
                boomlet_to_niso[self] := WithdrawalNonInitiatorBoomletNisoMessage4(DuressCheckCipher(space, boomlet_pending_duress_nonce_i[self]));
                wire_trace := wire_trace \cup
                    { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage4(DuressCheckCipher(space, boomlet_pending_duress_nonce_i[self]))) };
            end with;
        elsif msg.kind = "WithdrawalNisoBoomletMessage4" then
            assert DuressReplyMatchesSpace(self, boomlet_saved_duress_space_i[self], "initial", boomlet_saved_duress_seq_i[self], boomlet_pending_duress_nonce_i[self], msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet);
            duressSignal := DerivedDuressSignal(
                boomlet_saved_duress_space_i[self],
                Decrypt(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet, BoomletActor(self)).content);
            if duressSignal = duress_consent_set_i[self] then
                boomlet_duress_placeholder_plaintext_i[self] := SafePaddingPlaintext(self, "commit", boomlet_saved_duress_seq_i[self]);
            else
                boomlet_duress_placeholder_plaintext_i[self] := doxing_key_i[self];
            end if;
            boomlet_duress_placeholder_cipher_i[self] :=
                PlaceholderCipherForSAR(self, "commit", boomlet_saved_duress_seq_i[self], boomlet_duress_placeholder_plaintext_i[self]);
            boomlet_signed_commit_inner_i[self] :=
                SignedCommitInner(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self]);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalBoomletNisoMessage4(
                CommitCipherForWT(
                    self,
                    boomlet_committed_tx_id_i[self],
                    niso_event_block_height_i[self],
                    boomlet_duress_placeholder_cipher_i[self]));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage4(
                    CommitCipherForWT(
                        self,
                        boomlet_committed_tx_id_i[self],
                        niso_event_block_height_i[self],
                        boomlet_duress_placeholder_cipher_i[self]))) };
        elsif msg.kind = "WithdrawalNonInitiatorNisoBoomletMessage5" then
            assert DuressReplyMatchesSpace(self, boomlet_saved_duress_space_i[self], "initial", boomlet_saved_duress_seq_i[self], boomlet_pending_duress_nonce_i[self], msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet);
            duressSignal := DerivedDuressSignal(
                boomlet_saved_duress_space_i[self],
                Decrypt(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet, BoomletActor(self)).content);
            if duressSignal = duress_consent_set_i[self] then
                boomlet_duress_placeholder_plaintext_i[self] := SafePaddingPlaintext(self, "commit", boomlet_saved_duress_seq_i[self]);
            else
                boomlet_duress_placeholder_plaintext_i[self] := doxing_key_i[self];
            end if;
            boomlet_duress_placeholder_cipher_i[self] :=
                PlaceholderCipherForSAR(self, "commit", boomlet_saved_duress_seq_i[self], boomlet_duress_placeholder_plaintext_i[self]);
            boomlet_approvals_bundle_i[self] :=
                SignatureOnMessage(
                    BoomletActor(self),
                    ApprovalsBundle(
                        [j \in Peers |->
                            IF j = INITIATOR
                            THEN boomlet_signed_tx_approval_i[INITIATOR]
                            ELSE boomlet_all_peer_approvals_i[self][j]],
                        boomlet_saved_wt_tx_approval_i[self]));
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalNonInitiatorBoomletNisoMessage5(boomlet_approvals_bundle_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage5(boomlet_approvals_bundle_i[self])) };
        elsif msg.kind = "WithdrawalNonInitiatorNisoBoomletMessage6" then
            assert WTSignedCommitValid(
                msg.peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt,
                INITIATOR,
                boomlet_committed_tx_id_i[self],
                IF msg.niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                THEN msg.niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                ELSE 0,
                msg.niso_1_event_block_height);
            boomlet_signed_commit_inner_i[self] := SignedCommitInner(self, boomlet_committed_tx_id_i[self], msg.niso_1_event_block_height);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalNonInitiatorBoomletNisoMessage6(
                CommitCipherForWT(
                    self,
                    boomlet_committed_tx_id_i[self],
                    msg.niso_1_event_block_height,
                    boomlet_duress_placeholder_cipher_i[self]));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage6(
                    CommitCipherForWT(
                        self,
                        boomlet_committed_tx_id_i[self],
                        msg.niso_1_event_block_height,
                        boomlet_duress_placeholder_cipher_i[self]))) };
        elsif msg.kind = "WithdrawalNisoBoomletMessage5" then
            assert SARReplyValidForPeer(self, boomlet_duress_placeholder_cipher_i[self], msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet);
            assert msg.niso_0_event_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS;
            assert \A j \in Peers :
                WTSignedCommitValid(
                    msg.all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt[j],
                    j,
                    boomlet_committed_tx_id_i[self],
                    IF msg.niso_0_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                    THEN msg.niso_0_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                    ELSE 0,
                    msg.niso_0_event_block_height
                        - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS);
            boomlet_commit_collection_i[self] := msg.all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt;
            boomlet_counter_i[self] := 0;
            boomlet_ping_seq_num_i[self] := 0;
            boomlet_reached_mystery_flag_i[self] := FALSE;
            boomlet_known_reached_i[self] := {};
            boomlet_prev_pings_i[self] := NoValue;
            boomlet_last_seen_block_i[self] := msg.niso_0_event_block_height;
            boomlet_duress_placeholder_cipher_i[self] :=
                PlaceholderCipherForSAR(self, "ping", 0, boomlet_duress_placeholder_plaintext_i[self]);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalBoomletNisoMessage5(
                PingCipherForWT(
                    self,
                    boomlet_committed_tx_id_i[self],
                    boomlet_last_seen_block_i[self],
                    boomlet_ping_seq_num_i[self],
                    boomlet_reached_mystery_flag_i[self],
                    boomlet_duress_placeholder_cipher_i[self]));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage5(
                    PingCipherForWT(
                        self,
                        boomlet_committed_tx_id_i[self],
                        boomlet_last_seen_block_i[self],
                        boomlet_ping_seq_num_i[self],
                        boomlet_reached_mystery_flag_i[self],
                        boomlet_duress_placeholder_cipher_i[self]))) };
        elsif msg.kind = "WithdrawalNisoBoomletMessage6" then
            assert SARReplyValidForPeer(self, boomlet_duress_placeholder_cipher_i[self], msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet);
            assert PongDeliveryValidForPeer(
                msg,
                self,
                boomlet_committed_tx_id_i[self],
                msg.niso_0_event_block_height,
                boomlet_prev_pings_i[self],
                boomlet_known_reached_i[self]);
            signedPong := Decrypt(msg.pong_signed_by_wt_encrypted_by_wt_for_boomlet, BoomletActor(self));
            prevPings := SignedContent(signedPong).prev_pings.items;
            if CanIncrementCounter(self, msg.niso_0_event_block_height, prevPings, boomlet_last_seen_block_i[self]) then
                boomlet_counter_i[self] := boomlet_counter_i[self] + 1;
            end if;
            boomlet_known_reached_i[self] :=
                boomlet_known_reached_i[self] \cup { j \in (Peers \ {self}) : SignedContent(prevPings[j]).reached_mystery_flag };
            if boomlet_counter_i[self] >= boomlet_mystery_i[self] then
                boomlet_reached_mystery_flag_i[self] := TRUE;
            end if;
            if boomlet_last_seen_block_i[self] < msg.niso_0_event_block_height then
                if boomlet_last_seen_block_i[self] + JUMP_IN_BLOCKS_IF_LAST_SEEN_BLOCK_LAGS_BEHIND_NISO_EVENT_BLOCK_HEIGHT_IN_BOOMLET < msg.niso_0_event_block_height then
                    boomlet_last_seen_block_i[self] := boomlet_last_seen_block_i[self] + JUMP_IN_BLOCKS_IF_LAST_SEEN_BLOCK_LAGS_BEHIND_NISO_EVENT_BLOCK_HEIGHT_IN_BOOMLET;
                else
                    boomlet_last_seen_block_i[self] := msg.niso_0_event_block_height;
                end if;
            end if;
            boomlet_prev_pings_i[self] := prevPings;
            with prng_draw \in RecurringDuressPRNGDraws do
                if RecurringDuressCheckFires(prng_draw) then
                    boomlet_saved_duress_stage_i[self] := "loop";
                    boomlet_saved_duress_seq_i[self] := boomlet_saved_duress_seq_i[self] + 1;
                    with space \in DuressCheckSpaces(self, "loop", boomlet_saved_duress_seq_i[self]) do
                        boomlet_saved_duress_space_i[self] := space;
                        boomlet_pending_duress_nonce_i[self] := NonceValue(self, "loop_duress", boomlet_saved_duress_seq_i[self]);
                        assert boomlet_to_niso[self] = NoValue;
                        boomlet_to_niso[self] := WithdrawalBoomletNisoMessage6(DuressCheckCipher(space, boomlet_pending_duress_nonce_i[self]));
                        wire_trace := wire_trace \cup
                            { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage6(DuressCheckCipher(space, boomlet_pending_duress_nonce_i[self]))) };
                    end with;
                else
                    boomlet_ping_seq_num_i[self] := boomlet_ping_seq_num_i[self] + 1;
                    boomlet_duress_placeholder_cipher_i[self] :=
                        PlaceholderCipherForSAR(self, "ping", boomlet_ping_seq_num_i[self], boomlet_duress_placeholder_plaintext_i[self]);
                    assert boomlet_to_niso[self] = NoValue;
                    boomlet_to_niso[self] := WithdrawalBoomletNisoMessage7(
                        PingCipherForWT(
                            self,
                            boomlet_committed_tx_id_i[self],
                            boomlet_last_seen_block_i[self],
                            boomlet_ping_seq_num_i[self],
                            boomlet_reached_mystery_flag_i[self],
                            boomlet_duress_placeholder_cipher_i[self]));
                    wire_trace := wire_trace \cup
                        { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage7(
                            PingCipherForWT(
                                self,
                                boomlet_committed_tx_id_i[self],
                            boomlet_last_seen_block_i[self],
                            boomlet_ping_seq_num_i[self],
                            boomlet_reached_mystery_flag_i[self],
                            boomlet_duress_placeholder_cipher_i[self]))) };
                end if;
            end with;
        elsif msg.kind = "WithdrawalNisoBoomletMessage7" then
            assert DuressReplyMatchesSpace(self, boomlet_saved_duress_space_i[self], "loop", boomlet_saved_duress_seq_i[self], boomlet_pending_duress_nonce_i[self], msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet);
            duressSignal := DerivedDuressSignal(
                boomlet_saved_duress_space_i[self],
                Decrypt(msg.duress_signal_index_with_nonce_encrypted_by_st_for_boomlet, BoomletActor(self)).content);
            if duressSignal = duress_consent_set_i[self] then
                boomlet_duress_placeholder_plaintext_i[self] := SafePaddingPlaintext(self, "ping", boomlet_saved_duress_seq_i[self]);
            else
                boomlet_duress_placeholder_plaintext_i[self] := doxing_key_i[self];
            end if;
            boomlet_ping_seq_num_i[self] := boomlet_ping_seq_num_i[self] + 1;
            boomlet_duress_placeholder_cipher_i[self] :=
                PlaceholderCipherForSAR(self, "ping", boomlet_ping_seq_num_i[self], boomlet_duress_placeholder_plaintext_i[self]);
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalBoomletNisoMessage7(
                PingCipherForWT(
                    self,
                    boomlet_committed_tx_id_i[self],
                    boomlet_last_seen_block_i[self],
                    boomlet_ping_seq_num_i[self],
                    boomlet_reached_mystery_flag_i[self],
                    boomlet_duress_placeholder_cipher_i[self]));
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage7(
                    PingCipherForWT(
                        self,
                        boomlet_committed_tx_id_i[self],
                        boomlet_last_seen_block_i[self],
                        boomlet_ping_seq_num_i[self],
                        boomlet_reached_mystery_flag_i[self],
                        boomlet_duress_placeholder_cipher_i[self]))) };
        elsif msg.kind = "WithdrawalNisoBoomletMessage8" then
            hydrated := msg.hydrated_psbt;
            assert \A j \in Peers :
                ReachedPingSigValid(msg.reached_pings_collection.items[j], j, boomlet_committed_tx_id_i[self]);
            assert hydrated.tx_id = boomlet_committed_tx_id_i[self];
            boomlet_saved_psbt_i[self] := hydrated;
            boomlet_ready_to_sign_i[self] := TRUE;
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalBoomletNisoMessage8;
            wire_trace := wire_trace \cup { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage8) };
        elsif msg.kind = "WithdrawalNisoBoomletMessage9" then
            assert boomlet_signed_psbt_i[self] # NoValue;
            assert boomlet_to_niso[self] = NoValue;
            boomlet_to_niso[self] := WithdrawalBoomletNisoMessage9(boomlet_signed_psbt_i[self]);
            wire_trace := wire_trace \cup { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage9(boomlet_signed_psbt_i[self])) };
            boomlet_saved_psbt_i[self] := NoValue;
            boomlet_committed_tx_id_i[self] := NoValue;
            boomlet_pending_txid_nonce_i[self] := NoValue;
            boomlet_saved_duress_space_i[self] := NoValue;
            boomlet_pending_duress_nonce_i[self] := NoValue;
            boomlet_duress_placeholder_plaintext_i[self] := NoValue;
            boomlet_duress_placeholder_cipher_i[self] := NoValue;
            boomlet_signed_commit_inner_i[self] := NoValue;
            boomlet_commit_collection_i[self] := NoValue;
            boomlet_counter_i[self] := 0;
            boomlet_last_seen_block_i[self] := Milestone0;
            boomlet_ping_seq_num_i[self] := 0;
            boomlet_reached_mystery_flag_i[self] := FALSE;
            boomlet_known_reached_i[self] := {};
            boomlet_prev_pings_i[self] := NoValue;
            boomlet_ready_to_sign_i[self] := FALSE;
            with fresh \in {m \in Nat : m > 0 /\ m # boomlet_mystery_i[self]} do
                boomlet_mystery_i[self] := fresh;
            end with;
        end if;
    else
        msg := iso_to_boomlet[self];
        iso_to_boomlet[self] := NoValue;
        if msg.kind = "WithdrawalIsoBoomletMessage1" then
            boomlet_pubnonce_boom_i[self] := PubnonceBoom(self, TxOfPsbt[BasePsbtOf(boomlet_saved_psbt_i[self])]);
            assert boomlet_to_iso[self] = NoValue;
            boomlet_to_iso[self] := WithdrawalBoomletIsoMessage1(
                boomlet_saved_psbt_i[self],
                boomerang_descriptor,
                [kind |-> "BoomPubkeyShare", peer |-> self],
                boomlet_pubnonce_boom_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(BoomletActor(self), IsoActor(self), WithdrawalBoomletIsoMessage1(
                    boomlet_saved_psbt_i[self],
                    boomerang_descriptor,
                    [kind |-> "BoomPubkeyShare", peer |-> self],
                    boomlet_pubnonce_boom_i[self])) };
        else
            assert msg.kind = "WithdrawalIsoBoomletMessage2";
            boomlet_partialsig_boom_i[self] := PartialSigBoom(self, TxOfPsbt[BasePsbtOf(boomlet_saved_psbt_i[self])]);
            boomlet_signed_psbt_i[self] := PsbtSigned(self, TxOfPsbt[BasePsbtOf(boomlet_saved_psbt_i[self])], boomlet_saved_psbt_i[self]);
            assert boomlet_to_iso[self] = NoValue;
            boomlet_to_iso[self] := WithdrawalBoomletIsoMessage2(boomlet_partialsig_boom_i[self]);
            wire_trace := wire_trace \cup { WireHop(BoomletActor(self), IsoActor(self), WithdrawalBoomletIsoMessage2(boomlet_partialsig_boom_i[self])) };
        end if;
    end if;
    goto BoomletLoop;
end process;

process IsoFlow \in Peers
variables msg = NoValue;
begin
IsoLoop:
    await user_to_iso[self] # NoValue \/ boomlet_to_iso[self] # NoValue;
    if user_to_iso[self] # NoValue then
        msg := user_to_iso[self];
        user_to_iso[self] := NoValue;
        if msg.kind = "WithdrawalIsoInput1" then
            assert iso_to_boomlet[self] = NoValue;
            iso_to_boomlet[self] := WithdrawalIsoBoomletMessage1;
            wire_trace := wire_trace \cup { WireHop(IsoActor(self), BoomletActor(self), WithdrawalIsoBoomletMessage1) };
        end if;
    else
        msg := boomlet_to_iso[self];
        boomlet_to_iso[self] := NoValue;
        if msg.kind = "WithdrawalBoomletIsoMessage1" then
            iso_pubnonce_normal_i[self] := PubnonceNormal(self, TxOfPsbt[BasePsbtOf(msg.psbt)]);
            iso_partialsig_normal_i[self] := PartialSigNormal(self, TxOfPsbt[BasePsbtOf(msg.psbt)]);
            assert iso_to_boomlet[self] = NoValue;
            iso_to_boomlet[self] := WithdrawalIsoBoomletMessage2(iso_pubnonce_normal_i[self], iso_partialsig_normal_i[self]);
            wire_trace := wire_trace \cup
                { WireHop(IsoActor(self), BoomletActor(self), WithdrawalIsoBoomletMessage2(iso_pubnonce_normal_i[self], iso_partialsig_normal_i[self])) };
        else
            assert msg.kind = "WithdrawalBoomletIsoMessage2";
            iso_signed_psbt_i[self] := PsbtSigned(self, msg.partialsig_boom.tx_id, boomlet_saved_psbt_i[self]);
            assert iso_to_user[self] = NoValue;
            iso_to_user[self] := WithdrawalIsoOutput1;
            wire_trace := wire_trace \cup { WireHop(IsoActor(self), UserActor(self), WithdrawalIsoOutput1) };
        end if;
    end if;
    goto IsoLoop;
end process;

process SARFlow \in Peers
variables msg = NoValue,
          plaintext = NoValue,
          reply = NoValue;
begin
SARLoop:
    await wt_to_sar[self] # NoValue;
    msg := wt_to_sar[self];
    wt_to_sar[self] := NoValue;
    plaintext := Decrypt(msg.duress_placeholder, SARActor(self));
    assert plaintext # NoValue;
    if /\ ~IsSafePaddingPlaintextForPeer(self, plaintext)
       /\ <<BoomletActor(self), msg.duress_placeholder.iv>> \notin sar_seen_placeholder_iv_i[self]
    then
        sar_escalated_i[self] := TRUE;
        sar_last_doxing_identifier_i[self] := DoxingDataIdentifier(plaintext);
        sar_seen_placeholder_iv_i[self] := sar_seen_placeholder_iv_i[self] \cup { <<BoomletActor(self), msg.duress_placeholder.iv>> };
    end if;
    reply := SARReplyCipher(self, msg.duress_placeholder);
    assert sar_to_wt[self] = NoValue;
    if msg.kind = "WithdrawalWtSarsMessage2" then
        sar_to_wt[self] := WithdrawalSarsWtMessage2(reply);
        wire_trace := wire_trace \cup { WireHop(SARActor(self), WTActor, WithdrawalSarsWtMessage2(reply)) };
    elsif msg.kind = "WithdrawalWtSarsMessage1" then
        sar_to_wt[self] := WithdrawalSarsWtMessage1(reply);
        wire_trace := wire_trace \cup { WireHop(SARActor(self), WTActor, WithdrawalSarsWtMessage1(reply)) };
    else
        sar_to_wt[self] := WithdrawalNonInitiatorSarsWtMessage1(reply);
        wire_trace := wire_trace \cup { WireHop(SARActor(self), WTActor, WithdrawalNonInitiatorSarsWtMessage1(reply)) };
    end if;
    goto SARLoop;
end process;

process Watchtower = WT_ID
variables msg = NoValue,
          peer = INITIATOR,
          decrypted = NoValue,
          signedInner = NoValue,
          placeholder = NoValue,
          wtHeight = 0,
          pongMap = [i \in Peers |-> NoValue];
begin
WTLoop:
    await (\E i \in Peers : niso_to_wt[i] # NoValue)
       \/ (\E i \in Peers : sar_to_wt[i] # NoValue)
       \/ ( /\ ~wt_relayed_all_approvals
            /\ \A j \in NonInitiators : wt_noninitiator_tx_approval_i[j] # NoValue
            /\ \A j \in Peers : wt_to_niso[j] = NoValue
            /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
            /\ \A j \in NonInitiators :
                 /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height >=
                    Max2(
                        SignedContent(wt_saved_wt_tx_approval).event_block_height,
                        IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                        THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                        ELSE 0)
                 /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height <=
                    most_work_bitcoin_block_height
                        - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
            /\ SignedContent(wt_initiator_tx_approval).event_block_height >=
               Max2(
                    IF SignedContent(wt_saved_wt_tx_approval).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                    THEN SignedContent(wt_saved_wt_tx_approval).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                    ELSE 0,
                    IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                    THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                    ELSE 0)
            /\ SignedContent(wt_initiator_tx_approval).event_block_height <= SignedContent(wt_saved_wt_tx_approval).event_block_height )
       \/ ( /\ ~wt_relayed_all_commits
            /\ \A j \in Peers : wt_signed_commit_i[j] # NoValue /\ wt_commit_sar_reply_i[j] # NoValue
            /\ \A j \in Peers : wt_to_niso[j] = NoValue
            /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS
            /\ \A j \in Peers :
                 /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height >=
                    IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                    THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                    ELSE 0
                 /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height <=
                    most_work_bitcoin_block_height
                        - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS );
    if /\ ~wt_relayed_all_approvals
       /\ \A j \in NonInitiators : wt_noninitiator_tx_approval_i[j] # NoValue
       /\ \A j \in Peers : wt_to_niso[j] = NoValue
       /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
       /\ \A j \in NonInitiators :
            /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height >=
               Max2(
                    SignedContent(wt_saved_wt_tx_approval).event_block_height,
                    IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                    THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                    ELSE 0)
            /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height <=
               most_work_bitcoin_block_height
                   - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
       /\ SignedContent(wt_initiator_tx_approval).event_block_height >=
          Max2(
                IF SignedContent(wt_saved_wt_tx_approval).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                THEN SignedContent(wt_saved_wt_tx_approval).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                ELSE 0,
                IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                ELSE 0)
       /\ SignedContent(wt_initiator_tx_approval).event_block_height <= SignedContent(wt_saved_wt_tx_approval).event_block_height
    then
        wt_to_niso := [j \in Peers |->
            IF j = INITIATOR
            THEN WithdrawalWtNisoMessage1([k \in Peers |->
                    IF k = INITIATOR THEN wt_initiator_tx_approval ELSE wt_noninitiator_tx_approval_i[k]],
                  wt_saved_wt_tx_approval)
            ELSE WithdrawalWtNonInitiatorNisoMessage2([k \in NonInitiators |-> wt_noninitiator_tx_approval_i[k]])];
        wt_relayed_all_approvals := TRUE;
        wire_trace := wire_trace \cup
            { WireHop(WTActor, NisoActor(j),
                IF j = INITIATOR
                THEN WithdrawalWtNisoMessage1([k \in Peers |->
                        IF k = INITIATOR THEN wt_initiator_tx_approval ELSE wt_noninitiator_tx_approval_i[k]],
                      wt_saved_wt_tx_approval)
                ELSE WithdrawalWtNonInitiatorNisoMessage2([k \in NonInitiators |-> wt_noninitiator_tx_approval_i[k]])) : j \in Peers };
    elsif /\ ~wt_relayed_all_commits
          /\ \A j \in Peers : wt_signed_commit_i[j] # NoValue /\ wt_commit_sar_reply_i[j] # NoValue
          /\ \A j \in Peers : wt_to_niso[j] = NoValue
          /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS
          /\ \A j \in Peers :
               /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height >=
                  IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                  THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                  ELSE 0
               /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height <=
                  most_work_bitcoin_block_height
                      - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS
    then
        wt_to_niso := [j \in Peers |->
            IF j = INITIATOR
            THEN WithdrawalWtNisoMessage2(wt_signed_commit_i, wt_commit_sar_reply_i[j])
            ELSE WithdrawalWtNonInitiatorNisoMessage4(wt_signed_commit_i, wt_commit_sar_reply_i[j])];
        wt_relayed_all_commits := TRUE;
        wire_trace := wire_trace \cup
            { WireHop(WTActor, NisoActor(j),
                IF j = INITIATOR
                THEN WithdrawalWtNisoMessage2(wt_signed_commit_i, wt_commit_sar_reply_i[j])
                ELSE WithdrawalWtNonInitiatorNisoMessage4(wt_signed_commit_i, wt_commit_sar_reply_i[j])) : j \in Peers };
    elsif \E i \in Peers : sar_to_wt[i] # NoValue then
        with i \in { j \in Peers : sar_to_wt[j] # NoValue } do
            peer := i;
            msg := sar_to_wt[peer];
            sar_to_wt[peer] := NoValue;
            if wt_pending_sar_stage_i[peer] = "commit" then
                assert SARReplyValidForPeer(peer, wt_pending_placeholder_i[peer], msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet);
                wt_commit_sar_reply_i[peer] := msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet;
                signedInner := wt_pending_signed_inner_i[peer];
                wtHeight := most_work_bitcoin_block_height;
                assert CommitSigValid(
                    signedInner,
                    peer,
                    wt_saved_tx_id,
                    0,
                    wtHeight);
                wt_signed_commit_i[peer] := SignatureOnMessage(WTActor, signedInner);
                if peer = INITIATOR then
                    assert \A j \in NonInitiators : wt_to_niso[j] = NoValue;
                    wt_to_niso := [j \in Peers |->
                        IF j \in NonInitiators
                        THEN WithdrawalWtNonInitiatorNisoMessage3(wt_signed_commit_i[peer])
                        ELSE wt_to_niso[j]];
                    wire_trace := wire_trace \cup
                        { WireHop(WTActor, NisoActor(j), WithdrawalWtNonInitiatorNisoMessage3(wt_signed_commit_i[peer])) : j \in NonInitiators };
                end if;
            else
                assert wt_pending_sar_stage_i[peer] = "ping";
                assert SARReplyValidForPeer(peer, wt_pending_placeholder_i[peer], msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet);
                wt_ping_sar_reply_i[peer] := msg.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet;
                signedInner := wt_pending_signed_inner_i[peer];
                wtHeight := most_work_bitcoin_block_height;
                assert PingSigValid(
                    signedInner,
                    peer,
                    wt_saved_tx_id,
                    IF wtHeight >= TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_TO_RECEIVING_ALL_PINGS_BY_WT_AND_HAVING_SAR_RESPONSE_BACK_TO_WT
                    THEN wtHeight - TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_TO_RECEIVING_ALL_PINGS_BY_WT_AND_HAVING_SAR_RESPONSE_BACK_TO_WT
                    ELSE 0,
                    wtHeight);
                if wt_last_accepted_ping_i[peer] = NoValue then
                    assert ~SignedContent(signedInner).reached_mystery_flag;
                else
                    assert SignedContent(signedInner).ping_seq_num > SignedContent(wt_last_accepted_ping_i[peer]).ping_seq_num;
                end if;
                wt_last_accepted_ping_i[peer] := signedInner;
                if SignedContent(signedInner).reached_mystery_flag then
                    wt_reached_pings_collection[peer] := signedInner;
                end if;
                if AllReached(wt_reached_pings_collection) then
                    assert \A j \in Peers : wt_to_niso[j] = NoValue;
                    wt_to_niso := [j \in Peers |-> WithdrawalWtNisoMessage4(ReachedPingsCollection(wt_reached_pings_collection))];
                    wire_trace := wire_trace \cup
                        { WireHop(WTActor, NisoActor(j), WithdrawalWtNisoMessage4(ReachedPingsCollection(wt_reached_pings_collection))) : j \in Peers };
                elsif /\ \A j \in Peers : wt_last_accepted_ping_i[j] # NoValue
                      /\ (wt_last_pong_height = NoValue
                          \/ most_work_bitcoin_block_height >= wt_last_pong_height + REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PING_AND_PONG)
                then
                    assert \A j \in Peers : wt_to_niso[j] = NoValue;
                    wt_last_pong_height := most_work_bitcoin_block_height;
                    wt_to_niso := [j \in Peers |->
                        WithdrawalWtNisoMessage3(
                            PongCipherForPeer(j, wt_saved_tx_id, most_work_bitcoin_block_height, [k \in (Peers \ {j}) |-> wt_last_accepted_ping_i[k]]),
                            wt_ping_sar_reply_i[j])];
                    wire_trace := wire_trace \cup
                        { WireHop(WTActor, NisoActor(j),
                            WithdrawalWtNisoMessage3(
                                PongCipherForPeer(j, wt_saved_tx_id, most_work_bitcoin_block_height, [k \in (Peers \ {j}) |-> wt_last_accepted_ping_i[k]]),
                                wt_ping_sar_reply_i[j])) : j \in Peers };
                end if;
            end if;
            wt_pending_sar_stage_i[peer] := NoValue;
            wt_pending_placeholder_i[peer] := NoValue;
            wt_pending_signed_inner_i[peer] := NoValue;
        end with;
    else
        with i \in { j \in Peers : niso_to_wt[j] # NoValue } do
            peer := i;
            msg := niso_to_wt[peer];
            niso_to_wt[peer] := NoValue;
            if msg.kind = "WithdrawalNisoWtMessage1" then
                decrypted := Decrypt(msg.initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, WTActor);
                assert TxApprovalSigValid(
                    decrypted,
                    INITIATOR,
                    SignedContent(decrypted).tx_id,
                    0,
                    most_work_bitcoin_block_height);
                wt_saved_tx_id := SignedContent(decrypted).tx_id;
                wt_initiator_tx_approval := decrypted;
                wt_saved_wt_tx_approval := SignedWTTxApproval(wt_saved_tx_id, most_work_bitcoin_block_height, INITIATOR);
                assert \A j \in NonInitiators : wt_to_niso[j] = NoValue;
                wt_to_niso := [j \in Peers |->
                    IF j \in NonInitiators
                    THEN WithdrawalWtNonInitiatorNisoMessage1(
                        wt_saved_wt_tx_approval,
                        wt_initiator_tx_approval,
                        msg.psbt_encrypted_collection.items[j])
                    ELSE wt_to_niso[j]];
                wire_trace := wire_trace \cup
                    { WireHop(WTActor, NisoActor(j),
                        WithdrawalWtNonInitiatorNisoMessage1(
                            wt_saved_wt_tx_approval,
                            wt_initiator_tx_approval,
                            msg.psbt_encrypted_collection.items[j])) : j \in NonInitiators };
            elsif msg.kind = "WithdrawalNonInitiatorNisoWtMessage1" then
                decrypted := Decrypt(msg.peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt, WTActor);
                assert TxApprovalSigValid(
                    decrypted,
                    peer,
                    wt_saved_tx_id,
                    SignedContent(wt_saved_wt_tx_approval).event_block_height,
                    most_work_bitcoin_block_height);
                wt_noninitiator_tx_approval_i[peer] := decrypted;
            elsif msg.kind = "WithdrawalNonInitiatorNisoWtMessage2" then
                assert ApprovalsBundleSigValid(
                    msg.approvals_signed_by_boomlet_i,
                    peer,
                    [k \in Peers |->
                        IF k = INITIATOR THEN wt_initiator_tx_approval ELSE wt_noninitiator_tx_approval_i[k]],
                    wt_saved_wt_tx_approval);
                wt_approvals_bundle_i[peer] := msg.approvals_signed_by_boomlet_i;
            elsif msg.kind = "WithdrawalNisoWtMessage2" then
                decrypted := Decrypt(msg.peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, WTActor);
                assert ValidSig(decrypted, BoomletActor(peer));
                placeholder := PaddedPadding(SignedContent(decrypted));
                signedInner := PaddedContent(SignedContent(decrypted));
                wt_pending_sar_stage_i[peer] := "commit";
                wt_pending_placeholder_i[peer] := placeholder;
                wt_pending_signed_inner_i[peer] := signedInner;
                assert wt_to_sar[peer] = NoValue;
                wt_to_sar[peer] := WithdrawalWtSarsMessage1(placeholder, BoomletActor(peer));
                wire_trace := wire_trace \cup { WireHop(WTActor, SARActor(peer), WithdrawalWtSarsMessage1(placeholder, BoomletActor(peer))) };
            elsif msg.kind = "WithdrawalNonInitiatorNisoWtMessage3" then
                decrypted := Decrypt(msg.peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt, WTActor);
                assert ValidSig(decrypted, BoomletActor(peer));
                placeholder := PaddedPadding(SignedContent(decrypted));
                signedInner := PaddedContent(SignedContent(decrypted));
                wt_pending_sar_stage_i[peer] := "commit";
                wt_pending_placeholder_i[peer] := placeholder;
                wt_pending_signed_inner_i[peer] := signedInner;
                assert wt_to_sar[peer] = NoValue;
                wt_to_sar[peer] := WithdrawalNonInitiatorWtSarsMessage1(placeholder, BoomletActor(peer));
                wire_trace := wire_trace \cup { WireHop(WTActor, SARActor(peer), WithdrawalNonInitiatorWtSarsMessage1(placeholder, BoomletActor(peer))) };
            elsif msg.kind \in {"WithdrawalNisoWtMessage3", "WithdrawalNisoWtMessage4", "WithdrawalNonInitiatorNisoWtMessage4"} then
                decrypted := Decrypt(msg.peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt, WTActor);
                assert ValidSig(decrypted, BoomletActor(peer));
                placeholder := PaddedPadding(SignedContent(decrypted));
                signedInner := PaddedContent(SignedContent(decrypted));
                wt_pending_sar_stage_i[peer] := "ping";
                wt_pending_placeholder_i[peer] := placeholder;
                wt_pending_signed_inner_i[peer] := signedInner;
                assert wt_to_sar[peer] = NoValue;
                wt_to_sar[peer] := WithdrawalWtSarsMessage2(placeholder, BoomletActor(peer));
                wire_trace := wire_trace \cup { WireHop(WTActor, SARActor(peer), WithdrawalWtSarsMessage2(placeholder, BoomletActor(peer))) };
            else
                assert msg.kind = "WithdrawalNisoWtMessage5";
                wt_signed_psbt_i[peer] := msg.psbt_signed_i;
                if AllPeerSignedPsbtsPresent(wt_signed_psbt_i) then
                    wt_broadcast := Broadcast(wt_saved_tx_id, Collection(wt_signed_psbt_i));
                end if;
            end if;
        end with;
    end if;
    goto WTLoop;
end process;

process Environment = "ENV"
begin
Tick:
    most_work_bitcoin_block_height := most_work_bitcoin_block_height + 1;
    goto Tick;
end process;
end algorithm;
*)
\* BEGIN TRANSLATION (chksum(pcal) = "bfffc32e" /\ chksum(tla) = "9d53d9f4")
\* Process variable msg of process UserFlow at line 1145 col 11 changed to msg_
\* Process variable signalIndex of process UserFlow at line 1146 col 11 changed to signalIndex_
\* Process variable msg of process STFlow at line 1211 col 11 changed to msg_S
\* Process variable msg of process NisoFlow at line 1275 col 11 changed to msg_N
\* Process variable msg of process BoomletFlow at line 1613 col 11 changed to msg_B
\* Process variable msg of process IsoFlow at line 2056 col 11 changed to msg_I
\* Process variable msg of process SARFlow at line 2090 col 11 changed to msg_SA
VARIABLES wire_trace, boomerang_descriptor, peer_id_collection, 
          st_identity_pubkey_i, sar_pubkey_i, doxing_key_i, 
          duress_consent_set_i, boomlet_mystery_i, 
          most_work_bitcoin_block_height, user_saved_psbt_i, 
          user_initiator_peer_id_i, user_last_duress_space_i, 
          user_sent_initial_psbt_i, user_sent_psbt_agreement_i, 
          user_sent_iso_credentials_i, user_sent_connect_back_to_niso_i, 
          niso_saved_psbt_i, niso_saved_tx_id_i, niso_event_block_height_i, 
          niso_initiator_peer_id_i, niso_saved_wt_tx_approval_i, 
          niso_hydrated_psbt_i, niso_reached_pings_collection_i, 
          boomlet_saved_psbt_i, boomlet_committed_tx_id_i, 
          boomlet_pending_txid_nonce_i, boomlet_saved_duress_space_i, 
          boomlet_saved_duress_stage_i, boomlet_saved_duress_seq_i, 
          boomlet_pending_duress_nonce_i, 
          boomlet_duress_placeholder_plaintext_i, 
          boomlet_duress_placeholder_cipher_i, boomlet_signed_tx_approval_i, 
          boomlet_saved_wt_tx_approval_i, boomlet_all_peer_approvals_i, 
          boomlet_approvals_bundle_i, boomlet_signed_commit_inner_i, 
          boomlet_commit_collection_i, boomlet_counter_i, 
          boomlet_last_seen_block_i, boomlet_ping_seq_num_i, 
          boomlet_reached_mystery_flag_i, boomlet_known_reached_i, 
          boomlet_prev_pings_i, boomlet_ready_to_sign_i, 
          boomlet_signed_psbt_i, boomlet_pubnonce_boom_i, 
          boomlet_partialsig_boom_i, st_last_txid_with_nonce_i, 
          st_last_duress_check_i, iso_pubnonce_normal_i, 
          iso_partialsig_normal_i, iso_signed_psbt_i, 
          sar_seen_placeholder_iv_i, sar_escalated_i, 
          sar_last_doxing_identifier_i, wt_saved_tx_id, 
          wt_saved_wt_tx_approval, wt_initiator_tx_approval, 
          wt_noninitiator_tx_approval_i, wt_approvals_bundle_i, 
          wt_pending_sar_stage_i, wt_pending_placeholder_i, 
          wt_pending_signed_inner_i, wt_commit_sar_reply_i, 
          wt_ping_sar_reply_i, wt_signed_commit_i, wt_last_accepted_ping_i, 
          wt_reached_pings_collection, wt_last_pong_height, 
          wt_relayed_all_approvals, wt_relayed_all_commits, wt_signed_psbt_i, 
          wt_broadcast, user_to_niso, niso_to_user, user_to_st, st_to_user, 
          boomlet_to_niso, niso_to_boomlet, niso_to_st, st_to_niso, 
          user_to_iso, iso_to_user, boomlet_to_iso, iso_to_boomlet, 
          niso_to_wt, wt_to_niso, wt_to_sar, sar_to_wt, pc, msg_, 
          signalIndex_, msg_S, nonceWrapped, signalIndex, msg_N, approvalSig, 
          wtSig, commitSig, signedPing, msg_B, signedAck, duressSignal, 
          hydrated, signedPong, prevPings, msg_I, msg_SA, plaintext, reply, 
          msg, peer, decrypted, signedInner, placeholder, wtHeight, pongMap

vars == << wire_trace, boomerang_descriptor, peer_id_collection, 
           st_identity_pubkey_i, sar_pubkey_i, doxing_key_i, 
           duress_consent_set_i, boomlet_mystery_i, 
           most_work_bitcoin_block_height, user_saved_psbt_i, 
           user_initiator_peer_id_i, user_last_duress_space_i, 
           user_sent_initial_psbt_i, user_sent_psbt_agreement_i, 
           user_sent_iso_credentials_i, user_sent_connect_back_to_niso_i, 
           niso_saved_psbt_i, niso_saved_tx_id_i, niso_event_block_height_i, 
           niso_initiator_peer_id_i, niso_saved_wt_tx_approval_i, 
           niso_hydrated_psbt_i, niso_reached_pings_collection_i, 
           boomlet_saved_psbt_i, boomlet_committed_tx_id_i, 
           boomlet_pending_txid_nonce_i, boomlet_saved_duress_space_i, 
           boomlet_saved_duress_stage_i, boomlet_saved_duress_seq_i, 
           boomlet_pending_duress_nonce_i, 
           boomlet_duress_placeholder_plaintext_i, 
           boomlet_duress_placeholder_cipher_i, boomlet_signed_tx_approval_i, 
           boomlet_saved_wt_tx_approval_i, boomlet_all_peer_approvals_i, 
           boomlet_approvals_bundle_i, boomlet_signed_commit_inner_i, 
           boomlet_commit_collection_i, boomlet_counter_i, 
           boomlet_last_seen_block_i, boomlet_ping_seq_num_i, 
           boomlet_reached_mystery_flag_i, boomlet_known_reached_i, 
           boomlet_prev_pings_i, boomlet_ready_to_sign_i, 
           boomlet_signed_psbt_i, boomlet_pubnonce_boom_i, 
           boomlet_partialsig_boom_i, st_last_txid_with_nonce_i, 
           st_last_duress_check_i, iso_pubnonce_normal_i, 
           iso_partialsig_normal_i, iso_signed_psbt_i, 
           sar_seen_placeholder_iv_i, sar_escalated_i, 
           sar_last_doxing_identifier_i, wt_saved_tx_id, 
           wt_saved_wt_tx_approval, wt_initiator_tx_approval, 
           wt_noninitiator_tx_approval_i, wt_approvals_bundle_i, 
           wt_pending_sar_stage_i, wt_pending_placeholder_i, 
           wt_pending_signed_inner_i, wt_commit_sar_reply_i, 
           wt_ping_sar_reply_i, wt_signed_commit_i, wt_last_accepted_ping_i, 
           wt_reached_pings_collection, wt_last_pong_height, 
           wt_relayed_all_approvals, wt_relayed_all_commits, wt_signed_psbt_i, 
           wt_broadcast, user_to_niso, niso_to_user, user_to_st, st_to_user, 
           boomlet_to_niso, niso_to_boomlet, niso_to_st, st_to_niso, 
           user_to_iso, iso_to_user, boomlet_to_iso, iso_to_boomlet, 
           niso_to_wt, wt_to_niso, wt_to_sar, sar_to_wt, pc, msg_, 
           signalIndex_, msg_S, nonceWrapped, signalIndex, msg_N, approvalSig, 
           wtSig, commitSig, signedPing, msg_B, signedAck, duressSignal, 
           hydrated, signedPong, prevPings, msg_I, msg_SA, plaintext, reply, 
           msg, peer, decrypted, signedInner, placeholder, wtHeight, pongMap
        >>

ProcSet == (Peers) \cup (Peers) \cup (Peers) \cup (Peers) \cup (Peers) \cup (Peers) \cup {WT_ID} \cup {"ENV"}

Init == (* Global variables *)
        /\ wire_trace = {}
        /\ boomerang_descriptor = [milestone_block_0 |-> Milestone0]
        /\ peer_id_collection = { BoomletActor(i) : i \in Peers }
        /\ st_identity_pubkey_i = [i \in Peers |-> STActor(i)]
        /\ sar_pubkey_i = [i \in Peers |-> SARActor(i)]
        /\ doxing_key_i = InitDoxingKey
        /\ duress_consent_set_i = InitConsentSet
        /\ boomlet_mystery_i = InitMystery
        /\ most_work_bitcoin_block_height = Milestone0
        /\ user_saved_psbt_i = [i \in Peers |-> IF i = INITIATOR THEN CanonicalPsbt ELSE NoValue]
        /\ user_initiator_peer_id_i = [i \in Peers |-> NoValue]
        /\ user_last_duress_space_i = [i \in Peers |-> NoValue]
        /\ user_sent_initial_psbt_i = [i \in Peers |-> FALSE]
        /\ user_sent_psbt_agreement_i = [i \in Peers |-> FALSE]
        /\ user_sent_iso_credentials_i = [i \in Peers |-> FALSE]
        /\ user_sent_connect_back_to_niso_i = [i \in Peers |-> FALSE]
        /\ niso_saved_psbt_i = [i \in Peers |-> NoValue]
        /\ niso_saved_tx_id_i = [i \in Peers |-> NoValue]
        /\ niso_event_block_height_i = [i \in Peers |-> Milestone0]
        /\ niso_initiator_peer_id_i = [i \in Peers |-> NoValue]
        /\ niso_saved_wt_tx_approval_i = [i \in Peers |-> NoValue]
        /\ niso_hydrated_psbt_i = [i \in Peers |-> NoValue]
        /\ niso_reached_pings_collection_i = [i \in Peers |-> NoValue]
        /\ boomlet_saved_psbt_i = [i \in Peers |-> NoValue]
        /\ boomlet_committed_tx_id_i = [i \in Peers |-> NoValue]
        /\ boomlet_pending_txid_nonce_i = [i \in Peers |-> NoValue]
        /\ boomlet_saved_duress_space_i = [i \in Peers |-> NoValue]
        /\ boomlet_saved_duress_stage_i = [i \in Peers |-> NoValue]
        /\ boomlet_saved_duress_seq_i = [i \in Peers |-> 0]
        /\ boomlet_pending_duress_nonce_i = [i \in Peers |-> NoValue]
        /\ boomlet_duress_placeholder_plaintext_i = [i \in Peers |-> NoValue]
        /\ boomlet_duress_placeholder_cipher_i = [i \in Peers |-> NoValue]
        /\ boomlet_signed_tx_approval_i = [i \in Peers |-> NoValue]
        /\ boomlet_saved_wt_tx_approval_i = [i \in Peers |-> NoValue]
        /\ boomlet_all_peer_approvals_i = [i \in Peers |-> NoValue]
        /\ boomlet_approvals_bundle_i = [i \in Peers |-> NoValue]
        /\ boomlet_signed_commit_inner_i = [i \in Peers |-> NoValue]
        /\ boomlet_commit_collection_i = [i \in Peers |-> NoValue]
        /\ boomlet_counter_i = [i \in Peers |-> 0]
        /\ boomlet_last_seen_block_i = [i \in Peers |-> Milestone0]
        /\ boomlet_ping_seq_num_i = [i \in Peers |-> 0]
        /\ boomlet_reached_mystery_flag_i = [i \in Peers |-> FALSE]
        /\ boomlet_known_reached_i = [i \in Peers |-> {}]
        /\ boomlet_prev_pings_i = [i \in Peers |-> NoValue]
        /\ boomlet_ready_to_sign_i = [i \in Peers |-> FALSE]
        /\ boomlet_signed_psbt_i = [i \in Peers |-> NoValue]
        /\ boomlet_pubnonce_boom_i = [i \in Peers |-> NoValue]
        /\ boomlet_partialsig_boom_i = [i \in Peers |-> NoValue]
        /\ st_last_txid_with_nonce_i = [i \in Peers |-> NoValue]
        /\ st_last_duress_check_i = [i \in Peers |-> NoValue]
        /\ iso_pubnonce_normal_i = [i \in Peers |-> NoValue]
        /\ iso_partialsig_normal_i = [i \in Peers |-> NoValue]
        /\ iso_signed_psbt_i = [i \in Peers |-> NoValue]
        /\ sar_seen_placeholder_iv_i = [i \in Peers |-> {}]
        /\ sar_escalated_i = [i \in Peers |-> FALSE]
        /\ sar_last_doxing_identifier_i = [i \in Peers |-> NoValue]
        /\ wt_saved_tx_id = NoValue
        /\ wt_saved_wt_tx_approval = NoValue
        /\ wt_initiator_tx_approval = NoValue
        /\ wt_noninitiator_tx_approval_i = [i \in Peers |-> NoValue]
        /\ wt_approvals_bundle_i = [i \in Peers |-> NoValue]
        /\ wt_pending_sar_stage_i = [i \in Peers |-> NoValue]
        /\ wt_pending_placeholder_i = [i \in Peers |-> NoValue]
        /\ wt_pending_signed_inner_i = [i \in Peers |-> NoValue]
        /\ wt_commit_sar_reply_i = [i \in Peers |-> NoValue]
        /\ wt_ping_sar_reply_i = [i \in Peers |-> NoValue]
        /\ wt_signed_commit_i = [i \in Peers |-> NoValue]
        /\ wt_last_accepted_ping_i = [i \in Peers |-> NoValue]
        /\ wt_reached_pings_collection = [i \in Peers |-> NoValue]
        /\ wt_last_pong_height = NoValue
        /\ wt_relayed_all_approvals = FALSE
        /\ wt_relayed_all_commits = FALSE
        /\ wt_signed_psbt_i = [i \in Peers |-> NoValue]
        /\ wt_broadcast = NoValue
        /\ user_to_niso = [i \in Peers |-> NoValue]
        /\ niso_to_user = [i \in Peers |-> NoValue]
        /\ user_to_st = [i \in Peers |-> NoValue]
        /\ st_to_user = [i \in Peers |-> NoValue]
        /\ boomlet_to_niso = [i \in Peers |-> NoValue]
        /\ niso_to_boomlet = [i \in Peers |-> NoValue]
        /\ niso_to_st = [i \in Peers |-> NoValue]
        /\ st_to_niso = [i \in Peers |-> NoValue]
        /\ user_to_iso = [i \in Peers |-> NoValue]
        /\ iso_to_user = [i \in Peers |-> NoValue]
        /\ boomlet_to_iso = [i \in Peers |-> NoValue]
        /\ iso_to_boomlet = [i \in Peers |-> NoValue]
        /\ niso_to_wt = [i \in Peers |-> NoValue]
        /\ wt_to_niso = [i \in Peers |-> NoValue]
        /\ wt_to_sar = [i \in Peers |-> NoValue]
        /\ sar_to_wt = [i \in Peers |-> NoValue]
        (* Process UserFlow *)
        /\ msg_ = [self \in Peers |-> NoValue]
        /\ signalIndex_ = [self \in Peers |-> NoValue]
        (* Process STFlow *)
        /\ msg_S = [self \in Peers |-> NoValue]
        /\ nonceWrapped = [self \in Peers |-> NoValue]
        /\ signalIndex = [self \in Peers |-> NoValue]
        (* Process NisoFlow *)
        /\ msg_N = [self \in Peers |-> NoValue]
        /\ approvalSig = [self \in Peers |-> NoValue]
        /\ wtSig = [self \in Peers |-> NoValue]
        /\ commitSig = [self \in Peers |-> NoValue]
        /\ signedPing = [self \in Peers |-> NoValue]
        (* Process BoomletFlow *)
        /\ msg_B = [self \in Peers |-> NoValue]
        /\ signedAck = [self \in Peers |-> NoValue]
        /\ duressSignal = [self \in Peers |-> NoValue]
        /\ hydrated = [self \in Peers |-> NoValue]
        /\ signedPong = [self \in Peers |-> NoValue]
        /\ prevPings = [self \in Peers |-> NoValue]
        (* Process IsoFlow *)
        /\ msg_I = [self \in Peers |-> NoValue]
        (* Process SARFlow *)
        /\ msg_SA = [self \in Peers |-> NoValue]
        /\ plaintext = [self \in Peers |-> NoValue]
        /\ reply = [self \in Peers |-> NoValue]
        (* Process Watchtower *)
        /\ msg = NoValue
        /\ peer = INITIATOR
        /\ decrypted = NoValue
        /\ signedInner = NoValue
        /\ placeholder = NoValue
        /\ wtHeight = 0
        /\ pongMap = [i \in Peers |-> NoValue]
        /\ pc = [self \in ProcSet |-> CASE self \in Peers -> "UserLoop"
                                        [] self \in Peers -> "STLoop"
                                        [] self \in Peers -> "NisoLoop"
                                        [] self \in Peers -> "BoomletLoop"
                                        [] self \in Peers -> "IsoLoop"
                                        [] self \in Peers -> "SARLoop"
                                        [] self = WT_ID -> "WTLoop"
                                        [] self = "ENV" -> "Tick"]

UserLoop(self) == /\ pc[self] = "UserLoop"
                  /\    (self = INITIATOR /\ ~user_sent_initial_psbt_i[self] /\ user_to_niso[self] = NoValue)
                     \/ st_to_user[self] # NoValue
                     \/ niso_to_user[self] # NoValue
                     \/ iso_to_user[self] # NoValue
                  /\ IF self = INITIATOR /\ ~user_sent_initial_psbt_i[self] /\ user_to_niso[self] = NoValue
                        THEN /\ user_to_niso' = [user_to_niso EXCEPT ![self] = WithdrawalNisoInput1(CanonicalPsbt)]
                             /\ user_sent_initial_psbt_i' = [user_sent_initial_psbt_i EXCEPT ![self] = TRUE]
                             /\ wire_trace' = (wire_trace \cup { WireHop(UserActor(self), NisoActor(self), WithdrawalNisoInput1(CanonicalPsbt)) })
                             /\ UNCHANGED << user_saved_psbt_i, 
                                             user_initiator_peer_id_i, 
                                             user_last_duress_space_i, 
                                             user_sent_psbt_agreement_i, 
                                             user_sent_iso_credentials_i, 
                                             user_sent_connect_back_to_niso_i, 
                                             niso_to_user, user_to_st, 
                                             st_to_user, user_to_iso, 
                                             iso_to_user, msg_, signalIndex_ >>
                        ELSE /\ IF st_to_user[self] # NoValue
                                   THEN /\ msg_' = [msg_ EXCEPT ![self] = st_to_user[self]]
                                        /\ st_to_user' = [st_to_user EXCEPT ![self] = NoValue]
                                        /\ IF msg_'[self].kind = TxIdOutputKind(self)
                                              THEN /\ Assert(msg_'[self].tx_id = TxOfPsbt[user_saved_psbt_i[self]], 
                                                             "Failure of assertion at line 1161, column 13.")
                                                   /\ Assert(user_to_st[self] = NoValue, 
                                                             "Failure of assertion at line 1162, column 13.")
                                                   /\ user_to_st' = [user_to_st EXCEPT ![self] = TxIdUserAckMessage(self)]
                                                   /\ wire_trace' = (wire_trace \cup { WireHop(UserActor(self), STActor(self), TxIdUserAckMessage(self)) })
                                                   /\ UNCHANGED << user_last_duress_space_i, 
                                                                   signalIndex_ >>
                                              ELSE /\ IF msg_'[self].kind \in {InitialDuressOutputKind(self), RecurringDuressOutputKind}
                                                         THEN /\ user_last_duress_space_i' = [user_last_duress_space_i EXCEPT ![self] = msg_'[self].duress_check_space]
                                                              /\ signalIndex_' = [signalIndex_ EXCEPT ![self] = BuildDuressSignalIndex(msg_'[self].duress_check_space, TRUE, duress_consent_set_i[self])]
                                                              /\ Assert(user_to_st[self] = NoValue, 
                                                                        "Failure of assertion at line 1168, column 13.")
                                                              /\ user_to_st' = [user_to_st EXCEPT ![self] = [ kind |-> IF msg_'[self].kind = RecurringDuressOutputKind THEN RecurringDuressInputKind ELSE InitialDuressInputKind(self),
                                                                                                              duress_signal_index |-> signalIndex_'[self],
                                                                                                              stage |-> msg_'[self].stage,
                                                                                                              seq |-> msg_'[self].seq ]]
                                                              /\ wire_trace' = (          wire_trace \cup
                                                                                { WireHop(UserActor(self), STActor(self),
                                                                                    [ kind |-> IF msg_'[self].kind = RecurringDuressOutputKind THEN RecurringDuressInputKind ELSE InitialDuressInputKind(self),
                                                                                      duress_signal_index |-> signalIndex_'[self],
                                                                                      stage |-> msg_'[self].stage,
                                                                                      seq |-> msg_'[self].seq ]) })
                                                         ELSE /\ TRUE
                                                              /\ UNCHANGED << wire_trace, 
                                                                              user_last_duress_space_i, 
                                                                              user_to_st, 
                                                                              signalIndex_ >>
                                        /\ UNCHANGED << user_saved_psbt_i, 
                                                        user_initiator_peer_id_i, 
                                                        user_sent_psbt_agreement_i, 
                                                        user_sent_iso_credentials_i, 
                                                        user_sent_connect_back_to_niso_i, 
                                                        user_to_niso, 
                                                        niso_to_user, 
                                                        user_to_iso, 
                                                        iso_to_user >>
                                   ELSE /\ IF niso_to_user[self] # NoValue
                                              THEN /\ msg_' = [msg_ EXCEPT ![self] = niso_to_user[self]]
                                                   /\ niso_to_user' = [niso_to_user EXCEPT ![self] = NoValue]
                                                   /\ IF msg_'[self].kind = "WithdrawalNonInitiatorNisoOutput1"
                                                         THEN /\ user_saved_psbt_i' = [user_saved_psbt_i EXCEPT ![self] = msg_'[self].psbt]
                                                              /\ user_initiator_peer_id_i' = [user_initiator_peer_id_i EXCEPT ![self] = msg_'[self].initiator_peer_id]
                                                              /\ Assert(user_to_niso[self] = NoValue, 
                                                                        "Failure of assertion at line 1187, column 13.")
                                                              /\ user_to_niso' = [user_to_niso EXCEPT ![self] = WithdrawalNonInitiatorNisoInput1]
                                                              /\ user_sent_psbt_agreement_i' = [user_sent_psbt_agreement_i EXCEPT ![self] = TRUE]
                                                              /\ wire_trace' = (wire_trace \cup { WireHop(UserActor(self), NisoActor(self), WithdrawalNonInitiatorNisoInput1) })
                                                              /\ UNCHANGED << user_sent_iso_credentials_i, 
                                                                              user_to_iso >>
                                                         ELSE /\ IF msg_'[self].kind = "WithdrawalNisoOutput1"
                                                                    THEN /\ Assert(user_to_iso[self] = NoValue, 
                                                                                   "Failure of assertion at line 1192, column 13.")
                                                                         /\ user_to_iso' = [user_to_iso EXCEPT ![self] = WithdrawalIsoInput1]
                                                                         /\ user_sent_iso_credentials_i' = [user_sent_iso_credentials_i EXCEPT ![self] = TRUE]
                                                                         /\ wire_trace' = (wire_trace \cup { WireHop(UserActor(self), IsoActor(self), WithdrawalIsoInput1) })
                                                                    ELSE /\ TRUE
                                                                         /\ UNCHANGED << wire_trace, 
                                                                                         user_sent_iso_credentials_i, 
                                                                                         user_to_iso >>
                                                              /\ UNCHANGED << user_saved_psbt_i, 
                                                                              user_initiator_peer_id_i, 
                                                                              user_sent_psbt_agreement_i, 
                                                                              user_to_niso >>
                                                   /\ UNCHANGED << user_sent_connect_back_to_niso_i, 
                                                                   iso_to_user >>
                                              ELSE /\ msg_' = [msg_ EXCEPT ![self] = iso_to_user[self]]
                                                   /\ iso_to_user' = [iso_to_user EXCEPT ![self] = NoValue]
                                                   /\ IF msg_'[self].kind = "WithdrawalIsoOutput1"
                                                         THEN /\ Assert(user_to_niso[self] = NoValue, 
                                                                        "Failure of assertion at line 1201, column 13.")
                                                              /\ user_to_niso' = [user_to_niso EXCEPT ![self] = WithdrawalNisoInput2]
                                                              /\ user_sent_connect_back_to_niso_i' = [user_sent_connect_back_to_niso_i EXCEPT ![self] = TRUE]
                                                              /\ wire_trace' = (wire_trace \cup { WireHop(UserActor(self), NisoActor(self), WithdrawalNisoInput2) })
                                                         ELSE /\ TRUE
                                                              /\ UNCHANGED << wire_trace, 
                                                                              user_sent_connect_back_to_niso_i, 
                                                                              user_to_niso >>
                                                   /\ UNCHANGED << user_saved_psbt_i, 
                                                                   user_initiator_peer_id_i, 
                                                                   user_sent_psbt_agreement_i, 
                                                                   user_sent_iso_credentials_i, 
                                                                   niso_to_user, 
                                                                   user_to_iso >>
                                        /\ UNCHANGED << user_last_duress_space_i, 
                                                        user_to_st, st_to_user, 
                                                        signalIndex_ >>
                             /\ UNCHANGED user_sent_initial_psbt_i
                  /\ pc' = [pc EXCEPT ![self] = "UserLoop"]
                  /\ UNCHANGED << boomerang_descriptor, peer_id_collection, 
                                  st_identity_pubkey_i, sar_pubkey_i, 
                                  doxing_key_i, duress_consent_set_i, 
                                  boomlet_mystery_i, 
                                  most_work_bitcoin_block_height, 
                                  niso_saved_psbt_i, niso_saved_tx_id_i, 
                                  niso_event_block_height_i, 
                                  niso_initiator_peer_id_i, 
                                  niso_saved_wt_tx_approval_i, 
                                  niso_hydrated_psbt_i, 
                                  niso_reached_pings_collection_i, 
                                  boomlet_saved_psbt_i, 
                                  boomlet_committed_tx_id_i, 
                                  boomlet_pending_txid_nonce_i, 
                                  boomlet_saved_duress_space_i, 
                                  boomlet_saved_duress_stage_i, 
                                  boomlet_saved_duress_seq_i, 
                                  boomlet_pending_duress_nonce_i, 
                                  boomlet_duress_placeholder_plaintext_i, 
                                  boomlet_duress_placeholder_cipher_i, 
                                  boomlet_signed_tx_approval_i, 
                                  boomlet_saved_wt_tx_approval_i, 
                                  boomlet_all_peer_approvals_i, 
                                  boomlet_approvals_bundle_i, 
                                  boomlet_signed_commit_inner_i, 
                                  boomlet_commit_collection_i, 
                                  boomlet_counter_i, boomlet_last_seen_block_i, 
                                  boomlet_ping_seq_num_i, 
                                  boomlet_reached_mystery_flag_i, 
                                  boomlet_known_reached_i, 
                                  boomlet_prev_pings_i, 
                                  boomlet_ready_to_sign_i, 
                                  boomlet_signed_psbt_i, 
                                  boomlet_pubnonce_boom_i, 
                                  boomlet_partialsig_boom_i, 
                                  st_last_txid_with_nonce_i, 
                                  st_last_duress_check_i, 
                                  iso_pubnonce_normal_i, 
                                  iso_partialsig_normal_i, iso_signed_psbt_i, 
                                  sar_seen_placeholder_iv_i, sar_escalated_i, 
                                  sar_last_doxing_identifier_i, wt_saved_tx_id, 
                                  wt_saved_wt_tx_approval, 
                                  wt_initiator_tx_approval, 
                                  wt_noninitiator_tx_approval_i, 
                                  wt_approvals_bundle_i, 
                                  wt_pending_sar_stage_i, 
                                  wt_pending_placeholder_i, 
                                  wt_pending_signed_inner_i, 
                                  wt_commit_sar_reply_i, wt_ping_sar_reply_i, 
                                  wt_signed_commit_i, wt_last_accepted_ping_i, 
                                  wt_reached_pings_collection, 
                                  wt_last_pong_height, 
                                  wt_relayed_all_approvals, 
                                  wt_relayed_all_commits, wt_signed_psbt_i, 
                                  wt_broadcast, boomlet_to_niso, 
                                  niso_to_boomlet, niso_to_st, st_to_niso, 
                                  boomlet_to_iso, iso_to_boomlet, niso_to_wt, 
                                  wt_to_niso, wt_to_sar, sar_to_wt, msg_S, 
                                  nonceWrapped, signalIndex, msg_N, 
                                  approvalSig, wtSig, commitSig, signedPing, 
                                  msg_B, signedAck, duressSignal, hydrated, 
                                  signedPong, prevPings, msg_I, msg_SA, 
                                  plaintext, reply, msg, peer, decrypted, 
                                  signedInner, placeholder, wtHeight, pongMap >>

UserFlow(self) == UserLoop(self)

STLoop(self) == /\ pc[self] = "STLoop"
                /\ niso_to_st[self] # NoValue \/ user_to_st[self] # NoValue
                /\ IF niso_to_st[self] # NoValue
                      THEN /\ msg_S' = [msg_S EXCEPT ![self] = niso_to_st[self]]
                           /\ niso_to_st' = [niso_to_st EXCEPT ![self] = NoValue]
                           /\ IF msg_S'[self].kind \in {"WithdrawalNisoStMessage1", "WithdrawalNonInitiatorNisoStMessage1"}
                                 THEN /\ nonceWrapped' = [nonceWrapped EXCEPT ![self] = Decrypt(msg_S'[self].tx_id_with_nonce_encrypted_by_boomlet_for_st, STActor(self))]
                                      /\ Assert(nonceWrapped'[self] # NoValue, 
                                                "Failure of assertion at line 1222, column 13.")
                                      /\ st_last_txid_with_nonce_i' = [st_last_txid_with_nonce_i EXCEPT ![self] = nonceWrapped'[self]]
                                      /\ Assert(st_to_user[self] = NoValue, 
                                                "Failure of assertion at line 1224, column 13.")
                                      /\ st_to_user' = [st_to_user EXCEPT ![self] = WithdrawalStOutput1(self, nonceWrapped'[self].content)]
                                      /\ wire_trace' = (wire_trace \cup { WireHop(STActor(self), UserActor(self), WithdrawalStOutput1(self, nonceWrapped'[self].content)) })
                                      /\ UNCHANGED st_last_duress_check_i
                                 ELSE /\ nonceWrapped' = [nonceWrapped EXCEPT ![self] = Decrypt(msg_S'[self].duress_check_space_with_nonce_encrypted_by_boomlet_for_st, STActor(self))]
                                      /\ Assert(nonceWrapped'[self] # NoValue, 
                                                "Failure of assertion at line 1229, column 13.")
                                      /\ st_last_duress_check_i' = [st_last_duress_check_i EXCEPT ![self] = nonceWrapped'[self]]
                                      /\ Assert(st_to_user[self] = NoValue, 
                                                "Failure of assertion at line 1231, column 13.")
                                      /\ IF msg_S'[self].kind = "WithdrawalNisoStMessage3"
                                            THEN /\ st_to_user' = [st_to_user EXCEPT ![self] = WithdrawalStOutput3(nonceWrapped'[self].content, nonceWrapped'[self].content.stage, nonceWrapped'[self].content.seq)]
                                                 /\ wire_trace' = (          wire_trace \cup
                                                                   { WireHop(STActor(self), UserActor(self), WithdrawalStOutput3(nonceWrapped'[self].content, nonceWrapped'[self].content.stage, nonceWrapped'[self].content.seq)) })
                                            ELSE /\ st_to_user' = [st_to_user EXCEPT ![self] = WithdrawalStOutput2(self, nonceWrapped'[self].content, nonceWrapped'[self].content.stage, nonceWrapped'[self].content.seq)]
                                                 /\ wire_trace' = (          wire_trace \cup
                                                                   { WireHop(STActor(self), UserActor(self), WithdrawalStOutput2(self, nonceWrapped'[self].content, nonceWrapped'[self].content.stage, nonceWrapped'[self].content.seq)) })
                                      /\ UNCHANGED st_last_txid_with_nonce_i
                           /\ UNCHANGED << user_to_st, st_to_niso, signalIndex >>
                      ELSE /\ msg_S' = [msg_S EXCEPT ![self] = user_to_st[self]]
                           /\ user_to_st' = [user_to_st EXCEPT ![self] = NoValue]
                           /\ IF msg_S'[self].kind \in {"WithdrawalStInput1", "WithdrawalNonInitiatorStInput1"}
                                 THEN /\ Assert(st_last_txid_with_nonce_i[self] # NoValue, 
                                                "Failure of assertion at line 1246, column 13.")
                                      /\ Assert(st_to_niso[self] = NoValue, 
                                                "Failure of assertion at line 1247, column 13.")
                                      /\ st_to_niso' = [st_to_niso EXCEPT ![self] = WithdrawalStNisoMessage1(self, TxIdAckCipher(self, st_last_txid_with_nonce_i[self].content, st_last_txid_with_nonce_i[self].nonce))]
                                      /\ wire_trace' = (          wire_trace \cup
                                                        { WireHop(STActor(self), NisoActor(self), WithdrawalStNisoMessage1(self, TxIdAckCipher(self, st_last_txid_with_nonce_i[self].content, st_last_txid_with_nonce_i[self].nonce))) })
                                      /\ UNCHANGED signalIndex
                                 ELSE /\ Assert(st_last_duress_check_i[self] # NoValue, 
                                                "Failure of assertion at line 1252, column 13.")
                                      /\ signalIndex' = [signalIndex EXCEPT ![self] = msg_S'[self].duress_signal_index]
                                      /\ Assert(st_to_niso[self] = NoValue, 
                                                "Failure of assertion at line 1254, column 13.")
                                      /\ IF msg_S'[self].kind = "WithdrawalStInput3"
                                            THEN /\ st_to_niso' = [st_to_niso EXCEPT ![self] =                 WithdrawalStNisoMessage3(
                                                                                               DuressReplyCipher(self, msg_S'[self].stage, msg_S'[self].seq, st_last_duress_check_i[self].nonce, signalIndex'[self]))]
                                                 /\ wire_trace' = (          wire_trace \cup
                                                                   { WireHop(STActor(self), NisoActor(self),
                                                                       WithdrawalStNisoMessage3(DuressReplyCipher(self, msg_S'[self].stage, msg_S'[self].seq, st_last_duress_check_i[self].nonce, signalIndex'[self]))) })
                                            ELSE /\ st_to_niso' = [st_to_niso EXCEPT ![self] =                 WithdrawalStNisoMessage2(
                                                                                               self,
                                                                                               DuressReplyCipher(self, msg_S'[self].stage, msg_S'[self].seq, st_last_duress_check_i[self].nonce, signalIndex'[self]))]
                                                 /\ wire_trace' = (          wire_trace \cup
                                                                   { WireHop(STActor(self), NisoActor(self),
                                                                       WithdrawalStNisoMessage2(self, DuressReplyCipher(self, msg_S'[self].stage, msg_S'[self].seq, st_last_duress_check_i[self].nonce, signalIndex'[self]))) })
                           /\ UNCHANGED << st_last_txid_with_nonce_i, 
                                           st_last_duress_check_i, st_to_user, 
                                           niso_to_st, nonceWrapped >>
                /\ pc' = [pc EXCEPT ![self] = "STLoop"]
                /\ UNCHANGED << boomerang_descriptor, peer_id_collection, 
                                st_identity_pubkey_i, sar_pubkey_i, 
                                doxing_key_i, duress_consent_set_i, 
                                boomlet_mystery_i, 
                                most_work_bitcoin_block_height, 
                                user_saved_psbt_i, user_initiator_peer_id_i, 
                                user_last_duress_space_i, 
                                user_sent_initial_psbt_i, 
                                user_sent_psbt_agreement_i, 
                                user_sent_iso_credentials_i, 
                                user_sent_connect_back_to_niso_i, 
                                niso_saved_psbt_i, niso_saved_tx_id_i, 
                                niso_event_block_height_i, 
                                niso_initiator_peer_id_i, 
                                niso_saved_wt_tx_approval_i, 
                                niso_hydrated_psbt_i, 
                                niso_reached_pings_collection_i, 
                                boomlet_saved_psbt_i, 
                                boomlet_committed_tx_id_i, 
                                boomlet_pending_txid_nonce_i, 
                                boomlet_saved_duress_space_i, 
                                boomlet_saved_duress_stage_i, 
                                boomlet_saved_duress_seq_i, 
                                boomlet_pending_duress_nonce_i, 
                                boomlet_duress_placeholder_plaintext_i, 
                                boomlet_duress_placeholder_cipher_i, 
                                boomlet_signed_tx_approval_i, 
                                boomlet_saved_wt_tx_approval_i, 
                                boomlet_all_peer_approvals_i, 
                                boomlet_approvals_bundle_i, 
                                boomlet_signed_commit_inner_i, 
                                boomlet_commit_collection_i, boomlet_counter_i, 
                                boomlet_last_seen_block_i, 
                                boomlet_ping_seq_num_i, 
                                boomlet_reached_mystery_flag_i, 
                                boomlet_known_reached_i, boomlet_prev_pings_i, 
                                boomlet_ready_to_sign_i, boomlet_signed_psbt_i, 
                                boomlet_pubnonce_boom_i, 
                                boomlet_partialsig_boom_i, 
                                iso_pubnonce_normal_i, iso_partialsig_normal_i, 
                                iso_signed_psbt_i, sar_seen_placeholder_iv_i, 
                                sar_escalated_i, sar_last_doxing_identifier_i, 
                                wt_saved_tx_id, wt_saved_wt_tx_approval, 
                                wt_initiator_tx_approval, 
                                wt_noninitiator_tx_approval_i, 
                                wt_approvals_bundle_i, wt_pending_sar_stage_i, 
                                wt_pending_placeholder_i, 
                                wt_pending_signed_inner_i, 
                                wt_commit_sar_reply_i, wt_ping_sar_reply_i, 
                                wt_signed_commit_i, wt_last_accepted_ping_i, 
                                wt_reached_pings_collection, 
                                wt_last_pong_height, wt_relayed_all_approvals, 
                                wt_relayed_all_commits, wt_signed_psbt_i, 
                                wt_broadcast, user_to_niso, niso_to_user, 
                                boomlet_to_niso, niso_to_boomlet, user_to_iso, 
                                iso_to_user, boomlet_to_iso, iso_to_boomlet, 
                                niso_to_wt, wt_to_niso, wt_to_sar, sar_to_wt, 
                                msg_, signalIndex_, msg_N, approvalSig, wtSig, 
                                commitSig, signedPing, msg_B, signedAck, 
                                duressSignal, hydrated, signedPong, prevPings, 
                                msg_I, msg_SA, plaintext, reply, msg, peer, 
                                decrypted, signedInner, placeholder, wtHeight, 
                                pongMap >>

STFlow(self) == STLoop(self)

NisoLoop(self) == /\ pc[self] = "NisoLoop"
                  /\    user_to_niso[self] # NoValue
                     \/ boomlet_to_niso[self] # NoValue
                     \/ st_to_niso[self] # NoValue
                     \/ wt_to_niso[self] # NoValue
                  /\ IF user_to_niso[self] # NoValue
                        THEN /\ msg_N' = [msg_N EXCEPT ![self] = user_to_niso[self]]
                             /\ user_to_niso' = [user_to_niso EXCEPT ![self] = NoValue]
                             /\ IF msg_N'[self].kind = "WithdrawalNisoInput1"
                                   THEN /\ Assert(self = INITIATOR, 
                                                  "Failure of assertion at line 1290, column 13.")
                                        /\ Assert(most_work_bitcoin_block_height >= boomerang_descriptor.milestone_block_0, 
                                                  "Failure of assertion at line 1291, column 13.")
                                        /\ Assert(PsbtSatisfiable(msg_N'[self].psbt), 
                                                  "Failure of assertion at line 1292, column 13.")
                                        /\ niso_saved_psbt_i' = [niso_saved_psbt_i EXCEPT ![self] = msg_N'[self].psbt]
                                        /\ niso_saved_tx_id_i' = [niso_saved_tx_id_i EXCEPT ![self] = TxOfPsbt[msg_N'[self].psbt]]
                                        /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                        /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                  "Failure of assertion at line 1296, column 13.")
                                        /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNisoBoomletMessage1(msg_N'[self].psbt, niso_event_block_height_i'[self])]
                                        /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage1(msg_N'[self].psbt, niso_event_block_height_i'[self])) })
                                   ELSE /\ IF msg_N'[self].kind = "WithdrawalNonInitiatorNisoInput1"
                                              THEN /\ Assert(self # INITIATOR, 
                                                             "Failure of assertion at line 1300, column 13.")
                                                   /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                             "Failure of assertion at line 1301, column 13.")
                                                   /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNonInitiatorNisoBoomletMessage2]
                                                   /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage2) })
                                              ELSE /\ Assert(msg_N'[self].kind = "WithdrawalNisoInput2", 
                                                             "Failure of assertion at line 1305, column 13.")
                                                   /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                             "Failure of assertion at line 1306, column 13.")
                                                   /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNisoBoomletMessage9]
                                                   /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage9) })
                                        /\ UNCHANGED << niso_saved_psbt_i, 
                                                        niso_saved_tx_id_i, 
                                                        niso_event_block_height_i >>
                             /\ UNCHANGED << niso_initiator_peer_id_i, 
                                             niso_saved_wt_tx_approval_i, 
                                             niso_hydrated_psbt_i, 
                                             niso_reached_pings_collection_i, 
                                             niso_to_user, boomlet_to_niso, 
                                             niso_to_st, st_to_niso, 
                                             niso_to_wt, wt_to_niso, 
                                             approvalSig, wtSig, commitSig >>
                        ELSE /\ IF boomlet_to_niso[self] # NoValue
                                   THEN /\ msg_N' = [msg_N EXCEPT ![self] = boomlet_to_niso[self]]
                                        /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = NoValue]
                                        /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage1"
                                              THEN /\ Assert(niso_to_st[self] = NoValue, 
                                                             "Failure of assertion at line 1314, column 13.")
                                                   /\ niso_to_st' = [niso_to_st EXCEPT ![self] = WithdrawalNisoStMessage1(self, msg_N'[self].tx_id_with_nonce_encrypted_by_boomlet_for_st)]
                                                   /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage1(self, msg_N'[self].tx_id_with_nonce_encrypted_by_boomlet_for_st)) })
                                                   /\ UNCHANGED << niso_saved_psbt_i, 
                                                                   niso_to_user, 
                                                                   niso_to_wt >>
                                              ELSE /\ IF msg_N'[self].kind = "WithdrawalNonInitiatorBoomletNisoMessage1"
                                                         THEN /\ Assert(PsbtSatisfiable(msg_N'[self].psbt), 
                                                                        "Failure of assertion at line 1318, column 13.")
                                                              /\ Assert(TxOfPsbt[msg_N'[self].psbt] = niso_saved_tx_id_i[self], 
                                                                        "Failure of assertion at line 1319, column 13.")
                                                              /\ niso_saved_psbt_i' = [niso_saved_psbt_i EXCEPT ![self] = msg_N'[self].psbt]
                                                              /\ Assert(niso_to_user[self] = NoValue, 
                                                                        "Failure of assertion at line 1321, column 13.")
                                                              /\ niso_to_user' = [niso_to_user EXCEPT ![self] = WithdrawalNonInitiatorNisoOutput1(msg_N'[self].psbt, niso_initiator_peer_id_i[self])]
                                                              /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), UserActor(self), WithdrawalNonInitiatorNisoOutput1(msg_N'[self].psbt, niso_initiator_peer_id_i[self])) })
                                                              /\ UNCHANGED << niso_to_st, 
                                                                              niso_to_wt >>
                                                         ELSE /\ IF msg_N'[self].kind = "WithdrawalNonInitiatorBoomletNisoMessage2"
                                                                    THEN /\ Assert(niso_to_st[self] = NoValue, 
                                                                                   "Failure of assertion at line 1325, column 13.")
                                                                         /\ niso_to_st' = [niso_to_st EXCEPT ![self] = WithdrawalNisoStMessage1(self, msg_N'[self].tx_id_with_nonce_encrypted_by_boomlet_for_st)]
                                                                         /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage1(self, msg_N'[self].tx_id_with_nonce_encrypted_by_boomlet_for_st)) })
                                                                         /\ UNCHANGED << niso_to_user, 
                                                                                         niso_to_wt >>
                                                                    ELSE /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage2"
                                                                               THEN /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                              "Failure of assertion at line 1329, column 13.")
                                                                                    /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] =                 WithdrawalNisoWtMessage1(
                                                                                                                                  msg_N'[self].initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt,
                                                                                                                                  msg_N'[self].psbt_encrypted_collection)]
                                                                                    /\ wire_trace' = (          wire_trace \cup
                                                                                                      { WireHop(NisoActor(self), WTActor, WithdrawalNisoWtMessage1(
                                                                                                          msg_N'[self].initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt,
                                                                                                          msg_N'[self].psbt_encrypted_collection)) })
                                                                                    /\ UNCHANGED << niso_to_user, 
                                                                                                    niso_to_st >>
                                                                               ELSE /\ IF msg_N'[self].kind = "WithdrawalNonInitiatorBoomletNisoMessage3"
                                                                                          THEN /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                                         "Failure of assertion at line 1338, column 13.")
                                                                                               /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] = WithdrawalNonInitiatorNisoWtMessage1(msg_N'[self].peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)]
                                                                                               /\ wire_trace' = (          wire_trace \cup
                                                                                                                 { WireHop(NisoActor(self), WTActor, WithdrawalNonInitiatorNisoWtMessage1(msg_N'[self].peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) })
                                                                                               /\ UNCHANGED << niso_to_user, 
                                                                                                               niso_to_st >>
                                                                                          ELSE /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage3"
                                                                                                     THEN /\ Assert(niso_to_st[self] = NoValue, 
                                                                                                                    "Failure of assertion at line 1343, column 13.")
                                                                                                          /\ niso_to_st' = [niso_to_st EXCEPT ![self] = WithdrawalNisoStMessage2(self, msg_N'[self].duress_check_space_with_nonce_encrypted_by_boomlet_for_st)]
                                                                                                          /\ wire_trace' = (          wire_trace \cup
                                                                                                                            { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage2(self, msg_N'[self].duress_check_space_with_nonce_encrypted_by_boomlet_for_st)) })
                                                                                                          /\ UNCHANGED << niso_to_user, 
                                                                                                                          niso_to_wt >>
                                                                                                     ELSE /\ IF msg_N'[self].kind = "WithdrawalNonInitiatorBoomletNisoMessage4"
                                                                                                                THEN /\ Assert(niso_to_st[self] = NoValue, 
                                                                                                                               "Failure of assertion at line 1348, column 13.")
                                                                                                                     /\ niso_to_st' = [niso_to_st EXCEPT ![self] = WithdrawalNisoStMessage2(self, msg_N'[self].duress_check_space_with_nonce_encrypted_by_boomlet_for_st)]
                                                                                                                     /\ wire_trace' = (          wire_trace \cup
                                                                                                                                       { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage2(self, msg_N'[self].duress_check_space_with_nonce_encrypted_by_boomlet_for_st)) })
                                                                                                                     /\ UNCHANGED << niso_to_user, 
                                                                                                                                     niso_to_wt >>
                                                                                                                ELSE /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage4"
                                                                                                                           THEN /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                                                                          "Failure of assertion at line 1353, column 13.")
                                                                                                                                /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] = WithdrawalNisoWtMessage2(msg_N'[self].peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt)]
                                                                                                                                /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                  { WireHop(NisoActor(self), WTActor, WithdrawalNisoWtMessage2(msg_N'[self].peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt)) })
                                                                                                                                /\ UNCHANGED << niso_to_user, 
                                                                                                                                                niso_to_st >>
                                                                                                                           ELSE /\ IF msg_N'[self].kind = "WithdrawalNonInitiatorBoomletNisoMessage5"
                                                                                                                                      THEN /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                                                                                     "Failure of assertion at line 1358, column 13.")
                                                                                                                                           /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] = WithdrawalNonInitiatorNisoWtMessage2(msg_N'[self].approvals_signed_by_boomlet_i)]
                                                                                                                                           /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                             { WireHop(NisoActor(self), WTActor, WithdrawalNonInitiatorNisoWtMessage2(msg_N'[self].approvals_signed_by_boomlet_i)) })
                                                                                                                                           /\ UNCHANGED << niso_to_user, 
                                                                                                                                                           niso_to_st >>
                                                                                                                                      ELSE /\ IF msg_N'[self].kind = "WithdrawalNonInitiatorBoomletNisoMessage6"
                                                                                                                                                 THEN /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                                                                                                "Failure of assertion at line 1363, column 13.")
                                                                                                                                                      /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] = WithdrawalNonInitiatorNisoWtMessage3(msg_N'[self].peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)]
                                                                                                                                                      /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                        { WireHop(NisoActor(self), WTActor, WithdrawalNonInitiatorNisoWtMessage3(msg_N'[self].peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) })
                                                                                                                                                      /\ UNCHANGED << niso_to_user, 
                                                                                                                                                                      niso_to_st >>
                                                                                                                                                 ELSE /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage5"
                                                                                                                                                            THEN /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                                                                                                           "Failure of assertion at line 1368, column 13.")
                                                                                                                                                                 /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] = PingToWTMessage(self, FALSE, msg_N'[self].peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)]
                                                                                                                                                                 /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                                   { WireHop(NisoActor(self), WTActor, PingToWTMessage(self, FALSE, msg_N'[self].peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) })
                                                                                                                                                                 /\ UNCHANGED << niso_to_user, 
                                                                                                                                                                                 niso_to_st >>
                                                                                                                                                            ELSE /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage6"
                                                                                                                                                                       THEN /\ Assert(niso_to_st[self] = NoValue, 
                                                                                                                                                                                      "Failure of assertion at line 1373, column 13.")
                                                                                                                                                                            /\ niso_to_st' = [niso_to_st EXCEPT ![self] = WithdrawalNisoStMessage3(msg_N'[self].duress_check_space_with_nonce_encrypted_by_boomlet_for_st)]
                                                                                                                                                                            /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                                              { WireHop(NisoActor(self), STActor(self), WithdrawalNisoStMessage3(msg_N'[self].duress_check_space_with_nonce_encrypted_by_boomlet_for_st)) })
                                                                                                                                                                            /\ UNCHANGED << niso_to_user, 
                                                                                                                                                                                            niso_to_wt >>
                                                                                                                                                                       ELSE /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage7"
                                                                                                                                                                                  THEN /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                                                                                                                                 "Failure of assertion at line 1378, column 13.")
                                                                                                                                                                                       /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] = PingToWTMessage(self, TRUE, msg_N'[self].peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)]
                                                                                                                                                                                       /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                                                         { WireHop(NisoActor(self), WTActor, PingToWTMessage(self, TRUE, msg_N'[self].peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt)) })
                                                                                                                                                                                       /\ UNCHANGED niso_to_user
                                                                                                                                                                                  ELSE /\ IF msg_N'[self].kind = "WithdrawalBoomletNisoMessage8"
                                                                                                                                                                                             THEN /\ Assert(niso_to_user[self] = NoValue, 
                                                                                                                                                                                                            "Failure of assertion at line 1383, column 13.")
                                                                                                                                                                                                  /\ niso_to_user' = [niso_to_user EXCEPT ![self] = WithdrawalNisoOutput1]
                                                                                                                                                                                                  /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), UserActor(self), WithdrawalNisoOutput1) })
                                                                                                                                                                                                  /\ UNCHANGED niso_to_wt
                                                                                                                                                                                             ELSE /\ Assert(msg_N'[self].kind = "WithdrawalBoomletNisoMessage9", 
                                                                                                                                                                                                            "Failure of assertion at line 1387, column 13.")
                                                                                                                                                                                                  /\ Assert(niso_to_wt[self] = NoValue, 
                                                                                                                                                                                                            "Failure of assertion at line 1388, column 13.")
                                                                                                                                                                                                  /\ niso_to_wt' = [niso_to_wt EXCEPT ![self] = WithdrawalNisoWtMessage5(msg_N'[self].psbt_signed_i)]
                                                                                                                                                                                                  /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), WTActor, WithdrawalNisoWtMessage5(msg_N'[self].psbt_signed_i)) })
                                                                                                                                                                                                  /\ UNCHANGED niso_to_user
                                                                                                                                                                            /\ UNCHANGED niso_to_st
                                                              /\ UNCHANGED niso_saved_psbt_i
                                        /\ UNCHANGED << niso_saved_tx_id_i, 
                                                        niso_event_block_height_i, 
                                                        niso_initiator_peer_id_i, 
                                                        niso_saved_wt_tx_approval_i, 
                                                        niso_hydrated_psbt_i, 
                                                        niso_reached_pings_collection_i, 
                                                        niso_to_boomlet, 
                                                        st_to_niso, wt_to_niso, 
                                                        approvalSig, wtSig, 
                                                        commitSig >>
                                   ELSE /\ IF st_to_niso[self] # NoValue
                                              THEN /\ msg_N' = [msg_N EXCEPT ![self] = st_to_niso[self]]
                                                   /\ st_to_niso' = [st_to_niso EXCEPT ![self] = NoValue]
                                                   /\ IF msg_N'[self].kind \in {"WithdrawalStNisoMessage1", "WithdrawalNonInitiatorStNisoMessage1"}
                                                         THEN /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                        "Failure of assertion at line 1396, column 13.")
                                                              /\ IF self = INITIATOR
                                                                    THEN /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNisoBoomletMessage2(msg_N'[self].tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet)]
                                                                         /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage2(msg_N'[self].tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet)) })
                                                                         /\ UNCHANGED niso_event_block_height_i
                                                                    ELSE /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                                                         /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNonInitiatorNisoBoomletMessage3(msg_N'[self].tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet, niso_event_block_height_i'[self])]
                                                                         /\ wire_trace' = (          wire_trace \cup
                                                                                           { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage3(msg_N'[self].tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet, niso_event_block_height_i'[self])) })
                                                         ELSE /\ IF msg_N'[self].kind \in {"WithdrawalStNisoMessage2", "WithdrawalNonInitiatorStNisoMessage2"}
                                                                    THEN /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                   "Failure of assertion at line 1407, column 13.")
                                                                         /\ IF self = INITIATOR
                                                                               THEN /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNisoBoomletMessage4(msg_N'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)]
                                                                                    /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage4(msg_N'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)) })
                                                                               ELSE /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNonInitiatorNisoBoomletMessage5(msg_N'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)]
                                                                                    /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage5(msg_N'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)) })
                                                                    ELSE /\ Assert(msg_N'[self].kind = "WithdrawalStNisoMessage3", 
                                                                                   "Failure of assertion at line 1416, column 13.")
                                                                         /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                   "Failure of assertion at line 1417, column 13.")
                                                                         /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNisoBoomletMessage7(msg_N'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)]
                                                                         /\ wire_trace' = (wire_trace \cup { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage7(msg_N'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet)) })
                                                              /\ UNCHANGED niso_event_block_height_i
                                                   /\ UNCHANGED << niso_saved_tx_id_i, 
                                                                   niso_initiator_peer_id_i, 
                                                                   niso_saved_wt_tx_approval_i, 
                                                                   niso_hydrated_psbt_i, 
                                                                   niso_reached_pings_collection_i, 
                                                                   wt_to_niso, 
                                                                   approvalSig, 
                                                                   wtSig, 
                                                                   commitSig >>
                                              ELSE /\ msg_N' = [msg_N EXCEPT ![self] = wt_to_niso[self]]
                                                   /\ wt_to_niso' = [wt_to_niso EXCEPT ![self] = NoValue]
                                                   /\ IF msg_N'[self].kind = "WithdrawalWtNonInitiatorNisoMessage1"
                                                         THEN /\ wtSig' = [wtSig EXCEPT ![self] = msg_N'[self].wt_tx_approval_signed_by_wt]
                                                              /\ approvalSig' = [approvalSig EXCEPT ![self] = msg_N'[self].peer_0_tx_approval_signed_by_boomlet_0]
                                                              /\ Assert(   WTTxApprovalSigValid(
                                                                        wtSig'[self],
                                                                        SignedContent(approvalSig'[self]).tx_id,
                                                                        INITIATOR,
                                                                        SignedContent(approvalSig'[self]).event_block_height,
                                                                        most_work_bitcoin_block_height), 
                                                                        "Failure of assertion at line 1427, column 13.")
                                                              /\ Assert(ValidSig(approvalSig'[self], BoomletActor(INITIATOR)), 
                                                                        "Failure of assertion at line 1433, column 13.")
                                                              /\ Assert(SignedContent(wtSig'[self]).initiator_id \in peer_id_collection, 
                                                                        "Failure of assertion at line 1434, column 13.")
                                                              /\ Assert(SignedContent(approvalSig'[self]).magic = "approved", 
                                                                        "Failure of assertion at line 1435, column 13.")
                                                              /\ Assert(SignedContent(wtSig'[self]).magic = "approved", 
                                                                        "Failure of assertion at line 1436, column 13.")
                                                              /\ Assert(SignedContent(approvalSig'[self]).tx_id = SignedContent(wtSig'[self]).tx_id, 
                                                                        "Failure of assertion at line 1437, column 13.")
                                                              /\ Assert(   SignedContent(wtSig'[self]).event_block_height >=
                                                                        Max2(
                                                                            SignedContent(approvalSig'[self]).event_block_height,
                                                                            IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                                                                            THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                                                                            ELSE 0), 
                                                                        "Failure of assertion at line 1438, column 13.")
                                                              /\ niso_saved_tx_id_i' = [niso_saved_tx_id_i EXCEPT ![self] = SignedContent(wtSig'[self]).tx_id]
                                                              /\ niso_initiator_peer_id_i' = [niso_initiator_peer_id_i EXCEPT ![self] = SignedContent(wtSig'[self]).initiator_id]
                                                              /\ niso_saved_wt_tx_approval_i' = [niso_saved_wt_tx_approval_i EXCEPT ![self] = wtSig'[self]]
                                                              /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                                              /\ Assert(most_work_bitcoin_block_height >= boomerang_descriptor.milestone_block_0, 
                                                                        "Failure of assertion at line 1448, column 13.")
                                                              /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                        "Failure of assertion at line 1449, column 13.")
                                                              /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] =                      WithdrawalNonInitiatorNisoBoomletMessage1(
                                                                                                                      wtSig'[self],
                                                                                                                      approvalSig'[self],
                                                                                                                      msg_N'[self].psbt_encrypted_by_boomlet_0_for_boomlet_i,
                                                                                                                      niso_event_block_height_i'[self])]
                                                              /\ wire_trace' = (          wire_trace \cup
                                                                                { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage1(
                                                                                    wtSig'[self],
                                                                                    approvalSig'[self],
                                                                                    msg_N'[self].psbt_encrypted_by_boomlet_0_for_boomlet_i,
                                                                                    niso_event_block_height_i'[self])) })
                                                              /\ UNCHANGED << niso_hydrated_psbt_i, 
                                                                              niso_reached_pings_collection_i, 
                                                                              commitSig >>
                                                         ELSE /\ IF msg_N'[self].kind = "WithdrawalWtNisoMessage1"
                                                                    THEN /\ wtSig' = [wtSig EXCEPT ![self] = msg_N'[self].wt_tx_approval_signed_by_wt]
                                                                         /\ Assert(   WTTxApprovalSigValid(
                                                                                   wtSig'[self],
                                                                                   SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).tx_id,
                                                                                   INITIATOR,
                                                                                   SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).event_block_height,
                                                                                   most_work_bitcoin_block_height), 
                                                                                   "Failure of assertion at line 1463, column 13.")
                                                                         /\ Assert(ValidSig(msg_N'[self].all_peer_tx_approvals[INITIATOR], BoomletActor(INITIATOR)), 
                                                                                   "Failure of assertion at line 1469, column 13.")
                                                                         /\ Assert(SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).magic = "approved", 
                                                                                   "Failure of assertion at line 1470, column 13.")
                                                                         /\ Assert(SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).tx_id = niso_saved_tx_id_i[self], 
                                                                                   "Failure of assertion at line 1471, column 13.")
                                                                         /\ Assert(SignedContent(wtSig'[self]).magic = "approved", 
                                                                                   "Failure of assertion at line 1472, column 13.")
                                                                         /\ Assert(SignedContent(wtSig'[self]).tx_id = niso_saved_tx_id_i[self], 
                                                                                   "Failure of assertion at line 1473, column 13.")
                                                                         /\ Assert(SignedContent(wtSig'[self]).event_block_height >= SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).event_block_height, 
                                                                                   "Failure of assertion at line 1474, column 13.")
                                                                         /\ Assert(   SignedContent(wtSig'[self]).event_block_height <=
                                                                                   Min2(
                                                                                       SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).event_block_height
                                                                                           + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT,
                                                                                       most_work_bitcoin_block_height), 
                                                                                   "Failure of assertion at line 1475, column 13.")
                                                                         /\ Assert(   SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).event_block_height >=
                                                                                   Max2(
                                                                                       IF SignedContent(wtSig'[self]).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                                                                                       THEN SignedContent(wtSig'[self]).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                                                                                       ELSE 0,
                                                                                       IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                                                                                       THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                                                                                       ELSE 0), 
                                                                                   "Failure of assertion at line 1480, column 13.")
                                                                         /\ Assert(SignedContent(msg_N'[self].all_peer_tx_approvals[INITIATOR]).event_block_height <= SignedContent(wtSig'[self]).event_block_height, 
                                                                                   "Failure of assertion at line 1488, column 13.")
                                                                         /\ Assert(most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER, 
                                                                                   "Failure of assertion at line 1489, column 13.")
                                                                         /\ Assert(   \A j \in NonInitiators :
                                                                                   /\ ValidSig(msg_N'[self].all_peer_tx_approvals[j], BoomletActor(j))
                                                                                   /\ SignedContent(msg_N'[self].all_peer_tx_approvals[j]).magic = "approved"
                                                                                   /\ SignedContent(msg_N'[self].all_peer_tx_approvals[j]).tx_id = niso_saved_tx_id_i[self]
                                                                                   /\ SignedContent(msg_N'[self].all_peer_tx_approvals[j]).event_block_height >=
                                                                                       Max2(
                                                                                           SignedContent(wtSig'[self]).event_block_height,
                                                                                           IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                                                                                           THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                                                                                           ELSE 0)
                                                                                   /\ SignedContent(msg_N'[self].all_peer_tx_approvals[j]).event_block_height <=
                                                                                       most_work_bitcoin_block_height
                                                                                           - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER, 
                                                                                   "Failure of assertion at line 1490, column 13.")
                                                                         /\ niso_saved_wt_tx_approval_i' = [niso_saved_wt_tx_approval_i EXCEPT ![self] = wtSig'[self]]
                                                                         /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                                                         /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                   "Failure of assertion at line 1505, column 13.")
                                                                         /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] =                      WithdrawalNisoBoomletMessage3(
                                                                                                                                 [j \in NonInitiators |-> msg_N'[self].all_peer_tx_approvals[j]],
                                                                                                                                 wtSig'[self],
                                                                                                                                 niso_event_block_height_i'[self])]
                                                                         /\ wire_trace' = (          wire_trace \cup
                                                                                           { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage3(
                                                                                               [j \in NonInitiators |-> msg_N'[self].all_peer_tx_approvals[j]],
                                                                                               wtSig'[self],
                                                                                               niso_event_block_height_i'[self])) })
                                                                         /\ UNCHANGED << niso_hydrated_psbt_i, 
                                                                                         niso_reached_pings_collection_i, 
                                                                                         commitSig >>
                                                                    ELSE /\ IF msg_N'[self].kind = "WithdrawalWtNonInitiatorNisoMessage2"
                                                                               THEN /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                                                                    /\ Assert(niso_saved_wt_tx_approval_i[self] # NoValue, 
                                                                                              "Failure of assertion at line 1517, column 13.")
                                                                                    /\ Assert(   \A j \in NonInitiators :
                                                                                              /\ ValidSig(msg_N'[self].non_initiator_tx_approvals[j], BoomletActor(j))
                                                                                              /\ SignedContent(msg_N'[self].non_initiator_tx_approvals[j]).magic = "approved"
                                                                                              /\ SignedContent(msg_N'[self].non_initiator_tx_approvals[j]).tx_id = niso_saved_tx_id_i[self]
                                                                                              /\ SignedContent(msg_N'[self].non_initiator_tx_approvals[j]).event_block_height >=
                                                                                                  Max2(
                                                                                                      SignedContent(niso_saved_wt_tx_approval_i[self]).event_block_height,
                                                                                                      IF niso_event_block_height_i'[self] >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                                      THEN niso_event_block_height_i'[self] - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                                      ELSE 0)
                                                                                              /\ SignedContent(msg_N'[self].non_initiator_tx_approvals[j]).event_block_height <=
                                                                                                  Min2(
                                                                                                      niso_event_block_height_i'[self],
                                                                                                      SignedContent(niso_saved_wt_tx_approval_i[self]).event_block_height
                                                                                                          + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS), 
                                                                                              "Failure of assertion at line 1518, column 13.")
                                                                                    /\ Assert(   SignedContent(niso_saved_wt_tx_approval_i[self]).event_block_height >=
                                                                                              IF niso_event_block_height_i'[self] >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                              THEN niso_event_block_height_i'[self] - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                              ELSE 0, 
                                                                                              "Failure of assertion at line 1533, column 13.")
                                                                                    /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                              "Failure of assertion at line 1537, column 13.")
                                                                                    /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] =                      WithdrawalNonInitiatorNisoBoomletMessage4(
                                                                                                                                            msg_N'[self].non_initiator_tx_approvals,
                                                                                                                                            niso_event_block_height_i'[self])]
                                                                                    /\ wire_trace' = (          wire_trace \cup
                                                                                                      { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage4(
                                                                                                          msg_N'[self].non_initiator_tx_approvals,
                                                                                                          niso_event_block_height_i'[self])) })
                                                                                    /\ UNCHANGED << niso_hydrated_psbt_i, 
                                                                                                    niso_reached_pings_collection_i, 
                                                                                                    commitSig >>
                                                                               ELSE /\ IF msg_N'[self].kind = "WithdrawalWtNonInitiatorNisoMessage3"
                                                                                          THEN /\ commitSig' = [commitSig EXCEPT ![self] = msg_N'[self].peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt]
                                                                                               /\ Assert(   WTSignedCommitValid(
                                                                                                         commitSig'[self],
                                                                                                         INITIATOR,
                                                                                                         SignedContent(SignedContent(commitSig'[self])).tx_id,
                                                                                                         IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                                                                                                         THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                                                                                                         ELSE 0,
                                                                                                         most_work_bitcoin_block_height), 
                                                                                                         "Failure of assertion at line 1547, column 13.")
                                                                                               /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                                                                               /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                                         "Failure of assertion at line 1556, column 13.")
                                                                                               /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNonInitiatorNisoBoomletMessage6(commitSig'[self], niso_event_block_height_i'[self])]
                                                                                               /\ wire_trace' = (          wire_trace \cup
                                                                                                                 { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNonInitiatorNisoBoomletMessage6(commitSig'[self], niso_event_block_height_i'[self])) })
                                                                                               /\ UNCHANGED << niso_hydrated_psbt_i, 
                                                                                                               niso_reached_pings_collection_i >>
                                                                                          ELSE /\ IF msg_N'[self].kind \in {"WithdrawalWtNisoMessage2", "WithdrawalWtNonInitiatorNisoMessage4"}
                                                                                                     THEN /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                                                                                          /\ Assert(niso_event_block_height_i'[self] >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS, 
                                                                                                                    "Failure of assertion at line 1562, column 13.")
                                                                                                          /\ Assert(   \A j \in Peers :
                                                                                                                    WTSignedCommitValid(
                                                                                                                        msg_N'[self].all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt[j],
                                                                                                                        j,
                                                                                                                        niso_saved_tx_id_i[self],
                                                                                                                        IF niso_event_block_height_i'[self] >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                                                                                                                        THEN niso_event_block_height_i'[self] - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                                                                                                                        ELSE 0,
                                                                                                                        niso_event_block_height_i'[self]
                                                                                                                            - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS), 
                                                                                                                    "Failure of assertion at line 1563, column 13.")
                                                                                                          /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                                                    "Failure of assertion at line 1573, column 13.")
                                                                                                          /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] =                      WithdrawalNisoBoomletMessage5(
                                                                                                                                                                  msg_N'[self].all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt,
                                                                                                                                                                  msg_N'[self].duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                                                                                                                                                                  niso_event_block_height_i'[self])]
                                                                                                          /\ wire_trace' = (          wire_trace \cup
                                                                                                                            { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage5(
                                                                                                                                msg_N'[self].all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt,
                                                                                                                                msg_N'[self].duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                                                                                                                                niso_event_block_height_i'[self])) })
                                                                                                          /\ UNCHANGED << niso_hydrated_psbt_i, 
                                                                                                                          niso_reached_pings_collection_i >>
                                                                                                     ELSE /\ IF msg_N'[self].kind = "WithdrawalWtNisoMessage3"
                                                                                                                THEN /\ niso_event_block_height_i' = [niso_event_block_height_i EXCEPT ![self] = most_work_bitcoin_block_height]
                                                                                                                     /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                                                               "Failure of assertion at line 1585, column 13.")
                                                                                                                     /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] =                      WithdrawalNisoBoomletMessage6(
                                                                                                                                                                             msg_N'[self].pong_signed_by_wt_encrypted_by_wt_for_boomlet,
                                                                                                                                                                             msg_N'[self].duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                                                                                                                                                                             niso_event_block_height_i'[self])]
                                                                                                                     /\ wire_trace' = (          wire_trace \cup
                                                                                                                                       { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage6(
                                                                                                                                           msg_N'[self].pong_signed_by_wt_encrypted_by_wt_for_boomlet,
                                                                                                                                           msg_N'[self].duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet,
                                                                                                                                           niso_event_block_height_i'[self])) })
                                                                                                                     /\ UNCHANGED << niso_hydrated_psbt_i, 
                                                                                                                                     niso_reached_pings_collection_i >>
                                                                                                                ELSE /\ Assert(msg_N'[self].kind = "WithdrawalWtNisoMessage4", 
                                                                                                                               "Failure of assertion at line 1596, column 13.")
                                                                                                                     /\ Assert(msg_N'[self].reached_pings_collection.kind = "ReachedPingsCollection", 
                                                                                                                               "Failure of assertion at line 1597, column 13.")
                                                                                                                     /\ Assert(   \A j \in Peers :
                                                                                                                               ReachedPingSigValid(msg_N'[self].reached_pings_collection.items[j], j, niso_saved_tx_id_i[self]), 
                                                                                                                               "Failure of assertion at line 1598, column 13.")
                                                                                                                     /\ niso_reached_pings_collection_i' = [niso_reached_pings_collection_i EXCEPT ![self] = msg_N'[self].reached_pings_collection]
                                                                                                                     /\ niso_hydrated_psbt_i' = [niso_hydrated_psbt_i EXCEPT ![self] = HydratePsbt(niso_saved_psbt_i[self])]
                                                                                                                     /\ Assert(niso_hydrated_psbt_i'[self] # NoValue, 
                                                                                                                               "Failure of assertion at line 1602, column 13.")
                                                                                                                     /\ Assert(niso_to_boomlet[self] = NoValue, 
                                                                                                                               "Failure of assertion at line 1603, column 13.")
                                                                                                                     /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = WithdrawalNisoBoomletMessage8(msg_N'[self].reached_pings_collection, niso_hydrated_psbt_i'[self])]
                                                                                                                     /\ wire_trace' = (          wire_trace \cup
                                                                                                                                       { WireHop(NisoActor(self), BoomletActor(self), WithdrawalNisoBoomletMessage8(msg_N'[self].reached_pings_collection, niso_hydrated_psbt_i'[self])) })
                                                                                                                     /\ UNCHANGED niso_event_block_height_i
                                                                                               /\ UNCHANGED commitSig
                                                                         /\ UNCHANGED << niso_saved_wt_tx_approval_i, 
                                                                                         wtSig >>
                                                              /\ UNCHANGED << niso_saved_tx_id_i, 
                                                                              niso_initiator_peer_id_i, 
                                                                              approvalSig >>
                                                   /\ UNCHANGED st_to_niso
                                        /\ UNCHANGED << niso_saved_psbt_i, 
                                                        niso_to_user, 
                                                        boomlet_to_niso, 
                                                        niso_to_st, niso_to_wt >>
                             /\ UNCHANGED user_to_niso
                  /\ pc' = [pc EXCEPT ![self] = "NisoLoop"]
                  /\ UNCHANGED << boomerang_descriptor, peer_id_collection, 
                                  st_identity_pubkey_i, sar_pubkey_i, 
                                  doxing_key_i, duress_consent_set_i, 
                                  boomlet_mystery_i, 
                                  most_work_bitcoin_block_height, 
                                  user_saved_psbt_i, user_initiator_peer_id_i, 
                                  user_last_duress_space_i, 
                                  user_sent_initial_psbt_i, 
                                  user_sent_psbt_agreement_i, 
                                  user_sent_iso_credentials_i, 
                                  user_sent_connect_back_to_niso_i, 
                                  boomlet_saved_psbt_i, 
                                  boomlet_committed_tx_id_i, 
                                  boomlet_pending_txid_nonce_i, 
                                  boomlet_saved_duress_space_i, 
                                  boomlet_saved_duress_stage_i, 
                                  boomlet_saved_duress_seq_i, 
                                  boomlet_pending_duress_nonce_i, 
                                  boomlet_duress_placeholder_plaintext_i, 
                                  boomlet_duress_placeholder_cipher_i, 
                                  boomlet_signed_tx_approval_i, 
                                  boomlet_saved_wt_tx_approval_i, 
                                  boomlet_all_peer_approvals_i, 
                                  boomlet_approvals_bundle_i, 
                                  boomlet_signed_commit_inner_i, 
                                  boomlet_commit_collection_i, 
                                  boomlet_counter_i, boomlet_last_seen_block_i, 
                                  boomlet_ping_seq_num_i, 
                                  boomlet_reached_mystery_flag_i, 
                                  boomlet_known_reached_i, 
                                  boomlet_prev_pings_i, 
                                  boomlet_ready_to_sign_i, 
                                  boomlet_signed_psbt_i, 
                                  boomlet_pubnonce_boom_i, 
                                  boomlet_partialsig_boom_i, 
                                  st_last_txid_with_nonce_i, 
                                  st_last_duress_check_i, 
                                  iso_pubnonce_normal_i, 
                                  iso_partialsig_normal_i, iso_signed_psbt_i, 
                                  sar_seen_placeholder_iv_i, sar_escalated_i, 
                                  sar_last_doxing_identifier_i, wt_saved_tx_id, 
                                  wt_saved_wt_tx_approval, 
                                  wt_initiator_tx_approval, 
                                  wt_noninitiator_tx_approval_i, 
                                  wt_approvals_bundle_i, 
                                  wt_pending_sar_stage_i, 
                                  wt_pending_placeholder_i, 
                                  wt_pending_signed_inner_i, 
                                  wt_commit_sar_reply_i, wt_ping_sar_reply_i, 
                                  wt_signed_commit_i, wt_last_accepted_ping_i, 
                                  wt_reached_pings_collection, 
                                  wt_last_pong_height, 
                                  wt_relayed_all_approvals, 
                                  wt_relayed_all_commits, wt_signed_psbt_i, 
                                  wt_broadcast, user_to_st, st_to_user, 
                                  user_to_iso, iso_to_user, boomlet_to_iso, 
                                  iso_to_boomlet, wt_to_sar, sar_to_wt, msg_, 
                                  signalIndex_, msg_S, nonceWrapped, 
                                  signalIndex, signedPing, msg_B, signedAck, 
                                  duressSignal, hydrated, signedPong, 
                                  prevPings, msg_I, msg_SA, plaintext, reply, 
                                  msg, peer, decrypted, signedInner, 
                                  placeholder, wtHeight, pongMap >>

NisoFlow(self) == NisoLoop(self)

BoomletLoop(self) == /\ pc[self] = "BoomletLoop"
                     /\ niso_to_boomlet[self] # NoValue \/ iso_to_boomlet[self] # NoValue
                     /\ IF niso_to_boomlet[self] # NoValue
                           THEN /\ msg_B' = [msg_B EXCEPT ![self] = niso_to_boomlet[self]]
                                /\ niso_to_boomlet' = [niso_to_boomlet EXCEPT ![self] = NoValue]
                                /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage1"
                                      THEN /\ Assert(self = INITIATOR, 
                                                     "Failure of assertion at line 1626, column 13.")
                                           /\ Assert(msg_B'[self].niso_0_event_block_height >= boomerang_descriptor.milestone_block_0, 
                                                     "Failure of assertion at line 1627, column 13.")
                                           /\ boomlet_saved_psbt_i' = [boomlet_saved_psbt_i EXCEPT ![self] = msg_B'[self].psbt]
                                           /\ boomlet_committed_tx_id_i' = [boomlet_committed_tx_id_i EXCEPT ![self] = TxOfPsbt[msg_B'[self].psbt]]
                                           /\ boomlet_pending_txid_nonce_i' = [boomlet_pending_txid_nonce_i EXCEPT ![self] = NonceValue(self, "txid", 0)]
                                           /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                     "Failure of assertion at line 1631, column 13.")
                                           /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalBoomletNisoMessage1(
                                                                                                   TxIdChallengeCipher(self, boomlet_committed_tx_id_i'[self], boomlet_pending_txid_nonce_i'[self]))]
                                           /\ wire_trace' = (          wire_trace \cup
                                                             { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage1(
                                                                 TxIdChallengeCipher(self, boomlet_committed_tx_id_i'[self], boomlet_pending_txid_nonce_i'[self]))) })
                                           /\ UNCHANGED << boomlet_mystery_i, 
                                                           boomlet_saved_duress_space_i, 
                                                           boomlet_saved_duress_stage_i, 
                                                           boomlet_saved_duress_seq_i, 
                                                           boomlet_pending_duress_nonce_i, 
                                                           boomlet_duress_placeholder_plaintext_i, 
                                                           boomlet_duress_placeholder_cipher_i, 
                                                           boomlet_signed_tx_approval_i, 
                                                           boomlet_saved_wt_tx_approval_i, 
                                                           boomlet_all_peer_approvals_i, 
                                                           boomlet_approvals_bundle_i, 
                                                           boomlet_signed_commit_inner_i, 
                                                           boomlet_commit_collection_i, 
                                                           boomlet_counter_i, 
                                                           boomlet_last_seen_block_i, 
                                                           boomlet_ping_seq_num_i, 
                                                           boomlet_reached_mystery_flag_i, 
                                                           boomlet_known_reached_i, 
                                                           boomlet_prev_pings_i, 
                                                           boomlet_ready_to_sign_i, 
                                                           duressSignal, 
                                                           hydrated, 
                                                           signedPong, 
                                                           prevPings >>
                                      ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage2"
                                                 THEN /\ Assert(TxIdAckValid(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self], msg_B'[self].tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet), 
                                                                "Failure of assertion at line 1638, column 13.")
                                                      /\ boomlet_signed_tx_approval_i' = [boomlet_signed_tx_approval_i EXCEPT ![self] = SignedTxApproval(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self])]
                                                      /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                "Failure of assertion at line 1640, column 13.")
                                                      /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalBoomletNisoMessage2(
                                                                                                              ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self]),
                                                                                                              Collection([j \in NonInitiators |-> PsbtCipherForPeer(self, j, boomlet_saved_psbt_i[self], boomlet_committed_tx_id_i[self]) ]))]
                                                      /\ wire_trace' = (          wire_trace \cup
                                                                        { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage2(
                                                                            ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self]),
                                                                            Collection([j \in NonInitiators |-> PsbtCipherForPeer(self, j, boomlet_saved_psbt_i[self], boomlet_committed_tx_id_i[self]) ]))) })
                                                      /\ UNCHANGED << boomlet_mystery_i, 
                                                                      boomlet_saved_psbt_i, 
                                                                      boomlet_committed_tx_id_i, 
                                                                      boomlet_pending_txid_nonce_i, 
                                                                      boomlet_saved_duress_space_i, 
                                                                      boomlet_saved_duress_stage_i, 
                                                                      boomlet_saved_duress_seq_i, 
                                                                      boomlet_pending_duress_nonce_i, 
                                                                      boomlet_duress_placeholder_plaintext_i, 
                                                                      boomlet_duress_placeholder_cipher_i, 
                                                                      boomlet_saved_wt_tx_approval_i, 
                                                                      boomlet_all_peer_approvals_i, 
                                                                      boomlet_approvals_bundle_i, 
                                                                      boomlet_signed_commit_inner_i, 
                                                                      boomlet_commit_collection_i, 
                                                                      boomlet_counter_i, 
                                                                      boomlet_last_seen_block_i, 
                                                                      boomlet_ping_seq_num_i, 
                                                                      boomlet_reached_mystery_flag_i, 
                                                                      boomlet_known_reached_i, 
                                                                      boomlet_prev_pings_i, 
                                                                      boomlet_ready_to_sign_i, 
                                                                      duressSignal, 
                                                                      hydrated, 
                                                                      signedPong, 
                                                                      prevPings >>
                                                 ELSE /\ IF msg_B'[self].kind = "WithdrawalNonInitiatorNisoBoomletMessage1"
                                                            THEN /\ Assert(self # INITIATOR, 
                                                                           "Failure of assertion at line 1649, column 13.")
                                                                 /\ Assert(ValidSig(msg_B'[self].wt_tx_approval_signed_by_wt, WTActor), 
                                                                           "Failure of assertion at line 1650, column 13.")
                                                                 /\ Assert(ValidSig(msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0, BoomletActor(INITIATOR)), 
                                                                           "Failure of assertion at line 1651, column 13.")
                                                                 /\ Assert(SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).initiator_id \in peer_id_collection, 
                                                                           "Failure of assertion at line 1652, column 13.")
                                                                 /\ Assert(SignedContent(msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0).magic = "approved", 
                                                                           "Failure of assertion at line 1653, column 13.")
                                                                 /\ Assert(SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).magic = "approved", 
                                                                           "Failure of assertion at line 1654, column 13.")
                                                                 /\ boomlet_saved_wt_tx_approval_i' = [boomlet_saved_wt_tx_approval_i EXCEPT ![self] = msg_B'[self].wt_tx_approval_signed_by_wt]
                                                                 /\ boomlet_signed_tx_approval_i' = [boomlet_signed_tx_approval_i EXCEPT ![INITIATOR] = msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0]
                                                                 /\ boomlet_saved_psbt_i' = [boomlet_saved_psbt_i EXCEPT ![self] = Decrypt(msg_B'[self].psbt_encrypted_by_boomlet_0_for_boomlet_i, BoomletActor(self))]
                                                                 /\ Assert(boomlet_saved_psbt_i'[self] # NoValue, 
                                                                           "Failure of assertion at line 1658, column 13.")
                                                                 /\ boomlet_committed_tx_id_i' = [boomlet_committed_tx_id_i EXCEPT ![self] = TxOfPsbt[boomlet_saved_psbt_i'[self]]]
                                                                 /\ Assert(boomlet_committed_tx_id_i'[self] = SignedContent(msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0).tx_id, 
                                                                           "Failure of assertion at line 1660, column 13.")
                                                                 /\ Assert(SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).tx_id = boomlet_committed_tx_id_i'[self], 
                                                                           "Failure of assertion at line 1661, column 13.")
                                                                 /\ Assert(   SignedContent(msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0).event_block_height >=
                                                                           IF SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                                                                           THEN SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                                                                           ELSE 0, 
                                                                           "Failure of assertion at line 1662, column 13.")
                                                                 /\ Assert(   SignedContent(msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0).event_block_height <=
                                                                           Min2(
                                                                               msg_B'[self].niso_1_event_block_height,
                                                                               SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height), 
                                                                           "Failure of assertion at line 1666, column 13.")
                                                                 /\ Assert(   SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height >=
                                                                           Max2(
                                                                               SignedContent(msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0).event_block_height,
                                                                               IF msg_B'[self].niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                                                                               THEN msg_B'[self].niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_WT_TX_APPROVAL_BY_NON_INITIATOR_PEERS
                                                                               ELSE 0), 
                                                                           "Failure of assertion at line 1670, column 13.")
                                                                 /\ Assert(   SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height <=
                                                                           Min2(
                                                                               SignedContent(msg_B'[self].peer_0_tx_approval_signed_by_boomlet_0).event_block_height
                                                                                   + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT,
                                                                               msg_B'[self].niso_1_event_block_height), 
                                                                           "Failure of assertion at line 1676, column 13.")
                                                                 /\ Assert(msg_B'[self].niso_1_event_block_height >= boomerang_descriptor.milestone_block_0, 
                                                                           "Failure of assertion at line 1681, column 13.")
                                                                 /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                           "Failure of assertion at line 1682, column 13.")
                                                                 /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = WithdrawalNonInitiatorBoomletNisoMessage1(boomlet_saved_psbt_i'[self])]
                                                                 /\ wire_trace' = (          wire_trace \cup
                                                                                   { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage1(boomlet_saved_psbt_i'[self])) })
                                                                 /\ UNCHANGED << boomlet_mystery_i, 
                                                                                 boomlet_pending_txid_nonce_i, 
                                                                                 boomlet_saved_duress_space_i, 
                                                                                 boomlet_saved_duress_stage_i, 
                                                                                 boomlet_saved_duress_seq_i, 
                                                                                 boomlet_pending_duress_nonce_i, 
                                                                                 boomlet_duress_placeholder_plaintext_i, 
                                                                                 boomlet_duress_placeholder_cipher_i, 
                                                                                 boomlet_all_peer_approvals_i, 
                                                                                 boomlet_approvals_bundle_i, 
                                                                                 boomlet_signed_commit_inner_i, 
                                                                                 boomlet_commit_collection_i, 
                                                                                 boomlet_counter_i, 
                                                                                 boomlet_last_seen_block_i, 
                                                                                 boomlet_ping_seq_num_i, 
                                                                                 boomlet_reached_mystery_flag_i, 
                                                                                 boomlet_known_reached_i, 
                                                                                 boomlet_prev_pings_i, 
                                                                                 boomlet_ready_to_sign_i, 
                                                                                 duressSignal, 
                                                                                 hydrated, 
                                                                                 signedPong, 
                                                                                 prevPings >>
                                                            ELSE /\ IF msg_B'[self].kind = "WithdrawalNonInitiatorNisoBoomletMessage2"
                                                                       THEN /\ boomlet_pending_txid_nonce_i' = [boomlet_pending_txid_nonce_i EXCEPT ![self] = NonceValue(self, "txid", 0)]
                                                                            /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                      "Failure of assertion at line 1688, column 13.")
                                                                            /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalNonInitiatorBoomletNisoMessage2(
                                                                                                                                    TxIdChallengeCipher(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i'[self]))]
                                                                            /\ wire_trace' = (          wire_trace \cup
                                                                                              { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage2(
                                                                                                  TxIdChallengeCipher(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i'[self]))) })
                                                                            /\ UNCHANGED << boomlet_mystery_i, 
                                                                                            boomlet_saved_psbt_i, 
                                                                                            boomlet_committed_tx_id_i, 
                                                                                            boomlet_saved_duress_space_i, 
                                                                                            boomlet_saved_duress_stage_i, 
                                                                                            boomlet_saved_duress_seq_i, 
                                                                                            boomlet_pending_duress_nonce_i, 
                                                                                            boomlet_duress_placeholder_plaintext_i, 
                                                                                            boomlet_duress_placeholder_cipher_i, 
                                                                                            boomlet_signed_tx_approval_i, 
                                                                                            boomlet_saved_wt_tx_approval_i, 
                                                                                            boomlet_all_peer_approvals_i, 
                                                                                            boomlet_approvals_bundle_i, 
                                                                                            boomlet_signed_commit_inner_i, 
                                                                                            boomlet_commit_collection_i, 
                                                                                            boomlet_counter_i, 
                                                                                            boomlet_last_seen_block_i, 
                                                                                            boomlet_ping_seq_num_i, 
                                                                                            boomlet_reached_mystery_flag_i, 
                                                                                            boomlet_known_reached_i, 
                                                                                            boomlet_prev_pings_i, 
                                                                                            boomlet_ready_to_sign_i, 
                                                                                            duressSignal, 
                                                                                            hydrated, 
                                                                                            signedPong, 
                                                                                            prevPings >>
                                                                       ELSE /\ IF msg_B'[self].kind = "WithdrawalNonInitiatorNisoBoomletMessage3"
                                                                                  THEN /\ Assert(TxIdAckValid(self, boomlet_committed_tx_id_i[self], boomlet_pending_txid_nonce_i[self], msg_B'[self].tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet), 
                                                                                                 "Failure of assertion at line 1695, column 13.")
                                                                                       /\ boomlet_signed_tx_approval_i' = [boomlet_signed_tx_approval_i EXCEPT ![self] = SignedTxApproval(self, boomlet_committed_tx_id_i[self], msg_B'[self].niso_1_event_block_height)]
                                                                                       /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                 "Failure of assertion at line 1697, column 13.")
                                                                                       /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalNonInitiatorBoomletNisoMessage3(
                                                                                                                                               ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], msg_B'[self].niso_1_event_block_height))]
                                                                                       /\ wire_trace' = (          wire_trace \cup
                                                                                                         { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage3(
                                                                                                             ApprovalCipherForWT(self, boomlet_committed_tx_id_i[self], msg_B'[self].niso_1_event_block_height))) })
                                                                                       /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                       boomlet_saved_psbt_i, 
                                                                                                       boomlet_committed_tx_id_i, 
                                                                                                       boomlet_pending_txid_nonce_i, 
                                                                                                       boomlet_saved_duress_space_i, 
                                                                                                       boomlet_saved_duress_stage_i, 
                                                                                                       boomlet_saved_duress_seq_i, 
                                                                                                       boomlet_pending_duress_nonce_i, 
                                                                                                       boomlet_duress_placeholder_plaintext_i, 
                                                                                                       boomlet_duress_placeholder_cipher_i, 
                                                                                                       boomlet_saved_wt_tx_approval_i, 
                                                                                                       boomlet_all_peer_approvals_i, 
                                                                                                       boomlet_approvals_bundle_i, 
                                                                                                       boomlet_signed_commit_inner_i, 
                                                                                                       boomlet_commit_collection_i, 
                                                                                                       boomlet_counter_i, 
                                                                                                       boomlet_last_seen_block_i, 
                                                                                                       boomlet_ping_seq_num_i, 
                                                                                                       boomlet_reached_mystery_flag_i, 
                                                                                                       boomlet_known_reached_i, 
                                                                                                       boomlet_prev_pings_i, 
                                                                                                       boomlet_ready_to_sign_i, 
                                                                                                       duressSignal, 
                                                                                                       hydrated, 
                                                                                                       signedPong, 
                                                                                                       prevPings >>
                                                                                  ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage3"
                                                                                             THEN /\ Assert(ValidSig(msg_B'[self].wt_tx_approval_signed_by_wt, WTActor), 
                                                                                                            "Failure of assertion at line 1704, column 13.")
                                                                                                  /\ Assert(SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).magic = "approved", 
                                                                                                            "Failure of assertion at line 1705, column 13.")
                                                                                                  /\ Assert(SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).tx_id = boomlet_committed_tx_id_i[self], 
                                                                                                            "Failure of assertion at line 1706, column 13.")
                                                                                                  /\ Assert(   \A j \in NonInitiators :
                                                                                                            /\ ValidSig(msg_B'[self].all_peer_tx_approvals[j], BoomletActor(j))
                                                                                                            /\ SignedContent(msg_B'[self].all_peer_tx_approvals[j]).magic = "approved"
                                                                                                            /\ SignedContent(msg_B'[self].all_peer_tx_approvals[j]).tx_id = boomlet_committed_tx_id_i[self]
                                                                                                            /\ SignedContent(msg_B'[self].all_peer_tx_approvals[j]).event_block_height >=
                                                                                                                Max2(
                                                                                                                    SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height,
                                                                                                                    IF msg_B'[self].niso_0_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                                                                                                                    THEN msg_B'[self].niso_0_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                                                                                                                    ELSE 0)
                                                                                                            /\ msg_B'[self].niso_0_event_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                                                                                                            /\ SignedContent(msg_B'[self].all_peer_tx_approvals[j]).event_block_height <=
                                                                                                                msg_B'[self].niso_0_event_block_height
                                                                                                                             - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER, 
                                                                                                            "Failure of assertion at line 1707, column 13.")
                                                                                                  /\ Assert(SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height >= SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height, 
                                                                                                            "Failure of assertion at line 1721, column 13.")
                                                                                                  /\ Assert(   SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height <=
                                                                                                            Min2(
                                                                                                                SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height
                                                                                                                    + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT,
                                                                                                                msg_B'[self].niso_0_event_block_height), 
                                                                                                            "Failure of assertion at line 1722, column 13.")
                                                                                                  /\ Assert(   SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height >=
                                                                                                            Max2(
                                                                                                                IF SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                                                                                                                THEN SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                                                                                                                ELSE 0,
                                                                                                                IF msg_B'[self].niso_0_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                                                                                                                THEN msg_B'[self].niso_0_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                                                                                                                ELSE 0), 
                                                                                                            "Failure of assertion at line 1727, column 13.")
                                                                                                  /\ Assert(SignedContent(boomlet_signed_tx_approval_i[self]).event_block_height <= SignedContent(msg_B'[self].wt_tx_approval_signed_by_wt).event_block_height, 
                                                                                                            "Failure of assertion at line 1735, column 13.")
                                                                                                  /\ boomlet_all_peer_approvals_i' = [boomlet_all_peer_approvals_i EXCEPT ![self] = msg_B'[self].all_peer_tx_approvals]
                                                                                                  /\ boomlet_saved_wt_tx_approval_i' = [boomlet_saved_wt_tx_approval_i EXCEPT ![self] = msg_B'[self].wt_tx_approval_signed_by_wt]
                                                                                                  /\ boomlet_saved_duress_stage_i' = [boomlet_saved_duress_stage_i EXCEPT ![self] = "initial"]
                                                                                                  /\ boomlet_saved_duress_seq_i' = [boomlet_saved_duress_seq_i EXCEPT ![self] = 1]
                                                                                                  /\ \E space \in DuressCheckSpaces(self, "initial", 1):
                                                                                                       /\ boomlet_saved_duress_space_i' = [boomlet_saved_duress_space_i EXCEPT ![self] = space]
                                                                                                       /\ boomlet_pending_duress_nonce_i' = [boomlet_pending_duress_nonce_i EXCEPT ![self] = NonceValue(self, "initial_duress", 1)]
                                                                                                       /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                 "Failure of assertion at line 1743, column 17.")
                                                                                                       /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = WithdrawalBoomletNisoMessage3(DuressCheckCipher(space, boomlet_pending_duress_nonce_i'[self]))]
                                                                                                       /\ wire_trace' = (          wire_trace \cup
                                                                                                                         { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage3(DuressCheckCipher(space, boomlet_pending_duress_nonce_i'[self]))) })
                                                                                                  /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                  boomlet_saved_psbt_i, 
                                                                                                                  boomlet_committed_tx_id_i, 
                                                                                                                  boomlet_pending_txid_nonce_i, 
                                                                                                                  boomlet_duress_placeholder_plaintext_i, 
                                                                                                                  boomlet_duress_placeholder_cipher_i, 
                                                                                                                  boomlet_approvals_bundle_i, 
                                                                                                                  boomlet_signed_commit_inner_i, 
                                                                                                                  boomlet_commit_collection_i, 
                                                                                                                  boomlet_counter_i, 
                                                                                                                  boomlet_last_seen_block_i, 
                                                                                                                  boomlet_ping_seq_num_i, 
                                                                                                                  boomlet_reached_mystery_flag_i, 
                                                                                                                  boomlet_known_reached_i, 
                                                                                                                  boomlet_prev_pings_i, 
                                                                                                                  boomlet_ready_to_sign_i, 
                                                                                                                  duressSignal, 
                                                                                                                  hydrated, 
                                                                                                                  signedPong, 
                                                                                                                  prevPings >>
                                                                                             ELSE /\ IF msg_B'[self].kind = "WithdrawalNonInitiatorNisoBoomletMessage4"
                                                                                                        THEN /\ Assert(boomlet_saved_wt_tx_approval_i[self] # NoValue, 
                                                                                                                       "Failure of assertion at line 1749, column 13.")
                                                                                                             /\ Assert(   \A j \in NonInitiators :
                                                                                                                       /\ ValidSig(msg_B'[self].non_initiator_tx_approvals[j], BoomletActor(j))
                                                                                                                       /\ SignedContent(msg_B'[self].non_initiator_tx_approvals[j]).magic = "approved"
                                                                                                                       /\ SignedContent(msg_B'[self].non_initiator_tx_approvals[j]).tx_id = boomlet_committed_tx_id_i[self]
                                                                                                                       /\ SignedContent(msg_B'[self].non_initiator_tx_approvals[j]).event_block_height >=
                                                                                                                           Max2(
                                                                                                                               SignedContent(boomlet_saved_wt_tx_approval_i[self]).event_block_height,
                                                                                                                               IF msg_B'[self].niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                                                               THEN msg_B'[self].niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                                                               ELSE 0)
                                                                                                                       /\ SignedContent(msg_B'[self].non_initiator_tx_approvals[j]).event_block_height <=
                                                                                                                           Min2(
                                                                                                                               msg_B'[self].niso_1_event_block_height,
                                                                                                                               SignedContent(boomlet_saved_wt_tx_approval_i[self]).event_block_height
                                                                                                                                   + TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS), 
                                                                                                                       "Failure of assertion at line 1750, column 13.")
                                                                                                             /\ Assert(   SignedContent(boomlet_saved_wt_tx_approval_i[self]).event_block_height >=
                                                                                                                       IF msg_B'[self].niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                                                       THEN msg_B'[self].niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_WT_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_OTHER_NON_INITIATOR_PEERS
                                                                                                                       ELSE 0, 
                                                                                                                       "Failure of assertion at line 1765, column 13.")
                                                                                                             /\ boomlet_all_peer_approvals_i' = [boomlet_all_peer_approvals_i EXCEPT ![self] = msg_B'[self].non_initiator_tx_approvals]
                                                                                                             /\ boomlet_saved_duress_stage_i' = [boomlet_saved_duress_stage_i EXCEPT ![self] = "initial"]
                                                                                                             /\ boomlet_saved_duress_seq_i' = [boomlet_saved_duress_seq_i EXCEPT ![self] = 1]
                                                                                                             /\ \E space \in DuressCheckSpaces(self, "initial", 1):
                                                                                                                  /\ boomlet_saved_duress_space_i' = [boomlet_saved_duress_space_i EXCEPT ![self] = space]
                                                                                                                  /\ boomlet_pending_duress_nonce_i' = [boomlet_pending_duress_nonce_i EXCEPT ![self] = NonceValue(self, "initial_duress", 1)]
                                                                                                                  /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                            "Failure of assertion at line 1775, column 17.")
                                                                                                                  /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = WithdrawalNonInitiatorBoomletNisoMessage4(DuressCheckCipher(space, boomlet_pending_duress_nonce_i'[self]))]
                                                                                                                  /\ wire_trace' = (          wire_trace \cup
                                                                                                                                    { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage4(DuressCheckCipher(space, boomlet_pending_duress_nonce_i'[self]))) })
                                                                                                             /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                             boomlet_saved_psbt_i, 
                                                                                                                             boomlet_committed_tx_id_i, 
                                                                                                                             boomlet_pending_txid_nonce_i, 
                                                                                                                             boomlet_duress_placeholder_plaintext_i, 
                                                                                                                             boomlet_duress_placeholder_cipher_i, 
                                                                                                                             boomlet_approvals_bundle_i, 
                                                                                                                             boomlet_signed_commit_inner_i, 
                                                                                                                             boomlet_commit_collection_i, 
                                                                                                                             boomlet_counter_i, 
                                                                                                                             boomlet_last_seen_block_i, 
                                                                                                                             boomlet_ping_seq_num_i, 
                                                                                                                             boomlet_reached_mystery_flag_i, 
                                                                                                                             boomlet_known_reached_i, 
                                                                                                                             boomlet_prev_pings_i, 
                                                                                                                             boomlet_ready_to_sign_i, 
                                                                                                                             duressSignal, 
                                                                                                                             hydrated, 
                                                                                                                             signedPong, 
                                                                                                                             prevPings >>
                                                                                                        ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage4"
                                                                                                                   THEN /\ Assert(DuressReplyMatchesSpace(self, boomlet_saved_duress_space_i[self], "initial", boomlet_saved_duress_seq_i[self], boomlet_pending_duress_nonce_i[self], msg_B'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet), 
                                                                                                                                  "Failure of assertion at line 1781, column 13.")
                                                                                                                        /\ duressSignal' = [duressSignal EXCEPT ![self] =             DerivedDuressSignal(
                                                                                                                                                                          boomlet_saved_duress_space_i[self],
                                                                                                                                                                          Decrypt(msg_B'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet, BoomletActor(self)).content)]
                                                                                                                        /\ IF duressSignal'[self] = duress_consent_set_i[self]
                                                                                                                              THEN /\ boomlet_duress_placeholder_plaintext_i' = [boomlet_duress_placeholder_plaintext_i EXCEPT ![self] = SafePaddingPlaintext(self, "commit", boomlet_saved_duress_seq_i[self])]
                                                                                                                              ELSE /\ boomlet_duress_placeholder_plaintext_i' = [boomlet_duress_placeholder_plaintext_i EXCEPT ![self] = doxing_key_i[self]]
                                                                                                                        /\ boomlet_duress_placeholder_cipher_i' = [boomlet_duress_placeholder_cipher_i EXCEPT ![self] = PlaceholderCipherForSAR(self, "commit", boomlet_saved_duress_seq_i[self], boomlet_duress_placeholder_plaintext_i'[self])]
                                                                                                                        /\ boomlet_signed_commit_inner_i' = [boomlet_signed_commit_inner_i EXCEPT ![self] = SignedCommitInner(self, boomlet_committed_tx_id_i[self], niso_event_block_height_i[self])]
                                                                                                                        /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                  "Failure of assertion at line 1794, column 13.")
                                                                                                                        /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalBoomletNisoMessage4(
                                                                                                                                                                                CommitCipherForWT(
                                                                                                                                                                                    self,
                                                                                                                                                                                    boomlet_committed_tx_id_i[self],
                                                                                                                                                                                    niso_event_block_height_i[self],
                                                                                                                                                                                    boomlet_duress_placeholder_cipher_i'[self]))]
                                                                                                                        /\ wire_trace' = (          wire_trace \cup
                                                                                                                                          { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage4(
                                                                                                                                              CommitCipherForWT(
                                                                                                                                                  self,
                                                                                                                                                  boomlet_committed_tx_id_i[self],
                                                                                                                                                  niso_event_block_height_i[self],
                                                                                                                                                  boomlet_duress_placeholder_cipher_i'[self]))) })
                                                                                                                        /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                                        boomlet_saved_psbt_i, 
                                                                                                                                        boomlet_committed_tx_id_i, 
                                                                                                                                        boomlet_pending_txid_nonce_i, 
                                                                                                                                        boomlet_saved_duress_space_i, 
                                                                                                                                        boomlet_saved_duress_stage_i, 
                                                                                                                                        boomlet_saved_duress_seq_i, 
                                                                                                                                        boomlet_pending_duress_nonce_i, 
                                                                                                                                        boomlet_approvals_bundle_i, 
                                                                                                                                        boomlet_commit_collection_i, 
                                                                                                                                        boomlet_counter_i, 
                                                                                                                                        boomlet_last_seen_block_i, 
                                                                                                                                        boomlet_ping_seq_num_i, 
                                                                                                                                        boomlet_reached_mystery_flag_i, 
                                                                                                                                        boomlet_known_reached_i, 
                                                                                                                                        boomlet_prev_pings_i, 
                                                                                                                                        boomlet_ready_to_sign_i, 
                                                                                                                                        hydrated, 
                                                                                                                                        signedPong, 
                                                                                                                                        prevPings >>
                                                                                                                   ELSE /\ IF msg_B'[self].kind = "WithdrawalNonInitiatorNisoBoomletMessage5"
                                                                                                                              THEN /\ Assert(DuressReplyMatchesSpace(self, boomlet_saved_duress_space_i[self], "initial", boomlet_saved_duress_seq_i[self], boomlet_pending_duress_nonce_i[self], msg_B'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet), 
                                                                                                                                             "Failure of assertion at line 1809, column 13.")
                                                                                                                                   /\ duressSignal' = [duressSignal EXCEPT ![self] =             DerivedDuressSignal(
                                                                                                                                                                                     boomlet_saved_duress_space_i[self],
                                                                                                                                                                                     Decrypt(msg_B'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet, BoomletActor(self)).content)]
                                                                                                                                   /\ IF duressSignal'[self] = duress_consent_set_i[self]
                                                                                                                                         THEN /\ boomlet_duress_placeholder_plaintext_i' = [boomlet_duress_placeholder_plaintext_i EXCEPT ![self] = SafePaddingPlaintext(self, "commit", boomlet_saved_duress_seq_i[self])]
                                                                                                                                         ELSE /\ boomlet_duress_placeholder_plaintext_i' = [boomlet_duress_placeholder_plaintext_i EXCEPT ![self] = doxing_key_i[self]]
                                                                                                                                   /\ boomlet_duress_placeholder_cipher_i' = [boomlet_duress_placeholder_cipher_i EXCEPT ![self] = PlaceholderCipherForSAR(self, "commit", boomlet_saved_duress_seq_i[self], boomlet_duress_placeholder_plaintext_i'[self])]
                                                                                                                                   /\ boomlet_approvals_bundle_i' = [boomlet_approvals_bundle_i EXCEPT ![self] = SignatureOnMessage(
                                                                                                                                                                                                                     BoomletActor(self),
                                                                                                                                                                                                                     ApprovalsBundle(
                                                                                                                                                                                                                         [j \in Peers |->
                                                                                                                                                                                                                             IF j = INITIATOR
                                                                                                                                                                                                                             THEN boomlet_signed_tx_approval_i[INITIATOR]
                                                                                                                                                                                                                             ELSE boomlet_all_peer_approvals_i[self][j]],
                                                                                                                                                                                                                         boomlet_saved_wt_tx_approval_i[self]))]
                                                                                                                                   /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                             "Failure of assertion at line 1829, column 13.")
                                                                                                                                   /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = WithdrawalNonInitiatorBoomletNisoMessage5(boomlet_approvals_bundle_i'[self])]
                                                                                                                                   /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                     { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage5(boomlet_approvals_bundle_i'[self])) })
                                                                                                                                   /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                                                   boomlet_saved_psbt_i, 
                                                                                                                                                   boomlet_committed_tx_id_i, 
                                                                                                                                                   boomlet_pending_txid_nonce_i, 
                                                                                                                                                   boomlet_saved_duress_space_i, 
                                                                                                                                                   boomlet_saved_duress_stage_i, 
                                                                                                                                                   boomlet_saved_duress_seq_i, 
                                                                                                                                                   boomlet_pending_duress_nonce_i, 
                                                                                                                                                   boomlet_signed_commit_inner_i, 
                                                                                                                                                   boomlet_commit_collection_i, 
                                                                                                                                                   boomlet_counter_i, 
                                                                                                                                                   boomlet_last_seen_block_i, 
                                                                                                                                                   boomlet_ping_seq_num_i, 
                                                                                                                                                   boomlet_reached_mystery_flag_i, 
                                                                                                                                                   boomlet_known_reached_i, 
                                                                                                                                                   boomlet_prev_pings_i, 
                                                                                                                                                   boomlet_ready_to_sign_i, 
                                                                                                                                                   hydrated, 
                                                                                                                                                   signedPong, 
                                                                                                                                                   prevPings >>
                                                                                                                              ELSE /\ IF msg_B'[self].kind = "WithdrawalNonInitiatorNisoBoomletMessage6"
                                                                                                                                         THEN /\ Assert(   WTSignedCommitValid(
                                                                                                                                                        msg_B'[self].peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt,
                                                                                                                                                        INITIATOR,
                                                                                                                                                        boomlet_committed_tx_id_i[self],
                                                                                                                                                        IF msg_B'[self].niso_1_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                                                                                                                                                        THEN msg_B'[self].niso_1_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_PEER_TO_RECEIVING_INITIATOR_PEER_TX_COMMITMENT_BY_NON_INITIATOR_PEERS
                                                                                                                                                        ELSE 0,
                                                                                                                                                        msg_B'[self].niso_1_event_block_height), 
                                                                                                                                                        "Failure of assertion at line 1834, column 13.")
                                                                                                                                              /\ boomlet_signed_commit_inner_i' = [boomlet_signed_commit_inner_i EXCEPT ![self] = SignedCommitInner(self, boomlet_committed_tx_id_i[self], msg_B'[self].niso_1_event_block_height)]
                                                                                                                                              /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                                        "Failure of assertion at line 1843, column 13.")
                                                                                                                                              /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalNonInitiatorBoomletNisoMessage6(
                                                                                                                                                                                                      CommitCipherForWT(
                                                                                                                                                                                                          self,
                                                                                                                                                                                                          boomlet_committed_tx_id_i[self],
                                                                                                                                                                                                          msg_B'[self].niso_1_event_block_height,
                                                                                                                                                                                                          boomlet_duress_placeholder_cipher_i[self]))]
                                                                                                                                              /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                { WireHop(BoomletActor(self), NisoActor(self), WithdrawalNonInitiatorBoomletNisoMessage6(
                                                                                                                                                                    CommitCipherForWT(
                                                                                                                                                                        self,
                                                                                                                                                                        boomlet_committed_tx_id_i[self],
                                                                                                                                                                        msg_B'[self].niso_1_event_block_height,
                                                                                                                                                                        boomlet_duress_placeholder_cipher_i[self]))) })
                                                                                                                                              /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                                                              boomlet_saved_psbt_i, 
                                                                                                                                                              boomlet_committed_tx_id_i, 
                                                                                                                                                              boomlet_pending_txid_nonce_i, 
                                                                                                                                                              boomlet_saved_duress_space_i, 
                                                                                                                                                              boomlet_saved_duress_stage_i, 
                                                                                                                                                              boomlet_saved_duress_seq_i, 
                                                                                                                                                              boomlet_pending_duress_nonce_i, 
                                                                                                                                                              boomlet_duress_placeholder_plaintext_i, 
                                                                                                                                                              boomlet_duress_placeholder_cipher_i, 
                                                                                                                                                              boomlet_commit_collection_i, 
                                                                                                                                                              boomlet_counter_i, 
                                                                                                                                                              boomlet_last_seen_block_i, 
                                                                                                                                                              boomlet_ping_seq_num_i, 
                                                                                                                                                              boomlet_reached_mystery_flag_i, 
                                                                                                                                                              boomlet_known_reached_i, 
                                                                                                                                                              boomlet_prev_pings_i, 
                                                                                                                                                              boomlet_ready_to_sign_i, 
                                                                                                                                                              duressSignal, 
                                                                                                                                                              hydrated, 
                                                                                                                                                              signedPong, 
                                                                                                                                                              prevPings >>
                                                                                                                                         ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage5"
                                                                                                                                                    THEN /\ Assert(SARReplyValidForPeer(self, boomlet_duress_placeholder_cipher_i[self], msg_B'[self].duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet), 
                                                                                                                                                                   "Failure of assertion at line 1858, column 13.")
                                                                                                                                                         /\ Assert(msg_B'[self].niso_0_event_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS, 
                                                                                                                                                                   "Failure of assertion at line 1859, column 13.")
                                                                                                                                                         /\ Assert(   \A j \in Peers :
                                                                                                                                                                   WTSignedCommitValid(
                                                                                                                                                                       msg_B'[self].all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt[j],
                                                                                                                                                                       j,
                                                                                                                                                                       boomlet_committed_tx_id_i[self],
                                                                                                                                                                       IF msg_B'[self].niso_0_event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                                                                                                                                                                       THEN msg_B'[self].niso_0_event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                                                                                                                                                                       ELSE 0,
                                                                                                                                                                       msg_B'[self].niso_0_event_block_height
                                                                                                                                                                                    - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS), 
                                                                                                                                                                   "Failure of assertion at line 1860, column 13.")
                                                                                                                                                         /\ boomlet_commit_collection_i' = [boomlet_commit_collection_i EXCEPT ![self] = msg_B'[self].all_peer_tx_commit_signed_by_boomlet_i_signed_by_wt]
                                                                                                                                                         /\ boomlet_counter_i' = [boomlet_counter_i EXCEPT ![self] = 0]
                                                                                                                                                         /\ boomlet_ping_seq_num_i' = [boomlet_ping_seq_num_i EXCEPT ![self] = 0]
                                                                                                                                                         /\ boomlet_reached_mystery_flag_i' = [boomlet_reached_mystery_flag_i EXCEPT ![self] = FALSE]
                                                                                                                                                         /\ boomlet_known_reached_i' = [boomlet_known_reached_i EXCEPT ![self] = {}]
                                                                                                                                                         /\ boomlet_prev_pings_i' = [boomlet_prev_pings_i EXCEPT ![self] = NoValue]
                                                                                                                                                         /\ boomlet_last_seen_block_i' = [boomlet_last_seen_block_i EXCEPT ![self] = msg_B'[self].niso_0_event_block_height]
                                                                                                                                                         /\ boomlet_duress_placeholder_cipher_i' = [boomlet_duress_placeholder_cipher_i EXCEPT ![self] = PlaceholderCipherForSAR(self, "ping", 0, boomlet_duress_placeholder_plaintext_i[self])]
                                                                                                                                                         /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                                                   "Failure of assertion at line 1879, column 13.")
                                                                                                                                                         /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalBoomletNisoMessage5(
                                                                                                                                                                                                                 PingCipherForWT(
                                                                                                                                                                                                                     self,
                                                                                                                                                                                                                     boomlet_committed_tx_id_i[self],
                                                                                                                                                                                                                     boomlet_last_seen_block_i'[self],
                                                                                                                                                                                                                     boomlet_ping_seq_num_i'[self],
                                                                                                                                                                                                                     boomlet_reached_mystery_flag_i'[self],
                                                                                                                                                                                                                     boomlet_duress_placeholder_cipher_i'[self]))]
                                                                                                                                                         /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                           { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage5(
                                                                                                                                                                               PingCipherForWT(
                                                                                                                                                                                   self,
                                                                                                                                                                                   boomlet_committed_tx_id_i[self],
                                                                                                                                                                                   boomlet_last_seen_block_i'[self],
                                                                                                                                                                                   boomlet_ping_seq_num_i'[self],
                                                                                                                                                                                   boomlet_reached_mystery_flag_i'[self],
                                                                                                                                                                                   boomlet_duress_placeholder_cipher_i'[self]))) })
                                                                                                                                                         /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                                                                         boomlet_saved_psbt_i, 
                                                                                                                                                                         boomlet_committed_tx_id_i, 
                                                                                                                                                                         boomlet_pending_txid_nonce_i, 
                                                                                                                                                                         boomlet_saved_duress_space_i, 
                                                                                                                                                                         boomlet_saved_duress_stage_i, 
                                                                                                                                                                         boomlet_saved_duress_seq_i, 
                                                                                                                                                                         boomlet_pending_duress_nonce_i, 
                                                                                                                                                                         boomlet_duress_placeholder_plaintext_i, 
                                                                                                                                                                         boomlet_signed_commit_inner_i, 
                                                                                                                                                                         boomlet_ready_to_sign_i, 
                                                                                                                                                                         duressSignal, 
                                                                                                                                                                         hydrated, 
                                                                                                                                                                         signedPong, 
                                                                                                                                                                         prevPings >>
                                                                                                                                                    ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage6"
                                                                                                                                                               THEN /\ Assert(SARReplyValidForPeer(self, boomlet_duress_placeholder_cipher_i[self], msg_B'[self].duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet), 
                                                                                                                                                                              "Failure of assertion at line 1898, column 13.")
                                                                                                                                                                    /\ Assert(   PongDeliveryValidForPeer(
                                                                                                                                                                              msg_B'[self],
                                                                                                                                                                              self,
                                                                                                                                                                              boomlet_committed_tx_id_i[self],
                                                                                                                                                                              msg_B'[self].niso_0_event_block_height,
                                                                                                                                                                              boomlet_prev_pings_i[self],
                                                                                                                                                                              boomlet_known_reached_i[self]), 
                                                                                                                                                                              "Failure of assertion at line 1899, column 13.")
                                                                                                                                                                    /\ signedPong' = [signedPong EXCEPT ![self] = Decrypt(msg_B'[self].pong_signed_by_wt_encrypted_by_wt_for_boomlet, BoomletActor(self))]
                                                                                                                                                                    /\ prevPings' = [prevPings EXCEPT ![self] = SignedContent(signedPong'[self]).prev_pings.items]
                                                                                                                                                                    /\ IF CanIncrementCounter(self, msg_B'[self].niso_0_event_block_height, prevPings'[self], boomlet_last_seen_block_i[self])
                                                                                                                                                                          THEN /\ boomlet_counter_i' = [boomlet_counter_i EXCEPT ![self] = boomlet_counter_i[self] + 1]
                                                                                                                                                                          ELSE /\ TRUE
                                                                                                                                                                               /\ UNCHANGED boomlet_counter_i
                                                                                                                                                                    /\ boomlet_known_reached_i' = [boomlet_known_reached_i EXCEPT ![self] = boomlet_known_reached_i[self] \cup { j \in (Peers \ {self}) : SignedContent(prevPings'[self][j]).reached_mystery_flag }]
                                                                                                                                                                    /\ IF boomlet_counter_i'[self] >= boomlet_mystery_i[self]
                                                                                                                                                                          THEN /\ boomlet_reached_mystery_flag_i' = [boomlet_reached_mystery_flag_i EXCEPT ![self] = TRUE]
                                                                                                                                                                          ELSE /\ TRUE
                                                                                                                                                                               /\ UNCHANGED boomlet_reached_mystery_flag_i
                                                                                                                                                                    /\ IF boomlet_last_seen_block_i[self] < msg_B'[self].niso_0_event_block_height
                                                                                                                                                                          THEN /\ IF boomlet_last_seen_block_i[self] + JUMP_IN_BLOCKS_IF_LAST_SEEN_BLOCK_LAGS_BEHIND_NISO_EVENT_BLOCK_HEIGHT_IN_BOOMLET < msg_B'[self].niso_0_event_block_height
                                                                                                                                                                                     THEN /\ boomlet_last_seen_block_i' = [boomlet_last_seen_block_i EXCEPT ![self] = boomlet_last_seen_block_i[self] + JUMP_IN_BLOCKS_IF_LAST_SEEN_BLOCK_LAGS_BEHIND_NISO_EVENT_BLOCK_HEIGHT_IN_BOOMLET]
                                                                                                                                                                                     ELSE /\ boomlet_last_seen_block_i' = [boomlet_last_seen_block_i EXCEPT ![self] = msg_B'[self].niso_0_event_block_height]
                                                                                                                                                                          ELSE /\ TRUE
                                                                                                                                                                               /\ UNCHANGED boomlet_last_seen_block_i
                                                                                                                                                                    /\ boomlet_prev_pings_i' = [boomlet_prev_pings_i EXCEPT ![self] = prevPings'[self]]
                                                                                                                                                                    /\ \E prng_draw \in RecurringDuressPRNGDraws:
                                                                                                                                                                         IF RecurringDuressCheckFires(prng_draw)
                                                                                                                                                                            THEN /\ boomlet_saved_duress_stage_i' = [boomlet_saved_duress_stage_i EXCEPT ![self] = "loop"]
                                                                                                                                                                                 /\ boomlet_saved_duress_seq_i' = [boomlet_saved_duress_seq_i EXCEPT ![self] = boomlet_saved_duress_seq_i[self] + 1]
                                                                                                                                                                                 /\ \E space \in DuressCheckSpaces(self, "loop", boomlet_saved_duress_seq_i'[self]):
                                                                                                                                                                                      /\ boomlet_saved_duress_space_i' = [boomlet_saved_duress_space_i EXCEPT ![self] = space]
                                                                                                                                                                                      /\ boomlet_pending_duress_nonce_i' = [boomlet_pending_duress_nonce_i EXCEPT ![self] = NonceValue(self, "loop_duress", boomlet_saved_duress_seq_i'[self])]
                                                                                                                                                                                      /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                                                                                "Failure of assertion at line 1931, column 25.")
                                                                                                                                                                                      /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = WithdrawalBoomletNisoMessage6(DuressCheckCipher(space, boomlet_pending_duress_nonce_i'[self]))]
                                                                                                                                                                                      /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                                                        { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage6(DuressCheckCipher(space, boomlet_pending_duress_nonce_i'[self]))) })
                                                                                                                                                                                 /\ UNCHANGED << boomlet_duress_placeholder_cipher_i, 
                                                                                                                                                                                                 boomlet_ping_seq_num_i >>
                                                                                                                                                                            ELSE /\ boomlet_ping_seq_num_i' = [boomlet_ping_seq_num_i EXCEPT ![self] = boomlet_ping_seq_num_i[self] + 1]
                                                                                                                                                                                 /\ boomlet_duress_placeholder_cipher_i' = [boomlet_duress_placeholder_cipher_i EXCEPT ![self] = PlaceholderCipherForSAR(self, "ping", boomlet_ping_seq_num_i'[self], boomlet_duress_placeholder_plaintext_i[self])]
                                                                                                                                                                                 /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                                                                           "Failure of assertion at line 1940, column 21.")
                                                                                                                                                                                 /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalBoomletNisoMessage7(
                                                                                                                                                                                                                                         PingCipherForWT(
                                                                                                                                                                                                                                             self,
                                                                                                                                                                                                                                             boomlet_committed_tx_id_i[self],
                                                                                                                                                                                                                                             boomlet_last_seen_block_i'[self],
                                                                                                                                                                                                                                             boomlet_ping_seq_num_i'[self],
                                                                                                                                                                                                                                             boomlet_reached_mystery_flag_i'[self],
                                                                                                                                                                                                                                             boomlet_duress_placeholder_cipher_i'[self]))]
                                                                                                                                                                                 /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                                                   { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage7(
                                                                                                                                                                                                       PingCipherForWT(
                                                                                                                                                                                                           self,
                                                                                                                                                                                                           boomlet_committed_tx_id_i[self],
                                                                                                                                                                                                       boomlet_last_seen_block_i'[self],
                                                                                                                                                                                                       boomlet_ping_seq_num_i'[self],
                                                                                                                                                                                                       boomlet_reached_mystery_flag_i'[self],
                                                                                                                                                                                                       boomlet_duress_placeholder_cipher_i'[self]))) })
                                                                                                                                                                                 /\ UNCHANGED << boomlet_saved_duress_space_i, 
                                                                                                                                                                                                 boomlet_saved_duress_stage_i, 
                                                                                                                                                                                                 boomlet_saved_duress_seq_i, 
                                                                                                                                                                                                 boomlet_pending_duress_nonce_i >>
                                                                                                                                                                    /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                                                                                    boomlet_saved_psbt_i, 
                                                                                                                                                                                    boomlet_committed_tx_id_i, 
                                                                                                                                                                                    boomlet_pending_txid_nonce_i, 
                                                                                                                                                                                    boomlet_duress_placeholder_plaintext_i, 
                                                                                                                                                                                    boomlet_signed_commit_inner_i, 
                                                                                                                                                                                    boomlet_commit_collection_i, 
                                                                                                                                                                                    boomlet_ready_to_sign_i, 
                                                                                                                                                                                    duressSignal, 
                                                                                                                                                                                    hydrated >>
                                                                                                                                                               ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage7"
                                                                                                                                                                          THEN /\ Assert(DuressReplyMatchesSpace(self, boomlet_saved_duress_space_i[self], "loop", boomlet_saved_duress_seq_i[self], boomlet_pending_duress_nonce_i[self], msg_B'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet), 
                                                                                                                                                                                         "Failure of assertion at line 1961, column 13.")
                                                                                                                                                                               /\ duressSignal' = [duressSignal EXCEPT ![self] =             DerivedDuressSignal(
                                                                                                                                                                                                                                 boomlet_saved_duress_space_i[self],
                                                                                                                                                                                                                                 Decrypt(msg_B'[self].duress_signal_index_with_nonce_encrypted_by_st_for_boomlet, BoomletActor(self)).content)]
                                                                                                                                                                               /\ IF duressSignal'[self] = duress_consent_set_i[self]
                                                                                                                                                                                     THEN /\ boomlet_duress_placeholder_plaintext_i' = [boomlet_duress_placeholder_plaintext_i EXCEPT ![self] = SafePaddingPlaintext(self, "ping", boomlet_saved_duress_seq_i[self])]
                                                                                                                                                                                     ELSE /\ boomlet_duress_placeholder_plaintext_i' = [boomlet_duress_placeholder_plaintext_i EXCEPT ![self] = doxing_key_i[self]]
                                                                                                                                                                               /\ boomlet_ping_seq_num_i' = [boomlet_ping_seq_num_i EXCEPT ![self] = boomlet_ping_seq_num_i[self] + 1]
                                                                                                                                                                               /\ boomlet_duress_placeholder_cipher_i' = [boomlet_duress_placeholder_cipher_i EXCEPT ![self] = PlaceholderCipherForSAR(self, "ping", boomlet_ping_seq_num_i'[self], boomlet_duress_placeholder_plaintext_i'[self])]
                                                                                                                                                                               /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                                                                         "Failure of assertion at line 1973, column 13.")
                                                                                                                                                                               /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] =                      WithdrawalBoomletNisoMessage7(
                                                                                                                                                                                                                                       PingCipherForWT(
                                                                                                                                                                                                                                           self,
                                                                                                                                                                                                                                           boomlet_committed_tx_id_i[self],
                                                                                                                                                                                                                                           boomlet_last_seen_block_i[self],
                                                                                                                                                                                                                                           boomlet_ping_seq_num_i'[self],
                                                                                                                                                                                                                                           boomlet_reached_mystery_flag_i[self],
                                                                                                                                                                                                                                           boomlet_duress_placeholder_cipher_i'[self]))]
                                                                                                                                                                               /\ wire_trace' = (          wire_trace \cup
                                                                                                                                                                                                 { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage7(
                                                                                                                                                                                                     PingCipherForWT(
                                                                                                                                                                                                         self,
                                                                                                                                                                                                         boomlet_committed_tx_id_i[self],
                                                                                                                                                                                                         boomlet_last_seen_block_i[self],
                                                                                                                                                                                                         boomlet_ping_seq_num_i'[self],
                                                                                                                                                                                                         boomlet_reached_mystery_flag_i[self],
                                                                                                                                                                                                         boomlet_duress_placeholder_cipher_i'[self]))) })
                                                                                                                                                                               /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                                                                                               boomlet_saved_psbt_i, 
                                                                                                                                                                                               boomlet_committed_tx_id_i, 
                                                                                                                                                                                               boomlet_pending_txid_nonce_i, 
                                                                                                                                                                                               boomlet_saved_duress_space_i, 
                                                                                                                                                                                               boomlet_pending_duress_nonce_i, 
                                                                                                                                                                                               boomlet_signed_commit_inner_i, 
                                                                                                                                                                                               boomlet_commit_collection_i, 
                                                                                                                                                                                               boomlet_counter_i, 
                                                                                                                                                                                               boomlet_last_seen_block_i, 
                                                                                                                                                                                               boomlet_reached_mystery_flag_i, 
                                                                                                                                                                                               boomlet_known_reached_i, 
                                                                                                                                                                                               boomlet_prev_pings_i, 
                                                                                                                                                                                               boomlet_ready_to_sign_i, 
                                                                                                                                                                                               hydrated >>
                                                                                                                                                                          ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage8"
                                                                                                                                                                                     THEN /\ hydrated' = [hydrated EXCEPT ![self] = msg_B'[self].hydrated_psbt]
                                                                                                                                                                                          /\ Assert(   \A j \in Peers :
                                                                                                                                                                                                    ReachedPingSigValid(msg_B'[self].reached_pings_collection.items[j], j, boomlet_committed_tx_id_i[self]), 
                                                                                                                                                                                                    "Failure of assertion at line 1993, column 13.")
                                                                                                                                                                                          /\ Assert(hydrated'[self].tx_id = boomlet_committed_tx_id_i[self], 
                                                                                                                                                                                                    "Failure of assertion at line 1995, column 13.")
                                                                                                                                                                                          /\ boomlet_saved_psbt_i' = [boomlet_saved_psbt_i EXCEPT ![self] = hydrated'[self]]
                                                                                                                                                                                          /\ boomlet_ready_to_sign_i' = [boomlet_ready_to_sign_i EXCEPT ![self] = TRUE]
                                                                                                                                                                                          /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                                                                                    "Failure of assertion at line 1998, column 13.")
                                                                                                                                                                                          /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = WithdrawalBoomletNisoMessage8]
                                                                                                                                                                                          /\ wire_trace' = (wire_trace \cup { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage8) })
                                                                                                                                                                                          /\ UNCHANGED << boomlet_mystery_i, 
                                                                                                                                                                                                          boomlet_committed_tx_id_i, 
                                                                                                                                                                                                          boomlet_pending_txid_nonce_i, 
                                                                                                                                                                                                          boomlet_saved_duress_space_i, 
                                                                                                                                                                                                          boomlet_pending_duress_nonce_i, 
                                                                                                                                                                                                          boomlet_duress_placeholder_plaintext_i, 
                                                                                                                                                                                                          boomlet_duress_placeholder_cipher_i, 
                                                                                                                                                                                                          boomlet_signed_commit_inner_i, 
                                                                                                                                                                                                          boomlet_commit_collection_i, 
                                                                                                                                                                                                          boomlet_counter_i, 
                                                                                                                                                                                                          boomlet_last_seen_block_i, 
                                                                                                                                                                                                          boomlet_ping_seq_num_i, 
                                                                                                                                                                                                          boomlet_reached_mystery_flag_i, 
                                                                                                                                                                                                          boomlet_known_reached_i, 
                                                                                                                                                                                                          boomlet_prev_pings_i >>
                                                                                                                                                                                     ELSE /\ IF msg_B'[self].kind = "WithdrawalNisoBoomletMessage9"
                                                                                                                                                                                                THEN /\ Assert(boomlet_signed_psbt_i[self] # NoValue, 
                                                                                                                                                                                                               "Failure of assertion at line 2002, column 13.")
                                                                                                                                                                                                     /\ Assert(boomlet_to_niso[self] = NoValue, 
                                                                                                                                                                                                               "Failure of assertion at line 2003, column 13.")
                                                                                                                                                                                                     /\ boomlet_to_niso' = [boomlet_to_niso EXCEPT ![self] = WithdrawalBoomletNisoMessage9(boomlet_signed_psbt_i[self])]
                                                                                                                                                                                                     /\ wire_trace' = (wire_trace \cup { WireHop(BoomletActor(self), NisoActor(self), WithdrawalBoomletNisoMessage9(boomlet_signed_psbt_i[self])) })
                                                                                                                                                                                                     /\ boomlet_saved_psbt_i' = [boomlet_saved_psbt_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_committed_tx_id_i' = [boomlet_committed_tx_id_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_pending_txid_nonce_i' = [boomlet_pending_txid_nonce_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_saved_duress_space_i' = [boomlet_saved_duress_space_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_pending_duress_nonce_i' = [boomlet_pending_duress_nonce_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_duress_placeholder_plaintext_i' = [boomlet_duress_placeholder_plaintext_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_duress_placeholder_cipher_i' = [boomlet_duress_placeholder_cipher_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_signed_commit_inner_i' = [boomlet_signed_commit_inner_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_commit_collection_i' = [boomlet_commit_collection_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_counter_i' = [boomlet_counter_i EXCEPT ![self] = 0]
                                                                                                                                                                                                     /\ boomlet_last_seen_block_i' = [boomlet_last_seen_block_i EXCEPT ![self] = Milestone0]
                                                                                                                                                                                                     /\ boomlet_ping_seq_num_i' = [boomlet_ping_seq_num_i EXCEPT ![self] = 0]
                                                                                                                                                                                                     /\ boomlet_reached_mystery_flag_i' = [boomlet_reached_mystery_flag_i EXCEPT ![self] = FALSE]
                                                                                                                                                                                                     /\ boomlet_known_reached_i' = [boomlet_known_reached_i EXCEPT ![self] = {}]
                                                                                                                                                                                                     /\ boomlet_prev_pings_i' = [boomlet_prev_pings_i EXCEPT ![self] = NoValue]
                                                                                                                                                                                                     /\ boomlet_ready_to_sign_i' = [boomlet_ready_to_sign_i EXCEPT ![self] = FALSE]
                                                                                                                                                                                                     /\ \E fresh \in {m \in Nat : m > 0 /\ m # boomlet_mystery_i[self]}:
                                                                                                                                                                                                          boomlet_mystery_i' = [boomlet_mystery_i EXCEPT ![self] = fresh]
                                                                                                                                                                                                ELSE /\ TRUE
                                                                                                                                                                                                     /\ UNCHANGED << wire_trace, 
                                                                                                                                                                                                                     boomlet_mystery_i, 
                                                                                                                                                                                                                     boomlet_saved_psbt_i, 
                                                                                                                                                                                                                     boomlet_committed_tx_id_i, 
                                                                                                                                                                                                                     boomlet_pending_txid_nonce_i, 
                                                                                                                                                                                                                     boomlet_saved_duress_space_i, 
                                                                                                                                                                                                                     boomlet_pending_duress_nonce_i, 
                                                                                                                                                                                                                     boomlet_duress_placeholder_plaintext_i, 
                                                                                                                                                                                                                     boomlet_duress_placeholder_cipher_i, 
                                                                                                                                                                                                                     boomlet_signed_commit_inner_i, 
                                                                                                                                                                                                                     boomlet_commit_collection_i, 
                                                                                                                                                                                                                     boomlet_counter_i, 
                                                                                                                                                                                                                     boomlet_last_seen_block_i, 
                                                                                                                                                                                                                     boomlet_ping_seq_num_i, 
                                                                                                                                                                                                                     boomlet_reached_mystery_flag_i, 
                                                                                                                                                                                                                     boomlet_known_reached_i, 
                                                                                                                                                                                                                     boomlet_prev_pings_i, 
                                                                                                                                                                                                                     boomlet_ready_to_sign_i, 
                                                                                                                                                                                                                     boomlet_to_niso >>
                                                                                                                                                                                          /\ UNCHANGED hydrated
                                                                                                                                                                               /\ UNCHANGED duressSignal
                                                                                                                                                                    /\ UNCHANGED << boomlet_saved_duress_stage_i, 
                                                                                                                                                                                    boomlet_saved_duress_seq_i, 
                                                                                                                                                                                    signedPong, 
                                                                                                                                                                                    prevPings >>
                                                                                                                                   /\ UNCHANGED boomlet_approvals_bundle_i
                                                                                                             /\ UNCHANGED boomlet_all_peer_approvals_i
                                                                                                  /\ UNCHANGED boomlet_saved_wt_tx_approval_i
                                                                                       /\ UNCHANGED boomlet_signed_tx_approval_i
                                /\ UNCHANGED << boomlet_signed_psbt_i, 
                                                boomlet_pubnonce_boom_i, 
                                                boomlet_partialsig_boom_i, 
                                                boomlet_to_iso, iso_to_boomlet >>
                           ELSE /\ msg_B' = [msg_B EXCEPT ![self] = iso_to_boomlet[self]]
                                /\ iso_to_boomlet' = [iso_to_boomlet EXCEPT ![self] = NoValue]
                                /\ IF msg_B'[self].kind = "WithdrawalIsoBoomletMessage1"
                                      THEN /\ boomlet_pubnonce_boom_i' = [boomlet_pubnonce_boom_i EXCEPT ![self] = PubnonceBoom(self, TxOfPsbt[BasePsbtOf(boomlet_saved_psbt_i[self])])]
                                           /\ Assert(boomlet_to_iso[self] = NoValue, 
                                                     "Failure of assertion at line 2031, column 13.")
                                           /\ boomlet_to_iso' = [boomlet_to_iso EXCEPT ![self] =                     WithdrawalBoomletIsoMessage1(
                                                                                                 boomlet_saved_psbt_i[self],
                                                                                                 boomerang_descriptor,
                                                                                                 [kind |-> "BoomPubkeyShare", peer |-> self],
                                                                                                 boomlet_pubnonce_boom_i'[self])]
                                           /\ wire_trace' = (          wire_trace \cup
                                                             { WireHop(BoomletActor(self), IsoActor(self), WithdrawalBoomletIsoMessage1(
                                                                 boomlet_saved_psbt_i[self],
                                                                 boomerang_descriptor,
                                                                 [kind |-> "BoomPubkeyShare", peer |-> self],
                                                                 boomlet_pubnonce_boom_i'[self])) })
                                           /\ UNCHANGED << boomlet_signed_psbt_i, 
                                                           boomlet_partialsig_boom_i >>
                                      ELSE /\ Assert(msg_B'[self].kind = "WithdrawalIsoBoomletMessage2", 
                                                     "Failure of assertion at line 2044, column 13.")
                                           /\ boomlet_partialsig_boom_i' = [boomlet_partialsig_boom_i EXCEPT ![self] = PartialSigBoom(self, TxOfPsbt[BasePsbtOf(boomlet_saved_psbt_i[self])])]
                                           /\ boomlet_signed_psbt_i' = [boomlet_signed_psbt_i EXCEPT ![self] = PsbtSigned(self, TxOfPsbt[BasePsbtOf(boomlet_saved_psbt_i[self])], boomlet_saved_psbt_i[self])]
                                           /\ Assert(boomlet_to_iso[self] = NoValue, 
                                                     "Failure of assertion at line 2047, column 13.")
                                           /\ boomlet_to_iso' = [boomlet_to_iso EXCEPT ![self] = WithdrawalBoomletIsoMessage2(boomlet_partialsig_boom_i'[self])]
                                           /\ wire_trace' = (wire_trace \cup { WireHop(BoomletActor(self), IsoActor(self), WithdrawalBoomletIsoMessage2(boomlet_partialsig_boom_i'[self])) })
                                           /\ UNCHANGED boomlet_pubnonce_boom_i
                                /\ UNCHANGED << boomlet_mystery_i, 
                                                boomlet_saved_psbt_i, 
                                                boomlet_committed_tx_id_i, 
                                                boomlet_pending_txid_nonce_i, 
                                                boomlet_saved_duress_space_i, 
                                                boomlet_saved_duress_stage_i, 
                                                boomlet_saved_duress_seq_i, 
                                                boomlet_pending_duress_nonce_i, 
                                                boomlet_duress_placeholder_plaintext_i, 
                                                boomlet_duress_placeholder_cipher_i, 
                                                boomlet_signed_tx_approval_i, 
                                                boomlet_saved_wt_tx_approval_i, 
                                                boomlet_all_peer_approvals_i, 
                                                boomlet_approvals_bundle_i, 
                                                boomlet_signed_commit_inner_i, 
                                                boomlet_commit_collection_i, 
                                                boomlet_counter_i, 
                                                boomlet_last_seen_block_i, 
                                                boomlet_ping_seq_num_i, 
                                                boomlet_reached_mystery_flag_i, 
                                                boomlet_known_reached_i, 
                                                boomlet_prev_pings_i, 
                                                boomlet_ready_to_sign_i, 
                                                boomlet_to_niso, 
                                                niso_to_boomlet, duressSignal, 
                                                hydrated, signedPong, 
                                                prevPings >>
                     /\ pc' = [pc EXCEPT ![self] = "BoomletLoop"]
                     /\ UNCHANGED << boomerang_descriptor, peer_id_collection, 
                                     st_identity_pubkey_i, sar_pubkey_i, 
                                     doxing_key_i, duress_consent_set_i, 
                                     most_work_bitcoin_block_height, 
                                     user_saved_psbt_i, 
                                     user_initiator_peer_id_i, 
                                     user_last_duress_space_i, 
                                     user_sent_initial_psbt_i, 
                                     user_sent_psbt_agreement_i, 
                                     user_sent_iso_credentials_i, 
                                     user_sent_connect_back_to_niso_i, 
                                     niso_saved_psbt_i, niso_saved_tx_id_i, 
                                     niso_event_block_height_i, 
                                     niso_initiator_peer_id_i, 
                                     niso_saved_wt_tx_approval_i, 
                                     niso_hydrated_psbt_i, 
                                     niso_reached_pings_collection_i, 
                                     st_last_txid_with_nonce_i, 
                                     st_last_duress_check_i, 
                                     iso_pubnonce_normal_i, 
                                     iso_partialsig_normal_i, 
                                     iso_signed_psbt_i, 
                                     sar_seen_placeholder_iv_i, 
                                     sar_escalated_i, 
                                     sar_last_doxing_identifier_i, 
                                     wt_saved_tx_id, wt_saved_wt_tx_approval, 
                                     wt_initiator_tx_approval, 
                                     wt_noninitiator_tx_approval_i, 
                                     wt_approvals_bundle_i, 
                                     wt_pending_sar_stage_i, 
                                     wt_pending_placeholder_i, 
                                     wt_pending_signed_inner_i, 
                                     wt_commit_sar_reply_i, 
                                     wt_ping_sar_reply_i, wt_signed_commit_i, 
                                     wt_last_accepted_ping_i, 
                                     wt_reached_pings_collection, 
                                     wt_last_pong_height, 
                                     wt_relayed_all_approvals, 
                                     wt_relayed_all_commits, wt_signed_psbt_i, 
                                     wt_broadcast, user_to_niso, niso_to_user, 
                                     user_to_st, st_to_user, niso_to_st, 
                                     st_to_niso, user_to_iso, iso_to_user, 
                                     niso_to_wt, wt_to_niso, wt_to_sar, 
                                     sar_to_wt, msg_, signalIndex_, msg_S, 
                                     nonceWrapped, signalIndex, msg_N, 
                                     approvalSig, wtSig, commitSig, signedPing, 
                                     signedAck, msg_I, msg_SA, plaintext, 
                                     reply, msg, peer, decrypted, signedInner, 
                                     placeholder, wtHeight, pongMap >>

BoomletFlow(self) == BoomletLoop(self)

IsoLoop(self) == /\ pc[self] = "IsoLoop"
                 /\ user_to_iso[self] # NoValue \/ boomlet_to_iso[self] # NoValue
                 /\ IF user_to_iso[self] # NoValue
                       THEN /\ msg_I' = [msg_I EXCEPT ![self] = user_to_iso[self]]
                            /\ user_to_iso' = [user_to_iso EXCEPT ![self] = NoValue]
                            /\ IF msg_I'[self].kind = "WithdrawalIsoInput1"
                                  THEN /\ Assert(iso_to_boomlet[self] = NoValue, 
                                                 "Failure of assertion at line 2064, column 13.")
                                       /\ iso_to_boomlet' = [iso_to_boomlet EXCEPT ![self] = WithdrawalIsoBoomletMessage1]
                                       /\ wire_trace' = (wire_trace \cup { WireHop(IsoActor(self), BoomletActor(self), WithdrawalIsoBoomletMessage1) })
                                  ELSE /\ TRUE
                                       /\ UNCHANGED << wire_trace, 
                                                       iso_to_boomlet >>
                            /\ UNCHANGED << iso_pubnonce_normal_i, 
                                            iso_partialsig_normal_i, 
                                            iso_signed_psbt_i, iso_to_user, 
                                            boomlet_to_iso >>
                       ELSE /\ msg_I' = [msg_I EXCEPT ![self] = boomlet_to_iso[self]]
                            /\ boomlet_to_iso' = [boomlet_to_iso EXCEPT ![self] = NoValue]
                            /\ IF msg_I'[self].kind = "WithdrawalBoomletIsoMessage1"
                                  THEN /\ iso_pubnonce_normal_i' = [iso_pubnonce_normal_i EXCEPT ![self] = PubnonceNormal(self, TxOfPsbt[BasePsbtOf(msg_I'[self].psbt)])]
                                       /\ iso_partialsig_normal_i' = [iso_partialsig_normal_i EXCEPT ![self] = PartialSigNormal(self, TxOfPsbt[BasePsbtOf(msg_I'[self].psbt)])]
                                       /\ Assert(iso_to_boomlet[self] = NoValue, 
                                                 "Failure of assertion at line 2074, column 13.")
                                       /\ iso_to_boomlet' = [iso_to_boomlet EXCEPT ![self] = WithdrawalIsoBoomletMessage2(iso_pubnonce_normal_i'[self], iso_partialsig_normal_i'[self])]
                                       /\ wire_trace' = (          wire_trace \cup
                                                         { WireHop(IsoActor(self), BoomletActor(self), WithdrawalIsoBoomletMessage2(iso_pubnonce_normal_i'[self], iso_partialsig_normal_i'[self])) })
                                       /\ UNCHANGED << iso_signed_psbt_i, 
                                                       iso_to_user >>
                                  ELSE /\ Assert(msg_I'[self].kind = "WithdrawalBoomletIsoMessage2", 
                                                 "Failure of assertion at line 2079, column 13.")
                                       /\ iso_signed_psbt_i' = [iso_signed_psbt_i EXCEPT ![self] = PsbtSigned(self, msg_I'[self].partialsig_boom.tx_id, boomlet_saved_psbt_i[self])]
                                       /\ Assert(iso_to_user[self] = NoValue, 
                                                 "Failure of assertion at line 2081, column 13.")
                                       /\ iso_to_user' = [iso_to_user EXCEPT ![self] = WithdrawalIsoOutput1]
                                       /\ wire_trace' = (wire_trace \cup { WireHop(IsoActor(self), UserActor(self), WithdrawalIsoOutput1) })
                                       /\ UNCHANGED << iso_pubnonce_normal_i, 
                                                       iso_partialsig_normal_i, 
                                                       iso_to_boomlet >>
                            /\ UNCHANGED user_to_iso
                 /\ pc' = [pc EXCEPT ![self] = "IsoLoop"]
                 /\ UNCHANGED << boomerang_descriptor, peer_id_collection, 
                                 st_identity_pubkey_i, sar_pubkey_i, 
                                 doxing_key_i, duress_consent_set_i, 
                                 boomlet_mystery_i, 
                                 most_work_bitcoin_block_height, 
                                 user_saved_psbt_i, user_initiator_peer_id_i, 
                                 user_last_duress_space_i, 
                                 user_sent_initial_psbt_i, 
                                 user_sent_psbt_agreement_i, 
                                 user_sent_iso_credentials_i, 
                                 user_sent_connect_back_to_niso_i, 
                                 niso_saved_psbt_i, niso_saved_tx_id_i, 
                                 niso_event_block_height_i, 
                                 niso_initiator_peer_id_i, 
                                 niso_saved_wt_tx_approval_i, 
                                 niso_hydrated_psbt_i, 
                                 niso_reached_pings_collection_i, 
                                 boomlet_saved_psbt_i, 
                                 boomlet_committed_tx_id_i, 
                                 boomlet_pending_txid_nonce_i, 
                                 boomlet_saved_duress_space_i, 
                                 boomlet_saved_duress_stage_i, 
                                 boomlet_saved_duress_seq_i, 
                                 boomlet_pending_duress_nonce_i, 
                                 boomlet_duress_placeholder_plaintext_i, 
                                 boomlet_duress_placeholder_cipher_i, 
                                 boomlet_signed_tx_approval_i, 
                                 boomlet_saved_wt_tx_approval_i, 
                                 boomlet_all_peer_approvals_i, 
                                 boomlet_approvals_bundle_i, 
                                 boomlet_signed_commit_inner_i, 
                                 boomlet_commit_collection_i, 
                                 boomlet_counter_i, boomlet_last_seen_block_i, 
                                 boomlet_ping_seq_num_i, 
                                 boomlet_reached_mystery_flag_i, 
                                 boomlet_known_reached_i, boomlet_prev_pings_i, 
                                 boomlet_ready_to_sign_i, 
                                 boomlet_signed_psbt_i, 
                                 boomlet_pubnonce_boom_i, 
                                 boomlet_partialsig_boom_i, 
                                 st_last_txid_with_nonce_i, 
                                 st_last_duress_check_i, 
                                 sar_seen_placeholder_iv_i, sar_escalated_i, 
                                 sar_last_doxing_identifier_i, wt_saved_tx_id, 
                                 wt_saved_wt_tx_approval, 
                                 wt_initiator_tx_approval, 
                                 wt_noninitiator_tx_approval_i, 
                                 wt_approvals_bundle_i, wt_pending_sar_stage_i, 
                                 wt_pending_placeholder_i, 
                                 wt_pending_signed_inner_i, 
                                 wt_commit_sar_reply_i, wt_ping_sar_reply_i, 
                                 wt_signed_commit_i, wt_last_accepted_ping_i, 
                                 wt_reached_pings_collection, 
                                 wt_last_pong_height, wt_relayed_all_approvals, 
                                 wt_relayed_all_commits, wt_signed_psbt_i, 
                                 wt_broadcast, user_to_niso, niso_to_user, 
                                 user_to_st, st_to_user, boomlet_to_niso, 
                                 niso_to_boomlet, niso_to_st, st_to_niso, 
                                 niso_to_wt, wt_to_niso, wt_to_sar, sar_to_wt, 
                                 msg_, signalIndex_, msg_S, nonceWrapped, 
                                 signalIndex, msg_N, approvalSig, wtSig, 
                                 commitSig, signedPing, msg_B, signedAck, 
                                 duressSignal, hydrated, signedPong, prevPings, 
                                 msg_SA, plaintext, reply, msg, peer, 
                                 decrypted, signedInner, placeholder, wtHeight, 
                                 pongMap >>

IsoFlow(self) == IsoLoop(self)

SARLoop(self) == /\ pc[self] = "SARLoop"
                 /\ wt_to_sar[self] # NoValue
                 /\ msg_SA' = [msg_SA EXCEPT ![self] = wt_to_sar[self]]
                 /\ wt_to_sar' = [wt_to_sar EXCEPT ![self] = NoValue]
                 /\ plaintext' = [plaintext EXCEPT ![self] = Decrypt(msg_SA'[self].duress_placeholder, SARActor(self))]
                 /\ Assert(plaintext'[self] # NoValue, 
                           "Failure of assertion at line 2099, column 5.")
                 /\ IF /\ ~IsSafePaddingPlaintextForPeer(self, plaintext'[self])
                       /\ <<BoomletActor(self), msg_SA'[self].duress_placeholder.iv>> \notin sar_seen_placeholder_iv_i[self]
                       THEN /\ sar_escalated_i' = [sar_escalated_i EXCEPT ![self] = TRUE]
                            /\ sar_last_doxing_identifier_i' = [sar_last_doxing_identifier_i EXCEPT ![self] = DoxingDataIdentifier(plaintext'[self])]
                            /\ sar_seen_placeholder_iv_i' = [sar_seen_placeholder_iv_i EXCEPT ![self] = sar_seen_placeholder_iv_i[self] \cup { <<BoomletActor(self), msg_SA'[self].duress_placeholder.iv>> }]
                       ELSE /\ TRUE
                            /\ UNCHANGED << sar_seen_placeholder_iv_i, 
                                            sar_escalated_i, 
                                            sar_last_doxing_identifier_i >>
                 /\ reply' = [reply EXCEPT ![self] = SARReplyCipher(self, msg_SA'[self].duress_placeholder)]
                 /\ Assert(sar_to_wt[self] = NoValue, 
                           "Failure of assertion at line 2108, column 5.")
                 /\ IF msg_SA'[self].kind = "WithdrawalWtSarsMessage2"
                       THEN /\ sar_to_wt' = [sar_to_wt EXCEPT ![self] = WithdrawalSarsWtMessage2(reply'[self])]
                            /\ wire_trace' = (wire_trace \cup { WireHop(SARActor(self), WTActor, WithdrawalSarsWtMessage2(reply'[self])) })
                       ELSE /\ IF msg_SA'[self].kind = "WithdrawalWtSarsMessage1"
                                  THEN /\ sar_to_wt' = [sar_to_wt EXCEPT ![self] = WithdrawalSarsWtMessage1(reply'[self])]
                                       /\ wire_trace' = (wire_trace \cup { WireHop(SARActor(self), WTActor, WithdrawalSarsWtMessage1(reply'[self])) })
                                  ELSE /\ sar_to_wt' = [sar_to_wt EXCEPT ![self] = WithdrawalNonInitiatorSarsWtMessage1(reply'[self])]
                                       /\ wire_trace' = (wire_trace \cup { WireHop(SARActor(self), WTActor, WithdrawalNonInitiatorSarsWtMessage1(reply'[self])) })
                 /\ pc' = [pc EXCEPT ![self] = "SARLoop"]
                 /\ UNCHANGED << boomerang_descriptor, peer_id_collection, 
                                 st_identity_pubkey_i, sar_pubkey_i, 
                                 doxing_key_i, duress_consent_set_i, 
                                 boomlet_mystery_i, 
                                 most_work_bitcoin_block_height, 
                                 user_saved_psbt_i, user_initiator_peer_id_i, 
                                 user_last_duress_space_i, 
                                 user_sent_initial_psbt_i, 
                                 user_sent_psbt_agreement_i, 
                                 user_sent_iso_credentials_i, 
                                 user_sent_connect_back_to_niso_i, 
                                 niso_saved_psbt_i, niso_saved_tx_id_i, 
                                 niso_event_block_height_i, 
                                 niso_initiator_peer_id_i, 
                                 niso_saved_wt_tx_approval_i, 
                                 niso_hydrated_psbt_i, 
                                 niso_reached_pings_collection_i, 
                                 boomlet_saved_psbt_i, 
                                 boomlet_committed_tx_id_i, 
                                 boomlet_pending_txid_nonce_i, 
                                 boomlet_saved_duress_space_i, 
                                 boomlet_saved_duress_stage_i, 
                                 boomlet_saved_duress_seq_i, 
                                 boomlet_pending_duress_nonce_i, 
                                 boomlet_duress_placeholder_plaintext_i, 
                                 boomlet_duress_placeholder_cipher_i, 
                                 boomlet_signed_tx_approval_i, 
                                 boomlet_saved_wt_tx_approval_i, 
                                 boomlet_all_peer_approvals_i, 
                                 boomlet_approvals_bundle_i, 
                                 boomlet_signed_commit_inner_i, 
                                 boomlet_commit_collection_i, 
                                 boomlet_counter_i, boomlet_last_seen_block_i, 
                                 boomlet_ping_seq_num_i, 
                                 boomlet_reached_mystery_flag_i, 
                                 boomlet_known_reached_i, boomlet_prev_pings_i, 
                                 boomlet_ready_to_sign_i, 
                                 boomlet_signed_psbt_i, 
                                 boomlet_pubnonce_boom_i, 
                                 boomlet_partialsig_boom_i, 
                                 st_last_txid_with_nonce_i, 
                                 st_last_duress_check_i, iso_pubnonce_normal_i, 
                                 iso_partialsig_normal_i, iso_signed_psbt_i, 
                                 wt_saved_tx_id, wt_saved_wt_tx_approval, 
                                 wt_initiator_tx_approval, 
                                 wt_noninitiator_tx_approval_i, 
                                 wt_approvals_bundle_i, wt_pending_sar_stage_i, 
                                 wt_pending_placeholder_i, 
                                 wt_pending_signed_inner_i, 
                                 wt_commit_sar_reply_i, wt_ping_sar_reply_i, 
                                 wt_signed_commit_i, wt_last_accepted_ping_i, 
                                 wt_reached_pings_collection, 
                                 wt_last_pong_height, wt_relayed_all_approvals, 
                                 wt_relayed_all_commits, wt_signed_psbt_i, 
                                 wt_broadcast, user_to_niso, niso_to_user, 
                                 user_to_st, st_to_user, boomlet_to_niso, 
                                 niso_to_boomlet, niso_to_st, st_to_niso, 
                                 user_to_iso, iso_to_user, boomlet_to_iso, 
                                 iso_to_boomlet, niso_to_wt, wt_to_niso, msg_, 
                                 signalIndex_, msg_S, nonceWrapped, 
                                 signalIndex, msg_N, approvalSig, wtSig, 
                                 commitSig, signedPing, msg_B, signedAck, 
                                 duressSignal, hydrated, signedPong, prevPings, 
                                 msg_I, msg, peer, decrypted, signedInner, 
                                 placeholder, wtHeight, pongMap >>

SARFlow(self) == SARLoop(self)

WTLoop == /\ pc[WT_ID] = "WTLoop"
          /\    (\E i \in Peers : niso_to_wt[i] # NoValue)
             \/ (\E i \in Peers : sar_to_wt[i] # NoValue)
             \/ ( /\ ~wt_relayed_all_approvals
                  /\ \A j \in NonInitiators : wt_noninitiator_tx_approval_i[j] # NoValue
                  /\ \A j \in Peers : wt_to_niso[j] = NoValue
                  /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                  /\ \A j \in NonInitiators :
                       /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height >=
                          Max2(
                              SignedContent(wt_saved_wt_tx_approval).event_block_height,
                              IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                              THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                              ELSE 0)
                       /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height <=
                          most_work_bitcoin_block_height
                              - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                  /\ SignedContent(wt_initiator_tx_approval).event_block_height >=
                     Max2(
                          IF SignedContent(wt_saved_wt_tx_approval).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                          THEN SignedContent(wt_saved_wt_tx_approval).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                          ELSE 0,
                          IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                          THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                          ELSE 0)
                  /\ SignedContent(wt_initiator_tx_approval).event_block_height <= SignedContent(wt_saved_wt_tx_approval).event_block_height )
             \/ ( /\ ~wt_relayed_all_commits
                  /\ \A j \in Peers : wt_signed_commit_i[j] # NoValue /\ wt_commit_sar_reply_i[j] # NoValue
                  /\ \A j \in Peers : wt_to_niso[j] = NoValue
                  /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS
                  /\ \A j \in Peers :
                       /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height >=
                          IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                          THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                          ELSE 0
                       /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height <=
                          most_work_bitcoin_block_height
                              - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS )
          /\ IF /\ ~wt_relayed_all_approvals
                /\ \A j \in NonInitiators : wt_noninitiator_tx_approval_i[j] # NoValue
                /\ \A j \in Peers : wt_to_niso[j] = NoValue
                /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                /\ \A j \in NonInitiators :
                     /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height >=
                        Max2(
                             SignedContent(wt_saved_wt_tx_approval).event_block_height,
                             IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                             THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_NON_INITIATOR_PEERS_TO_RECEIVING_NON_INITIATOR_TX_APPROVAL_BY_INITIATOR_PEER
                             ELSE 0)
                     /\ SignedContent(wt_noninitiator_tx_approval_i[j]).event_block_height <=
                        most_work_bitcoin_block_height
                            - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_INITIATOR_PEER_TX_APPROVAL_AND_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                /\ SignedContent(wt_initiator_tx_approval).event_block_height >=
                   Max2(
                         IF SignedContent(wt_saved_wt_tx_approval).event_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                         THEN SignedContent(wt_saved_wt_tx_approval).event_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_TX_APPROVAL_BY_WT
                         ELSE 0,
                         IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                         THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_APPROVAL_BY_INITIATOR_PEER_TO_RECEIVING_ALL_NON_INITIATOR_TX_APPROVALS_BY_INITIATOR_PEER
                         ELSE 0)
                /\ SignedContent(wt_initiator_tx_approval).event_block_height <= SignedContent(wt_saved_wt_tx_approval).event_block_height
                THEN /\ wt_to_niso' =           [j \in Peers |->
                                      IF j = INITIATOR
                                      THEN WithdrawalWtNisoMessage1([k \in Peers |->
                                              IF k = INITIATOR THEN wt_initiator_tx_approval ELSE wt_noninitiator_tx_approval_i[k]],
                                            wt_saved_wt_tx_approval)
                                      ELSE WithdrawalWtNonInitiatorNisoMessage2([k \in NonInitiators |-> wt_noninitiator_tx_approval_i[k]])]
                     /\ wt_relayed_all_approvals' = TRUE
                     /\ wire_trace' = (          wire_trace \cup
                                       { WireHop(WTActor, NisoActor(j),
                                           IF j = INITIATOR
                                           THEN WithdrawalWtNisoMessage1([k \in Peers |->
                                                   IF k = INITIATOR THEN wt_initiator_tx_approval ELSE wt_noninitiator_tx_approval_i[k]],
                                                 wt_saved_wt_tx_approval)
                                           ELSE WithdrawalWtNonInitiatorNisoMessage2([k \in NonInitiators |-> wt_noninitiator_tx_approval_i[k]])) : j \in Peers })
                     /\ UNCHANGED << wt_saved_tx_id, wt_saved_wt_tx_approval, 
                                     wt_initiator_tx_approval, 
                                     wt_noninitiator_tx_approval_i, 
                                     wt_approvals_bundle_i, 
                                     wt_pending_sar_stage_i, 
                                     wt_pending_placeholder_i, 
                                     wt_pending_signed_inner_i, 
                                     wt_commit_sar_reply_i, 
                                     wt_ping_sar_reply_i, wt_signed_commit_i, 
                                     wt_last_accepted_ping_i, 
                                     wt_reached_pings_collection, 
                                     wt_last_pong_height, 
                                     wt_relayed_all_commits, wt_signed_psbt_i, 
                                     wt_broadcast, niso_to_wt, wt_to_sar, 
                                     sar_to_wt, msg, peer, decrypted, 
                                     signedInner, placeholder, wtHeight >>
                ELSE /\ IF /\ ~wt_relayed_all_commits
                           /\ \A j \in Peers : wt_signed_commit_i[j] # NoValue /\ wt_commit_sar_reply_i[j] # NoValue
                           /\ \A j \in Peers : wt_to_niso[j] = NoValue
                           /\ most_work_bitcoin_block_height >= REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS
                           /\ \A j \in Peers :
                                /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height >=
                                   IF most_work_bitcoin_block_height >= TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                                   THEN most_work_bitcoin_block_height - TOLERANCE_IN_BLOCKS_FROM_TX_COMMITMENT_BY_INITIATOR_AND_NON_INITIATOR_PEERS_TO_RECEIVING_TX_COMMITMENT_BY_ALL_PEERS
                                   ELSE 0
                                /\ SignedContent(SignedContent(wt_signed_commit_i[j])).event_block_height <=
                                   most_work_bitcoin_block_height
                                       - REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PEER_TX_COMMITMENT_AND_RECEIVING_ALL_TX_COMMITMENT_BY_PEERS
                           THEN /\ wt_to_niso' =           [j \in Peers |->
                                                 IF j = INITIATOR
                                                 THEN WithdrawalWtNisoMessage2(wt_signed_commit_i, wt_commit_sar_reply_i[j])
                                                 ELSE WithdrawalWtNonInitiatorNisoMessage4(wt_signed_commit_i, wt_commit_sar_reply_i[j])]
                                /\ wt_relayed_all_commits' = TRUE
                                /\ wire_trace' = (          wire_trace \cup
                                                  { WireHop(WTActor, NisoActor(j),
                                                      IF j = INITIATOR
                                                      THEN WithdrawalWtNisoMessage2(wt_signed_commit_i, wt_commit_sar_reply_i[j])
                                                      ELSE WithdrawalWtNonInitiatorNisoMessage4(wt_signed_commit_i, wt_commit_sar_reply_i[j])) : j \in Peers })
                                /\ UNCHANGED << wt_saved_tx_id, 
                                                wt_saved_wt_tx_approval, 
                                                wt_initiator_tx_approval, 
                                                wt_noninitiator_tx_approval_i, 
                                                wt_approvals_bundle_i, 
                                                wt_pending_sar_stage_i, 
                                                wt_pending_placeholder_i, 
                                                wt_pending_signed_inner_i, 
                                                wt_commit_sar_reply_i, 
                                                wt_ping_sar_reply_i, 
                                                wt_signed_commit_i, 
                                                wt_last_accepted_ping_i, 
                                                wt_reached_pings_collection, 
                                                wt_last_pong_height, 
                                                wt_signed_psbt_i, wt_broadcast, 
                                                niso_to_wt, wt_to_sar, 
                                                sar_to_wt, msg, peer, 
                                                decrypted, signedInner, 
                                                placeholder, wtHeight >>
                           ELSE /\ IF \E i \in Peers : sar_to_wt[i] # NoValue
                                      THEN /\ \E i \in { j \in Peers : sar_to_wt[j] # NoValue }:
                                                /\ peer' = i
                                                /\ msg' = sar_to_wt[peer']
                                                /\ sar_to_wt' = [sar_to_wt EXCEPT ![peer'] = NoValue]
                                                /\ IF wt_pending_sar_stage_i[peer'] = "commit"
                                                      THEN /\ Assert(SARReplyValidForPeer(peer', wt_pending_placeholder_i[peer'], msg'.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet), 
                                                                     "Failure of assertion at line 2236, column 17.")
                                                           /\ wt_commit_sar_reply_i' = [wt_commit_sar_reply_i EXCEPT ![peer'] = msg'.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet]
                                                           /\ signedInner' = wt_pending_signed_inner_i[peer']
                                                           /\ wtHeight' = most_work_bitcoin_block_height
                                                           /\ Assert(   CommitSigValid(
                                                                     signedInner',
                                                                     peer',
                                                                     wt_saved_tx_id,
                                                                     0,
                                                                     wtHeight'), 
                                                                     "Failure of assertion at line 2240, column 17.")
                                                           /\ wt_signed_commit_i' = [wt_signed_commit_i EXCEPT ![peer'] = SignatureOnMessage(WTActor, signedInner')]
                                                           /\ IF peer' = INITIATOR
                                                                 THEN /\ Assert(\A j \in NonInitiators : wt_to_niso[j] = NoValue, 
                                                                                "Failure of assertion at line 2248, column 21.")
                                                                      /\ wt_to_niso' =           [j \in Peers |->
                                                                                       IF j \in NonInitiators
                                                                                       THEN WithdrawalWtNonInitiatorNisoMessage3(wt_signed_commit_i'[peer'])
                                                                                       ELSE wt_to_niso[j]]
                                                                      /\ wire_trace' = (          wire_trace \cup
                                                                                        { WireHop(WTActor, NisoActor(j), WithdrawalWtNonInitiatorNisoMessage3(wt_signed_commit_i'[peer'])) : j \in NonInitiators })
                                                                 ELSE /\ TRUE
                                                                      /\ UNCHANGED << wire_trace, 
                                                                                      wt_to_niso >>
                                                           /\ UNCHANGED << wt_ping_sar_reply_i, 
                                                                           wt_last_accepted_ping_i, 
                                                                           wt_reached_pings_collection, 
                                                                           wt_last_pong_height >>
                                                      ELSE /\ Assert(wt_pending_sar_stage_i[peer'] = "ping", 
                                                                     "Failure of assertion at line 2257, column 17.")
                                                           /\ Assert(SARReplyValidForPeer(peer', wt_pending_placeholder_i[peer'], msg'.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet), 
                                                                     "Failure of assertion at line 2258, column 17.")
                                                           /\ wt_ping_sar_reply_i' = [wt_ping_sar_reply_i EXCEPT ![peer'] = msg'.duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet]
                                                           /\ signedInner' = wt_pending_signed_inner_i[peer']
                                                           /\ wtHeight' = most_work_bitcoin_block_height
                                                           /\ Assert(   PingSigValid(
                                                                     signedInner',
                                                                     peer',
                                                                     wt_saved_tx_id,
                                                                     IF wtHeight' >= TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_TO_RECEIVING_ALL_PINGS_BY_WT_AND_HAVING_SAR_RESPONSE_BACK_TO_WT
                                                                     THEN wtHeight' - TOLERANCE_IN_BLOCKS_FROM_CREATING_PING_TO_RECEIVING_ALL_PINGS_BY_WT_AND_HAVING_SAR_RESPONSE_BACK_TO_WT
                                                                     ELSE 0,
                                                                     wtHeight'), 
                                                                     "Failure of assertion at line 2262, column 17.")
                                                           /\ IF wt_last_accepted_ping_i[peer'] = NoValue
                                                                 THEN /\ Assert(~SignedContent(signedInner').reached_mystery_flag, 
                                                                                "Failure of assertion at line 2271, column 21.")
                                                                 ELSE /\ Assert(SignedContent(signedInner').ping_seq_num > SignedContent(wt_last_accepted_ping_i[peer']).ping_seq_num, 
                                                                                "Failure of assertion at line 2273, column 21.")
                                                           /\ wt_last_accepted_ping_i' = [wt_last_accepted_ping_i EXCEPT ![peer'] = signedInner']
                                                           /\ IF SignedContent(signedInner').reached_mystery_flag
                                                                 THEN /\ wt_reached_pings_collection' = [wt_reached_pings_collection EXCEPT ![peer'] = signedInner']
                                                                 ELSE /\ TRUE
                                                                      /\ UNCHANGED wt_reached_pings_collection
                                                           /\ IF AllReached(wt_reached_pings_collection')
                                                                 THEN /\ Assert(\A j \in Peers : wt_to_niso[j] = NoValue, 
                                                                                "Failure of assertion at line 2280, column 21.")
                                                                      /\ wt_to_niso' = [j \in Peers |-> WithdrawalWtNisoMessage4(ReachedPingsCollection(wt_reached_pings_collection'))]
                                                                      /\ wire_trace' = (          wire_trace \cup
                                                                                        { WireHop(WTActor, NisoActor(j), WithdrawalWtNisoMessage4(ReachedPingsCollection(wt_reached_pings_collection'))) : j \in Peers })
                                                                      /\ UNCHANGED wt_last_pong_height
                                                                 ELSE /\ IF /\ \A j \in Peers : wt_last_accepted_ping_i'[j] # NoValue
                                                                            /\ (wt_last_pong_height = NoValue
                                                                                \/ most_work_bitcoin_block_height >= wt_last_pong_height + REQUIRED_MINIMUM_DISTANCE_IN_BLOCKS_BETWEEN_PING_AND_PONG)
                                                                            THEN /\ Assert(\A j \in Peers : wt_to_niso[j] = NoValue, 
                                                                                           "Failure of assertion at line 2288, column 21.")
                                                                                 /\ wt_last_pong_height' = most_work_bitcoin_block_height
                                                                                 /\ wt_to_niso' =           [j \in Peers |->
                                                                                                  WithdrawalWtNisoMessage3(
                                                                                                      PongCipherForPeer(j, wt_saved_tx_id, most_work_bitcoin_block_height, [k \in (Peers \ {j}) |-> wt_last_accepted_ping_i'[k]]),
                                                                                                      wt_ping_sar_reply_i'[j])]
                                                                                 /\ wire_trace' = (          wire_trace \cup
                                                                                                   { WireHop(WTActor, NisoActor(j),
                                                                                                       WithdrawalWtNisoMessage3(
                                                                                                           PongCipherForPeer(j, wt_saved_tx_id, most_work_bitcoin_block_height, [k \in (Peers \ {j}) |-> wt_last_accepted_ping_i'[k]]),
                                                                                                           wt_ping_sar_reply_i'[j])) : j \in Peers })
                                                                            ELSE /\ TRUE
                                                                                 /\ UNCHANGED << wire_trace, 
                                                                                                 wt_last_pong_height, 
                                                                                                 wt_to_niso >>
                                                           /\ UNCHANGED << wt_commit_sar_reply_i, 
                                                                           wt_signed_commit_i >>
                                                /\ wt_pending_sar_stage_i' = [wt_pending_sar_stage_i EXCEPT ![peer'] = NoValue]
                                                /\ wt_pending_placeholder_i' = [wt_pending_placeholder_i EXCEPT ![peer'] = NoValue]
                                                /\ wt_pending_signed_inner_i' = [wt_pending_signed_inner_i EXCEPT ![peer'] = NoValue]
                                           /\ UNCHANGED << wt_saved_tx_id, 
                                                           wt_saved_wt_tx_approval, 
                                                           wt_initiator_tx_approval, 
                                                           wt_noninitiator_tx_approval_i, 
                                                           wt_approvals_bundle_i, 
                                                           wt_signed_psbt_i, 
                                                           wt_broadcast, 
                                                           niso_to_wt, 
                                                           wt_to_sar, 
                                                           decrypted, 
                                                           placeholder >>
                                      ELSE /\ \E i \in { j \in Peers : niso_to_wt[j] # NoValue }:
                                                /\ peer' = i
                                                /\ msg' = niso_to_wt[peer']
                                                /\ niso_to_wt' = [niso_to_wt EXCEPT ![peer'] = NoValue]
                                                /\ IF msg'.kind = "WithdrawalNisoWtMessage1"
                                                      THEN /\ decrypted' = Decrypt(msg'.initiator_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, WTActor)
                                                           /\ Assert(   TxApprovalSigValid(
                                                                     decrypted',
                                                                     INITIATOR,
                                                                     SignedContent(decrypted').tx_id,
                                                                     0,
                                                                     most_work_bitcoin_block_height), 
                                                                     "Failure of assertion at line 2312, column 17.")
                                                           /\ wt_saved_tx_id' = SignedContent(decrypted').tx_id
                                                           /\ wt_initiator_tx_approval' = decrypted'
                                                           /\ wt_saved_wt_tx_approval' = SignedWTTxApproval(wt_saved_tx_id', most_work_bitcoin_block_height, INITIATOR)
                                                           /\ Assert(\A j \in NonInitiators : wt_to_niso[j] = NoValue, 
                                                                     "Failure of assertion at line 2321, column 17.")
                                                           /\ wt_to_niso' =           [j \in Peers |->
                                                                            IF j \in NonInitiators
                                                                            THEN WithdrawalWtNonInitiatorNisoMessage1(
                                                                                wt_saved_wt_tx_approval',
                                                                                wt_initiator_tx_approval',
                                                                                msg'.psbt_encrypted_collection.items[j])
                                                                            ELSE wt_to_niso[j]]
                                                           /\ wire_trace' = (          wire_trace \cup
                                                                             { WireHop(WTActor, NisoActor(j),
                                                                                 WithdrawalWtNonInitiatorNisoMessage1(
                                                                                     wt_saved_wt_tx_approval',
                                                                                     wt_initiator_tx_approval',
                                                                                     msg'.psbt_encrypted_collection.items[j])) : j \in NonInitiators })
                                                           /\ UNCHANGED << wt_noninitiator_tx_approval_i, 
                                                                           wt_approvals_bundle_i, 
                                                                           wt_pending_sar_stage_i, 
                                                                           wt_pending_placeholder_i, 
                                                                           wt_pending_signed_inner_i, 
                                                                           wt_signed_psbt_i, 
                                                                           wt_broadcast, 
                                                                           wt_to_sar, 
                                                                           signedInner, 
                                                                           placeholder >>
                                                      ELSE /\ IF msg'.kind = "WithdrawalNonInitiatorNisoWtMessage1"
                                                                 THEN /\ decrypted' = Decrypt(msg'.peer_i_tx_approval_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt, WTActor)
                                                                      /\ Assert(   TxApprovalSigValid(
                                                                                decrypted',
                                                                                peer',
                                                                                wt_saved_tx_id,
                                                                                SignedContent(wt_saved_wt_tx_approval).event_block_height,
                                                                                most_work_bitcoin_block_height), 
                                                                                "Failure of assertion at line 2337, column 17.")
                                                                      /\ wt_noninitiator_tx_approval_i' = [wt_noninitiator_tx_approval_i EXCEPT ![peer'] = decrypted']
                                                                      /\ UNCHANGED << wire_trace, 
                                                                                      wt_approvals_bundle_i, 
                                                                                      wt_pending_sar_stage_i, 
                                                                                      wt_pending_placeholder_i, 
                                                                                      wt_pending_signed_inner_i, 
                                                                                      wt_signed_psbt_i, 
                                                                                      wt_broadcast, 
                                                                                      wt_to_sar, 
                                                                                      signedInner, 
                                                                                      placeholder >>
                                                                 ELSE /\ IF msg'.kind = "WithdrawalNonInitiatorNisoWtMessage2"
                                                                            THEN /\ Assert(   ApprovalsBundleSigValid(
                                                                                           msg'.approvals_signed_by_boomlet_i,
                                                                                           peer',
                                                                                           [k \in Peers |->
                                                                                               IF k = INITIATOR THEN wt_initiator_tx_approval ELSE wt_noninitiator_tx_approval_i[k]],
                                                                                           wt_saved_wt_tx_approval), 
                                                                                           "Failure of assertion at line 2345, column 17.")
                                                                                 /\ wt_approvals_bundle_i' = [wt_approvals_bundle_i EXCEPT ![peer'] = msg'.approvals_signed_by_boomlet_i]
                                                                                 /\ UNCHANGED << wire_trace, 
                                                                                                 wt_pending_sar_stage_i, 
                                                                                                 wt_pending_placeholder_i, 
                                                                                                 wt_pending_signed_inner_i, 
                                                                                                 wt_signed_psbt_i, 
                                                                                                 wt_broadcast, 
                                                                                                 wt_to_sar, 
                                                                                                 decrypted, 
                                                                                                 signedInner, 
                                                                                                 placeholder >>
                                                                            ELSE /\ IF msg'.kind = "WithdrawalNisoWtMessage2"
                                                                                       THEN /\ decrypted' = Decrypt(msg'.peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, WTActor)
                                                                                            /\ Assert(ValidSig(decrypted', BoomletActor(peer')), 
                                                                                                      "Failure of assertion at line 2354, column 17.")
                                                                                            /\ placeholder' = PaddedPadding(SignedContent(decrypted'))
                                                                                            /\ signedInner' = PaddedContent(SignedContent(decrypted'))
                                                                                            /\ wt_pending_sar_stage_i' = [wt_pending_sar_stage_i EXCEPT ![peer'] = "commit"]
                                                                                            /\ wt_pending_placeholder_i' = [wt_pending_placeholder_i EXCEPT ![peer'] = placeholder']
                                                                                            /\ wt_pending_signed_inner_i' = [wt_pending_signed_inner_i EXCEPT ![peer'] = signedInner']
                                                                                            /\ Assert(wt_to_sar[peer'] = NoValue, 
                                                                                                      "Failure of assertion at line 2360, column 17.")
                                                                                            /\ wt_to_sar' = [wt_to_sar EXCEPT ![peer'] = WithdrawalWtSarsMessage1(placeholder', BoomletActor(peer'))]
                                                                                            /\ wire_trace' = (wire_trace \cup { WireHop(WTActor, SARActor(peer'), WithdrawalWtSarsMessage1(placeholder', BoomletActor(peer'))) })
                                                                                            /\ UNCHANGED << wt_signed_psbt_i, 
                                                                                                            wt_broadcast >>
                                                                                       ELSE /\ IF msg'.kind = "WithdrawalNonInitiatorNisoWtMessage3"
                                                                                                  THEN /\ decrypted' = Decrypt(msg'.peer_i_tx_commit_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt, WTActor)
                                                                                                       /\ Assert(ValidSig(decrypted', BoomletActor(peer')), 
                                                                                                                 "Failure of assertion at line 2365, column 17.")
                                                                                                       /\ placeholder' = PaddedPadding(SignedContent(decrypted'))
                                                                                                       /\ signedInner' = PaddedContent(SignedContent(decrypted'))
                                                                                                       /\ wt_pending_sar_stage_i' = [wt_pending_sar_stage_i EXCEPT ![peer'] = "commit"]
                                                                                                       /\ wt_pending_placeholder_i' = [wt_pending_placeholder_i EXCEPT ![peer'] = placeholder']
                                                                                                       /\ wt_pending_signed_inner_i' = [wt_pending_signed_inner_i EXCEPT ![peer'] = signedInner']
                                                                                                       /\ Assert(wt_to_sar[peer'] = NoValue, 
                                                                                                                 "Failure of assertion at line 2371, column 17.")
                                                                                                       /\ wt_to_sar' = [wt_to_sar EXCEPT ![peer'] = WithdrawalNonInitiatorWtSarsMessage1(placeholder', BoomletActor(peer'))]
                                                                                                       /\ wire_trace' = (wire_trace \cup { WireHop(WTActor, SARActor(peer'), WithdrawalNonInitiatorWtSarsMessage1(placeholder', BoomletActor(peer'))) })
                                                                                                       /\ UNCHANGED << wt_signed_psbt_i, 
                                                                                                                       wt_broadcast >>
                                                                                                  ELSE /\ IF msg'.kind \in {"WithdrawalNisoWtMessage3", "WithdrawalNisoWtMessage4", "WithdrawalNonInitiatorNisoWtMessage4"}
                                                                                                             THEN /\ decrypted' = Decrypt(msg'.peer_i_ping_signed_by_boomlet_i_padded_signed_by_boomlet_i_encrypted_by_boomlet_i_for_wt, WTActor)
                                                                                                                  /\ Assert(ValidSig(decrypted', BoomletActor(peer')), 
                                                                                                                            "Failure of assertion at line 2376, column 17.")
                                                                                                                  /\ placeholder' = PaddedPadding(SignedContent(decrypted'))
                                                                                                                  /\ signedInner' = PaddedContent(SignedContent(decrypted'))
                                                                                                                  /\ wt_pending_sar_stage_i' = [wt_pending_sar_stage_i EXCEPT ![peer'] = "ping"]
                                                                                                                  /\ wt_pending_placeholder_i' = [wt_pending_placeholder_i EXCEPT ![peer'] = placeholder']
                                                                                                                  /\ wt_pending_signed_inner_i' = [wt_pending_signed_inner_i EXCEPT ![peer'] = signedInner']
                                                                                                                  /\ Assert(wt_to_sar[peer'] = NoValue, 
                                                                                                                            "Failure of assertion at line 2382, column 17.")
                                                                                                                  /\ wt_to_sar' = [wt_to_sar EXCEPT ![peer'] = WithdrawalWtSarsMessage2(placeholder', BoomletActor(peer'))]
                                                                                                                  /\ wire_trace' = (wire_trace \cup { WireHop(WTActor, SARActor(peer'), WithdrawalWtSarsMessage2(placeholder', BoomletActor(peer'))) })
                                                                                                                  /\ UNCHANGED << wt_signed_psbt_i, 
                                                                                                                                  wt_broadcast >>
                                                                                                             ELSE /\ Assert(msg'.kind = "WithdrawalNisoWtMessage5", 
                                                                                                                            "Failure of assertion at line 2386, column 17.")
                                                                                                                  /\ wt_signed_psbt_i' = [wt_signed_psbt_i EXCEPT ![peer'] = msg'.psbt_signed_i]
                                                                                                                  /\ IF AllPeerSignedPsbtsPresent(wt_signed_psbt_i')
                                                                                                                        THEN /\ wt_broadcast' = Broadcast(wt_saved_tx_id, Collection(wt_signed_psbt_i'))
                                                                                                                        ELSE /\ TRUE
                                                                                                                             /\ UNCHANGED wt_broadcast
                                                                                                                  /\ UNCHANGED << wire_trace, 
                                                                                                                                  wt_pending_sar_stage_i, 
                                                                                                                                  wt_pending_placeholder_i, 
                                                                                                                                  wt_pending_signed_inner_i, 
                                                                                                                                  wt_to_sar, 
                                                                                                                                  decrypted, 
                                                                                                                                  signedInner, 
                                                                                                                                  placeholder >>
                                                                                 /\ UNCHANGED wt_approvals_bundle_i
                                                                      /\ UNCHANGED wt_noninitiator_tx_approval_i
                                                           /\ UNCHANGED << wt_saved_tx_id, 
                                                                           wt_saved_wt_tx_approval, 
                                                                           wt_initiator_tx_approval, 
                                                                           wt_to_niso >>
                                           /\ UNCHANGED << wt_commit_sar_reply_i, 
                                                           wt_ping_sar_reply_i, 
                                                           wt_signed_commit_i, 
                                                           wt_last_accepted_ping_i, 
                                                           wt_reached_pings_collection, 
                                                           wt_last_pong_height, 
                                                           sar_to_wt, wtHeight >>
                                /\ UNCHANGED wt_relayed_all_commits
                     /\ UNCHANGED wt_relayed_all_approvals
          /\ pc' = [pc EXCEPT ![WT_ID] = "WTLoop"]
          /\ UNCHANGED << boomerang_descriptor, peer_id_collection, 
                          st_identity_pubkey_i, sar_pubkey_i, doxing_key_i, 
                          duress_consent_set_i, boomlet_mystery_i, 
                          most_work_bitcoin_block_height, user_saved_psbt_i, 
                          user_initiator_peer_id_i, user_last_duress_space_i, 
                          user_sent_initial_psbt_i, user_sent_psbt_agreement_i, 
                          user_sent_iso_credentials_i, 
                          user_sent_connect_back_to_niso_i, niso_saved_psbt_i, 
                          niso_saved_tx_id_i, niso_event_block_height_i, 
                          niso_initiator_peer_id_i, 
                          niso_saved_wt_tx_approval_i, niso_hydrated_psbt_i, 
                          niso_reached_pings_collection_i, 
                          boomlet_saved_psbt_i, boomlet_committed_tx_id_i, 
                          boomlet_pending_txid_nonce_i, 
                          boomlet_saved_duress_space_i, 
                          boomlet_saved_duress_stage_i, 
                          boomlet_saved_duress_seq_i, 
                          boomlet_pending_duress_nonce_i, 
                          boomlet_duress_placeholder_plaintext_i, 
                          boomlet_duress_placeholder_cipher_i, 
                          boomlet_signed_tx_approval_i, 
                          boomlet_saved_wt_tx_approval_i, 
                          boomlet_all_peer_approvals_i, 
                          boomlet_approvals_bundle_i, 
                          boomlet_signed_commit_inner_i, 
                          boomlet_commit_collection_i, boomlet_counter_i, 
                          boomlet_last_seen_block_i, boomlet_ping_seq_num_i, 
                          boomlet_reached_mystery_flag_i, 
                          boomlet_known_reached_i, boomlet_prev_pings_i, 
                          boomlet_ready_to_sign_i, boomlet_signed_psbt_i, 
                          boomlet_pubnonce_boom_i, boomlet_partialsig_boom_i, 
                          st_last_txid_with_nonce_i, st_last_duress_check_i, 
                          iso_pubnonce_normal_i, iso_partialsig_normal_i, 
                          iso_signed_psbt_i, sar_seen_placeholder_iv_i, 
                          sar_escalated_i, sar_last_doxing_identifier_i, 
                          user_to_niso, niso_to_user, user_to_st, st_to_user, 
                          boomlet_to_niso, niso_to_boomlet, niso_to_st, 
                          st_to_niso, user_to_iso, iso_to_user, boomlet_to_iso, 
                          iso_to_boomlet, msg_, signalIndex_, msg_S, 
                          nonceWrapped, signalIndex, msg_N, approvalSig, wtSig, 
                          commitSig, signedPing, msg_B, signedAck, 
                          duressSignal, hydrated, signedPong, prevPings, msg_I, 
                          msg_SA, plaintext, reply, pongMap >>

Watchtower == WTLoop

Tick == /\ pc["ENV"] = "Tick"
        /\ most_work_bitcoin_block_height' = most_work_bitcoin_block_height + 1
        /\ pc' = [pc EXCEPT !["ENV"] = "Tick"]
        /\ UNCHANGED << wire_trace, boomerang_descriptor, peer_id_collection, 
                        st_identity_pubkey_i, sar_pubkey_i, doxing_key_i, 
                        duress_consent_set_i, boomlet_mystery_i, 
                        user_saved_psbt_i, user_initiator_peer_id_i, 
                        user_last_duress_space_i, user_sent_initial_psbt_i, 
                        user_sent_psbt_agreement_i, 
                        user_sent_iso_credentials_i, 
                        user_sent_connect_back_to_niso_i, niso_saved_psbt_i, 
                        niso_saved_tx_id_i, niso_event_block_height_i, 
                        niso_initiator_peer_id_i, niso_saved_wt_tx_approval_i, 
                        niso_hydrated_psbt_i, niso_reached_pings_collection_i, 
                        boomlet_saved_psbt_i, boomlet_committed_tx_id_i, 
                        boomlet_pending_txid_nonce_i, 
                        boomlet_saved_duress_space_i, 
                        boomlet_saved_duress_stage_i, 
                        boomlet_saved_duress_seq_i, 
                        boomlet_pending_duress_nonce_i, 
                        boomlet_duress_placeholder_plaintext_i, 
                        boomlet_duress_placeholder_cipher_i, 
                        boomlet_signed_tx_approval_i, 
                        boomlet_saved_wt_tx_approval_i, 
                        boomlet_all_peer_approvals_i, 
                        boomlet_approvals_bundle_i, 
                        boomlet_signed_commit_inner_i, 
                        boomlet_commit_collection_i, boomlet_counter_i, 
                        boomlet_last_seen_block_i, boomlet_ping_seq_num_i, 
                        boomlet_reached_mystery_flag_i, 
                        boomlet_known_reached_i, boomlet_prev_pings_i, 
                        boomlet_ready_to_sign_i, boomlet_signed_psbt_i, 
                        boomlet_pubnonce_boom_i, boomlet_partialsig_boom_i, 
                        st_last_txid_with_nonce_i, st_last_duress_check_i, 
                        iso_pubnonce_normal_i, iso_partialsig_normal_i, 
                        iso_signed_psbt_i, sar_seen_placeholder_iv_i, 
                        sar_escalated_i, sar_last_doxing_identifier_i, 
                        wt_saved_tx_id, wt_saved_wt_tx_approval, 
                        wt_initiator_tx_approval, 
                        wt_noninitiator_tx_approval_i, wt_approvals_bundle_i, 
                        wt_pending_sar_stage_i, wt_pending_placeholder_i, 
                        wt_pending_signed_inner_i, wt_commit_sar_reply_i, 
                        wt_ping_sar_reply_i, wt_signed_commit_i, 
                        wt_last_accepted_ping_i, wt_reached_pings_collection, 
                        wt_last_pong_height, wt_relayed_all_approvals, 
                        wt_relayed_all_commits, wt_signed_psbt_i, wt_broadcast, 
                        user_to_niso, niso_to_user, user_to_st, st_to_user, 
                        boomlet_to_niso, niso_to_boomlet, niso_to_st, 
                        st_to_niso, user_to_iso, iso_to_user, boomlet_to_iso, 
                        iso_to_boomlet, niso_to_wt, wt_to_niso, wt_to_sar, 
                        sar_to_wt, msg_, signalIndex_, msg_S, nonceWrapped, 
                        signalIndex, msg_N, approvalSig, wtSig, commitSig, 
                        signedPing, msg_B, signedAck, duressSignal, hydrated, 
                        signedPong, prevPings, msg_I, msg_SA, plaintext, reply, 
                        msg, peer, decrypted, signedInner, placeholder, 
                        wtHeight, pongMap >>

Environment == Tick

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == Watchtower \/ Environment
           \/ (\E self \in Peers: UserFlow(self))
           \/ (\E self \in Peers: STFlow(self))
           \/ (\E self \in Peers: NisoFlow(self))
           \/ (\E self \in Peers: BoomletFlow(self))
           \/ (\E self \in Peers: IsoFlow(self))
           \/ (\E self \in Peers: SARFlow(self))
           \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 

WireSurfaceOnlyCanonical ==
    \A hop \in wire_trace : hop.message.kind \in CanonicalWireMessageKinds

NoExtraWTHops ==
    \A hop \in wire_trace :
        /\ ~(hop.sender = WTActor /\ hop.receiver.kind = "User")
        /\ hop.message.kind # "WTBroadcast"

CommittedTxConsistent ==
    /\ (wt_saved_tx_id = NoValue \/ wt_saved_tx_id = CanonicalTxId)
    /\ \A i \in Peers :
        /\ (niso_saved_tx_id_i[i] = NoValue \/ niso_saved_tx_id_i[i] = CanonicalTxId)
        /\ (boomlet_committed_tx_id_i[i] = NoValue \/ boomlet_committed_tx_id_i[i] = CanonicalTxId)

HydratedPsbtPreservesCommittedTx ==
    \A i \in Peers :
        /\ (niso_hydrated_psbt_i[i] = NoValue \/ niso_hydrated_psbt_i[i].tx_id = CanonicalTxId)
        /\ (boomlet_saved_psbt_i[i] = NoValue
            \/ boomlet_saved_psbt_i[i].kind # "HydratedPsbt"
            \/ boomlet_saved_psbt_i[i].tx_id = CanonicalTxId)

WTRelayRequiresAllSigned ==
    wt_broadcast = NoValue \/ AllPeerSignedPsbtsPresent(wt_signed_psbt_i)

SARDoxingIdentifiersExcludeSafePadding ==
    \A i \in Peers :
        sar_last_doxing_identifier_i[i] = NoValue
        \/ ~IsSafePaddingPlaintextForPeer(
                i,
                sar_last_doxing_identifier_i[i].duress_placeholder_payload)

NisoVisibleState(i) ==
    [ saved_psbt              |-> niso_saved_psbt_i[i],
      saved_tx_id             |-> niso_saved_tx_id_i[i],
      event_block_height      |-> niso_event_block_height_i[i],
      initiator_peer_id       |-> niso_initiator_peer_id_i[i],
      hydrated_psbt           |-> niso_hydrated_psbt_i[i],
      reached_pings_collection |-> niso_reached_pings_collection_i[i] ]

NisoVisibleMessages(i) ==
    { m \in {
        user_to_niso[i],
        niso_to_user[i],
        boomlet_to_niso[i],
        niso_to_boomlet[i],
        niso_to_st[i],
        st_to_niso[i],
        niso_to_wt[i],
        wt_to_niso[i]
      } : m # NoValue }

BoomletVisibleState(i) ==
    [ saved_psbt                |-> boomlet_saved_psbt_i[i],
      committed_tx_id           |-> boomlet_committed_tx_id_i[i],
      duress_placeholder_cipher |-> boomlet_duress_placeholder_cipher_i[i],
      counter                   |-> boomlet_counter_i[i],
      last_seen_block           |-> boomlet_last_seen_block_i[i],
      ping_seq_num              |-> boomlet_ping_seq_num_i[i],
      reached_flag              |-> boomlet_reached_mystery_flag_i[i],
      known_reached             |-> boomlet_known_reached_i[i],
      ready_to_sign             |-> boomlet_ready_to_sign_i[i] ]

=============================================================================
