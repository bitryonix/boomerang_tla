---- MODULE BoomerangSetupWire ----
EXTENDS Naturals, Sequences, FiniteSets, TLC

(***************************************************************************)
(* Wire-faithful symbolic setup model derived from boomerang_design.zip.    *)
(* Canonical sources for this module:                                      *)
(* - setup/README.md                                                       *)
(* - setup/setup_diagram_without_states.puml                               *)
(* - spec/SPEC.md, section 9, only to resolve narrative context            *)
(*                                                                         *)
(* Scope:                                                                  *)
(* - one local peer's full setup ceremony from the peer_0 viewpoint        *)
(* - fixed 5-peer profile                                                  *)
(* - SAR sign-up, Boomlet/ST duress enrollment, boomerang_params agreement *)
(* - WT activation, SAR finalization, Boomletwo backup, final peer sync    *)
(* - symbolic crypto only, with explicit wrapper layering                  *)
(*                                                                         *)
(* Design notes:                                                           *)
(* - actor hops are represented as a canonical sequence of WireHop records *)
(* - exact PlantUML wrapper names are used as message kind values          *)
(* - fields intentionally preserve peer_0 / peer_i wire vocabulary         *)
(* - no attempt is made to optimize TLC tractability                       *)
(***************************************************************************)

CONSTANTS
    Peers,
    LOCAL_PEER,
    WTIdsOrder,
    SARIdsOrder,
    Network,
    EntropyBytes,
    Passphrase,
    RpcClientUrl,
    RpcClientAuth,
    DoxingPassword,
    StaticDoxingData,
    DynamicDoxingData,
    MilestoneBlocks,
    MIN_TRIES_FOR_DIGGING_GAME_IN_BLOCKS,
    MAX_TRIES_FOR_DIGGING_GAME_IN_BLOCKS,
    InitDuressConsentAnswer1,
    InitDuressConsentAnswer2,
    BoomletIdentityPubkeySortRank

DuressColumns ==
    1..5

CountryRanks ==
    1..195

Image(f) ==
    { f[x] : x \in DOMAIN f }

SeqImage(seq) ==
    { seq[i] : i \in 1..Len(seq) }

DistinctSeq(seq) ==
    Cardinality(SeqImage(seq)) = Len(seq)

DistinctConsentAnswer(answer) ==
    /\ answer \in [DuressColumns -> CountryRanks]
    /\ Cardinality(Image(answer)) = Cardinality(DuressColumns)

ASSUME
    /\ IsFiniteSet(Peers)
    /\ Cardinality(Peers) = 5
    /\ LOCAL_PEER \in Peers
    /\ WTIdsOrder \in Seq(STRING)
    /\ Len(WTIdsOrder) >= 1
    /\ DistinctSeq(WTIdsOrder)
    /\ SARIdsOrder \in [Peers -> Seq(STRING)]
    /\ \A p \in Peers :
        /\ Len(SARIdsOrder[p]) >= 1
        /\ DistinctSeq(SARIdsOrder[p])
    /\ Network \in STRING
    /\ EntropyBytes \in [Peers -> STRING]
    /\ Passphrase \in [Peers -> STRING]
    /\ RpcClientUrl \in [Peers -> STRING]
    /\ RpcClientAuth \in [Peers -> STRING]
    /\ DoxingPassword \in [Peers -> STRING]
    /\ StaticDoxingData \in [Peers -> STRING]
    /\ DynamicDoxingData \in [Peers -> STRING]
    /\ MilestoneBlocks \in [0..5 -> Nat]
    /\ \A i, j \in 0..5 : i < j => MilestoneBlocks[i] < MilestoneBlocks[j]
    /\ MIN_TRIES_FOR_DIGGING_GAME_IN_BLOCKS \in Nat
    /\ MAX_TRIES_FOR_DIGGING_GAME_IN_BLOCKS \in Nat
    /\ MIN_TRIES_FOR_DIGGING_GAME_IN_BLOCKS > 0
    /\ MIN_TRIES_FOR_DIGGING_GAME_IN_BLOCKS < MAX_TRIES_FOR_DIGGING_GAME_IN_BLOCKS
    /\ InitDuressConsentAnswer1 \in [Peers -> [DuressColumns -> CountryRanks]]
    /\ InitDuressConsentAnswer2 \in [Peers -> [DuressColumns -> CountryRanks]]
    /\ \A p \in Peers :
        /\ DistinctConsentAnswer(InitDuressConsentAnswer1[p])
        /\ DistinctConsentAnswer(InitDuressConsentAnswer2[p])
        /\ Image(InitDuressConsentAnswer1[p]) = Image(InitDuressConsentAnswer2[p])
    /\ BoomletIdentityPubkeySortRank \in [Peers -> 1..5]
    /\ Image(BoomletIdentityPubkeySortRank) = 1..5

ModelStringFunction(label) ==
    [p \in Peers |-> label]

ModelWTIdsOrder ==
    <<"WT_PRIMARY">>

ModelSARIdsOrder ==
    [p \in Peers |-> <<"SAR_PRIMARY">>]

ModelEntropyBytes ==
    ModelStringFunction("ENTROPY")

ModelPassphrase ==
    ModelStringFunction("PASSPHRASE")

ModelRpcClientUrl ==
    ModelStringFunction("RPC_URL")

ModelRpcClientAuth ==
    ModelStringFunction("RPC_AUTH")

ModelDoxingPassword ==
    ModelStringFunction("DOXING_PASSWORD")

ModelStaticDoxingData ==
    ModelStringFunction("STATIC_DOXING_DATA")

ModelDynamicDoxingData ==
    ModelStringFunction("DYNAMIC_DOXING_DATA")

ModelMilestoneBlocks ==
    [i \in 0..5 |-> (i + 1) * 10]

ModelDuressConsentAnswer1 ==
    [p \in Peers |-> [c \in DuressColumns |-> c]]

ModelDuressConsentAnswer2 ==
    [p \in Peers |-> [c \in DuressColumns |-> 6 - c]]

ModelBoomletIdentityPubkeySortRank ==
    CHOOSE rank \in [Peers -> 1..5] : Image(rank) = 1..5

NoValue ==
    "NO_VALUE"

UserActor(i)       == [kind |-> "User", peer |-> i]
PhoneActor(i)      == [kind |-> "Phone", peer |-> i]
IsoActor(i)        == [kind |-> "Iso", peer |-> i]
BoomletActor(i)    == [kind |-> "Boomlet", peer |-> i]
STActor(i)         == [kind |-> "ST", peer |-> i]
BoomletwoActor(i)  == [kind |-> "Boomletwo", peer |-> i]
NisoActor(i)       == [kind |-> "Niso", peer |-> i]

ActiveWTLabel ==
    WTIdsOrder[1]

PrimarySARLabel(peer) ==
    SARIdsOrder[peer][1]

WTActorFor(wtLabel) ==
    [kind |-> "WT", wt_id_label |-> wtLabel]

WTActor ==
    WTActorFor(ActiveWTLabel)

SARActorFor(sarLabel) ==
    [kind |-> "SAR", sar_id_label |-> sarLabel]

SARActor(peer) ==
    SARActorFor(PrimarySARLabel(peer))

WireHop(step, sender, receiver, message) ==
    [ diagram_step |-> step,
      sender       |-> sender,
      receiver     |-> receiver,
      message      |-> message ]

Digest(algorithm, content) ==
    [ kind      |-> "Digest",
      algorithm |-> algorithm,
      content   |-> content ]

SHA256(content) ==
    Digest("sha256", content)

BoomerangPurpose ==
    [ kind              |-> "Bip32HardenedPurpose",
      derivation_rule   |-> "first_2_bytes_of_sha256_boomerang_hardened",
      source_digest     |-> SHA256("boomerang"),
      first_bytes_count |-> 2,
      hex               |-> "cb86",
      decimal           |-> 52102,
      hardened          |-> TRUE ]

NonceValue(peer, phase, seq) ==
    [ kind  |-> "Nonce",
      peer  |-> peer,
      phase |-> phase,
      seq   |-> seq ]

IVValue(peer, phase, seq) ==
    [ kind  |-> "IV",
      peer  |-> peer,
      phase |-> phase,
      seq   |-> seq ]

MessageWithNonce(content, nonce) ==
    [ kind    |-> "MessageWithNonce",
      content |-> content,
      nonce   |-> nonce ]

SignatureOnMessage(signer, content) ==
    [ kind    |-> "SignatureOnMessage",
      signer  |-> signer,
      content |-> content ]

SignedContent(sig) ==
    sig.content

ValidSig(sig, signer) ==
    /\ sig # NoValue
    /\ sig.kind = "SignatureOnMessage"
    /\ sig.signer = signer

EncryptedFor(recipient, sender, iv, payload) ==
    [ kind      |-> "EncryptedFor",
      recipient |-> recipient,
      sender    |-> sender,
      iv        |-> iv,
      payload   |-> payload ]

CanDecrypt(cipher, actor) ==
    /\ cipher # NoValue
    /\ cipher.kind = "EncryptedFor"
    /\ cipher.recipient = actor

Decrypt(cipher, actor) ==
    IF CanDecrypt(cipher, actor) THEN cipher.payload ELSE NoValue

EncryptedBySymmetricKey(key, iv, payload) ==
    [ kind    |-> "EncryptedBySymmetricKey",
      key     |-> key,
      iv      |-> iv,
      payload |-> payload ]

Collection(items) ==
    [ kind  |-> "Collection",
      items |-> items ]

Mnemonic(peer) ==
    [ kind          |-> "Mnemonic",
      peer          |-> peer,
      entropy_bytes |-> EntropyBytes[peer] ]

MasterXpriv0(peer) ==
    [ kind       |-> "MasterXpriv0",
      mnemonic   |-> Mnemonic(peer),
      passphrase |-> Passphrase[peer] ]

PurposeRootXpriv0(peer) ==
    [ kind         |-> "PurposeRootXpriv0",
      path         |-> "m/cb86'",
      decimal_path |-> "m/52102h",
      purpose      |-> BoomerangPurpose,
      master_xpriv |-> MasterXpriv0(peer) ]

PurposeRootXpub0(peer) ==
    [ kind               |-> "PurposeRootXpub0",
      purpose_root_xpriv |-> PurposeRootXpriv0(peer) ]

NormalPrivkey(peer) ==
    [ kind               |-> "NormalPrivkey",
      peer               |-> peer,
      purpose_root_xpriv |-> PurposeRootXpriv0(peer) ]

NormalPubkey(peer) ==
    [ kind              |-> "NormalPubkey",
      peer              |-> peer,
      purpose_root_xpub |-> PurposeRootXpub0(peer) ]

BoomletIdentityPrivkey(peer) ==
    [ kind |-> "BoomletIdentityPrivkey", peer |-> peer ]

BoomletIdentityPubkey(peer) ==
    [ kind    |-> "BoomletIdentityPubkey",
      peer    |-> peer,
      derived |-> BoomletIdentityPrivkey(peer) ]

BoomletwoIdentityPrivkey(peer) ==
    [ kind |-> "BoomletwoIdentityPrivkey", peer |-> peer ]

BoomletwoIdentityPubkey(peer) ==
    [ kind    |-> "BoomletwoIdentityPubkey",
      peer    |-> peer,
      derived |-> BoomletwoIdentityPrivkey(peer) ]

STIdentityPrivkey(peer) ==
    [ kind |-> "STIdentityPrivkey", peer |-> peer ]

STIdentityPubkey(peer) ==
    [ kind    |-> "STIdentityPubkey",
      peer    |-> peer,
      derived |-> STIdentityPrivkey(peer) ]

BoomMusig2PrivkeyShare(peer) ==
    [ kind |-> "BoomMusig2PrivkeyShare", peer |-> peer ]

BoomMusig2PubkeyShare(peer) ==
    [ kind    |-> "BoomMusig2PubkeyShare",
      peer    |-> peer,
      derived |-> BoomMusig2PrivkeyShare(peer) ]

BoomPubkey(peer) ==
    [ kind                  |-> "BoomPubkey",
      peer                  |-> peer,
      normal_pubkey         |-> NormalPubkey(peer),
      boom_musig2_pub_share |-> BoomMusig2PubkeyShare(peer) ]

PeerTorSecretKey(peer) ==
    [ kind |-> "PeerTorSecretKey", peer |-> peer ]

PeerTorAddress(peer) ==
    [ kind       |-> "PeerTorAddress",
      peer       |-> peer,
      derived_by |-> "onion_service",
      secret_key |-> PeerTorSecretKey(peer) ]

PeerTorAddressSignedByBoomlet(peer) ==
    SignatureOnMessage(BoomletActor(peer), PeerTorAddress(peer))

PeerId(peer) ==
    [ kind                    |-> "PeerId",
      boom_pubkey             |-> BoomPubkey(peer),
      normal_pubkey           |-> NormalPubkey(peer),
      boomlet_identity_pubkey |-> BoomletIdentityPubkey(peer) ]

PeerAddressRecord(peer) ==
    [ kind                                    |-> "PeerAddressRecord",
      peer_id                                 |-> PeerId(peer),
      peer_tor_address_signed_by_boomlet      |-> PeerTorAddressSignedByBoomlet(peer) ]

PeerAddressExchangePayload0(peer) ==
    [ peer_0_id                              |-> PeerId(peer),
      peer_0_tor_address_signed_by_boomlet_0 |-> PeerTorAddressSignedByBoomlet(peer) ]

PeerAddressExchangePayloadI(peer) ==
    [ peer_i_id                              |-> PeerId(peer),
      peer_i_tor_address_signed_by_boomlet_i |-> PeerTorAddressSignedByBoomlet(peer) ]

PeerAddressesCollection ==
    Collection([p \in Peers |-> PeerAddressRecord(p)])

PeerIdsCollection ==
    Collection([p \in Peers |-> PeerId(p)])

WTPubkeyFor(wtLabel) ==
    [ kind        |-> "WTPubkey",
      wt_id_label |-> wtLabel ]

WTPubkey ==
    WTPubkeyFor(ActiveWTLabel)

WTIdFor(wtLabel) ==
    [ kind           |-> "WTId",
      wt_tor_address |-> [ kind |-> "TorAddress", owner |-> WTActorFor(wtLabel) ],
      wt_pubkey      |-> WTPubkeyFor(wtLabel) ]

WTId ==
    WTIdFor(ActiveWTLabel)

WTIdsCollection ==
    Collection([n \in 1..Len(WTIdsOrder) |-> WTIdFor(WTIdsOrder[n])])

SARPubkeyFor(sarLabel) ==
    [ kind         |-> "SARPubkey",
      sar_id_label |-> sarLabel ]

SARPubkey(peer) ==
    SARPubkeyFor(PrimarySARLabel(peer))

SARIdFor(sarLabel) ==
    [ kind            |-> "SARId",
      sar_tor_address |-> [ kind |-> "TorAddress", owner |-> SARActorFor(sarLabel) ],
      sar_pubkey      |-> SARPubkeyFor(sarLabel) ]

SARId(peer) ==
    SARIdFor(PrimarySARLabel(peer))

SARIdsCollection(peer) ==
    Collection([n \in 1..Len(SARIdsOrder[peer]) |->
        SARIdFor(SARIdsOrder[peer][n])])

DoxingKey(peer) ==
    SHA256(DoxingPassword[peer])

DoxingDataIdentifier(peer) ==
    SHA256(DoxingKey(peer))

StaticDoxingDataCipher(peer) ==
    EncryptedBySymmetricKey(
        DoxingKey(peer),
        IVValue(peer, "static_doxing_data", 0),
        StaticDoxingData[peer])

DynamicDoxingDataCipher(peer) ==
    EncryptedBySymmetricKey(
        DoxingKey(peer),
        IVValue(peer, "dynamic_doxing_data", 0),
        DynamicDoxingData[peer])

StaticDoxingDataCipherFingerprint(peer) ==
    SHA256(StaticDoxingDataCipher(peer))

MilestoneBlockCollection ==
    Collection(MilestoneBlocks)

FallbackBranch(n) ==
    [ kind      |-> "DescriptorFallbackNormalBranch",
      threshold |-> 6 - n,
      keys      |-> [p \in Peers |-> NormalPubkey(p)],
      after     |-> MilestoneBlocks[n] ]

BoomerangBranch ==
    [ kind      |-> "DescriptorBoomerangBranch",
      threshold |-> Cardinality(Peers),
      keys      |-> [p \in Peers |-> BoomPubkey(p)],
      after     |-> MilestoneBlocks[0] ]

BoomerangScriptTree ==
    [n \in 0..5 |-> IF n = 0 THEN BoomerangBranch ELSE FallbackBranch(n)]

BoomerangDescriptor ==
    [ kind            |-> "BoomerangDescriptor",
      network         |-> Network,
      key_path        |-> "unspendable",
      milestone_blocks|-> MilestoneBlocks,
      script_tree     |-> BoomerangScriptTree ]

BoomerangParamsSeed ==
    [ kind                       |-> "BoomerangParamsSeed",
      peer_ids                   |-> PeerIdsCollection,
      wt_ids                     |-> WTIdsCollection,
      milestone_block_collection |-> MilestoneBlockCollection ]

BoomerangParams ==
    [ kind                  |-> "BoomerangParams",
      peer_ids_collection   |-> PeerIdsCollection,
      wt_ids_collection     |-> WTIdsCollection,
      boomerang_descriptor  |-> BoomerangDescriptor ]

BoomerangParamsFingerprint ==
    SHA256(BoomerangParams)

SortedAllPeerBoomletIdentityPubkeys ==
    [rank \in 1..5 |->
        BoomletIdentityPubkey(
            CHOOSE p \in Peers : BoomletIdentityPubkeySortRank[p] = rank)]

OtherPeer(peer, position) ==
    CHOOSE p \in Peers \ {peer} :
        Cardinality(
            { q \in Peers \ {peer} :
                BoomletIdentityPubkeySortRank[q] <= BoomletIdentityPubkeySortRank[p] })
            = position

DuressColumnPermutations ==
    { f \in [CountryRanks -> CountryRanks] : Image(f) = CountryRanks }

DuressSpaceRecord(peer, round, spaceMap) ==
    [ kind  |-> "DuressCheckSpace",
      peer  |-> peer,
      round |-> round,
      space |-> spaceMap ]

DuressCheckSpaces(peer, round) ==
    { DuressSpaceRecord(peer, round, spaceMap) :
        spaceMap \in [DuressColumns -> DuressColumnPermutations] }

FirstDuressSpace(peer) ==
    CHOOSE space \in DuressCheckSpaces(peer, "enroll") : TRUE

SecondDuressSpace(peer) ==
    CHOOSE space \in DuressCheckSpaces(peer, "confirm") : TRUE

IndexOfValueInSpace(space, column, value) ==
    CHOOSE index \in CountryRanks : space.space[column][index] = value

DuressSignalIndex(peer, round, selectedIndices) ==
    [ kind             |-> "DuressSignalIndex",
      peer             |-> peer,
      round            |-> round,
      selected_indices |-> selectedIndices ]

BuildDuressSignalIndex(space, answer) ==
    DuressSignalIndex(
        space.peer,
        space.round,
        [column \in DuressColumns |->
            IndexOfValueInSpace(space, column, answer[column])])

DerivedDuressSignal(space, signalIndex) ==
    [column \in DuressColumns |->
        space.space[column][signalIndex.selected_indices[column]]]

EnrollmentSignalIndex(peer) ==
    BuildDuressSignalIndex(FirstDuressSpace(peer), InitDuressConsentAnswer1[peer])

ConfirmationSignalIndex(peer) ==
    BuildDuressSignalIndex(SecondDuressSpace(peer), InitDuressConsentAnswer2[peer])

StoredDuressConsentSet(peer) ==
    Image(DerivedDuressSignal(FirstDuressSpace(peer), EnrollmentSignalIndex(peer)))

EnrollmentNonce(peer) ==
    NonceValue(peer, "setup_duress_enrollment", 1)

ConfirmationNonce(peer) ==
    NonceValue(peer, "setup_duress_confirmation", 2)

BoomerangParamsSeedNonce(peer) ==
    NonceValue(peer, "setup_boomerang_params_seed", 1)

DuressCheckCipher(peer, round, space, nonce) ==
    EncryptedFor(
        STActor(peer),
        BoomletActor(peer),
        IVValue(peer, round, 0),
        MessageWithNonce(space, nonce))

DuressReplyCipher(peer, round, signalIndex, nonce) ==
    EncryptedFor(
        BoomletActor(peer),
        STActor(peer),
        IVValue(peer, round, 1),
        MessageWithNonce(signalIndex, nonce))

BoomerangParamsSeedCipher(peer) ==
    EncryptedFor(
        STActor(peer),
        BoomletActor(peer),
        IVValue(peer, "boomerang_params_seed", 0),
        MessageWithNonce(BoomerangParamsSeed, BoomerangParamsSeedNonce(peer)))

BoomerangParamsSeedAckCipher(peer) ==
    EncryptedFor(
        BoomletActor(peer),
        STActor(peer),
        IVValue(peer, "boomerang_params_seed_ack", 0),
        SignatureOnMessage(
            STActor(peer),
            MessageWithNonce(BoomerangParamsSeed, BoomerangParamsSeedNonce(peer))))

SarServiceFeePaymentInfo(peer) ==
    [ kind                |-> "SarServiceFeePaymentInfo",
      service_fee_invoice |-> [kind |-> "SarServiceFeeInvoice", peer |-> peer],
      payment_deadline    |-> [kind |-> "SarPaymentDeadline", peer |-> peer],
      sar_id              |-> SARId(peer) ]

SarServiceFeePaymentReceipts(peer) ==
    [ kind         |-> "SarServiceFeePaymentReceipts",
      payment_info |-> SarServiceFeePaymentInfo(peer),
      paid_by      |-> UserActor(peer) ]

WTServiceFeePaymentInfo(peer) ==
    [ kind                |-> "WTServiceFeePaymentInfo",
      service_fee_invoice |-> [kind |-> "WTServiceFeeInvoice", peer |-> peer],
      payment_deadline    |-> [kind |-> "WTPaymentDeadline", peer |-> peer],
      wt_id               |-> WTId ]

WTServiceFeePaymentReceipt(peer) ==
    [ kind         |-> "WTServiceFeePaymentReceipt",
      payment_info |-> WTServiceFeePaymentInfo(peer),
      paid_by      |-> UserActor(peer) ]

SignedBoomerangParams(peer) ==
    SignatureOnMessage(BoomletActor(peer), BoomerangParams)

AllPeersSignedBoomerangParams ==
    Collection([p \in Peers |-> SignedBoomerangParams(p)])

SortedAllPeersBoomletIdentityPubkeysSigned(peer) ==
    SignatureOnMessage(BoomletActor(peer), SortedAllPeerBoomletIdentityPubkeys)

BoomerangParamsFingerprintSignedByBoomlet(peer) ==
    SignatureOnMessage(BoomletActor(peer), BoomerangParamsFingerprint)

BoomerangParamsFingerprintSuffixedByWT ==
    [ kind        |-> "WtBoomerangParamsFingerprintSuffix",
      fingerprint |-> BoomerangParamsFingerprint,
      suffix      |-> "setup_peers_registration_with_wt_completed" ]

BoomerangParamsFingerprintSuffixedByWTSigned ==
    SignatureOnMessage(WTActor, BoomerangParamsFingerprintSuffixedByWT)

SharedStateActiveWT ==
    [ kind             |-> "SharedStateBoomerangParams",
      boomerang_params |-> BoomerangParams,
      magic            |-> "setup_wt_service_initialized" ]

SharedStateActiveWTFingerprint ==
    SHA256(SharedStateActiveWT)

SharedStateActiveWTFingerprintSigned(peer) ==
    SignatureOnMessage(BoomletActor(peer), SharedStateActiveWTFingerprint)

AllPeersSharedStateActiveWTSigned ==
    Collection([p \in Peers |-> SharedStateActiveWTFingerprintSigned(p)])

SarIdsCollectionSignedByBoomlet(peer) ==
    SignatureOnMessage(BoomletActor(peer), SARIdsCollection(peer))

SarIdsCollectionSignedByBoomletEncryptedForWT(peer) ==
    EncryptedFor(
        WTActor,
        BoomletActor(peer),
        IVValue(peer, "sar_ids_for_wt", 0),
        SarIdsCollectionSignedByBoomlet(peer))

DoxingDataIdentifierEncryptedForSAR(peer) ==
    EncryptedFor(
        SARActor(peer),
        BoomletActor(peer),
        IVValue(peer, "doxing_identifier_for_sar", 0),
        DoxingDataIdentifier(peer))

SarSetupResponse(peer) ==
    [ kind                                                   |-> "SarSetupResponse",
      doxing_data_identifier                                 |-> DoxingDataIdentifier(peer),
      fingerprint_of_static_doxing_data_encrypted_by_doxing_key |-> StaticDoxingDataCipherFingerprint(peer),
      iv_of_static_doxing_data_encrypted_by_doxing_key       |-> StaticDoxingDataCipher(peer).iv ]

SarSetupResponseSignedBySAR(peer) ==
    SignatureOnMessage(SARActor(peer), SarSetupResponse(peer))

SarSetupResponseSignedBySAREncryptedForBoomlet(peer) ==
    EncryptedFor(
        BoomletActor(peer),
        SARActor(peer),
        IVValue(peer, "sar_setup_response_for_boomlet", 0),
        SarSetupResponseSignedBySAR(peer))

SarSetupResponseSuffixedByWT(peer) ==
    [ kind      |-> "WtSarSetupResponse",
      content   |-> SarSetupResponseSignedBySAREncryptedForBoomlet(peer),
      wt_suffix |-> "setup_sar_acknowledgement_of_finalization_received" ]

SarSetupResponseSuffixedByWTSigned(peer) ==
    SignatureOnMessage(WTActor, SarSetupResponseSuffixedByWT(peer))

SharedStateSarFinalization ==
    [ kind  |-> "SharedStateSarFinalization",
      magic |-> "setup_wt_received_sar_data" ]

SharedStateActiveSarFingerprint ==
    SHA256(SharedStateSarFinalization)

SharedStateActiveSarFingerprintSigned(peer) ==
    SignatureOnMessage(BoomletActor(peer), SharedStateActiveSarFingerprint)

AllPeersSharedStateActiveSarSigned ==
    Collection([p \in Peers |-> SharedStateActiveSarFingerprintSigned(p)])

Mystery(peer, device) ==
    [ kind       |-> "Mystery",
      peer       |-> peer,
      device     |-> device,
      lower_bound|-> MIN_TRIES_FOR_DIGGING_GAME_IN_BLOCKS,
      upper_bound|-> MAX_TRIES_FOR_DIGGING_GAME_IN_BLOCKS ]

BackupRequest(peer) ==
    [ kind                 |-> "BoomletBackupRequest",
      magic                |-> "boomlet_backup_request",
      backup_boomlet_pubkey|-> BoomletwoIdentityPubkey(peer),
      backup_normal_pubkey |-> NormalPubkey(peer) ]

BackupRequestSignedByNormal(peer) ==
    SignatureOnMessage(NormalPubkey(peer), BackupRequest(peer))

BoomletBackupPlaintext(peer) ==
    [ kind                     |-> "BoomletBackupPlaintext",
      excluded_fields          |-> {"mystery"},
      peer_id                  |-> PeerId(peer),
      normal_pubkey            |-> NormalPubkey(peer),
      boomlet_identity_privkey |-> BoomletIdentityPrivkey(peer),
      boomlet_identity_pubkey  |-> BoomletIdentityPubkey(peer),
      boom_musig2_privkey_share|-> BoomMusig2PrivkeyShare(peer),
      boom_musig2_pubkey_share |-> BoomMusig2PubkeyShare(peer),
      peer_tor_secret_key      |-> PeerTorSecretKey(peer),
      doxing_key               |-> DoxingKey(peer),
      sar_ids_collection       |-> SARIdsCollection(peer),
      network                  |-> Network,
      st_identity_pubkey       |-> STIdentityPubkey(peer),
      duress_consent_set       |-> StoredDuressConsentSet(peer),
      boomerang_params         |-> BoomerangParams,
      sar_setup_response       |-> SarSetupResponse(peer),
      counter                  |-> 0,
      reached_mystery_flag     |-> FALSE,
      mystery_exported         |-> FALSE ]

BoomletBackupEncryptedForBoomletwo(peer) ==
    EncryptedFor(
        BoomletwoActor(peer),
        BoomletActor(peer),
        IVValue(peer, "boomlet_backup_for_boomletwo", 0),
        BoomletBackupPlaintext(peer))

BackupDone(peer) ==
    [ kind                 |-> "BackupDone",
      magic                |-> "boomlet_backup_done",
      backup_boomlet_pubkey|-> BoomletwoIdentityPubkey(peer),
      boomlet_pubkey       |-> BoomletIdentityPubkey(peer) ]

BackupDoneSignedByBoomletwo(peer) ==
    SignatureOnMessage(BoomletwoActor(peer), BackupDone(peer))

SharedStateBackupDone ==
    [ kind  |-> "SharedStateBackupDone",
      magic |-> "boomlet_backup_done_and_setup_finish_initialized" ]

SharedStateActiveBackupFingerprint ==
    SHA256(SharedStateBackupDone)

SharedStateActiveBackupFingerprintSigned(peer) ==
    SignatureOnMessage(BoomletActor(peer), SharedStateActiveBackupFingerprint)

AllPeersSharedStateActiveBackupSigned ==
    Collection([p \in Peers |-> SharedStateActiveBackupFingerprintSigned(p)])

SetupPhoneInput1(peer) ==
    [ kind               |-> "SetupPhoneInput1",
      doxing_password    |-> DoxingPassword[peer],
      sar_ids_collection |-> SARIdsCollection(peer),
      static_doxing_data |-> StaticDoxingData[peer] ]

SetupPhoneSarMessage1(peer) ==
    [ kind                   |-> "SetupPhoneSarMessage1",
      doxing_data_identifier |-> DoxingDataIdentifier(peer) ]

SetupSarPhoneMessage1(peer) ==
    [ kind                         |-> "SetupSarPhoneMessage1",
      sar_service_fee_payment_info |-> SarServiceFeePaymentInfo(peer) ]

SetupPhoneOutput1(peer) ==
    [ kind                         |-> "SetupPhoneOutput1",
      sar_service_fee_payment_info |-> SarServiceFeePaymentInfo(peer) ]

SetupPhoneInput2(peer) ==
    [ kind                             |-> "SetupPhoneInput2",
      sar_service_fee_payment_receipts |-> SarServiceFeePaymentReceipts(peer) ]

SetupPhoneSarMessage2(peer) ==
    [ kind                                             |-> "SetupPhoneSarMessage2",
      sar_service_fee_payment_receipts                 |-> SarServiceFeePaymentReceipts(peer),
      static_doxing_data_encrypted_by_doxing_key       |-> StaticDoxingDataCipher(peer),
      doxing_data_identifier                           |-> DoxingDataIdentifier(peer),
      dynamic_doxing_data_encrypted_by_doxing_key      |-> DynamicDoxingDataCipher(peer) ]

SetupSarPhoneMessage2 ==
    [ kind  |-> "SetupSarPhoneMessage2",
      magic |-> "setup_sar_setup_done_and_in_sync_with_phone" ]

SetupPhoneOutput2 ==
    [ kind  |-> "SetupPhoneOutput2",
      magic |-> "setup_sar_registered_and_connected_to_phone" ]

SetupIsoInput1(peer) ==
    [ kind               |-> "SetupIsoInput1",
      network            |-> Network,
      entropy_bytes      |-> EntropyBytes[peer],
      passphrase         |-> Passphrase[peer],
      doxing_password    |-> DoxingPassword[peer],
      sar_ids_collection |-> SARIdsCollection(peer) ]

SetupIsoBoomletMessage1(peer) ==
    [ kind               |-> "SetupIsoBoomletMessage1",
      normal_pubkey_0    |-> NormalPubkey(peer),
      doxing_key         |-> DoxingKey(peer),
      sar_ids_collection |-> SARIdsCollection(peer),
      network            |-> Network ]

SetupBoomletIsoMessage1(peer) ==
    [ kind                      |-> "SetupBoomletIsoMessage1",
      boomlet_0_identity_pubkey |-> BoomletIdentityPubkey(peer) ]

SetupIsoStMessage1(peer) ==
    [ kind                      |-> "SetupIsoStMessage1",
      boomlet_0_identity_pubkey |-> BoomletIdentityPubkey(peer) ]

SetupStIsoMessage1(peer) ==
    [ kind                 |-> "SetupStIsoMessage1",
      st_0_identity_pubkey |-> STIdentityPubkey(peer) ]

SetupIsoBoomletMessage2(peer) ==
    [ kind                 |-> "SetupIsoBoomletMessage2",
      st_0_identity_pubkey |-> STIdentityPubkey(peer) ]

SetupBoomletIsoMessage2(peer) ==
    [ kind                                                     |-> "SetupBoomletIsoMessage2",
      duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st |-> DuressCheckCipher(peer, "enroll", FirstDuressSpace(peer), EnrollmentNonce(peer)) ]

SetupIsoStMessage2(peer) ==
    [ kind                                                     |-> "SetupIsoStMessage2",
      duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st |-> DuressCheckCipher(peer, "enroll", FirstDuressSpace(peer), EnrollmentNonce(peer)) ]

SetupStOutput1(peer) ==
    [ kind                |-> "SetupStOutput1",
      duress_check_space  |-> FirstDuressSpace(peer) ]

SetupStInput1(peer) ==
    [ kind                 |-> "SetupStInput1",
      duress_signal_index  |-> EnrollmentSignalIndex(peer) ]

SetupStIsoMessage2(peer) ==
    [ kind                                                        |-> "SetupStIsoMessage2",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 |-> DuressReplyCipher(peer, "enroll", EnrollmentSignalIndex(peer), EnrollmentNonce(peer)) ]

SetupIsoBoomletMessage3(peer) ==
    [ kind                                                        |-> "SetupIsoBoomletMessage3",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 |-> DuressReplyCipher(peer, "enroll", EnrollmentSignalIndex(peer), EnrollmentNonce(peer)) ]

SetupBoomletIsoMessage3(peer) ==
    [ kind                                                     |-> "SetupBoomletIsoMessage3",
      duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st |-> DuressCheckCipher(peer, "confirm", SecondDuressSpace(peer), ConfirmationNonce(peer)) ]

SetupIsoStMessage3(peer) ==
    [ kind                                                     |-> "SetupIsoStMessage3",
      duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st |-> DuressCheckCipher(peer, "confirm", SecondDuressSpace(peer), ConfirmationNonce(peer)) ]

SetupStOutput2(peer) ==
    [ kind               |-> "SetupStOutput2",
      duress_check_space |-> SecondDuressSpace(peer) ]

SetupStInput2(peer) ==
    [ kind                |-> "SetupStInput2",
      duress_signal_index |-> ConfirmationSignalIndex(peer) ]

SetupStIsoMessage3(peer) ==
    [ kind                                                        |-> "SetupStIsoMessage3",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 |-> DuressReplyCipher(peer, "confirm", ConfirmationSignalIndex(peer), ConfirmationNonce(peer)) ]

SetupIsoBoomletMessage4(peer) ==
    [ kind                                                        |-> "SetupIsoBoomletMessage4",
      duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 |-> DuressReplyCipher(peer, "confirm", ConfirmationSignalIndex(peer), ConfirmationNonce(peer)) ]

SetupBoomletIsoMessage4 ==
    [ kind  |-> "SetupBoomletIsoMessage4",
      magic |-> "setup_duress_finished" ]

SetupIsoOutput1(peer) ==
    [ kind     |-> "SetupIsoOutput1",
      mnemonic |-> Mnemonic(peer) ]

SetupNisoInput1(peer) ==
    [ kind            |-> "SetupNisoInput1",
      network         |-> Network,
      rpc_client_url  |-> RpcClientUrl[peer],
      rpc_client_auth |-> RpcClientAuth[peer] ]

SetupNisoBoomletMessage1 ==
    [ kind  |-> "SetupNisoBoomletMessage1",
      magic |-> "setup_initialized" ]

SetupBoomletNisoMessage1(peer) ==
    [ kind                                      |-> "SetupBoomletNisoMessage1",
      peer_0_id                                 |-> PeerId(peer),
      peer_0_tor_secret_key                     |-> PeerTorSecretKey(peer),
      peer_0_tor_address_signed_by_boomlet_0    |-> PeerTorAddressSignedByBoomlet(peer) ]

SetupNisoStMessage1(peer) ==
    [ kind                                   |-> "SetupNisoStMessage1",
      peer_0_id                              |-> PeerId(peer),
      peer_0_tor_address_signed_by_boomlet_0 |-> PeerTorAddressSignedByBoomlet(peer) ]

SetupStOutput3(peer) ==
    [ kind                                   |-> "SetupStOutput3",
      peer_0_id                              |-> PeerId(peer),
      peer_0_tor_address_signed_by_boomlet_0 |-> PeerTorAddressSignedByBoomlet(peer) ]

SetupUserPeersOutOfBandMessage1(payload) ==
    [ kind    |-> "SetupUserPeersOutOfBandMessage1",
      payload |-> payload ]

SetupNisoInput2 ==
    [ kind                       |-> "SetupNisoInput2",
      peer_addresses_collection  |-> PeerAddressesCollection,
      wt_ids_collection          |-> WTIdsCollection,
      milestone_block_collection |-> MilestoneBlockCollection ]

SetupNisoBoomletMessage2 ==
    [ kind                       |-> "SetupNisoBoomletMessage2",
      peer_addresses_collection  |-> PeerAddressesCollection,
      wt_ids_collection          |-> WTIdsCollection,
      milestone_block_collection |-> MilestoneBlockCollection ]

SetupBoomletNisoMessage2(peer) ==
    [ kind                                             |-> "SetupBoomletNisoMessage2",
      boomerang_params_seed_encrypted_by_boomlet_0_for_st |-> BoomerangParamsSeedCipher(peer) ]

SetupNisoStMessage2(peer) ==
    [ kind                                             |-> "SetupNisoStMessage2",
      boomerang_params_seed_encrypted_by_boomlet_0_for_st |-> BoomerangParamsSeedCipher(peer) ]

SetupStOutput4 ==
    [ kind                   |-> "SetupStOutput4",
      boomerang_params_seed  |-> BoomerangParamsSeed ]

SetupStInput3 ==
    [ kind  |-> "SetupStInput3",
      magic |-> "setup_user_verified_peer_ids_and_wt_ids_received_with_those_registered_before" ]

SetupStNisoMessage1(peer) ==
    [ kind                                                                  |-> "SetupStNisoMessage1",
      boomerang_params_seed_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_0 |-> BoomerangParamsSeedAckCipher(peer) ]

SetupNisoBoomletMessage3(peer) ==
    [ kind                                                                  |-> "SetupNisoBoomletMessage3",
      boomerang_params_seed_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_0 |-> BoomerangParamsSeedAckCipher(peer) ]

SetupBoomletNisoMessage3(peer) ==
    [ kind                                |-> "SetupBoomletNisoMessage3",
      boomerang_params_signed_by_boomlet_0 |-> SignedBoomerangParams(peer) ]

SetupNisoPeerNisoMessage1(payload) ==
    [ kind                                  |-> "SetupNisoPeerNisoMessage1",
      boomerang_params_signed_by_boomlet_i  |-> payload ]

SetupNisoBoomletMessage4 ==
    [ kind                              |-> "SetupNisoBoomletMessage4",
      boomerang_params_signed_by_all_peers |-> AllPeersSignedBoomerangParams ]

SetupBoomletNisoMessage4 ==
    [ kind  |-> "SetupBoomletNisoMessage4",
      magic |-> "setup_boomerang_params_fixed" ]

SetupNisoBoomletMessage5 ==
    [ kind  |-> "SetupNisoBoomletMessage5",
      magic |-> "setup_boomerang_params_fixed_boomlet_can_draw_mystery" ]

SetupBoomletNisoMessage5(peer) ==
    [ kind                                                        |-> "SetupBoomletNisoMessage5",
      sorted_all_peers_boomlet_identity_pubkeys_signed_by_boomlet_0 |-> SortedAllPeersBoomletIdentityPubkeysSigned(peer),
      boomerang_params_fingerprint_signed_by_boomlet_0           |-> BoomerangParamsFingerprintSignedByBoomlet(peer) ]

SetupNisoWtMessage1(peer) ==
    [ kind                                                        |-> "SetupNisoWtMessage1",
      boomlet_0_identity_pubkey                                   |-> BoomletIdentityPubkey(peer),
      sorted_all_peers_boomlet_identity_pubkeys_signed_by_boomlet_0 |-> SortedAllPeersBoomletIdentityPubkeysSigned(peer),
      peer_0_tor_address_signed_by_boomlet_0                     |-> PeerTorAddressSignedByBoomlet(peer),
      boomerang_params_fingerprint_signed_by_boomlet_0           |-> BoomerangParamsFingerprintSignedByBoomlet(peer) ]

SetupNisoWtMessage1PeerI(peer) ==
    [ kind                         |-> "SetupNisoWtMessage1",
      boomlet_i_identity_pubkey     |-> BoomletIdentityPubkey(peer),
      sorted_all_peers_boomlet_identity_pubkeys_signed_by_boomlet_i |-> SortedAllPeersBoomletIdentityPubkeysSigned(peer),
      peer_i_tor_address_signed_by_boomlet_i |-> PeerTorAddressSignedByBoomlet(peer),
      boomerang_params_fingerprint_signed_by_boomlet_i |-> BoomerangParamsFingerprintSignedByBoomlet(peer) ]

SetupWtNisoMessage1(peer) ==
    [ kind                        |-> "SetupWtNisoMessage1",
      wt_service_fee_payment_info |-> WTServiceFeePaymentInfo(peer) ]

SetupNisoOutput1(peer) ==
    [ kind                        |-> "SetupNisoOutput1",
      wt_service_fee_payment_info |-> WTServiceFeePaymentInfo(peer) ]

SetupNisoInput3(peer) ==
    [ kind                           |-> "SetupNisoInput3",
      wt_service_fee_payment_receipt |-> WTServiceFeePaymentReceipt(peer) ]

SetupNisoWtMessage2(peer) ==
    [ kind                           |-> "SetupNisoWtMessage2",
      wt_service_fee_payment_receipt |-> WTServiceFeePaymentReceipt(peer) ]

SetupWtNisoMessage2 ==
    [ kind                                                |-> "SetupWtNisoMessage2",
      boomerang_params_fingerprint_suffixed_by_wt_signed_by_wt |-> BoomerangParamsFingerprintSuffixedByWTSigned ]

SetupNisoBoomletMessage6 ==
    [ kind                                                |-> "SetupNisoBoomletMessage6",
      boomerang_params_fingerprint_suffixed_by_wt_signed_by_wt |-> BoomerangParamsFingerprintSuffixedByWTSigned ]

SetupBoomletNisoMessage6(peer) ==
    [ kind                                                |-> "SetupBoomletNisoMessage6",
      shared_state_active_wt_fingerprint_signed_by_boomlet_0 |-> SharedStateActiveWTFingerprintSigned(peer) ]

SetupNisoPeerNisoMessage2(payload) ==
    [ kind                                                |-> "SetupNisoPeerNisoMessage2",
      shared_state_active_wt_fingerprint_signed_by_boomlet_i |-> payload ]

SetupNisoBoomletMessage7 ==
    [ kind                                                |-> "SetupNisoBoomletMessage7",
      shared_state_active_wt_fingerprint_signed_by_all_peers |-> AllPeersSharedStateActiveWTSigned ]

SetupBoomletNisoMessage7 ==
    [ kind  |-> "SetupBoomletNisoMessage7",
      magic |-> "setup_wt_service_confirmed_by_peers" ]

SetupNisoBoomletMessage8 ==
    [ kind  |-> "SetupNisoBoomletMessage8",
      magic |-> "setup_wt_service_confirmed_by_peers_sars_can_be_finalized" ]

SetupBoomletNisoMessage8(peer) ==
    [ kind                                                     |-> "SetupBoomletNisoMessage8",
      sar_ids_collection_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt |-> SarIdsCollectionSignedByBoomletEncryptedForWT(peer),
      doxing_data_identifier_encrypted_by_boomlet_0_for_sar   |-> DoxingDataIdentifierEncryptedForSAR(peer) ]

SetupNisoWtMessage3(peer) ==
    [ kind                                                     |-> "SetupNisoWtMessage3",
      sar_ids_collection_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt |-> SarIdsCollectionSignedByBoomletEncryptedForWT(peer),
      doxing_data_identifier_encrypted_by_boomlet_0_for_sar   |-> DoxingDataIdentifierEncryptedForSAR(peer) ]

SetupWtSarMessage1(peer) ==
    [ kind                                                   |-> "SetupWtSarMessage1",
      doxing_data_identifier_encrypted_by_boomlet_0_for_sar |-> DoxingDataIdentifierEncryptedForSAR(peer),
      boomlet_0_identity_pubkey                              |-> BoomletIdentityPubkey(peer) ]

SetupSarWtMessage1(peer) ==
    [ kind                                                     |-> "SetupSarWtMessage1",
      sar_setup_response_signed_by_sar_encrypted_by_sar_for_boomlet_0 |-> SarSetupResponseSignedBySAREncryptedForBoomlet(peer) ]

SetupWtNisoMessage3(peer) ==
    [ kind                                                                  |-> "SetupWtNisoMessage3",
      sar_setup_response_signed_by_sar_encrypted_by_sar_for_boomlet_0_suffixed_by_wt_signed_by_wt |-> SarSetupResponseSuffixedByWTSigned(peer) ]

SetupNisoBoomletMessage9(peer) ==
    [ kind                                                                  |-> "SetupNisoBoomletMessage9",
      sar_setup_response_signed_by_sar_encrypted_by_sar_for_boomlet_0_suffixed_by_wt_signed_by_wt |-> SarSetupResponseSuffixedByWTSigned(peer) ]

SetupBoomletNisoMessage9(peer) ==
    [ kind                                                |-> "SetupBoomletNisoMessage9",
      shared_state_active_sar_fingerprint_signed_by_boomlet_0 |-> SharedStateActiveSarFingerprintSigned(peer) ]

SetupNisoPeerNisoMessage3(payload) ==
    [ kind                                                |-> "SetupNisoPeerNisoMessage3",
      shared_state_active_sar_fingerprint_signed_by_boomlet_i |-> payload ]

SetupNisoBoomletMessage10 ==
    [ kind                                                 |-> "SetupNisoBoomletMessage10",
      shared_state_active_sar_fingerprint_signed_by_all_peers |-> AllPeersSharedStateActiveSarSigned ]

SetupBoomletNisoMessage10 ==
    [ kind  |-> "SetupBoomletNisoMessage10",
      magic |-> "setup_sar_acknowledgement_of_finalization_received" ]

SetupNisoOutput2 ==
    [ kind  |-> "SetupNisoOutput2",
      magic |-> "setup_sar_finalization_confirmed" ]

SetupIsoInput2 ==
    [ kind  |-> "SetupIsoInput2",
      magic |-> "setup_user_is_informed_that_sar_is_set_and_can_install_boomlet_backup" ]

SetupIsoBoomletwo1 ==
    [ kind  |-> "SetupIsoBoomletwo1",
      magic |-> "setup_backup_started" ]

SetupBoomletwoIso1(peer) ==
    [ kind                    |-> "SetupBoomletwoIso1",
      boomletwo_Identity_pubkey |-> BoomletwoIdentityPubkey(peer) ]

SetupIsoOutput2 ==
    [ kind  |-> "SetupIsoOutput2",
      magic |-> "setup_boomletwo_identity_pubkey_received_connect_boomlet_to_iso" ]

SetupIsoInput3(peer) ==
    [ kind                       |-> "SetupIsoInput3",
      milestone_block_collection |-> MilestoneBlockCollection,
      network                    |-> Network,
      mnemonic                   |-> Mnemonic(peer),
      passphrase                 |-> Passphrase[peer],
      static_doxing_data         |-> StaticDoxingData[peer],
      doxing_password            |-> DoxingPassword[peer] ]

SetupIsoBoomletMessage5(peer) ==
    [ kind                         |-> "SetupIsoBoomletMessage5",
      backup_request_signed_by_normal_0 |-> BackupRequestSignedByNormal(peer) ]

SetupBoomletIsoMessage5(peer) ==
    [ kind                                           |-> "SetupBoomletIsoMessage5",
      boomlet_0_identity_pubkey                      |-> BoomletIdentityPubkey(peer),
      boomlet_0_backup_encrypted_by_boomlet_0_for_boomletwo |-> BoomletBackupEncryptedForBoomletwo(peer),
      boomerang_params                               |-> BoomerangParams,
      sar_setup_response                             |-> SarSetupResponse(peer) ]

SetupIsoOutput3 ==
    [ kind  |-> "SetupIsoOutput3",
      magic |-> "setup_boomlet_backup_data_received_connect_boomletwo_to_iso" ]

SetupIsoInput4 ==
    [ kind  |-> "SetupIsoInput4",
      magic |-> "setup_user_is_asked_to_connect_boomletwo_to_iso_boomletwo_connected_to_iso" ]

SetupIsoBoomletwo2(peer) ==
    [ kind                                           |-> "SetupIsoBoomletwo2",
      boomlet_0_identity_pubkey                      |-> BoomletIdentityPubkey(peer),
      boomlet_0_backup_encrypted_by_boomlet_0_for_boomletwo |-> BoomletBackupEncryptedForBoomletwo(peer) ]

SetupBoomletwoIso2(peer) ==
    [ kind                          |-> "SetupBoomletwoIso2",
      backup_done_signed_by_boomletwo |-> BackupDoneSignedByBoomletwo(peer) ]

SetupIsoOutput4 ==
    [ kind  |-> "SetupIsoOutput4",
      magic |-> "setup_boomlet_backup_done_connect_boomlet_to_iso" ]

SetupIsoInput5 ==
    [ kind  |-> "SetupIsoInput5",
      magic |-> "setup_user_is_asked_to_connect_boomlet_to_iso_boomlet_connected_to_iso" ]

SetupIsoBoomletMessage6(peer) ==
    [ kind                          |-> "SetupIsoBoomletMessage6",
      backup_done_signed_by_boomletwo |-> BackupDoneSignedByBoomletwo(peer) ]

SetupBoomletIsoMessage6 ==
    [ kind  |-> "SetupBoomletIsoMessage6",
      magic |-> "setup_boomlet_backup_done" ]

SetupIsoOutput5 ==
    [ kind  |-> "SetupIsoOutput5",
      magic |-> "setup_boomlet_backup_completed_boomlet_closed_ready_to_finish_setup" ]

SetupNisoInput4 ==
    [ kind  |-> "SetupNisoInput4",
      magic |-> "setup_user_is_informed_that_boomlet_is_closed" ]

SetupNisoBoomletMessage11 ==
    [ kind  |-> "SetupNisoBoomletMessage11",
      magic |-> "setup_boomlet_closed_finish_setup" ]

SetupBoomletNisoMessage11(peer) ==
    [ kind                                                  |-> "SetupBoomletNisoMessage11",
      shared_state_active_backup_fingerprint_signed_by_boomlet_0 |-> SharedStateActiveBackupFingerprintSigned(peer) ]

SetupNisoPeerNisoMessage4(payload) ==
    [ kind                                                  |-> "SetupNisoPeerNisoMessage4",
      shared_state_active_backup_fingerprint_signed_by_boomlet_i |-> payload ]

SetupNisoBoomletMessage12 ==
    [ kind                                                   |-> "SetupNisoBoomletMessage12",
      shared_state_active_backup_fingerprint_signed_by_all_peers |-> AllPeersSharedStateActiveBackupSigned ]

SetupBoomletNisoMessage12 ==
    [ kind  |-> "SetupBoomletNisoMessage12",
      magic |-> "setup_done" ]

SetupNisoOutput3 ==
    [ kind  |-> "SetupNisoOutput3",
      magic |-> "setup_done" ]

CanonicalWireMessageKinds ==
    {
      "SetupPhoneInput1",
      "SetupPhoneSarMessage1",
      "SetupSarPhoneMessage1",
      "SetupPhoneOutput1",
      "SetupPhoneInput2",
      "SetupPhoneSarMessage2",
      "SetupSarPhoneMessage2",
      "SetupPhoneOutput2",
      "SetupIsoInput1",
      "SetupIsoBoomletMessage1",
      "SetupBoomletIsoMessage1",
      "SetupIsoStMessage1",
      "SetupStIsoMessage1",
      "SetupIsoBoomletMessage2",
      "SetupBoomletIsoMessage2",
      "SetupIsoStMessage2",
      "SetupStOutput1",
      "SetupStInput1",
      "SetupStIsoMessage2",
      "SetupIsoBoomletMessage3",
      "SetupBoomletIsoMessage3",
      "SetupIsoStMessage3",
      "SetupStOutput2",
      "SetupStInput2",
      "SetupStIsoMessage3",
      "SetupIsoBoomletMessage4",
      "SetupBoomletIsoMessage4",
      "SetupIsoOutput1",
      "SetupNisoInput1",
      "SetupNisoBoomletMessage1",
      "SetupBoomletNisoMessage1",
      "SetupNisoStMessage1",
      "SetupStOutput3",
      "SetupUserPeersOutOfBandMessage1",
      "SetupNisoInput2",
      "SetupNisoBoomletMessage2",
      "SetupBoomletNisoMessage2",
      "SetupNisoStMessage2",
      "SetupStOutput4",
      "SetupStInput3",
      "SetupStNisoMessage1",
      "SetupNisoBoomletMessage3",
      "SetupBoomletNisoMessage3",
      "SetupNisoPeerNisoMessage1",
      "SetupNisoBoomletMessage4",
      "SetupBoomletNisoMessage4",
      "SetupNisoBoomletMessage5",
      "SetupBoomletNisoMessage5",
      "SetupNisoWtMessage1",
      "SetupWtNisoMessage1",
      "SetupNisoOutput1",
      "SetupNisoInput3",
      "SetupNisoWtMessage2",
      "SetupWtNisoMessage2",
      "SetupNisoBoomletMessage6",
      "SetupBoomletNisoMessage6",
      "SetupNisoPeerNisoMessage2",
      "SetupNisoBoomletMessage7",
      "SetupBoomletNisoMessage7",
      "SetupNisoBoomletMessage8",
      "SetupBoomletNisoMessage8",
      "SetupNisoWtMessage3",
      "SetupWtSarMessage1",
      "SetupSarWtMessage1",
      "SetupWtNisoMessage3",
      "SetupNisoBoomletMessage9",
      "SetupBoomletNisoMessage9",
      "SetupNisoPeerNisoMessage3",
      "SetupNisoBoomletMessage10",
      "SetupBoomletNisoMessage10",
      "SetupNisoOutput2",
      "SetupIsoInput2",
      "SetupIsoBoomletwo1",
      "SetupBoomletwoIso1",
      "SetupIsoOutput2",
      "SetupIsoInput3",
      "SetupIsoBoomletMessage5",
      "SetupBoomletIsoMessage5",
      "SetupIsoOutput3",
      "SetupIsoInput4",
      "SetupIsoBoomletwo2",
      "SetupBoomletwoIso2",
      "SetupIsoOutput4",
      "SetupIsoInput5",
      "SetupIsoBoomletMessage6",
      "SetupBoomletIsoMessage6",
      "SetupIsoOutput5",
      "SetupNisoInput4",
      "SetupNisoBoomletMessage11",
      "SetupBoomletNisoMessage11",
      "SetupNisoPeerNisoMessage4",
      "SetupNisoBoomletMessage12",
      "SetupBoomletNisoMessage12",
      "SetupNisoOutput3"
    }

SarSignupTrace(peer) ==
    <<
      WireHop(1, UserActor(peer), PhoneActor(peer), SetupPhoneInput1(peer)),
      WireHop(2, PhoneActor(peer), SARActor(peer), SetupPhoneSarMessage1(peer)),
      WireHop(3, SARActor(peer), PhoneActor(peer), SetupSarPhoneMessage1(peer)),
      WireHop(4, PhoneActor(peer), UserActor(peer), SetupPhoneOutput1(peer)),
      WireHop(5, UserActor(peer), PhoneActor(peer), SetupPhoneInput2(peer)),
      WireHop(6, PhoneActor(peer), SARActor(peer), SetupPhoneSarMessage2(peer)),
      WireHop(7, SARActor(peer), PhoneActor(peer), SetupSarPhoneMessage2),
      WireHop(8, PhoneActor(peer), UserActor(peer), SetupPhoneOutput2)
    >>

DuressSetupTrace(peer) ==
    <<
      WireHop(9, UserActor(peer), IsoActor(peer), SetupIsoInput1(peer)),
      WireHop(10, IsoActor(peer), BoomletActor(peer), SetupIsoBoomletMessage1(peer)),
      WireHop(11, BoomletActor(peer), IsoActor(peer), SetupBoomletIsoMessage1(peer)),
      WireHop(12, IsoActor(peer), STActor(peer), SetupIsoStMessage1(peer)),
      WireHop(13, STActor(peer), IsoActor(peer), SetupStIsoMessage1(peer)),
      WireHop(14, IsoActor(peer), BoomletActor(peer), SetupIsoBoomletMessage2(peer)),
      WireHop(15, BoomletActor(peer), IsoActor(peer), SetupBoomletIsoMessage2(peer)),
      WireHop(16, IsoActor(peer), STActor(peer), SetupIsoStMessage2(peer)),
      WireHop(17, STActor(peer), UserActor(peer), SetupStOutput1(peer)),
      WireHop(18, UserActor(peer), STActor(peer), SetupStInput1(peer)),
      WireHop(19, STActor(peer), IsoActor(peer), SetupStIsoMessage2(peer)),
      WireHop(20, IsoActor(peer), BoomletActor(peer), SetupIsoBoomletMessage3(peer)),
      WireHop(21, BoomletActor(peer), IsoActor(peer), SetupBoomletIsoMessage3(peer)),
      WireHop(22, IsoActor(peer), STActor(peer), SetupIsoStMessage3(peer)),
      WireHop(23, STActor(peer), UserActor(peer), SetupStOutput2(peer)),
      WireHop(24, UserActor(peer), STActor(peer), SetupStInput2(peer)),
      WireHop(25, STActor(peer), IsoActor(peer), SetupStIsoMessage3(peer)),
      WireHop(26, IsoActor(peer), BoomletActor(peer), SetupIsoBoomletMessage4(peer)),
      WireHop(27, BoomletActor(peer), IsoActor(peer), SetupBoomletIsoMessage4)
    >>

BoomerangParamsSetupTrace(peer) ==
    <<
      WireHop(28, IsoActor(peer), UserActor(peer), SetupIsoOutput1(peer)),
      WireHop(29, UserActor(peer), NisoActor(peer), SetupNisoInput1(peer)),
      WireHop(30, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage1),
      WireHop(31, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage1(peer)),
      WireHop(32, NisoActor(peer), STActor(peer), SetupNisoStMessage1(peer)),
      WireHop(33, STActor(peer), UserActor(peer), SetupStOutput3(peer)),
      WireHop(34, UserActor(peer), UserActor(OtherPeer(peer, 1)), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayload0(peer))),
      WireHop(34, UserActor(peer), UserActor(OtherPeer(peer, 2)), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayload0(peer))),
      WireHop(34, UserActor(peer), UserActor(OtherPeer(peer, 3)), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayload0(peer))),
      WireHop(34, UserActor(peer), UserActor(OtherPeer(peer, 4)), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayload0(peer))),
      WireHop(34, UserActor(OtherPeer(peer, 1)), UserActor(peer), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayloadI(OtherPeer(peer, 1)))),
      WireHop(34, UserActor(OtherPeer(peer, 2)), UserActor(peer), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayloadI(OtherPeer(peer, 2)))),
      WireHop(34, UserActor(OtherPeer(peer, 3)), UserActor(peer), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayloadI(OtherPeer(peer, 3)))),
      WireHop(34, UserActor(OtherPeer(peer, 4)), UserActor(peer), SetupUserPeersOutOfBandMessage1(PeerAddressExchangePayloadI(OtherPeer(peer, 4)))),
      WireHop(35, UserActor(peer), NisoActor(peer), SetupNisoInput2),
      WireHop(36, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage2),
      WireHop(37, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage2(peer)),
      WireHop(38, NisoActor(peer), STActor(peer), SetupNisoStMessage2(peer)),
      WireHop(39, STActor(peer), UserActor(peer), SetupStOutput4),
      WireHop(40, UserActor(peer), STActor(peer), SetupStInput3),
      WireHop(41, STActor(peer), NisoActor(peer), SetupStNisoMessage1(peer)),
      WireHop(42, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage3(peer)),
      WireHop(43, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage3(peer)),
      WireHop(44, NisoActor(peer), NisoActor(OtherPeer(peer, 1)), SetupNisoPeerNisoMessage1(SignedBoomerangParams(peer))),
      WireHop(44, NisoActor(peer), NisoActor(OtherPeer(peer, 2)), SetupNisoPeerNisoMessage1(SignedBoomerangParams(peer))),
      WireHop(44, NisoActor(peer), NisoActor(OtherPeer(peer, 3)), SetupNisoPeerNisoMessage1(SignedBoomerangParams(peer))),
      WireHop(44, NisoActor(peer), NisoActor(OtherPeer(peer, 4)), SetupNisoPeerNisoMessage1(SignedBoomerangParams(peer))),
      WireHop(44, NisoActor(OtherPeer(peer, 1)), NisoActor(peer), SetupNisoPeerNisoMessage1(SignedBoomerangParams(OtherPeer(peer, 1)))),
      WireHop(44, NisoActor(OtherPeer(peer, 2)), NisoActor(peer), SetupNisoPeerNisoMessage1(SignedBoomerangParams(OtherPeer(peer, 2)))),
      WireHop(44, NisoActor(OtherPeer(peer, 3)), NisoActor(peer), SetupNisoPeerNisoMessage1(SignedBoomerangParams(OtherPeer(peer, 3)))),
      WireHop(44, NisoActor(OtherPeer(peer, 4)), NisoActor(peer), SetupNisoPeerNisoMessage1(SignedBoomerangParams(OtherPeer(peer, 4)))),
      WireHop(45, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage4),
      WireHop(46, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage4),
      WireHop(47, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage5)
    >>

WatchtowerActivationTrace(peer) ==
    <<
      WireHop(48, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage5(peer)),
      WireHop(49, NisoActor(peer), WTActor, SetupNisoWtMessage1(peer)),
      WireHop(49, NisoActor(OtherPeer(peer, 1)), WTActor, SetupNisoWtMessage1PeerI(OtherPeer(peer, 1))),
      WireHop(49, NisoActor(OtherPeer(peer, 2)), WTActor, SetupNisoWtMessage1PeerI(OtherPeer(peer, 2))),
      WireHop(49, NisoActor(OtherPeer(peer, 3)), WTActor, SetupNisoWtMessage1PeerI(OtherPeer(peer, 3))),
      WireHop(49, NisoActor(OtherPeer(peer, 4)), WTActor, SetupNisoWtMessage1PeerI(OtherPeer(peer, 4))),
      WireHop(50, WTActor, NisoActor(peer), SetupWtNisoMessage1(peer)),
      WireHop(51, NisoActor(peer), UserActor(peer), SetupNisoOutput1(peer)),
      WireHop(52, UserActor(peer), NisoActor(peer), SetupNisoInput3(peer)),
      WireHop(53, NisoActor(peer), WTActor, SetupNisoWtMessage2(peer)),
      WireHop(54, WTActor, NisoActor(peer), SetupWtNisoMessage2),
      WireHop(55, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage6),
      WireHop(56, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage6(peer)),
      WireHop(57, NisoActor(peer), NisoActor(OtherPeer(peer, 1)), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(peer))),
      WireHop(57, NisoActor(peer), NisoActor(OtherPeer(peer, 2)), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(peer))),
      WireHop(57, NisoActor(peer), NisoActor(OtherPeer(peer, 3)), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(peer))),
      WireHop(57, NisoActor(peer), NisoActor(OtherPeer(peer, 4)), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(peer))),
      WireHop(57, NisoActor(OtherPeer(peer, 1)), NisoActor(peer), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(OtherPeer(peer, 1)))),
      WireHop(57, NisoActor(OtherPeer(peer, 2)), NisoActor(peer), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(OtherPeer(peer, 2)))),
      WireHop(57, NisoActor(OtherPeer(peer, 3)), NisoActor(peer), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(OtherPeer(peer, 3)))),
      WireHop(57, NisoActor(OtherPeer(peer, 4)), NisoActor(peer), SetupNisoPeerNisoMessage2(SharedStateActiveWTFingerprintSigned(OtherPeer(peer, 4)))),
      WireHop(58, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage7),
      WireHop(59, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage7),
      WireHop(60, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage8)
    >>

SarActivationTrace(peer) ==
    <<
      WireHop(61, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage8(peer)),
      WireHop(62, NisoActor(peer), WTActor, SetupNisoWtMessage3(peer)),
      WireHop(63, WTActor, SARActor(peer), SetupWtSarMessage1(peer)),
      WireHop(64, SARActor(peer), WTActor, SetupSarWtMessage1(peer)),
      WireHop(65, WTActor, NisoActor(peer), SetupWtNisoMessage3(peer)),
      WireHop(66, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage9(peer)),
      WireHop(67, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage9(peer)),
      WireHop(68, NisoActor(peer), NisoActor(OtherPeer(peer, 1)), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(peer))),
      WireHop(68, NisoActor(peer), NisoActor(OtherPeer(peer, 2)), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(peer))),
      WireHop(68, NisoActor(peer), NisoActor(OtherPeer(peer, 3)), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(peer))),
      WireHop(68, NisoActor(peer), NisoActor(OtherPeer(peer, 4)), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(peer))),
      WireHop(68, NisoActor(OtherPeer(peer, 1)), NisoActor(peer), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(OtherPeer(peer, 1)))),
      WireHop(68, NisoActor(OtherPeer(peer, 2)), NisoActor(peer), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(OtherPeer(peer, 2)))),
      WireHop(68, NisoActor(OtherPeer(peer, 3)), NisoActor(peer), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(OtherPeer(peer, 3)))),
      WireHop(68, NisoActor(OtherPeer(peer, 4)), NisoActor(peer), SetupNisoPeerNisoMessage3(SharedStateActiveSarFingerprintSigned(OtherPeer(peer, 4)))),
      WireHop(69, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage10),
      WireHop(70, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage10),
      WireHop(71, NisoActor(peer), UserActor(peer), SetupNisoOutput2)
    >>

BackupActivationTrace(peer) ==
    <<
      WireHop(72, UserActor(peer), IsoActor(peer), SetupIsoInput2),
      WireHop(73, IsoActor(peer), BoomletwoActor(peer), SetupIsoBoomletwo1),
      WireHop(74, BoomletwoActor(peer), IsoActor(peer), SetupBoomletwoIso1(peer)),
      WireHop(75, IsoActor(peer), UserActor(peer), SetupIsoOutput2),
      WireHop(76, UserActor(peer), IsoActor(peer), SetupIsoInput3(peer)),
      WireHop(77, IsoActor(peer), BoomletActor(peer), SetupIsoBoomletMessage5(peer)),
      WireHop(78, BoomletActor(peer), IsoActor(peer), SetupBoomletIsoMessage5(peer)),
      WireHop(79, IsoActor(peer), UserActor(peer), SetupIsoOutput3),
      WireHop(80, UserActor(peer), IsoActor(peer), SetupIsoInput4),
      WireHop(81, IsoActor(peer), BoomletwoActor(peer), SetupIsoBoomletwo2(peer)),
      WireHop(82, BoomletwoActor(peer), IsoActor(peer), SetupBoomletwoIso2(peer)),
      WireHop(83, IsoActor(peer), UserActor(peer), SetupIsoOutput4),
      WireHop(84, UserActor(peer), IsoActor(peer), SetupIsoInput5),
      WireHop(85, IsoActor(peer), BoomletActor(peer), SetupIsoBoomletMessage6(peer)),
      WireHop(86, BoomletActor(peer), IsoActor(peer), SetupBoomletIsoMessage6),
      WireHop(87, IsoActor(peer), UserActor(peer), SetupIsoOutput5),
      WireHop(88, UserActor(peer), NisoActor(peer), SetupNisoInput4),
      WireHop(89, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage11),
      WireHop(90, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage11(peer)),
      WireHop(91, NisoActor(peer), NisoActor(OtherPeer(peer, 1)), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(peer))),
      WireHop(91, NisoActor(peer), NisoActor(OtherPeer(peer, 2)), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(peer))),
      WireHop(91, NisoActor(peer), NisoActor(OtherPeer(peer, 3)), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(peer))),
      WireHop(91, NisoActor(peer), NisoActor(OtherPeer(peer, 4)), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(peer))),
      WireHop(91, NisoActor(OtherPeer(peer, 1)), NisoActor(peer), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(OtherPeer(peer, 1)))),
      WireHop(91, NisoActor(OtherPeer(peer, 2)), NisoActor(peer), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(OtherPeer(peer, 2)))),
      WireHop(91, NisoActor(OtherPeer(peer, 3)), NisoActor(peer), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(OtherPeer(peer, 3)))),
      WireHop(91, NisoActor(OtherPeer(peer, 4)), NisoActor(peer), SetupNisoPeerNisoMessage4(SharedStateActiveBackupFingerprintSigned(OtherPeer(peer, 4)))),
      WireHop(92, NisoActor(peer), BoomletActor(peer), SetupNisoBoomletMessage12),
      WireHop(93, BoomletActor(peer), NisoActor(peer), SetupBoomletNisoMessage12),
      WireHop(94, NisoActor(peer), UserActor(peer), SetupNisoOutput3)
    >>

SetupTraceForPeer(peer) ==
    SarSignupTrace(peer)
    \o DuressSetupTrace(peer)
    \o BoomerangParamsSetupTrace(peer)
    \o WatchtowerActivationTrace(peer)
    \o SarActivationTrace(peer)
    \o BackupActivationTrace(peer)

CanonicalSetupTranscript ==
    SetupTraceForPeer(LOCAL_PEER)

VARIABLES
    transcript_index,
    wire_trace

vars ==
    <<transcript_index, wire_trace>>

Init ==
    /\ transcript_index = 0
    /\ wire_trace = << >>

Next ==
    /\ transcript_index < Len(CanonicalSetupTranscript)
    /\ transcript_index' = transcript_index + 1
    /\ wire_trace' = Append(wire_trace, CanonicalSetupTranscript[transcript_index + 1])

Spec ==
    Init /\ [][Next]_vars

SetupDone ==
    transcript_index = Len(CanonicalSetupTranscript)

WireSurfaceOnlyCanonical ==
    \A hop \in SeqImage(wire_trace) :
        hop.message.kind \in CanonicalWireMessageKinds

TraceIsCanonicalPrefix ==
    /\ transcript_index \in 0..Len(CanonicalSetupTranscript)
    /\ IF transcript_index = 0
       THEN wire_trace = << >>
       ELSE wire_trace = SubSeq(CanonicalSetupTranscript, 1, transcript_index)

PeerAddressSignatureValid(peer) ==
    /\ ValidSig(PeerTorAddressSignedByBoomlet(peer), BoomletActor(peer))
    /\ SignedContent(PeerTorAddressSignedByBoomlet(peer)) = PeerTorAddress(peer)

PeerAddressesCollectionValid ==
    \A p \in Peers : PeerAddressSignatureValid(p)

DuressEnrollmentConfirmed(peer) ==
    StoredDuressConsentSet(peer)
        = Image(DerivedDuressSignal(SecondDuressSpace(peer), ConfirmationSignalIndex(peer)))

DescriptorUsesAgreedSetupInputs ==
    /\ BoomerangParams.boomerang_descriptor.network = Network
    /\ BoomerangParams.boomerang_descriptor.milestone_blocks = MilestoneBlocks
    /\ BoomerangParams.peer_ids_collection = PeerIdsCollection
    /\ BoomerangParams.wt_ids_collection = WTIdsCollection

ActiveServiceSelectionsMatchCollections ==
    /\ WTIdsCollection.items[1] = WTId
    /\ \A p \in Peers : SARIdsCollection(p).items[1] = SARId(p)

SharedFingerprintSignaturesValid(fingerprint, signedCollection) ==
    \A p \in Peers :
        /\ ValidSig(signedCollection.items[p], BoomletActor(p))
        /\ SignedContent(signedCollection.items[p]) = fingerprint

BoomerangParamsAgreementValid ==
    \A p \in Peers :
        /\ ValidSig(SignedBoomerangParams(p), BoomletActor(p))
        /\ SignedContent(SignedBoomerangParams(p)) = BoomerangParams

WTRegistrationSignaturesValid ==
    \A p \in Peers :
        /\ ValidSig(SortedAllPeersBoomletIdentityPubkeysSigned(p), BoomletActor(p))
        /\ SignedContent(SortedAllPeersBoomletIdentityPubkeysSigned(p)) = SortedAllPeerBoomletIdentityPubkeys
        /\ ValidSig(BoomerangParamsFingerprintSignedByBoomlet(p), BoomletActor(p))
        /\ SignedContent(BoomerangParamsFingerprintSignedByBoomlet(p)) = BoomerangParamsFingerprint
        /\ PeerAddressSignatureValid(p)

WTAcknowledgementBindsBoomerangParams ==
    /\ ValidSig(BoomerangParamsFingerprintSuffixedByWTSigned, WTActor)
    /\ SignedContent(BoomerangParamsFingerprintSuffixedByWTSigned).fingerprint = BoomerangParamsFingerprint
    /\ SignedContent(BoomerangParamsFingerprintSuffixedByWTSigned).suffix =
        "setup_peers_registration_with_wt_completed"

SARFinalizationBindsRegisteredDoxingData(peer) ==
    /\ CanDecrypt(DoxingDataIdentifierEncryptedForSAR(peer), SARActor(peer))
    /\ Decrypt(DoxingDataIdentifierEncryptedForSAR(peer), SARActor(peer)) = DoxingDataIdentifier(peer)
    /\ ValidSig(SarSetupResponseSignedBySAR(peer), SARActor(peer))
    /\ SignedContent(SarSetupResponseSignedBySAR(peer)).doxing_data_identifier = DoxingDataIdentifier(peer)
    /\ SignedContent(SarSetupResponseSignedBySAR(peer)).fingerprint_of_static_doxing_data_encrypted_by_doxing_key =
        StaticDoxingDataCipherFingerprint(peer)
    /\ ValidSig(SarSetupResponseSuffixedByWTSigned(peer), WTActor)
    /\ SignedContent(SarSetupResponseSuffixedByWTSigned(peer)).wt_suffix =
        "setup_sar_acknowledgement_of_finalization_received"

BackupPlaintextExcludesMystery(peer) ==
    /\ "mystery" \notin DOMAIN BoomletBackupPlaintext(peer)
    /\ "boomlet_mystery" \notin DOMAIN BoomletBackupPlaintext(peer)
    /\ BoomletBackupPlaintext(peer).mystery_exported = FALSE
    /\ "mystery" \in BoomletBackupPlaintext(peer).excluded_fields

BackupDoneValid(peer) ==
    /\ ValidSig(BackupRequestSignedByNormal(peer), NormalPubkey(peer))
    /\ SignedContent(BackupRequestSignedByNormal(peer)) = BackupRequest(peer)
    /\ CanDecrypt(BoomletBackupEncryptedForBoomletwo(peer), BoomletwoActor(peer))
    /\ Decrypt(BoomletBackupEncryptedForBoomletwo(peer), BoomletwoActor(peer)) = BoomletBackupPlaintext(peer)
    /\ BackupPlaintextExcludesMystery(peer)
    /\ ValidSig(BackupDoneSignedByBoomletwo(peer), BoomletwoActor(peer))
    /\ SignedContent(BackupDoneSignedByBoomletwo(peer)) = BackupDone(peer)

SetupDoneAfterBackupConsensus ==
    \A k \in 1..Len(wire_trace) :
        /\ wire_trace[k].message.kind = "SetupBoomletNisoMessage12"
        /\ wire_trace[k].message.magic = "setup_done"
        => \E j \in 1..(k - 1) :
            wire_trace[j].message.kind = "SetupNisoBoomletMessage12"

SetupMathematicalConsistency ==
    /\ PeerAddressesCollectionValid
    /\ DuressEnrollmentConfirmed(LOCAL_PEER)
    /\ DescriptorUsesAgreedSetupInputs
    /\ ActiveServiceSelectionsMatchCollections
    /\ BoomerangParamsAgreementValid
    /\ WTRegistrationSignaturesValid
    /\ WTAcknowledgementBindsBoomerangParams
    /\ SharedFingerprintSignaturesValid(
        SharedStateActiveWTFingerprint,
        AllPeersSharedStateActiveWTSigned)
    /\ SARFinalizationBindsRegisteredDoxingData(LOCAL_PEER)
    /\ SharedFingerprintSignaturesValid(
        SharedStateActiveSarFingerprint,
        AllPeersSharedStateActiveSarSigned)
    /\ BackupDoneValid(LOCAL_PEER)
    /\ SharedFingerprintSignaturesValid(
        SharedStateActiveBackupFingerprint,
        AllPeersSharedStateActiveBackupSigned)

====
