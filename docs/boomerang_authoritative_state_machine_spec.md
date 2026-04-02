1. Protocol intent and scope

Boomerang is a five-peer Bitcoin cold-storage protocol that tries to preserve spendability while making coercive withdrawal materially harder, slower, and less predictable. The protocol does this by separating spending into two descriptor regimes: a probabilistic boomerang regime, whose keys include unrecoverable Boomlet-held shares and whose withdrawal path is operationalized by the specified setup and withdrawal ceremonies; and a normal deterministic regime, whose timelocked waterfall scripts are present in the descriptor as a fallback but are not operationalized here as a ceremony. The specified setup flow establishes the long-lived state that the withdrawal flow later inherits: peer identities, Tor addressing, boomerang parameters, watchtower registration, SAR linkage, the per-user duress consent set, and backup state. The specified withdrawal flow operationalizes only spending in the boomerang regime, and only after `milestone_block_0` has been reached. Within that flow, the initiating peer starts a PSBT-based ceremony, all peers approve and commit to a single `tx_id`, and the Watchtower coordinates a non-deterministic digging game whose duration is controlled by secret per-Boomlet `mystery` thresholds. Duress signaling is mandatory at commitment time and may recur during the digging game at Boomlet-chosen random intervals; the design intent is that duress and non-duress executions do not diverge in observable protocol flow. The Watchtower is not a custodian; it is the liveness coordinator, block-height anchor, approval/commit/ping aggregator, and final relay point for signed PSBTs. SAR is not a signer; it is the recipient and interpreter of encrypted duress-bearing placeholders and the trigger for off-protocol search-and-rescue action when a valid duress signal is detected. The current deliverable therefore specifies one distributed state machine that covers setup, active-ready state, boomerang-regime withdrawal, signing handoff, broadcast, and immediate cleanup/reset, while explicitly marking ancillary procedures, deterministic fallback operation, and several failure recoveries as recognized but out of scope.

2. Source authority and conflict policy

This specification is synthesized only from the following design files and nothing else:

- `setup.md` and `setup.puml`
- `withdrawal.md`, `initiator_withdrawal.puml`, and `non_initiator_withdrawal.puml`
- `duress.md`, `duress_setup.puml`, and `duress_withdrawal.puml`
- `DEEPDIVE.md`

Authority is resolved in the order required by the request:

1. `setup.md` plus `setup.puml`, and `withdrawal.md` plus the two withdrawal diagrams, are authoritative for step ordering, actor interactions, message flow, validations, and phase boundaries.
2. `duress.md` plus the two duress diagrams are authoritative for duress semantics, assumptions, consequences, and coverage.
3. `DEEPDIVE.md` is authoritative for entities, descriptor and regime structure, design goals, trust model, system intent, and identified failure modes.

When one source is broader and another is more procedural, this document follows the procedural source for operative behavior and uses the broader source only for interpretation and intent. When a lower-authority source adds detail that does not conflict with a higher-authority source, that detail is included. When sources conflict, omit a required guard, use inconsistent data structures, or leave recovery behavior unspecified, this document does not silently repair the design. Instead it records the issue in Section 16, states the most conservative interpretation used here, and confines the state machine to behavior that is explicitly supported.

3. Modeling conventions

This is a distributed state-machine specification. Each actor owns local state, reacts to explicit events, validates incoming messages, emits outgoing messages, and updates persistent or volatile variables.

Definitions used throughout this document:

- **Actor**: a state-owning participant with independent control flow. Actors are `User(i)`, `Phone(i)`, `Iso(i)`, `Niso(i)`, `Boomlet(i)`, `Boomletwo(i)`, `ST(i)`, `WT`, and `SAR`, with `i in {0..4}`.
- **State**: a named control location for one actor or for one composite machine. A state name denotes both a phase of behavior and a set of variable obligations that must hold while the actor remains there.
- **Event**: an occurrence not controlled by the receiving actor, such as message arrival, user approval, user hardware reconnection, block-height advance, payment receipt, timeout, or freshness failure.
- **Message**: a directed communication unit between actors, containing a typed payload whose fields are interpreted abstractly. Local display-and-input interactions through ST are modeled as message-like events because they drive protocol state.
- **Guard**: a precondition that must hold for a transition to occur. Guards include signature validity, freshness checks, nonce equality, block-height thresholds, payload equality checks, membership checks, and phase consistency checks.
- **Action**: the local work performed if a guard passes. Actions include generating keys, computing hashes, encrypting or decrypting, comparing derived values, recording persistent values, setting flags, and relaying messages.
- **Emitted output**: any message, notification, display, or externally visible relay caused by a transition.
- **Persistent state**: information intended to survive actor restarts or disconnections within the design, especially Boomlet-held setup and withdrawal state, Phone-held SAR registration state, Niso-held online coordination state, WT-held coordination state, and SAR-held registered doxing records.
- **Volatile state**: information that exists only during a live local session or until an explicit reset. Iso state is predominantly volatile because the sources say Iso loses state on shutdown.
- **Derived state**: a control or data abstraction introduced here to make the machine explicit where the sources describe behavior procedurally but do not name the state. Every such state is marked `[DERIVED]` and justified.
- **Mirrored validation**: the same check intentionally performed in more than one actor, especially in both Niso and Boomlet. Mirrored validations are preserved rather than collapsed.

Block height is represented as an explicit observed quantity, never as an implicit clock. The model distinguishes global observations such as WT’s `most_work_bitcoin_block_height`, local observations such as `niso_i_event_block_height`, and message-embedded `event_block_height` fields. A freshness check is a guard that compares one or more of those heights against named tolerances or required minimum distances.

Signatures are modeled abstractly. A payload may be described as “signed by actor key K”; a receiver may perform `verify signature` as a guard. Encryption and decryption are likewise abstract. The model uses operations such as `encrypt for ST`, `encrypt for WT`, `encrypt for SAR`, `decrypt`, and `compare decrypted content to expected content`, without committing to a lower-level cryptographic implementation beyond what the sources state. A nonce is modeled as a fresh challenge value bound to exactly one challenge-response pair. A nonce equality check is a freshness guard against replay or substitution.

An encrypted payload remains opaque to actors not authorized to decrypt it. The model therefore never assumes that WT learns the plaintext of a duress-bearing placeholder, that Niso learns the content of a Boomlet–ST challenge, or that peers learn each other’s secrets by relay. The only semantic operations on encrypted payloads are generation, forwarding, decryption by the intended recipient, signature verification on nested content, and equality comparison to previously sent content where the sources require that.

4. Actor catalog

The protocol uses a parameterized peer family `Peer(i)` where `i in {0..4}`. Each peer contains `User(i)`, `Phone(i)`, `Iso(i)`, `Niso(i)`, `Boomlet(i)`, `Boomletwo(i)`, and `ST(i)`. `WT` and `SAR` are external shared services.

#### `User(i)`

Role: the human peer whose long-term normal key material is created and later reconstructed through mnemonic and passphrase, who approves setup data, who authorizes a specific withdrawal transaction, and who performs duress selections through ST. Trust assumptions: the user is honest when free, can verify displayed data, and can physically connect devices as required; under coercion the user may be observed and may be forced to continue, which is precisely why the duress mechanism exists. Main responsibilities: provide setup inputs, pay SAR and WT invoices, perform out-of-band peer exchange, approve boomerang parameters, approve PSBTs, confirm locally displayed `tx_id`, answer duress checks, and move Boomlet between Iso and Niso. User-owned states are high-level approval and reconnection states, not cryptographic storage states.

#### `Phone(i)`

Role: the user’s online channel to SAR during registration and later provider of dynamic doxing data. Trust assumptions: enough phone integrity exists to keep sending encrypted dynamic data, but the design explicitly recognizes phone compromise or data-feed loss as a concern rather than a solved property. Main responsibilities: derive `doxing_key` and `doxing_data_identifier` from user input, initiate SAR registration, forward payment information, send encrypted static and dynamic doxing data, and maintain synchronization with SAR. Phone-owned states are the SAR registration and in-sync states.

#### `Iso(i)`

Role: trusted isolated software used for offline key generation, ST pairing relay, setup verification, backup verification and transfer, and later MuSig2 signing with Boomlet. Trust assumptions: the isolated environment and the Iso software are trusted while active; the sources explicitly state that Iso loses state on shutdown. Main responsibilities: create mnemonic and `normal_pubkey_i`, install Boomlet and Boomletwo applets, relay ST pairing material, relay duress-setup traffic, verify descriptor and SAR fingerprint data during backup, reconstruct normal signing material from mnemonic and passphrase, and participate in the signing handoff. Iso-owned states are session-local and predominantly volatile.

#### `Niso(i)`

Role: the online, stateful coordination component for peer `i`, with access to a Bitcoin node and TOR network. Trust assumptions: Niso may be online and therefore not physically isolated, but it is expected to perform mirrored validations, maintain current block-height views, and communicate through TOR. Main responsibilities: connect to peers and WT, relay messages between local actors and remote actors, verify signatures and freshness in parallel with Boomlet, derive or hydrate PSBTs where the sources require, present data to User or ST, and export signed PSBTs to WT. Niso-owned states span online setup, withdrawal relay, and final export.

#### `Boomlet(i)`

Role: the secure hardware element that generates the unrecoverable boom share, stores the duress consent set, enforces the non-deterministic withdrawal ceremony, creates duress-bearing placeholders, and holds the secret `mystery` threshold. Trust assumptions: Boomlet’s Java Card security promises hold; cryptography and RNGs behave correctly; side-channel resistance is sufficient; the attacker cannot break the secure element. Main responsibilities: generate identity and boom-share keys, construct `peer_i_id`, pair with ST, store `duress_consent_set`, verify setup inputs, fix `boomerang_params`, generate `mystery`, register with WT, finalize SAR activation, export backup material excluding the current mystery, own the commitment and digging-game logic, enforce repeated duress checks, retain the committed `tx_id`, and clear withdrawal state after signed PSBT export while regenerating `mystery`. Boomlet owns most of the protocol’s load-bearing persistent states.

#### `Boomletwo(i)`

Role: backup Java Card applet for Boomlet. Trust assumptions: only one of Boomlet and Boomletwo should be active at a time, but the activation/deactivation procedure is explicitly not yet designed; this is therefore a recognized but out-of-scope operational requirement. Main responsibilities: receive imported backup data, generate its own `mystery`, acknowledge successful import, and remain inactive unless activated by an ancillary procedure. Boomletwo-owned states are installation and inactive imported-backup states.

#### `ST(i)`

Role: the secure terminal through which the user interacts with Boomlet for sensitive checks and duress selections. Trust assumptions: ST is tamper evident, its display is small enough to shield, and the attacker cannot simultaneously observe both the display and the user’s hand movements in a way that defeats the duress mechanism. Main responsibilities: pair cryptographically with Boomlet, display duress setup and duress check spaces, capture consent-set selections and confirmation selections, display boomerang parameter seeds, display `tx_id`, sign user acknowledgments for Boomlet, and preserve nonce-coupled freshness. ST owns pairing state and prompt-response control state.

#### `WT`

Role: the Watchtower, an online liveness coordinator and block-height anchor, not a signer or custodian of funds. Trust assumptions: WT is operationally trusted for coordination and freshness anchoring; availability is required for progress; metadata exposure to WT is recognized as a trust and privacy concern. Main responsibilities: register peers, verify registration and payment, acknowledge setup completion milestones, relay SAR-finalization traffic, collect transaction approvals and commitments, store the ceremony `tx_id`, coordinate the ping-pong loop using current block height, distribute pongs and the final reached-pings collection, collect signed PSBTs, aggregate them, and relay the final signed transaction to the network. WT owns the global coordination states and collections.

#### `SAR`

Role: Search And Rescue service that stores encrypted doxing data and interprets duress-bearing placeholders. Trust assumptions: SAR effectiveness is jurisdiction-dependent; SAR is trusted to act when valid duress is detected, but rogue or weak SAR behavior remains a recognized concern. Main responsibilities: register the user through Phone, store encrypted static and dynamic doxing data keyed by `doxing_data_identifier`, confirm finalization through WT during setup, decrypt duress placeholders during withdrawal, distinguish zero-padding from duress, suppress replay by tracking `(boomlet_identity_pubkey, iv)` pairs, and trigger off-protocol rescue operations when a valid match is found. SAR owns the customer registry and duress-processing states.

5. System boundaries and trust assumptions

### In-model

The following are part of the state machine:

- All local setup and withdrawal control states for `User(i)`, `Phone(i)`, `Iso(i)`, `Niso(i)`, `Boomlet(i)`, `Boomletwo(i)`, `ST(i)`, `WT`, and `SAR`.
- Explicit messages, local display-and-input interactions, user approvals, payment receipts, device reconnections, and message relays.
- Explicit block-height observations and message freshness checks.
- Abstract cryptographic guards and actions such as hashing, encrypting, decrypting, signature generation, signature verification, and equality comparison of derived values.
- Descriptor construction, agreement, fingerprints, SAR finalization responses, backup transfer, PSBT approval, commitment, ping-pong state updates, signing handoff, signed PSBT export, and WT aggregation/broadcast.

### Out-of-model

The following are acknowledged but not fully specified here:

- The detailed Bitcoin semantics of script execution, mempool behavior, mining, or confirmation beyond the abstract facts “block height observed”, “PSBT satisfiable”, “PSBT hydrated”, and “signed transaction relayed”.
- The internal behavior of the user’s watch-only wallet that creates the initiator PSBT.
- SAR’s real-world operational rescue procedure after a positive duress signal.
- The deterministic normal-regime spending ceremony. The descriptor contains that regime, but this deliverable does not specify an operational state machine for it.
- Ancillary procedures explicitly listed in `DEEPDIVE.md`: switching WT, activating Boomletwo, changing Phone, changing Niso, changing ST, modifying SAR membership, timeout handling, and prolonged peer-response handling.
- Multiple-WT voting, setup uniqueness improvements, extensive threat-model completion, and error-handling mechanisms that the roadmap says are still to be designed.

### Explicit trust and dependency assumptions

**Hardware trust**: Boomlet and Boomletwo must preserve secret key shares and `mystery`; ST must be tamper evident; the isolated hardware running Iso must be trusted while active. If those assumptions fail, the probabilistic and duress guarantees may collapse.

**Secure channels**: The protocol relies on the confidentiality and authenticity implied by DH-derived encryption, signatures, and secure out-of-band exchange. Tor is used for remote peer and WT communication, but Tor use is an operational measure, not a proof of confidentiality in this model.

**User behavior**: The user must verify displayed data during setup and withdrawal, must preserve mnemonic and passphrase, must choose and remember a valid duress consent set, must answer duress checks, and must reconnect devices when prompted. The model does not assume the user can force Boomlet to sign early.

**Watchtower honesty and availability**: WT need not be trusted with keys, but the protocol depends on WT to provide current block height, collect and redistribute approvals and commits, coordinate the digging game, and relay final signed PSBTs. WT unavailability blocks progress in the boomerang-regime ceremony.

**SAR effectiveness**: The design assumes SAR can act on decrypted doxing data, but recognizes that legal authority, jurisdiction, and practical enforcement determine whether rescue is effective. The protocol’s deterrence logic depends partly on that external reality.

**Block-height freshness**: Correctness of approval, commitment, ping, and pong transitions depends on block-height observations being recent enough to satisfy the named tolerances and required minimum distances.

**Non-compromised cryptography**: Signature security, encryption confidentiality, hashing, DH key agreement, and RNG unpredictability are treated as unbroken. The design explicitly assumes the attacker cannot break cryptography.

6. State variable catalog

Unless otherwise stated, `i` ranges over `{0..4}` and family variables are defined uniformly for each peer. Variables marked `[DERIVED]` are introduced here to make implicit source structure explicit.

### 6.1 Shared and per-peer setup variables

**`boomerang_descriptor`**  
Meaning: the Taproot descriptor containing the boomerang regime and the normal deterministic waterfall regime.  
Scope: per-peer, but fixed to the same value at all peers once setup consensus completes.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: constructed by `Boomlet(i)` after local ST approval of `boomerang_params_seed`, before peer-wide signature exchange.  
Cleared: not cleared by the specified withdrawal flow.

**`peer_ids_collection`**  
Meaning: the collection of all five `peer_i_id` values.  
Scope: per-peer.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: derived from `peer_addresses_collection` during setup parameter verification.  
Cleared: not cleared by the specified flows.

**`wt_ids_collection`**  
Meaning: the collection of configured Watchtower identifiers.  
Scope: per-peer.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: provided by `User(i)` during setup.  
Updated: once per setup; later replacement is ancillary and out of scope.  
Cleared: not cleared by the specified flows.

**`milestone_block_collection`**  
Meaning: the ordered block heights used to construct descriptor scripts.  
Scope: per-peer.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: provided by `User(i)` during setup.  
Updated: once per setup.  
Cleared: not cleared by the specified flows.

**`boomerang_params`**  
Meaning: `{peer_ids_collection, wt_ids_collection, boomerang_descriptor}` after peer-wide agreement.  
Scope: per-peer.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: fixed at setup step 45 after all signed peer copies match.  
Cleared: not cleared by withdrawal; supersession by future rollover is out of scope.

**`boomerang_params_fingerprint`**  
Meaning: hash of `boomerang_params`, used for WT registration and later comparisons.  
Scope: per-peer and WT.  
Persistence: persistent through setup; read-only afterward.  
Provenance: explicit.  
Initial value: unset.  
Updated: created when `Boomlet(i)` generates `mystery` and starts WT registration.  
Cleared: not explicitly cleared.

**`peer_addresses_collection`**  
Meaning: collection of pairs `<peer_i_id, peer_i_tor_address_signed_by_boomlet_i>`.  
Scope: per-peer, Niso and Boomlet visible.  
Persistence: persistent setup state.  
Provenance: explicit.  
Initial value: unset until out-of-band exchange completes.  
Updated: setup steps 34–36.  
Cleared: not explicitly cleared.

**`network`**  
Meaning: selected Bitcoin network.  
Scope: per-peer.  
Persistence: persistent setup input.  
Provenance: explicit.  
Initial value: user-supplied.  
Updated: setup input; reused during backup verification and signing.  
Cleared: not explicitly cleared.

**`normal_pubkey_i`**  
Meaning: recoverable normal public key derived from mnemonic/passphrase via the boomerang purpose path.  
Scope: peer-local, but distributed inside `peer_i_id`.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: created by Iso during setup; later reconstructed by Iso during backup/signing as needed.  
Cleared: never cleared from persistent setup state.

**`master_xpriv_i`, `purpose_root_xpriv_i`, `mnemonic`, `passphrase`**  
Meaning: recoverable normal-key material used by Iso.  
Scope: peer-local.  
Persistence: mnemonic/passphrase persist with the user; Iso session copies are volatile.  
Provenance: explicit.  
Initial value: unset.  
Updated: created or provided during setup; reconstructed during signing.  
Cleared: Iso loses session state on shutdown; user retains mnemonic/passphrase.

**`boomlet_i_identity_privkey`, `boomlet_i_identity_pubkey`**  
Meaning: Boomlet identity keypair for authentication, encryption contexts, and signatures.  
Scope: peer-local; public key distributed in `peer_i_id`.  
Persistence: Boomlet-persistent.  
Provenance: explicit.  
Initial value: unset until installation.  
Updated: generated once during Boomlet installation.  
Cleared: not cleared by specified flows.

**`boomlet_i_boom_musig2_privkey_share`, `boomlet_i_boom_musig2_pubkey_share`, `boom_pubkey_i`**  
Meaning: unrecoverable boom share, its public share, and the aggregated boomerang-regime public key.  
Scope: peer-local for private share; public components distributed.  
Persistence: Boomlet-persistent.  
Provenance: explicit.  
Initial value: unset until Boomlet installation.  
Updated: generated once during installation; used again during signing.  
Cleared: not cleared by specified flows.

**`peer_i_id`**  
Meaning: `{boom_pubkey_i, normal_pubkey_i, boomlet_i_identity_pubkey}`.  
Scope: peer-local and shared with peers and WT.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: created during Boomlet installation.  
Cleared: not cleared by specified flows.

**`peer_i_tor_secret_key`, `peer_i_tor_address_signed_by_boomlet_i`**  
Meaning: Tor service secret key and signed Tor address association for peer `i`.  
Scope: peer-local; signed address shared externally.  
Persistence: persistent for Boomlet/Niso.  
Provenance: explicit.  
Initial value: unset.  
Updated: secret generated during installation; address derived and signed when Niso initializes.  
Cleared: not cleared by specified flows.

**`st_i_identity_privkey`, `st_i_identity_pubkey`**  
Meaning: ST identity keypair for the Boomlet–ST channel.  
Scope: peer-local ST.  
Persistence: ST-persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: created during ST pairing.  
Cleared: not cleared by specified flows.

**`shared_boomlet_st_secret_i` `[DERIVED]`**  
Meaning: DH-derived secret shared between Boomlet and ST.  
Scope: peer-local, shared logically by Boomlet and ST.  
Persistence: persistent after pairing.  
Provenance: derived from explicit key-exchange steps.  
Initial value: unset.  
Updated: after both parties receive each other’s public keys during duress setup pairing.  
Cleared: not explicitly cleared.  
Why derived: the sources describe the DH computation and then use the resulting channel implicitly thereafter.

**`duress_consent_set_i`**  
Meaning: the five-number consent set encoded by the user’s memorized country choices.  
Scope: peer-local Boomlet; user remembers the semantic country set through ST.  
Persistence: Boomlet-persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: after the first duress setup selection is validated and stored.  
Cleared: not cleared by the specified flows.

**`doxing_key_i`**  
Meaning: `SHA256(doxing_password)` used to encrypt static and dynamic doxing data and later to signal duress to SAR.  
Scope: Phone, Iso, Boomlet, SAR-derived lookup context.  
Persistence: persistent at Phone and Boomlet; Iso copies are session-local.  
Provenance: explicit.  
Initial value: unset.  
Updated: derived during SAR sign-up and during Iso backup verification; reused when duress is signaled.  
Cleared: Iso session copy disappears on shutdown; otherwise not explicitly cleared.

**`doxing_data_identifier_i`**  
Meaning: `SHA256(doxing_key_i)` used as the SAR database lookup key during setup and duress.  
Scope: Phone, Boomlet, SAR.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: derived during SAR sign-up and again during SAR finalization.  
Cleared: not explicitly cleared.

**`sar_setup_response_i`**  
Meaning: SAR’s finalization response containing `{doxing_data_identifier, fingerprint_of_static_doxing_data_encrypted_by_doxing_key, iv_of_static_doxing_data_encrypted_by_doxing_key}`.  
Scope: Boomlet-persistent; read later by Iso during backup verification.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: received and stored during setup SAR finalization.  
Cleared: not explicitly cleared.

**`sar_ids_collection_i`**  
Meaning: configured SAR identifiers for peer `i`.  
Scope: peer-local; signed by Boomlet and forwarded to WT.  
Persistence: persistent.  
Provenance: explicit.  
Initial value: user-supplied.  
Updated: setup input only; later modification is ancillary and out of scope.  
Cleared: not explicitly cleared.

**`mystery_i`**  
Meaning: Boomlet’s secret withdrawal threshold controlling when it may announce readiness to sign.  
Scope: peer-local Boomlet or Boomletwo.  
Persistence: persistent between setup and withdrawal; regenerated after signed-PSBT export and when imported into Boomletwo.  
Provenance: explicit.  
Initial value: unset until setup mystery generation.  
Updated: generated after `boomerang_params` fixation; independently generated again by Boomletwo on backup import; regenerated by Boomlet after signed-PSBT export.  
Cleared: replaced, not simply cleared.

### 6.2 Setup synchronization and backup variables

**`shared_state_active_wt_fingerprint`**  
Meaning: hash representing that local WT registration is active.  
Scope: per-peer and compared across peers.  
Persistence: setup-persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: after WT returns the suffixed `boomerang_params_fingerprint` acknowledgment.  
Cleared: not explicitly cleared.

**`shared_state_active_sar_fingerprint`**  
Meaning: hash representing that local SAR finalization was acknowledged by WT/SAR.  
Scope: per-peer and compared across peers.  
Persistence: setup-persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: after `sar_setup_response` verification.  
Cleared: not explicitly cleared.

**`shared_state_active_backup_fingerprint`**  
Meaning: hash representing that backup creation completed and peers know it.  
Scope: per-peer and compared across peers.  
Persistence: setup-persistent.  
Provenance: explicit.  
Initial value: unset.  
Updated: final setup synchronization after backup completion.  
Cleared: not explicitly cleared.

**`boomlet_backup_blob_i` `[DERIVED]`**  
Meaning: the encrypted backup export from Boomlet to Boomletwo, explicitly excluding the current `mystery_i`.  
Scope: peer-local during backup session.  
Persistence: backup-session local.  
Provenance: derived from explicit “encrypt own data except mystery” steps.  
Initial value: unset.  
Updated: created on valid backup request.  
Cleared: after successful backup import or end of backup session.  
Why derived: the sources name the encrypted backup message but not a canonical state variable name for the blob as a stored object.

**`backup_done_signed_by_boomletwo_i`**  
Meaning: signed acknowledgment from Boomletwo that backup import completed.  
Scope: peer-local during backup session; later verified by Boomlet.  
Persistence: setup-session local.  
Provenance: explicit.  
Initial value: unset.  
Updated: on Boomletwo import completion.  
Cleared: after Boomlet verifies it or at end of setup session.

### 6.3 Withdrawal variables

**`psbt_i`**  
Meaning: the withdrawal PSBT currently bound to the ceremony. For initiator it is user-supplied; for non-initiators it is decrypted from the initiator’s encrypted copy.  
Scope: per-peer Niso/Boomlet/Iso.  
Persistence: withdrawal-local, then partly retained as signed PSBT output.  
Provenance: explicit.  
Initial value: unset in `ActiveReady`.  
Updated: at withdrawal start; later replaced by `hydrated_psbt_i` if the `tx_id` matches.  
Cleared: cleared by Boomlet’s withdrawal reset after signed export, except for the saved signed PSBT.

**`hydrated_psbt_i`**  
Meaning: PSBT after Niso hydrates it for signing once all peers are reached.  
Scope: per-peer Niso/Boomlet/Iso.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: unset.  
Updated: after WT sends `reached_pings_collection`.  
Cleared: after signing and export.

**`signed_psbt_i` / `psbt_signed_i`**  
Meaning: the peer’s locally signed PSBT fragment exported from Boomlet to Niso and then to WT.  
Scope: per-peer and WT collection.  
Persistence: persists past Boomlet’s reset until WT aggregation completes.  
Provenance: explicit.  
Initial value: unset.  
Updated: after MuSig2 signing finishes and Boomlet exports the result.  
Cleared: not specified locally; WT uses it for aggregation.

**`tx_id`**  
Meaning: the transaction identifier bound to the active withdrawal ceremony.  
Scope: per-peer Boomlet/Niso/WT; implicitly compared by ST and User.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: unset in `ActiveReady`.  
Updated: initiator Niso derives it from user PSBT; initiator Boomlet derives and locally latches it; WT stores it on initiator approval receipt; non-initiators derive it from decrypted PSBT and must match the WT/initiator approvals.  
Cleared: on withdrawal reset after signed export.  
Important note: the sources make Boomlet’s acceptance of the PSBT the local commitment point and WT’s storage of the initiator approval the global coordination point.

**`niso_i_event_block_height`**  
Meaning: peer-local latest block height observation attached to a local message.  
Scope: per-peer Niso and Boomlet.  
Persistence: withdrawal-local and refreshed often.  
Provenance: explicit.  
Initial value: unset at `ActiveReady`.  
Updated: whenever Niso queries its Bitcoin node or receives a new current height from WT-related flow.  
Cleared: on withdrawal reset.

**`most_work_bitcoin_block_height`**  
Meaning: current WT or Niso view of the chain height used in freshness checks.  
Scope: Niso and WT local views.  
Persistence: volatile.  
Provenance: explicit.  
Initial value: current node observation when first queried.  
Updated: each time the node is queried or WT constructs a fresh approval/pong.  
Cleared: overwritten on each refresh.

**`peer_tx_approval_collection` `[DERIVED]`**  
Meaning: map from peer id to that peer’s signed `"approved"` message.  
Scope: WT and each peer after distribution.  
Persistence: withdrawal-local.  
Provenance: derived from explicit individual approval messages and collection-distribution steps.  
Initial value: empty.  
Updated: as approvals arrive or are distributed.  
Cleared: on withdrawal reset.  
Why derived: the sources usually describe individual approvals and then a collection; the map form is needed to state invariants and completeness.

**`wt_tx_approval`**  
Meaning: WT’s signed transaction-approval message naming the initiator and current WT block height.  
Scope: WT and all peers.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: unset.  
Updated: created once after WT receives and accepts the initiator’s approval.  
Cleared: on withdrawal reset.

**`approvals_signed_by_boomlet_i`**  
Meaning: non-initiator’s signed bundle containing all peer approvals and `wt_tx_approval`.  
Scope: non-initiator peer and WT.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: unset.  
Updated: created by each non-initiator after the initial duress check and before that peer emits its own commit.  
Cleared: after WT validates it or on reset.

**`peer_tx_commit_collection` `[DERIVED]`**  
Meaning: map from peer id to that peer’s signed `"commit"` message, optionally WT-signed on outer acknowledgment.  
Scope: WT and each peer.  
Persistence: withdrawal-local.  
Provenance: derived from explicit commit messages and collection distribution.  
Initial value: empty.  
Updated: as commits are accepted by WT and redistributed.  
Cleared: on withdrawal reset.

**`duress_check_space_i`**  
Meaning: the current challenge space displayed through ST during setup or withdrawal.  
Scope: peer-local Boomlet and ST.  
Persistence: session-local.  
Provenance: explicit.  
Initial value: unset.  
Updated: each time Boomlet initiates a setup or withdrawal duress check.  
Cleared: after its matching response is processed.

**`duress_signal_index_i`**  
Meaning: ST’s encoded indices for the user’s chosen countries in the current challenge space.  
Scope: ST and Boomlet during an active check.  
Persistence: session-local.  
Provenance: explicit.  
Initial value: unset.  
Updated: when the user responds through ST.  
Cleared: after Boomlet processes the response.

**`duress_placeholder_plaintext_i`**  
Meaning: the plaintext from which the next duress-bearing placeholder is produced: either all-zero padding or `doxing_key_i`.  
Scope: peer-local Boomlet.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: zero-padding at non-duress commitment, unless the initial duress check is positive.  
Updated: after each duress check, or retained unchanged if no new duress check occurs.  
Cleared: on withdrawal reset.

**`duress_placeholder_i`**  
Meaning: the encrypted duress-bearing payload appended to commit, ping, or similar messages toward WT and then forwarded to SAR.  
Scope: peer-local Boomlet, WT relay, SAR processing, then peer-local verification of SAR return.  
Persistence: per-message plus comparison cache.  
Provenance: explicit.  
Initial value: unset.  
Updated: each time Boomlet encrypts `duress_placeholder_plaintext_i` for SAR.  
Cleared: after the matching SAR-signed placeholder is verified, though the sources imply the current placeholder value may be reused semantically until replaced.

**`duress_latched_i` `[DERIVED]`**  
Meaning: whether this peer has ever emitted a positive duress signal in the current withdrawal.  
Scope: peer-local Boomlet.  
Persistence: withdrawal-local.  
Provenance: derived from `duress_withdrawal.puml` and the “all subsequent messages bear the duress signal” rule.  
Initial value: false.  
Updated: set true on the first duress-positive evaluation.  
Cleared: on withdrawal reset.  
Why derived: the sources describe monotone post-duress behavior but do not name a latch variable.

**`saved_placeholder_for_sar_comparison_i` `[DERIVED]`**  
Meaning: the last placeholder that Boomlet expects SAR to sign and return.  
Scope: peer-local Boomlet.  
Persistence: withdrawal-local.  
Provenance: derived from explicit “check if the content matches the placeholder that was sent” validations.  
Initial value: unset.  
Updated: whenever a new placeholder is emitted.  
Cleared: on successful comparison or replacement.

**`counter_i`**  
Meaning: count of successful digging rounds toward `mystery_i`.  
Scope: peer-local Boomlet.  
Persistence: withdrawal-local active value; initialized earlier to zero in setup but operationally reinitialized at digging-game start.  
Provenance: explicit.  
Initial value: zero at digging-game entry.  
Updated: on pong processing when block-height conditions are satisfied.  
Cleared: on withdrawal reset.

**`ping_seq_num_i`**  
Meaning: monotonically increasing sequence number on this peer’s pings.  
Scope: peer-local Boomlet and WT/other peers as comparison state.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: zero at digging-game entry.  
Updated: incremented when generating each next ping after the first.  
Cleared: on withdrawal reset.

**`reached_mystery_flag_i`**  
Meaning: whether `counter_i >= mystery_i` has been reached and announced.  
Scope: peer-local Boomlet; visible to WT and peers through pings.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: zero at digging-game entry.  
Updated: set to one when the local counter reaches the local mystery.  
Cleared: on withdrawal reset.  
Monotonicity: once one, it never returns to zero within the ceremony.

**`reached_boomlets_collection_i`**  
Meaning: local map from peer id to the latest validated ping showing that peer already reached its mystery.  
Scope: peer-local Boomlet.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: empty set or empty map at digging-game entry.  
Updated: during pong processing when another peer’s previous ping shows `reached_mystery_flag = 1` and the peer is not already recorded.  
Cleared: on withdrawal reset.

**`last_seen_block_i`**  
Meaning: the local Boomlet block-height value used when creating the previous ping and when evaluating counter increments.  
Scope: peer-local Boomlet.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: `niso_i_event_block_height` at digging-game entry.  
Updated: on each pong-processing transition by the bounded min-update rule from the sources.  
Cleared: on withdrawal reset.

**`peer_ping_i` / `peer_ping_collection` / `pong_i`**  
Meaning: the current peer’s ping, the WT-collected ping set, and the per-peer pong built by WT.  
Scope: peer-local and WT.  
Persistence: withdrawal-local.  
Provenance: explicit.  
Initial value: unset until digging-game entry.  
Updated: pings on each loop iteration; pongs on each WT loop iteration after all pings for that round are collected.  
Cleared: superseded each round and cleared on reset.

**`reached_pings_collection`**  
Meaning: WT’s final map from every peer id to that peer’s validated reached ping.  
Scope: WT and all peers after loop exit.  
Persistence: withdrawal-local until signing handoff.  
Provenance: explicit.  
Initial value: empty at or before WT loop entry.  
Updated: when WT accepts a ping with `reached_mystery_flag = 1` from a peer not previously recorded.  
Cleared: after handoff completion or on reset.

### 6.4 WT and SAR registry variables

**`wt_registered_peer_state` `[DERIVED]`**  
Meaning: WT registry of peer identity pubkeys, signed Tor addresses, and boomerang-parameter fingerprints.  
Scope: WT.  
Persistence: persistent setup state.  
Provenance: derived from explicit WT registration steps.  
Initial value: empty.  
Updated: setup registration steps 49–53.  
Cleared: replacement or switching WT is ancillary and out of scope.

**`sar_registry` `[DERIVED]`**  
Meaning: SAR database keyed by `doxing_data_identifier`, containing encrypted static and dynamic doxing data and associated IV/fingerprint data.  
Scope: SAR.  
Persistence: persistent.  
Provenance: derived from explicit registration/finalization steps.  
Initial value: empty.  
Updated: Phone registration and SAR finalization.  
Cleared: not specified.

**`seen_duress_iv_pairs` `[DERIVED]`**  
Meaning: set of `(boomlet_identity_pubkey, iv)` pairs already processed by SAR to suppress replay or duplicate rescue triggers.  
Scope: SAR.  
Persistence: persistent during or across withdrawal handling.  
Provenance: derived from explicit replay-suppression language in `withdrawal.md`, the withdrawal diagrams, and `duress.md`.  
Initial value: empty.  
Updated: on each positive, new placeholder processed by SAR.  
Cleared: not specified.

7. Message catalog

The message catalog is grouped by message family. Fields listed below are normative: sender, receiver, payload, purpose, receiver-side validations, receiver state effect, and source anchors. Message names are descriptive family names, not implementation identifiers.

### 7.1 Setup: SAR sign-up and Phone sync

**Family `Setup.SARRegistration.Init`**  
Sender: `Phone(i)`  
Receiver: `SAR`  
Payload: `doxing_data_identifier_i`  
Purpose: begin SAR registration without revealing plaintext doxing data.  
Receiver validations: none beyond well-formedness are specified before invoice generation.  
State effect on receiver: create pending registration context and generate payment information.  
Source anchors: `setup.md` 1–2; `setup.puml` 1–2; `DEEPDIVE.md` setup Group 1.

**Family `Setup.SARRegistration.Invoice`**  
Sender: `SAR`  
Receiver: `Phone(i)`, then `User(i)`  
Payload: `sar_service_fee_payment_info` including invoice, deadline, and SAR id  
Purpose: request payment and identify the SAR instance.  
Receiver validations: Phone checks SAR id matches `sar_ids_collection_i`; User verifies invoice details before paying.  
State effect on receiver: Phone enters awaiting-receipt state; User enters payment state.  
Source anchors: `setup.md` 2–4; `setup.puml` 2–4.

**Family `Setup.SARRegistration.DataAndReceipt`**  
Sender: `Phone(i)`  
Receiver: `SAR`  
Payload: `sar_service_fee_payment_receipts`, `static_doxing_data_encrypted_by_doxing_key`, `dynamic_doxing_data_encrypted_by_doxing_key`, `doxing_data_identifier_i`  
Purpose: prove payment and deliver encrypted doxing data under the registration key.  
Receiver validations: verify receipt/payment association and identifier consistency.  
State effect on receiver: store encrypted static and dynamic doxing data keyed by `doxing_data_identifier_i`; mark phone as in sync.  
Source anchors: `setup.md` 5–7; `setup.puml` 5–7; `duress.md` doxing-data section.

**Family `Setup.SARRegistration.SyncAck`**  
Sender: `SAR`  
Receiver: `Phone(i)`, then `User(i)`  
Payload: setup magic strings indicating successful registration and sync  
Purpose: signal completion of the phone/SAR registration portion of setup.  
Receiver validations: magic value equality.  
State effect on receiver: Phone enters synced state; User is allowed to proceed to Boomlet installation.  
Source anchors: `setup.md` 6–8; `setup.puml` 6–8.

### 7.2 Setup: Boomlet installation and Boomlet–ST pairing

**Family `Setup.BoomletInstall`**  
Sender: `Iso(i)`  
Receiver: `Boomlet(i)`  
Payload: `normal_pubkey_i`, `doxing_key_i`, `sar_ids_collection_i`, `network`  
Purpose: personalize an empty smart card as `Boomlet(i)`.  
Receiver validations: card is empty; network and input fields are well-formed.  
State effect on receiver: generate Boomlet identity keypair, boom MuSig2 share, `boom_pubkey_i`, `peer_i_id`, and Tor secret key.  
Source anchors: `setup.md` 9–10; `setup.puml` 9–10.

**Family `Setup.BoomletIdentityToST`**  
Sender: `Boomlet(i)` via `Iso(i)`  
Receiver: `ST(i)`  
Payload: `boomlet_i_identity_pubkey`  
Purpose: allow ST to pair to Boomlet.  
Receiver validations: store the key as the peer-local Boomlet identity.  
State effect on receiver: ST can generate its own keypair and compute the shared Boomlet–ST secret.  
Source anchors: `setup.md` 10–13; `setup.puml` 10–13; `duress_setup.puml` messages 1–4.

**Family `Setup.STIdentityToBoomlet`**  
Sender: `ST(i)` via `Iso(i)`  
Receiver: `Boomlet(i)`  
Payload: `st_i_identity_pubkey`  
Purpose: complete pairing so Boomlet can compute the same shared secret.  
Receiver validations: none beyond well-formedness are specified.  
State effect on receiver: shared Boomlet–ST secret becomes available for all later ST-mediated checks.  
Source anchors: `setup.md` 12–14; `setup.puml` 12–14; `duress_setup.puml` messages 2–4.

### 7.3 Setup: duress consent-set establishment

**Family `Setup.Duress.InitialChallenge`**  
Sender: `Boomlet(i)` via `Iso(i)`  
Receiver: `ST(i)`  
Payload: encrypted `duress_check_space_i` plus nonce  
Purpose: let the user choose the consent set through ST without revealing plaintext to Iso or Niso.  
Receiver validations: decrypt with shared Boomlet–ST secret; preserve nonce.  
State effect on receiver: ST enters consent-selection state.  
Source anchors: `setup.md` 14–16; `setup.puml` 14–16.

**Family `Setup.Duress.InitialResponse`**  
Sender: `ST(i)` via `Iso(i)`  
Receiver: `Boomlet(i)`  
Payload: encrypted `duress_signal_index_i` plus copied nonce  
Purpose: return the user’s chosen indices from the displayed space.  
Receiver validations: nonce equality with the challenge; decryption under shared secret.  
State effect on receiver: derive and store `duress_consent_set_i`; drop redundant setup data.  
Source anchors: `setup.md` 17–20; `setup.puml` 17–20.

**Family `Setup.Duress.ConfirmationChallenge`**  
Sender: `Boomlet(i)` via `Iso(i)`  
Receiver: `ST(i)`  
Payload: second challenge space plus nonce  
Purpose: confirm that the user can reproduce the consent set.  
Receiver validations: decrypt and display.  
State effect on receiver: ST enters consent-confirmation state.  
Source anchors: `setup.md` 20–24; `setup.puml` 20–24; `duress_setup.puml` messages 11–16.

**Family `Setup.Duress.ConfirmationResponse`**  
Sender: `ST(i)` via `Iso(i)`  
Receiver: `Boomlet(i)`  
Payload: encrypted confirmation indices plus copied nonce  
Purpose: prove user memorization of the consent set.  
Receiver validations: nonce equality and resulting selected-number set equality to stored `duress_consent_set_i`.  
State effect on receiver: duress setup completes.  
Source anchors: `setup.md` 24–27; `setup.puml` 24–27; `duress_setup.puml` messages 15–17.  
Conflict note: retry semantics if confirmation fails are more specific in `duress_setup.puml` than in `setup.md`; see Section 16.

### 7.4 Setup: Tor identity and peer parameter verification

**Family `Setup.TorIdentity`**  
Sender: `Boomlet(i)`  
Receiver: `Niso(i)`, then `ST(i)`, then `User(i)`  
Payload: `peer_i_id`, `peer_i_tor_secret_key`, `peer_i_tor_address_signed_by_boomlet_i`  
Purpose: establish the peer’s signed Tor identity and allow out-of-band exchange.  
Receiver validations: Niso verifies Boomlet signature and reproduces the same Tor address; ST verifies that `peer_i_id` contains the already known Boomlet identity pubkey.  
State effect on receiver: Niso can connect to peers over Tor; User can exchange peer identity bundles out of band.  
Source anchors: `setup.md` 29–33; `setup.puml` 29–33.

**Family `Setup.PeerParamsSeedChallenge`**  
Sender: `Boomlet(i)` via `Niso(i)`  
Receiver: `ST(i)`, then `User(i)`  
Payload: encrypted `boomerang_params_seed` plus nonce  
Purpose: force direct user review of peer ids, WT ids, and milestone blocks before parameter fixation.  
Receiver validations: decryption under ST key; user semantic verification of ids and milestones.  
State effect on receiver: ST awaits user acknowledgment.  
Source anchors: `setup.md` 34–40; `setup.puml` 34–40.

**Family `Setup.PeerParamsSeedApproval`**  
Sender: `ST(i)` via `Niso(i)`  
Receiver: `Boomlet(i)`  
Payload: ST-signed `boomerang_params_seed_with_nonce` encrypted for Boomlet  
Purpose: prove that the user approved the exact displayed seed.  
Receiver validations: decrypt; verify ST signature; compare content and nonce to prior challenge.  
State effect on receiver: Boomlet may construct `boomerang_descriptor` and `boomerang_params`.  
Source anchors: `setup.md` 40–42; `setup.puml` 40–42.

**Family `Setup.PeerParamsConsensus`**  
Sender: each `Boomlet(i)` via `Niso(i)`  
Receiver: all peers’ `Niso`, then local `Boomlet`  
Payload: `boomerang_params_signed_by_boomlet_i` and later the collected all-peers collection  
Purpose: force exact equality of parameters across peers before setup proceeds.  
Receiver validations: verify every peer signature and content equality.  
State effect on receiver: local `boomerang_params` becomes fixed.  
Source anchors: `setup.md` 42–45; `setup.puml` 42–45.

### 7.5 Setup: WT registration and WT activation sync

**Family `Setup.WTRegistration.Request`**  
Sender: `Boomlet(i)` via `Niso(i)`  
Receiver: `WT`  
Payload: `boomlet_i_identity_pubkey`, signed sorted peer identity-pubkey list, signed `boomerang_params_fingerprint`, signed Tor address  
Purpose: register peer identity and common-parameter fingerprint with WT.  
Receiver validations: verify signatures under `boomlet_i_identity_pubkey`; register only matching data.  
State effect on receiver: WT stores peer registration record and generates WT service fee invoice.  
Source anchors: `setup.md` 46–50; `setup.puml` 46–50.

**Family `Setup.WTRegistration.InvoiceAndReceipt`**  
Sender: `WT`, then `User(i)` via `Niso(i)`  
Receiver: `User(i)`, then `WT`  
Payload: WT service fee payment info and payment receipt  
Purpose: settle WT service activation.  
Receiver validations: invoice verification by User; payment verification by WT.  
State effect on receiver: WT can issue the suffixed registration acknowledgment.  
Source anchors: `setup.md` 50–54; `setup.puml` 50–54.

**Family `Setup.WTRegistration.Ack`**  
Sender: `WT`  
Receiver: `Niso(i)`, then `Boomlet(i)`  
Payload: `boomerang_params_fingerprint` suffixed with `"setup_peers_registration_with_wt_completed"` and signed by WT  
Purpose: prove WT accepted this peer’s registration for the agreed parameter fingerprint.  
Receiver validations: verify WT signature; suffix equality; content equality to the previously sent fingerprint.  
State effect on receiver: Boomlet may enter peer-wide WT-activation sync.  
Source anchors: `setup.md` 53–58; `setup.puml` 53–58.

**Family `Setup.WTActivation.PeerSync`**  
Sender: each `Boomlet(i)` via `Niso(i)`  
Receiver: peers, then local `Boomlet(i)`  
Payload: signed `shared_state_active_wt_fingerprint` and later all-peers collection  
Purpose: prove that all peers reached the same WT-active state.  
Receiver validations: signature validity and content equality across all peers.  
State effect on receiver: local peer may proceed to SAR finalization.  
Source anchors: `setup.md` 55–59; `setup.puml` 55–59.

### 7.6 Setup: SAR activation through WT

**Family `Setup.SARFinalization.Init`**  
Sender: `Boomlet(i)` via `Niso(i)` and `WT`  
Receiver: `SAR`  
Payload: WT-encrypted signed `sar_ids_collection_i` and SAR-encrypted `doxing_data_identifier_i`, plus `boomlet_i_identity_pubkey`  
Purpose: bind Boomlet identity to the pre-existing phone/SAR registration.  
Receiver validations: WT verifies Boomlet signature on SAR ids; SAR decrypts the identifier and checks that it was previously registered.  
State effect on receiver: SAR creates `sar_setup_response_i`.  
Source anchors: `setup.md` 60–63; `setup.puml` 60–63.

**Family `Setup.SARFinalization.Response`**  
Sender: `SAR` via `WT`  
Receiver: `Boomlet(i)` via `Niso(i)`  
Payload: `sar_setup_response_signed_by_sar_encrypted_for_boomlet_i`, suffixed and signed by WT  
Purpose: prove that SAR recognized the identifier and can provide the fingerprint/IV needed for backup verification.  
Receiver validations: verify WT suffix and signature; decrypt inner content; verify SAR signature; compare `doxing_data_identifier_i`.  
State effect on receiver: Boomlet stores `sar_setup_response_i`.  
Source anchors: `setup.md` 63–66; `setup.puml` 63–66.

**Family `Setup.SARActivation.PeerSync`**  
Sender: each `Boomlet(i)` via `Niso(i)`  
Receiver: peers, then local `Boomlet(i)`  
Payload: signed `shared_state_active_sar_fingerprint` and later all-peers collection  
Purpose: prove that all peers have active SAR protection.  
Receiver validations: signature validity and content equality across all peers.  
State effect on receiver: local peer may proceed to backup creation.  
Source anchors: `setup.md` 66–70; `setup.puml` 66–70.

### 7.7 Setup: Boomlet backup and final synchronization

**Family `Setup.Backup.Request`**  
Sender: `Iso(i)`  
Receiver: `Boomlet(i)`  
Payload: `backup_request_signed_by_normal_i` containing magic, `boomletwo_identity_pubkey`, and `normal_pubkey_i`  
Purpose: authorize backup export using recoverable normal key material.  
Receiver validations: verify normal-key signature; magic equality; backup-normal-key equality to `normal_pubkey_i`.  
State effect on receiver: Boomlet emits encrypted backup data excluding current mystery.  
Source anchors: `setup.md` 75–77; `setup.puml` 75–77.

**Family `Setup.Backup.Export`**  
Sender: `Boomlet(i)`  
Receiver: `Iso(i)`  
Payload: encrypted backup blob, `boomlet_i_identity_pubkey`, `boomerang_params`, `sar_setup_response_i`  
Purpose: provide exactly the data needed for Boomletwo import and offline verification.  
Receiver validations: Iso reconstructs descriptor, re-derives `doxing_key_i` and `doxing_data_identifier_i`, and checks the static doxing-data fingerprint against `sar_setup_response_i`.  
State effect on receiver: Iso enters transfer-to-Boomletwo state.  
Source anchors: `setup.md` 77–78; `setup.puml` 77–78.

**Family `Setup.Backup.Import`**  
Sender: `Iso(i)`  
Receiver: `Boomletwo(i)`  
Payload: `boomlet_i_identity_pubkey`, encrypted backup blob  
Purpose: import backup state into Boomletwo.  
Receiver validations: decrypt using DH with `boomlet_i_identity_pubkey`; import data; generate independent `mystery_i` for Boomletwo.  
State effect on receiver: Boomletwo emits `backup_done_signed_by_boomletwo_i`.  
Source anchors: `setup.md` 79–82; `setup.puml` 79–82.

**Family `Setup.Backup.DoneAck`**  
Sender: `Boomletwo(i)` via `Iso(i)`  
Receiver: `Boomlet(i)`  
Payload: `backup_done_signed_by_boomletwo_i`  
Purpose: prove successful backup import to the original Boomlet.  
Receiver validations: verify Boomletwo signature, magic, backup Boomlet pubkey, and original Boomlet pubkey.  
State effect on receiver: Boomlet closes backup procedure and refuses further backup attempts for this setup instance.  
Source anchors: `setup.md` 82–86; `setup.puml` 82–86.

**Family `Setup.Backup.FinalPeerSync`**  
Sender: each `Boomlet(i)` via `Niso(i)`  
Receiver: peers, then local `Boomlet(i)`  
Payload: signed `shared_state_active_backup_fingerprint` and later all-peers collection  
Purpose: prove that all peers completed backup creation before final setup completion.  
Receiver validations: signature validity and content equality across all peers.  
State effect on receiver: local setup enters complete state and emits `"setup_done"`.  
Source anchors: `setup.md` 88–94; `setup.puml` 88–94.

### 7.8 Withdrawal: approval and PSBT distribution

**Family `Withdrawal.Initiator.LocalPSBTStart`**  
Sender: `User(initiator)` then `Niso(initiator)` then `Boomlet(initiator)` then `ST(initiator)`  
Receiver: local peer actors only  
Payload: PSBT, observed block height, encrypted `tx_id_with_nonce`, ST acknowledgment  
Purpose: start the ceremony, latch a single `tx_id`, and prove local user approval of that `tx_id`.  
Receiver validations: milestone block reached, PSBT satisfiable, `tx_id` equality, ST signature validity, nonce equality/freshness.  
State effect on receiver: initiator Boomlet creates the initiator approval and encrypted PSBT copies for non-initiators.  
Source anchors: `withdrawal.md` 1–8; `initiator_withdrawal.puml` 1–8.

**Family `Withdrawal.InitiatorApprovalToWT`**  
Sender: `Boomlet(initiator)` via `Niso(initiator)`  
Receiver: `WT`  
Payload: encrypted signed initiator `"approved"` message and per-peer encrypted PSBT collection  
Purpose: let WT fix the ceremony `tx_id` and distribute the PSBT to non-initiators.  
Receiver validations: WT decrypts, verifies initiator signature, magic `"approved"`, and initiator approval freshness.  
State effect on receiver: WT stores the ceremony `tx_id` and emits `wt_tx_approval`.  
Source anchors: `withdrawal.md` 8–10; `initiator_withdrawal.puml` 8–10.

**Family `Withdrawal.WTApprovalFanout`**  
Sender: `WT`  
Receiver: each non-initiator `Niso(i)`  
Payload: `wt_tx_approval_signed_by_wt`, initiator approval, and that peer’s encrypted PSBT  
Purpose: notify non-initiators of the ceremony and give each one its PSBT.  
Receiver validations: WT signature, initiator identity membership in `peer_ids_collection`, initiator signature, magic equality, `tx_id` equality, milestone reached, and freshness checks.  
State effect on receiver: non-initiator Boomlet can decrypt and locally present the PSBT.  
Source anchors: `withdrawal.md` 10–13; `non_initiator_withdrawal.puml` 10–13.

**Family `Withdrawal.NonInitiator.LocalPSBTApproval`**  
Sender: local non-initiator actors `Niso(i)`, `Boomlet(i)`, `ST(i)`, `User(i)`  
Receiver: local only  
Payload: decrypted PSBT, initiator identity, encrypted `tx_id_with_nonce`, ST acknowledgment  
Purpose: obtain local user approval for the same `tx_id` on each non-initiator peer.  
Receiver validations: PSBT satisfiable, `tx_id` equality, ST signature validity, nonce equality/freshness.  
State effect on receiver: non-initiator Boomlet creates its own peer approval for WT.  
Source anchors: `withdrawal.md` 13–23; `non_initiator_withdrawal.puml` 13–23.

**Family `Withdrawal.NonInitiatorApprovalsToWT`**  
Sender: each non-initiator `Boomlet(i)` via `Niso(i)`  
Receiver: `WT`  
Payload: encrypted signed `"approved"` message from that peer  
Purpose: inform WT that the peer locally approved the same transaction.  
Receiver validations: decrypt, verify signature, check magic, `tx_id`, and freshness relative to WT height and earlier WT approval.  
State effect on receiver: WT adds the approval to the approval collection and, once sufficient approvals arrive, redistributes approval collections.  
Source anchors: `withdrawal.md` 22–26; `non_initiator_withdrawal.puml` 22–26; `initiator_withdrawal.puml` 24–25.

### 7.9 Withdrawal: initial duress check and commitment

**Family `Withdrawal.InitialDuressCheck`**  
Sender: `Boomlet(i)` via `Niso(i)` to `ST(i)` and back  
Receiver: local only  
Payload: encrypted challenge space plus nonce; encrypted selected indices plus copied nonce  
Purpose: force the user to prove non-duress or signal duress immediately before commitment.  
Receiver validations: all approvals present and valid; nonce equality; challenge/response decrypt correctly; selected-number set equals or differs from `duress_consent_set_i`.  
State effect on receiver: set or update `duress_placeholder_plaintext_i`.  
Source anchors: `withdrawal.md` 27–33 and 27n–33n; `initiator_withdrawal.puml` 27–33; `non_initiator_withdrawal.puml` 27n–33n; `duress.md` withdrawal ceremony.

**Family `Withdrawal.InitiatorCommitToWT`**  
Sender: `Boomlet(initiator)` via `Niso(initiator)`  
Receiver: `WT`, then `SAR`, then non-initiators via WT  
Payload: encrypted padded initiator `"commit"` message plus, after SAR processing, WT-signed commit acknowledgment and SAR-signed placeholder for that initiator  
Purpose: commit the initiator to the fixed `tx_id` and send the first duress-bearing placeholder to SAR.  
Receiver validations: WT verifies outer and inner initiator signatures, magic `"commit"`, expected `tx_id`, freshness; SAR decrypts placeholder, detects zero or duress, signs placeholder back.  
State effect on receiver: WT stores initiator commit; non-initiators are then allowed to emit their own commits.  
Source anchors: `withdrawal.md` 33–38; `initiator_withdrawal.puml` 33–38; `DEEPDIVE.md` withdrawal Group 4.

**Family `Withdrawal.NonInitiatorApprovalsBundleToWT`**  
Sender: each non-initiator `Boomlet(i)` via `Niso(i)`  
Receiver: `WT`  
Payload: `approvals_signed_by_boomlet_i` containing all peer approvals and `wt_tx_approval`  
Purpose: prove that the non-initiator saw the same approval set before it emits its own commit.  
Receiver validations: verify non-initiator signature and bundled content equality to the expected approvals.  
State effect on receiver: WT accepts that the non-initiator may proceed once the initiator commit path advances.  
Source anchors: `withdrawal.md` 33n–35n; `non_initiator_withdrawal.puml` 33n–35n.  
Important asymmetry: this bundle is not the non-initiator’s own commit.

**Family `Withdrawal.NonInitiatorCommitToWT`**  
Sender: each non-initiator `Boomlet(i)` via `Niso(i)`  
Receiver: `WT`, then `SAR`, then all peers via WT  
Payload: encrypted padded non-initiator `"commit"` message, then SAR-signed placeholder, then WT-signed commit collection  
Purpose: commit each non-initiator after the initiator commit has already been WT-acknowledged.  
Receiver validations: WT verifies outer and inner signatures, magic `"commit"`, expected `tx_id`, and freshness; SAR processes the placeholder as above.  
State effect on receiver: once all commits exist, WT distributes the full commit collection and the corresponding SAR-signed placeholder to each peer.  
Source anchors: `withdrawal.md` 39–45; `non_initiator_withdrawal.puml` 39–44; `initiator_withdrawal.puml` 41–45.

### 7.10 Withdrawal: ping, pong, reached-pings, and signing handoff

**Family `Withdrawal.Ping`**  
Sender: each `Boomlet(i)` via `Niso(i)`  
Receiver: `WT`, then indirectly `SAR`  
Payload: padded signed `"ping"` containing `{tx_id, last_seen_block, ping_seq_num, reached_mystery_flag}` plus current `duress_placeholder_i`  
Purpose: advance the digging game and optionally announce that this peer reached its mystery threshold.  
Receiver validations: WT verifies outer and inner signatures, magic `"ping"`, expected `tx_id`, freshness, and sequence-number increase after the first ping; WT rejects a first ping that already has `reached_mystery_flag = 1`.  
State effect on receiver: WT may record a reached ping in `reached_pings_collection`; SAR processes the placeholder.  
Source anchors: `withdrawal.md` 46–49 and 58–59; `initiator_withdrawal.puml` 46–49 and 58–59; `DEEPDIVE.md` withdrawal Group 6.

**Family `Withdrawal.Pong`**  
Sender: `WT`  
Receiver: each `Niso(i)`, then local `Boomlet(i)`  
Payload: encrypted signed `"pong"` containing `{tx_id, WT block height, collection of other peers’ pings}` plus the SAR-signed placeholder corresponding to the recipient peer’s last sent placeholder  
Purpose: deliver a synchronized view of the prior ping round and allow each Boomlet to update its local digging-game variables.  
Receiver validations: WT signature, magic `"pong"`, expected `tx_id`, freshness relative to local Niso height; for each included previous ping, peer signature, magic, `tx_id`, monotone `ping_seq_num`, and consistency with previously reached peers.  
State effect on receiver: peer may update `counter_i`, `reached_boomlets_collection_i`, `reached_mystery_flag_i`, `last_seen_block_i`, and the next ping.  
Source anchors: `withdrawal.md` 49–57; `initiator_withdrawal.puml` 49–57; `DEEPDIVE.md` withdrawal Group 6.

**Family `Withdrawal.ReachedPingsCollection`**  
Sender: `WT`  
Receiver: every `Niso(i)` and then `Boomlet(i)`  
Payload: final `reached_pings_collection`  
Purpose: terminate the digging game once WT has a reached ping for every peer.  
Receiver validations: presence and validity of each peer’s reached ping.  
State effect on receiver: Niso hydrates the PSBT; Boomlet re-verifies the reached pings and the hydrated `tx_id`, then enters ready-to-sign state.  
Source anchors: `withdrawal.md` 59–62; `initiator_withdrawal.puml` 59–62; `DEEPDIVE.md` withdrawal Group 7.

**Family `Withdrawal.SigningHandoff`**  
Sender: `Niso(i)`, `User(i)`, `Iso(i)`, and `Boomlet(i)`  
Receiver: local only  
Payload: readiness magic, network, mnemonic, passphrase, PSBT, descriptor, boom share pubkey, public nonces, partial signatures  
Purpose: move from WT-coordinated digging to local Iso–Boomlet signing.  
Receiver validations: local actor-state consistency; by construction the peer is already in ready-to-sign state.  
State effect on receiver: produce and store `signed_psbt_i`.  
Source anchors: `withdrawal.md` 62–69; `initiator_withdrawal.puml` 62–69; `DEEPDIVE.md` withdrawal Group 7.

**Family `Withdrawal.SignedPSBTExportAndAggregation`**  
Sender: `Boomlet(i)` via `Niso(i)` to `WT`  
Receiver: `WT`  
Payload: `psbt_signed_i`  
Purpose: export the peer’s completed signed PSBT fragment and let WT aggregate all five.  
Receiver validations: the sources do not spell out a separate post-export validity check beyond aggregation, so this specification treats aggregation success as an abstract WT action guarded by receipt of all five signed PSBTs.  
State effect on receiver: WT aggregates and relays the final signed transaction; Boomlet resets withdrawal-local state and regenerates `mystery_i`.  
Source anchors: `withdrawal.md` 70–73; `initiator_withdrawal.puml` 70–73; `DEEPDIVE.md` withdrawal Group 7.

8. Global phase machine

The top-level machine is named `Global`. It advances only when the source files authorize a phase boundary.

### `Global.PreSetup`

Entry condition: no completed Boomerang setup exists for the peer set.  
Exit condition: the first SAR sign-up message is sent for each peer that will participate in the setup.  
Outbound transitions: to `Global.Setup.SARSignup`.  
Notes: this phase does not yet imply the existence of `boomerang_params` or any Boomlet state.

### `Global.Setup.SARSignup`

Entry condition: `Phone(i)` has user doxing inputs and starts SAR registration.  
Exit condition: all participating peers reached the user-visible `"setup_sar_registered_and_connected_to_phone"` point.  
Core effect: establish `doxing_key_i`, `doxing_data_identifier_i`, and a synced phone/SAR registration.  
Outbound transitions: to `Global.Setup.DuressSetup`.

### `Global.Setup.DuressSetup`

Entry condition: local Iso and Boomlet installation begins and ST pairing is available.  
Exit condition: each peer’s Boomlet emitted `"setup_duress_finished"` and Iso returned the mnemonic.  
Core effect: establish `normal_pubkey_i`, Boomlet identity and boom-share keys, shared Boomlet–ST secret, and `duress_consent_set_i`.  
Outbound transitions: to `Global.Setup.OnlineIdentityAndParams`.

### `Global.Setup.OnlineIdentityAndParams`

Entry condition: each user connects Boomlet to Niso after offline duress setup.  
Exit condition: `boomerang_params` are fixed across all peers.  
Core effect: establish Tor identity, exchange peer ids and addresses out of band, verify the boomerang parameter seed through ST, and obtain all-peers signed equality on `boomerang_params`.  
Outbound transitions: to `Global.Setup.WTRegistration`.

### `Global.Setup.WTRegistration`

Entry condition: `boomerang_params` are fixed and each Boomlet has generated its initial `mystery_i`.  
Exit condition: all peers have local proof that WT registration is active for every peer.  
Core effect: create `boomerang_params_fingerprint`, register peers and their Tor identities with WT, settle WT service fees, and synchronize `shared_state_active_wt_fingerprint`.  
Outbound transitions: to `Global.Setup.SARActivation`.

### `Global.Setup.SARActivation`

Entry condition: WT registration is confirmed.  
Exit condition: all peers have local proof that SAR finalization is active for every peer.  
Core effect: link each Boomlet identity to its pre-existing SAR registration through WT, store `sar_setup_response_i`, and synchronize `shared_state_active_sar_fingerprint`.  
Outbound transitions: to `Global.Setup.Backup`.

### `Global.Setup.Backup`

Entry condition: SAR activation is confirmed and the user is told to initialize the backup procedure.  
Exit condition: local Boomlet accepted `backup_done_signed_by_boomletwo_i`.  
Core effect: install Boomletwo, authorize backup export with the normal key, export Boomlet state excluding current `mystery_i`, verify descriptor and static doxing fingerprint offline, import backup into Boomletwo, and obtain signed backup completion from Boomletwo.  
Outbound transitions: to `Global.Setup.FinalSynchronization`.

### `Global.Setup.FinalSynchronization`

Entry condition: local backup procedure completed.  
Exit condition: every peer reached `"setup_done"`.  
Core effect: synchronize `shared_state_active_backup_fingerprint`, prove that all peers completed backup creation, and mark setup complete.  
Outbound transitions: to `Global.ActiveReady`.

### `Global.ActiveReady`

Entry condition: setup completed successfully and no boomerang-regime withdrawal is active.  
Exit condition: either the initiator starts a withdrawal ceremony after `milestone_block_0`, or an out-of-scope ancillary/deterministic fallback path is invoked.  
Core effect: hold inherited setup state stable for later withdrawal.  
Outbound transitions: to `Global.Withdrawal.Initiation`, or to explicit out-of-scope branches such as ancillary recovery or deterministic regime use.

### `Global.Withdrawal.Initiation`

Entry condition: an initiator user submits a PSBT and `milestone_block_0` has been reached.  
Exit condition: WT accepted the initiator approval and distributed `wt_tx_approval` plus encrypted PSBT copies to non-initiators.  
Core effect: latch a candidate `tx_id`, run the explicit ST/Boomlet nonce-coupled `tx_id` challenge-response, and only then create the initiator approval message.  
Outbound transitions: to `Global.Withdrawal.Approval`.

### `Global.Withdrawal.Approval`

Entry condition: non-initiators have received the WT initiation bundle.  
Exit condition: WT has collected the expected approval set and all peers have locally validated the approval collection required to proceed.  
Core effect: each non-initiator locally approves the PSBT, runs its own explicit ST/Boomlet nonce-coupled `tx_id` challenge-response, emits its own approval only after that transcript succeeds, and all peers mirror approval validations.  
Outbound transitions: to `Global.Withdrawal.Commitment`.

### `Global.Withdrawal.Commitment`

Entry condition: all approvals needed by the sources are present.  
Exit condition: WT has redistributed the full commit collection and each peer verified its own SAR-signed placeholder.  
Core effect: initial ST/Boomlet nonce-coupled duress check, initiator commit, non-initiator approvals bundle asymmetry, non-initiator commits, SAR processing of each placeholder, and full commit collection redistribution.  
Outbound transitions: to `Global.Withdrawal.DiggingGame`.

### `Global.Withdrawal.DiggingGame`

Entry condition: every peer verified the commit collection and entered the digging game with `counter=0`, `ping_seq_num=0`, `reached_mystery_flag=0`, and empty reached collections.  
Exit condition: WT holds a valid reached ping for every peer and distributes `reached_pings_collection`.  
Core effect: repeated ping-pong rounds, optional recurring ST/Boomlet nonce-coupled duress checks before selected next pings, counter increments, monotone reaching of local mysteries, and WT loop termination on all-peers reached condition.  
Outbound transitions: to `Global.Signing`.

### `Global.Signing`

Entry condition: each peer verified `reached_pings_collection`, updated the saved PSBT with `hydrated_psbt`, and emitted `"withdrawal_ready_to_sign"`.  
Exit condition: each peer has a locally stored `signed_psbt_i` and the user reconnected Boomlet to Niso for export.  
Core effect: Iso/Boomlet MuSig2 cooperation using the inherited setup material plus the hydrated PSBT.  
Outbound transitions: to `Global.Broadcast`.

### `Global.Broadcast`

Entry condition: each Boomlet has exported `psbt_signed_i` to its Niso and Niso forwarded it to WT.  
Exit condition: WT aggregated all five signed PSBTs and relayed the resulting signed transaction to the network.  
Core effect: aggregate and relay the fully signed transaction.  
Outbound transitions: to `Global.PostWithdrawalReset`.

### `Global.PostWithdrawalReset`

Entry condition: local Boomlet exported `psbt_signed_i`.  
Exit condition: local withdrawal state is cleared and `mystery_i` has been regenerated.  
Core effect: clear withdrawal-specific local state except the signed-PSBT artifact the sources preserve long enough to export, and regenerate the next `mystery_i`.  
Outbound transitions: to `Global.ActiveReady`.  
Important boundary: this reset is specified only for the immediate local Boomlet state after signing; multi-ceremony rollover, descriptor extension, and deterministic fallback are outside the current machine.

9. Parameterized composite machine `Peer(i)`

`Peer(i)` is the peer-local composite actor family, parameterized by `i in {0..4}`. It contains the sub-actors `User(i)`, `Phone(i)`, `Iso(i)`, `Niso(i)`, `Boomlet(i)`, `Boomletwo(i)`, and `ST(i)`. `WT` and `SAR` remain external actors even though `Peer(i)` interacts with them often.

### 9.1 Composite states

**`Peer(i).Setup.SARRegistered` [DERIVED]**  
Meaning: Phone/SAR registration has completed and user may proceed to offline hardware installation.  
Why needed: the sources treat SAR sign-up as a distinct phase inherited by later setup.  
Entry condition: Phone received the SAR sync magic and informed User.  
Exit condition: Iso begins Boomlet installation.  
Anchors: `setup.md` 1–8; `setup.puml` 1–8.

**`Peer(i).Setup.DuressConfigured` [DERIVED]**  
Meaning: Boomlet, ST, and User have established and confirmed `duress_consent_set_i`.  
Entry condition: `Boomlet(i)` emitted `"setup_duress_finished"`.  
Exit condition: User disconnects Iso and connects Boomlet to Niso.  
Anchors: `setup.md` 9–28; `setup.puml` 9–28; `duress_setup.puml`.

**`Peer(i).Setup.ParamsFixed`**  
Meaning: the peer has fixed `boomerang_params` locally and believes all peers have signed the same value.  
Entry condition: local Boomlet accepted `boomerang_params_signed_by_all_peers`.  
Exit condition: local WT registration begins.  
Anchors: `setup.md` 34–45; `setup.puml` 34–45.

**`Peer(i).Setup.WTAndSARActive` [DERIVED]**  
Meaning: local peer has proof that WT and SAR activation are both complete for all peers.  
Entry condition: local peer accepted both `shared_state_active_wt_fingerprint_signed_by_all_peers` and `shared_state_active_sar_fingerprint_signed_by_all_peers`.  
Exit condition: local backup procedure begins.  
Anchors: `setup.md` 46–70; `setup.puml` 46–70.

**`Peer(i).Setup.BackupComplete`**  
Meaning: local Boomlet verified `backup_done_signed_by_boomletwo_i` and local peer later accepted all-peers backup sync.  
Entry condition: local Boomlet accepts the backup completion and later all-peer backup fingerprint sync.  
Exit condition: local setup emits `"setup_done"`.  
Anchors: `setup.md` 71–94; `setup.puml` 71–94.

**`Peer(i).ActiveReady`**  
Meaning: setup state is complete and inherited, but no boomerang withdrawal is active.  
Entry condition: `"setup_done"` delivered to `User(i)`.  
Exit condition: withdrawal starts or an out-of-scope ancillary/deterministic path is taken.  
Anchors: setup completion and all later withdrawal note blocks.

### 9.2 Initiator versus non-initiator asymmetry

The initiating peer, denoted `Peer(0)` only by role and not by permanent identity, enters withdrawal through a locally created PSBT and sends the first approval to WT. Non-initiators enter only when WT forwards the initiator bundle containing `wt_tx_approval`, the initiator’s signed approval, and an encrypted PSBT copy. That asymmetry persists through the approval phase and into the commitment phase:

- The initiator performs local ST `tx_id` approval first and emits the first `"approved"` message.
- Each non-initiator decrypts the PSBT, obtains local user approval of the PSBT, performs its own ST `tx_id` approval, and emits its own `"approved"` message.
- At the first duress check, the initiator immediately emits its own padded `"commit"` to WT.
- A non-initiator does **not** emit its own commit immediately after the initial duress check. Instead it first sends `approvals_signed_by_boomlet_i`, a signed bundle of all approvals plus `wt_tx_approval`, and only emits its own padded `"commit"` after it has received and validated WT’s acknowledgment of the initiator’s commit.

The authoritative TLA+ withdrawal model now makes the ST/Boomlet challenge-response subflow explicit inside that asymmetry instead of treating it as an implicit local check:

- `withdrawal.md` steps `2-8` map to the initiator's internal `AwaitingInitialTxIdAck` substate, where Boomlet fixes `{sid, tx_id, nonce}`, ST returns the matching signed acknowledgement, and only then does the initiator emit its approval toward WT.
- `withdrawal.md` steps `16-22` map to the non-initiator's internal `AwaitingInitialTxIdAck` substate, with the same nonce-bound `tx_id` acknowledgement requirement before approval emission.
- `withdrawal.md` steps `28-33` map to `AwaitingInitialDuressAck`, where Boomlet issues a nonce-bound initial duress challenge and derives the first placeholder kind only from the matching ST response.
- `withdrawal.md` steps `52-57` map to `AwaitingRecurringDuressAck`, where a selected digging round pauses before the next ping until the nonce-bound recurring duress response has been accepted.

This asymmetry ends after WT redistributes the full commit collection and each peer verifies its SAR-signed placeholder. From that point onward, the non-initiator withdrawal diagram explicitly states that the non-initiator follows the same steps as the initiator. This specification therefore converges both roles into a common `Peer(i).Withdrawal.DiggingGame` state beginning at commit-collection verification.

### 9.3 Composite withdrawal states

**`Peer(i).Withdrawal.Initiator.AwaitingLocalApproval`**  
Entry: user submitted a PSBT to `Niso(i)` and local milestone/freshness guards passed.  
Exit: initiator approval and encrypted PSBT copies were sent to WT.  
Anchors: `withdrawal.md` 1–9; `initiator_withdrawal.puml` 1–9.

**`Peer(i).Withdrawal.AwaitingInitialTxIdAck`** [DERIVED]  
Entry: local Boomlet fixed the candidate `tx_id`, created a nonce-bound ST challenge, and is waiting for the matching ST acknowledgement.  
Exit: local approval is emitted toward WT.  
Anchors: `withdrawal.md` 2–8 for the initiator, `withdrawal.md` 16–22 for each non-initiator, plus the corresponding withdrawal diagrams.

**`Peer(i).Withdrawal.NonInitiator.AwaitingWTBundle`**  
Entry: peer is active-ready and WT has not yet sent an initiation bundle.  
Exit: non-initiator decrypted the PSBT and moved to local user approval.  
Anchors: `withdrawal.md` 10–13; `non_initiator_withdrawal.puml` 10–13.

**`Peer(i).Withdrawal.NonInitiator.AwaitingLocalApproval`**  
Entry: non-initiator decrypted the PSBT and locally presented it to the user.  
Exit: local `"approved"` message sent to WT.  
Anchors: `withdrawal.md` 13–23; `non_initiator_withdrawal.puml` 13–23.

**`Peer(i).Withdrawal.AwaitingInitialDuressAck`** [DERIVED]  
Entry: the source-required approval set is locally validated and Boomlet has emitted the nonce-bound initial duress challenge to ST.  
Exit: initiator emitted a commit, or non-initiator emitted its approvals bundle.  
Anchors: `withdrawal.md` 28–33 for the initiator, `withdrawal.md` 28n–33n for non-initiators, and the follow-on commit steps in both withdrawal diagrams.

**`Peer(i).Withdrawal.AwaitingCommitCollection`**  
Entry: initiator commit path or non-initiator approvals-bundle path has advanced to the WT/SAR roundtrip.  
Exit: peer verified the complete commit collection and matching SAR-signed placeholder.  
Anchors: `withdrawal.md` 35–45; both withdrawal diagrams.

**`Peer(i).Withdrawal.DiggingGame`**  
Entry: peer initialized `counter_i`, `ping_seq_num_i`, `reached_mystery_flag_i`, `reached_boomlets_collection_i`, and `last_seen_block_i`.  
Exit: WT distributed `reached_pings_collection`.  
Anchors: `withdrawal.md` 45–61; `initiator_withdrawal.puml` 45–61; convergence note from `non_initiator_withdrawal.puml` step 44.

**`Peer(i).Withdrawal.AwaitingRecurringDuressAck`** [DERIVED]  
Entry: during the digging game, Boomlet selected a check-bearing round and emitted a nonce-bound recurring duress challenge to ST before constructing the next ping.  
Exit: peer emits the next ping for the current `ping_seq_num + 1`.  
Anchors: `withdrawal.md` 52–57 and the corresponding repeated-check steps in the withdrawal diagrams.

**`Peer(i).Withdrawal.ReadyToSign`**  
Entry: peer verified `reached_pings_collection` and matching hydrated `tx_id`.  
Exit: user connected Boomlet to Iso and local signing began.  
Anchors: `withdrawal.md` 60–65; `initiator_withdrawal.puml` 60–65.

**`Peer(i).Withdrawal.Signing`**  
Entry: Iso received signing inputs and Boomlet emitted signing material.  
Exit: `signed_psbt_i` exists and user reconnects Boomlet to Niso.  
Anchors: `withdrawal.md` 64–69; `initiator_withdrawal.puml` 64–69.

**`Peer(i).Withdrawal.SignedPSBTExported`**  
Entry: Boomlet responded to the signed-PSBT export request.  
Exit: WT aggregated all signed PSBTs and local Boomlet reset completed.  
Anchors: `withdrawal.md` 70–73; `initiator_withdrawal.puml` 70–73.

10. Actor-local machines

The states below are the states explicitly used in this specification. Every state not explicitly named in the sources is marked `[DERIVED]`. For brevity, repeated signature and freshness checks are described once and then referred to by family where the source duplicates them.

### 10.1 `User(i)` machine

#### `User(i).Setup.AwaitingSARInvoice` `[DERIVED]`
Meaning: the user has supplied SAR registration inputs to Phone and is waiting for invoice details.  
Stored variables relevant in this state: none beyond human-held `doxing_password`, `static_doxing_data`, `sar_ids_collection_i`.  
Allowed incoming events/messages: SAR payment info forwarded by Phone.  
Guards/preconditions: none.  
Actions/validations: verify invoice details and decide to pay.  
Emitted messages: payment receipt to `Phone(i)`.  
Next states: `User(i).Setup.AwaitingPhoneSARSync`.  
Failure exits: payment not made or invoice rejected; behavior after refusal is unspecified.  
Source anchors: `setup.md` 1–4; `setup.puml` 1–4.

#### `User(i).Setup.AwaitingPhoneSARSync` `[DERIVED]`
Meaning: the user has paid SAR and waits for phone/SAR synchronization confirmation.  
Stored variables relevant: payment receipt evidence.  
Allowed incoming events/messages: phone notification that SAR registration is complete and in sync.  
Guards/preconditions: none.  
Actions/validations: accept the sync completion and proceed to offline setup.  
Emitted messages: setup inputs to Iso.  
Next states: `User(i).Setup.AwaitingMnemonic`.  
Failure exits: missing SAR acknowledgment; terminal for the current setup attempt unless manually retried.  
Source anchors: `setup.md` 5–9; `setup.puml` 5–9.

#### `User(i).Setup.AwaitingMnemonic`
Meaning: the user is engaged in offline Boomlet installation and duress setup, but mnemonic has not yet been returned by Iso.  
Stored variables relevant: chosen passphrase, doxing password, consent-set memory under formation.  
Allowed incoming events/messages: ST displays initial consent challenge, ST displays confirmation challenge, Iso returns mnemonic.  
Guards/preconditions: ST pairing exists.  
Actions/validations: choose five consent countries, later reproduce them during confirmation, and store mnemonic securely when returned.  
Emitted messages: ST joystick inputs; physical save action for mnemonic.  
Next states: `User(i).Setup.ExchangingPeerIdentityOutOfBand`.  
Failure exits: failed duress confirmation; retry semantics are ambiguous and recorded in Section 16.  
Source anchors: `setup.md` 9–28; `setup.puml` 9–28; `duress_setup.puml`.

#### `User(i).Setup.ExchangingPeerIdentityOutOfBand`
Meaning: the user has received the signed Tor identity bundle and exchanges it securely with peers.  
Stored variables relevant: local `peer_i_id`, signed Tor address, received peer bundles.  
Allowed incoming events/messages: ST display/output of local identity bundle; out-of-band peer bundles from other users.  
Guards/preconditions: local Tor address signature already verified by Niso and ST.  
Actions/validations: perform secure out-of-band exchange and assemble `peer_addresses_collection`.  
Emitted messages: `peer_addresses_collection`, `wt_ids_collection`, and `milestone_block_collection` to `Niso(i)`.  
Next states: `User(i).Setup.AwaitingParamApprovalOnST`.  
Failure exits: incomplete peer set or distrust of out-of-band data; terminal or externally retryable but unspecified.  
Source anchors: `setup.md` 29–35; `setup.puml` 29–35.

#### `User(i).Setup.AwaitingParamApprovalOnST`
Meaning: the user is directly verifying the boomerang parameter seed shown through ST.  
Stored variables relevant: expected peer ids, WT ids, milestone blocks.  
Allowed incoming events/messages: ST display of `boomerang_params_seed`.  
Guards/preconditions: none beyond receipt.  
Actions/validations: verify peer ids, WT ids, and milestones; acknowledge through ST only if correct.  
Emitted messages: ST acknowledgment magic.  
Next states: `User(i).Setup.AwaitingWTFeePayment`, then `User(i).Setup.AwaitingBackupProcedure`.  
Failure exits: user rejects the displayed seed; terminal for this setup attempt unless restarted.  
Source anchors: `setup.md` 36–45; `setup.puml` 36–45.

#### `User(i).Setup.AwaitingWTFeePayment` `[DERIVED]`
Meaning: peer parameters are fixed and WT registration invoice has been presented.  
Stored variables relevant: WT invoice details.  
Allowed incoming events/messages: WT service fee payment info from Niso.  
Guards/preconditions: none.  
Actions/validations: verify invoice and pay WT.  
Emitted messages: WT payment receipt to `Niso(i)`.  
Next states: `User(i).Setup.AwaitingBackupProcedure`.  
Failure exits: payment not made or invoice disputed; progress stops.  
Source anchors: `setup.md` 49–53; `setup.puml` 49–53.

#### `User(i).Setup.AwaitingBackupProcedure`
Meaning: SAR finalization is complete and the user must move through the Boomletwo backup choreography.  
Stored variables relevant: `milestone_block_collection`, `network`, mnemonic, passphrase, static doxing data, doxing password.  
Allowed incoming events/messages: Niso backup-initiation notification; Iso prompts to connect Boomletwo or Boomlet; final setup-done notification.  
Guards/preconditions: local SAR finalization confirmed.  
Actions/validations: connect Boomletwo to Iso, later reconnect Boomlet, provide verification inputs to Iso, then reconnect Boomlet to Niso for final sync.  
Emitted messages: local user input and device-reconnection events.  
Next states: `User(i).ActiveReady`.  
Failure exits: backup import failure, mismatch in descriptor or SAR fingerprint verification, or backup acknowledgment mismatch.  
Source anchors: `setup.md` 71–94; `setup.puml` 71–94.

#### `User(i).ActiveReady`
Meaning: setup is complete and no boomerang withdrawal is active.  
Stored variables relevant: mnemonic, passphrase, remembered consent countries.  
Allowed incoming events/messages: for initiator, local desire to withdraw; for non-initiator, PSBT presentation from Niso after WT initiation.  
Guards/preconditions: none.  
Actions/validations: either create a PSBT (initiator role) or wait.  
Emitted messages: PSBT to Niso if acting as initiator.  
Next states: `User(i).Withdrawal.Initiator.ReviewingLocalTxId`, or `User(i).Withdrawal.NonInitiator.ReviewingPSBT`.  
Failure exits: none.

#### `User(i).Withdrawal.Initiator.ReviewingLocalTxId`
Meaning: initiator user has created the PSBT and is validating the locally displayed `tx_id` on ST.  
Stored variables relevant: locally created PSBT.  
Allowed incoming events/messages: `tx_id` from ST.  
Guards/preconditions: PSBT already supplied to Niso and forwarded to Boomlet.  
Actions/validations: compare displayed `tx_id` to the PSBT-derived `tx_id`; acknowledge only if equal.  
Emitted messages: ST acknowledgment magic.  
Next states: `User(i).Withdrawal.RespondingToDuressCheck`.  
Failure exits: mismatch between ST-displayed `tx_id` and local PSBT.  
Source anchors: `withdrawal.md` 1–6; `initiator_withdrawal.puml` 1–6.

#### `User(i).Withdrawal.NonInitiator.ReviewingPSBT`
Meaning: non-initiator user is shown the initiator’s PSBT and initiator identity by local Niso.  
Stored variables relevant: decrypted PSBT, initiator peer identity.  
Allowed incoming events/messages: PSBT plus initiator id, later ST-displayed `tx_id`.  
Guards/preconditions: local Niso and Boomlet accepted the WT initiation bundle.  
Actions/validations: approve the PSBT, then compare ST-displayed `tx_id` to the PSBT-derived `tx_id`.  
Emitted messages: local user-approval magic to Niso, then ST acknowledgment magic.  
Next states: `User(i).Withdrawal.RespondingToDuressCheck`.  
Failure exits: PSBT rejection or `tx_id` mismatch.  
Source anchors: `withdrawal.md` 13–20; `non_initiator_withdrawal.puml` 13–20.

#### `User(i).Withdrawal.RespondingToDuressCheck`
Meaning: the user is answering either the initial commitment-time duress check or a later repeated digging-game duress check.  
Stored variables relevant: remembered consent countries.  
Allowed incoming events/messages: ST-displayed duress check space.  
Guards/preconditions: local Boomlet initiated the check.  
Actions/validations: choose one country per displayed column; choose the consent-set reconstruction when not in duress and any other set when signaling duress.  
Emitted messages: ST joystick selection.  
Next states: remains in the withdrawal ceremony; eventually `User(i).Withdrawal.ReadyToSignViaIso`.  
Failure exits: no response, malformed response, or freshness failure on the response.  
Source anchors: `withdrawal.md` 27–33, 27n–33n, and 52–57; both withdrawal diagrams; `duress.md` withdrawal section.

#### `User(i).Withdrawal.ReadyToSignViaIso`
Meaning: local peer reached the WT break condition and Niso instructed the user to connect Boomlet to Iso.  
Stored variables relevant: mnemonic, passphrase.  
Allowed incoming events/messages: Niso readiness magic, Iso completion magic after signing.  
Guards/preconditions: local Boomlet accepted `reached_pings_collection` and `hydrated_psbt`.  
Actions/validations: connect Boomlet to Iso, provide network, mnemonic, and passphrase, later reconnect Boomlet to Niso.  
Emitted messages: local reconnection events only.  
Next states: `User(i).Withdrawal.AwaitingBroadcast`.  
Failure exits: missing local signing inputs or inability to reconnect hardware.  
Source anchors: `withdrawal.md` 62–70; `initiator_withdrawal.puml` 62–70.

#### `User(i).Withdrawal.AwaitingBroadcast`
Meaning: local signed PSBT has been created and exported; WT aggregation and relay are pending.  
Stored variables relevant: none additional.  
Allowed incoming events/messages: none specified back to the user after WT broadcast.  
Guards/preconditions: local Niso forwarded `psbt_signed_i` to WT.  
Actions/validations: none specified.  
Emitted messages: none.  
Next states: `User(i).ActiveReady` after local post-withdrawal reset.  
Failure exits: WT aggregation failure or missing peer signatures, which are outside user control and not separately signaled to the user in the sources.  
Source anchors: `withdrawal.md` 69–73; `initiator_withdrawal.puml` 69–73.

### 10.2 `Phone(i)` machine

#### `Phone(i).Setup.AwaitingRegistrationInput`
Meaning: phone has not yet begun SAR registration.  
Stored variables relevant: none.  
Allowed incoming events/messages: user supplies `doxing_password`, `sar_ids_collection_i`, `static_doxing_data`.  
Guards/preconditions: none.  
Actions/validations: derive `doxing_key_i` and `doxing_data_identifier_i`; send identifier to SAR.  
Emitted messages: `Setup.SARRegistration.Init`.  
Next states: `Phone(i).Setup.AwaitingPaymentInfo`.  
Failure exits: none specified.  
Source anchors: `setup.md` 1; `setup.puml` 1.

#### `Phone(i).Setup.AwaitingPaymentInfo`
Meaning: phone has initiated SAR registration and awaits invoice details.  
Stored variables relevant: `doxing_key_i`, `doxing_data_identifier_i`.  
Allowed incoming events/messages: `sar_service_fee_payment_info` from SAR.  
Guards/preconditions: SAR id must match configured collection.  
Actions/validations: verify SAR id and forward payment info to User.  
Emitted messages: invoice to `User(i)`.  
Next states: `Phone(i).Setup.AwaitingUserReceipt`.  
Failure exits: invoice SAR id mismatch.  
Source anchors: `setup.md` 2–3; `setup.puml` 2–3.

#### `Phone(i).Setup.AwaitingUserReceipt`
Meaning: phone awaits proof that the user paid the SAR invoice.  
Stored variables relevant: invoice details, `doxing_key_i`, `doxing_data_identifier_i`.  
Allowed incoming events/messages: payment receipt from User.  
Guards/preconditions: none.  
Actions/validations: encrypt static and dynamic doxing data with `doxing_key_i`; send receipt plus encrypted data to SAR.  
Emitted messages: `Setup.SARRegistration.DataAndReceipt`.  
Next states: `Phone(i).Setup.AwaitingSARSyncAck`.  
Failure exits: none specified.  
Source anchors: `setup.md` 4–6; `setup.puml` 4–6.

#### `Phone(i).Setup.AwaitingSARSyncAck`
Meaning: phone has sent receipt and encrypted doxing data and is waiting for SAR sync confirmation.  
Stored variables relevant: `doxing_key_i`, `doxing_data_identifier_i`, encrypted data streams.  
Allowed incoming events/messages: SAR sync acknowledgment.  
Guards/preconditions: none.  
Actions/validations: inform User of success and continue generating encrypted dynamic doxing data.  
Emitted messages: sync-complete magic to `User(i)` and later recurring dynamic doxing data to SAR.  
Next states: `Phone(i).Setup.SyncedWithSAR`.  
Failure exits: missing SAR acknowledgment.  
Source anchors: `setup.md` 6–8; `setup.puml` 6–8.

#### `Phone(i).Setup.SyncedWithSAR`
Meaning: phone is in steady state with SAR and continues sending encrypted dynamic data.  
Stored variables relevant: `doxing_key_i`, `doxing_data_identifier_i`, dynamic doxing data feed.  
Allowed incoming events/messages: dynamic doxing updates from the originating device or phone OS.  
Guards/preconditions: none.  
Actions/validations: encrypt and forward new dynamic doxing data.  
Emitted messages: recurring encrypted dynamic doxing data to SAR.  
Next states: remains here across setup and withdrawal.  
Failure exits: loss or tampering of the dynamic data feed, recognized as a concern rather than a handled branch.  
Source anchors: `setup.md` 6–8; `duress.md` doxing-data section; `DEEPDIVE.md` concern on phone data.

### 10.3 `Iso(i)` machine

#### `Iso(i).Off`
Meaning: Iso is powered down and retains no operative state.  
Stored variables relevant: none.  
Allowed incoming events/messages: user power-on with setup or backup mode intent, or signing intent.  
Guards/preconditions: none.  
Actions/validations: start a new session.  
Emitted messages: none until inputs are supplied.  
Next states: `Iso(i).Setup.Running`, `Iso(i).Setup.BackupMode`, or `Iso(i).Withdrawal.SigningReady`.  
Failure exits: none.  
Source anchors: withdrawal note on inherited state; `setup.md` 27–28 and 71–72.

#### `Iso(i).Setup.Running`
Meaning: Iso is active for initial offline setup before Niso participation.  
Stored variables relevant: session copies of network, entropy bytes, passphrase, doxing password, SAR ids, mnemonic, derived normal key material.  
Allowed incoming events/messages: user setup inputs, Boomlet identity pubkey, ST identity pubkey, ST duress responses, Boomlet duress completion.  
Guards/preconditions: none beyond active session.  
Actions/validations: create mnemonic and `normal_pubkey_i`; install Boomlet; relay ST pairing and duress-setup messages; return mnemonic on success.  
Emitted messages: installation payloads to Boomlet, pairing relay to ST and back, duress-setup relays, mnemonic to User.  
Next states: `Iso(i).Off` after mnemonic return.  
Failure exits: installation failure, pairing failure, duress confirmation failure.  
Source anchors: `setup.md` 9–27; `setup.puml` 9–27.

#### `Iso(i).Setup.BackupMode`
Meaning: Iso is active to install Boomletwo and orchestrate backup import.  
Stored variables relevant: session-local backup verification inputs, reconstructed normal key material, `sar_setup_response_i`, encrypted backup blob.  
Allowed incoming events/messages: User backup-mode initiation, Boomletwo identity pubkey, Boomlet backup export, backup-done acknowledgment, Boomlet backup verification result.  
Guards/preconditions: local SAR finalization already completed.  
Actions/validations: install Boomletwo; generate signed backup request with normal key; reconstruct descriptor; re-derive doxing values and verify static doxing-data fingerprint from `sar_setup_response_i`; transfer backup blob to Boomletwo; relay `backup_done_signed_by_boomletwo_i` to Boomlet.  
Emitted messages: backup request, backup import transfer, user prompts.  
Next states: `Iso(i).Off` after backup completion is acknowledged by Boomlet.  
Failure exits: descriptor mismatch, doxing identifier mismatch, static doxing-data fingerprint mismatch, backup-done mismatch.  
Source anchors: `setup.md` 72–87; `setup.puml` 72–87.

#### `Iso(i).Withdrawal.SigningReady`
Meaning: Iso has been powered on for signing and has received network, mnemonic, and passphrase.  
Stored variables relevant: reconstructed normal private key material.  
Allowed incoming events/messages: user signing inputs.  
Guards/preconditions: local peer already in ready-to-sign state.  
Actions/validations: reconstruct normal signing material and notify Boomlet to begin collaborative signing.  
Emitted messages: `"withdrawal_initialized_start_signing"` to Boomlet.  
Next states: `Iso(i).Withdrawal.CoordinatingMuSig2`.  
Failure exits: inability to reconstruct signing material from mnemonic/passphrase.  
Source anchors: `withdrawal.md` 63–65; `initiator_withdrawal.puml` 63–65.

#### `Iso(i).Withdrawal.CoordinatingMuSig2`
Meaning: Iso is actively collaborating with Boomlet to sign the hydrated PSBT.  
Stored variables relevant: PSBT, descriptor, reconstructed normal-key material, pubnonce_normal, partialsig_normal, signed PSBT copy.  
Allowed incoming events/messages: PSBT, descriptor, Boomlet pubkey share, `pubnonce_boom`, then `partialsig_boom`.  
Guards/preconditions: none beyond prior entry.  
Actions/validations: generate `pubnonce_normal`; create `partialsig_normal`; accept `partialsig_boom`; keep signed PSBT copy; tell User to reconnect Boomlet to Niso.  
Emitted messages: `pubnonce_normal`, `partialsig_normal` to Boomlet; completion magic to User.  
Next states: `Iso(i).Off`.  
Failure exits: signing failure or mismatch not separately specified in the sources.  
Source anchors: `withdrawal.md` 65–69; `initiator_withdrawal.puml` 65–69.

### 10.4 `ST(i)` machine

#### `ST(i).Unpaired`
Meaning: ST does not yet have a paired Boomlet identity.  
Stored variables relevant: none.  
Allowed incoming events/messages: `boomlet_i_identity_pubkey` from Iso.  
Guards/preconditions: none.  
Actions/validations: generate ST identity keypair and shared Boomlet–ST secret.  
Emitted messages: `st_i_identity_pubkey` to Iso.  
Next states: `ST(i).Paired.Idle`.  
Failure exits: none specified.  
Source anchors: `setup.md` 11–13; `setup.puml` 11–13; `duress_setup.puml` 1–4.

#### `ST(i).Paired.Idle`
Meaning: ST is paired and waiting for the next Boomlet-originated challenge or display request.  
Stored variables relevant: paired keys and shared secret.  
Allowed incoming events/messages: encrypted duress setup challenge, encrypted boomerang params seed, encrypted `tx_id_with_nonce`, encrypted withdrawal duress-check challenge.  
Guards/preconditions: paired state exists.  
Actions/validations: branch to the appropriate prompting state.  
Emitted messages: none until the challenge is displayed or the user responds.  
Next states: `ST(i).Setup.AwaitingConsentSelection`, `ST(i).Setup.AwaitingConsentConfirmation`, `ST(i).Setup.AwaitingParamConfirmation`, `ST(i).Withdrawal.AwaitingTxIdAcknowledgement`, or `ST(i).Withdrawal.AwaitingDuressSelection`.  
Failure exits: decryption failure or malformed challenge.

#### `ST(i).Setup.AwaitingConsentSelection`
Meaning: ST has decrypted the initial setup challenge space and is waiting for the user’s consent-set choices.  
Stored variables relevant: `duress_check_space_i`, copied nonce.  
Allowed incoming events/messages: user joystick selection.  
Guards/preconditions: challenge decrypted successfully.  
Actions/validations: encode indices, attach copied nonce, encrypt for Boomlet, send through Iso.  
Emitted messages: encrypted `duress_signal_index_i` with nonce.  
Next states: `ST(i).Paired.Idle`.  
Failure exits: none specified.  
Source anchors: `setup.md` 14–19; `setup.puml` 14–19.

#### `ST(i).Setup.AwaitingConsentConfirmation`
Meaning: ST has decrypted the second setup challenge space and is waiting for the user to reproduce the consent set.  
Stored variables relevant: second `duress_check_space_i`, copied nonce.  
Allowed incoming events/messages: user joystick selection.  
Guards/preconditions: confirmation challenge decrypted successfully.  
Actions/validations: encode confirmation indices, attach copied nonce, encrypt for Boomlet, send through Iso.  
Emitted messages: encrypted confirmation response.  
Next states: `ST(i).Paired.Idle`.  
Failure exits: none specified by ST itself; failure is detected at Boomlet.  
Source anchors: `setup.md` 20–26; `setup.puml` 20–26; `duress_setup.puml` 11–16.

#### `ST(i).Setup.AwaitingParamConfirmation`
Meaning: ST has decrypted `boomerang_params_seed` and is displaying it to the user.  
Stored variables relevant: `boomerang_params_seed_with_nonce`.  
Allowed incoming events/messages: user acknowledgment magic.  
Guards/preconditions: successful decryption.  
Actions/validations: sign the exact `boomerang_params_seed_with_nonce`, encrypt for Boomlet, send through Niso.  
Emitted messages: ST-signed encrypted parameter-seed approval.  
Next states: `ST(i).Paired.Idle`.  
Failure exits: none specified.  
Source anchors: `setup.md` 36–41; `setup.puml` 36–41.

#### `ST(i).Withdrawal.AwaitingTxIdAcknowledgement`
Meaning: ST has decrypted `tx_id_with_nonce` and is displaying the `tx_id` to the user.  
Stored variables relevant: `tx_id_with_nonce`.  
Allowed incoming events/messages: user acknowledgment magic.  
Guards/preconditions: decryption succeeded.  
Actions/validations: sign `tx_id_with_nonce`, encrypt for Boomlet, send through Niso.  
Emitted messages: ST-signed encrypted `tx_id_with_nonce`.  
Next states: `ST(i).Paired.Idle`.  
Failure exits: local user refusal or mismatch observed by the user.  
Source anchors: `withdrawal.md` 3–7 and 16–21; both withdrawal diagrams.

#### `ST(i).Withdrawal.AwaitingDuressSelection`
Meaning: ST has decrypted a withdrawal duress-check challenge and is displaying the challenge columns to the user.  
Stored variables relevant: `duress_check_space_i`, copied nonce.  
Allowed incoming events/messages: user joystick selection.  
Guards/preconditions: challenge decrypted successfully.  
Actions/validations: encode selected indices, attach copied nonce, encrypt for Boomlet, send through Niso.  
Emitted messages: encrypted duress-check response.  
Next states: `ST(i).Paired.Idle`.  
Failure exits: no user response or malformed local input.  
Source anchors: `withdrawal.md` 28–32, 28n–32n, and 52–56; both withdrawal diagrams; `duress.md` withdrawal section.

### 10.5 `Boomlet(i)` machine

#### `Boomlet(i).Uninstalled`
Meaning: no personalized Boomlet applet exists on the smart card.  
Stored variables relevant: none.  
Allowed incoming events/messages: installation payload from Iso.  
Guards/preconditions: card must be empty.  
Actions/validations: personalize card and generate identity, boom-share, peer, and Tor-secret state.  
Emitted messages: `boomlet_i_identity_pubkey` to Iso.  
Next states: `Boomlet(i).Setup.AwaitingSTPairing`.  
Failure exits: installation on non-empty card or installation failure.  
Source anchors: `setup.md` 9–10; `setup.puml` 9–10.

#### `Boomlet(i).Setup.AwaitingSTPairing`
Meaning: Boomlet is installed but has not yet completed ST pairing.  
Stored variables relevant: identity keys, boom share, `peer_i_id`, Tor secret key, `doxing_key_i`, SAR ids.  
Allowed incoming events/messages: `st_i_identity_pubkey`.  
Guards/preconditions: none.  
Actions/validations: compute shared Boomlet–ST secret; create first duress-setup challenge.  
Emitted messages: encrypted initial duress challenge to ST via Iso.  
Next states: `Boomlet(i).Setup.AwaitingInitialConsentResponse`.  
Failure exits: missing or malformed ST key.  
Source anchors: `setup.md` 10–15; `setup.puml` 10–15.

#### `Boomlet(i).Setup.AwaitingInitialConsentResponse`
Meaning: Boomlet has sent the initial duress-setup challenge and awaits the user’s first consent-set selection.  
Stored variables relevant: `duress_check_space_i`, copied nonce, shared ST secret.  
Allowed incoming events/messages: encrypted `duress_signal_index_i` with nonce from ST via Iso.  
Guards/preconditions: nonce equality.  
Actions/validations: derive and store `duress_consent_set_i`; generate confirmation challenge.  
Emitted messages: confirmation challenge to ST via Iso.  
Next states: `Boomlet(i).Setup.AwaitingConsentConfirmationResponse`.  
Failure exits: nonce mismatch or malformed selection.  
Source anchors: `setup.md` 14–20; `setup.puml` 14–20.

#### `Boomlet(i).Setup.AwaitingConsentConfirmationResponse`
Meaning: Boomlet awaits the user’s reproduction of the consent set.  
Stored variables relevant: confirmation `duress_check_space_i`, stored `duress_consent_set_i`, copied nonce.  
Allowed incoming events/messages: encrypted confirmation indices via Iso.  
Guards/preconditions: nonce equality.  
Actions/validations: verify resulting selected-number set equals `duress_consent_set_i`; on success, emit `"setup_duress_finished"`.  
Emitted messages: setup-duress-finished magic to Iso.  
Next states: `Boomlet(i).Setup.OfflineReadyAwaitingNiso`.  
Failure exits: failed confirmation; retry/restart behavior ambiguous and recorded in Section 16.  
Source anchors: `setup.md` 20–27; `setup.puml` 20–27; `duress_setup.puml` 11–17.

#### `Boomlet(i).Setup.OfflineReadyAwaitingNiso`
Meaning: offline setup completed and Boomlet is waiting to be connected to Niso.  
Stored variables relevant: all setup-persistent keying material and `duress_consent_set_i`.  
Allowed incoming events/messages: `"setup_initialized"` from Niso.  
Guards/preconditions: none.  
Actions/validations: derive and sign Tor address; emit `peer_i_id`, Tor secret key, and signed Tor address.  
Emitted messages: Tor identity bundle to Niso.  
Next states: `Boomlet(i).Setup.AwaitingParamSeedApproval`.  
Failure exits: none specified.  
Source anchors: `setup.md` 27–36; `setup.puml` 27–36.

#### `Boomlet(i).Setup.AwaitingParamSeedApproval`
Meaning: Boomlet has received peer addresses, WT ids, and milestones and is waiting for the ST-signed approval of the parameter seed.  
Stored variables relevant: `peer_addresses_collection`, `wt_ids_collection`, `milestone_block_collection`, `boomerang_params_seed_with_nonce`.  
Allowed incoming events/messages: ST-signed encrypted parameter-seed approval via Niso.  
Guards/preconditions: verify every peer’s signed Tor address; verify self-inclusion in `peer_addresses_collection`; later verify ST signature and seed equality.  
Actions/validations: build `boomerang_descriptor` and `boomerang_params`; sign them and send to peers via Niso.  
Emitted messages: signed `boomerang_params`.  
Next states: `Boomlet(i).Setup.AwaitingPeerParamConsensus`.  
Failure exits: invalid peer signature, missing self entry, ST signature mismatch, seed mismatch.  
Source anchors: `setup.md` 35–43; `setup.puml` 35–43.

#### `Boomlet(i).Setup.AwaitingPeerParamConsensus`
Meaning: Boomlet has emitted its signed `boomerang_params` and waits for all peers’ matching signatures.  
Stored variables relevant: `boomerang_params`, own signed copy.  
Allowed incoming events/messages: all-peers signed parameter collection via Niso.  
Guards/preconditions: each signature valid and each content equal to the local copy.  
Actions/validations: fix `boomerang_params`; later generate `mystery_i` and `boomerang_params_fingerprint`.  
Emitted messages: fixed-state magic to Niso, then WT-registration material.  
Next states: `Boomlet(i).Setup.AwaitingWTRegistrationAck`.  
Failure exits: signature mismatch or content mismatch.  
Source anchors: `setup.md` 43–49; `setup.puml` 43–49.

#### `Boomlet(i).Setup.AwaitingWTRegistrationAck`
Meaning: Boomlet has started WT registration and waits for the suffixed WT acknowledgment and then peer-wide WT-active sync.  
Stored variables relevant: `mystery_i`, `boomerang_params_fingerprint`, signed sorted peer key list, shared WT-active fingerprint.  
Allowed incoming events/messages: WT registration acknowledgment via Niso; all-peers WT-active fingerprint collection.  
Guards/preconditions: WT signature valid; suffix equality; content equality to local fingerprint; peer signatures valid and content equal during sync.  
Actions/validations: mark WT active for the peer and then for all peers.  
Emitted messages: signed `shared_state_active_wt_fingerprint`.  
Next states: `Boomlet(i).Setup.AwaitingSARActivationAck`.  
Failure exits: invoice unpaid, WT acknowledgment mismatch, peer sync mismatch.  
Source anchors: `setup.md` 46–59; `setup.puml` 46–59.

#### `Boomlet(i).Setup.AwaitingSARActivationAck`
Meaning: Boomlet has sent SAR ids and encrypted identifier through WT and waits for the SAR finalization response plus all-peers SAR-active sync.  
Stored variables relevant: `doxing_data_identifier_i`, `sar_ids_collection_i`, `sar_setup_response_i`, SAR-active fingerprint.  
Allowed incoming events/messages: WT-suffixed SAR response; all-peers SAR-active fingerprint collection.  
Guards/preconditions: WT signature valid, suffix equality, inner SAR signature valid, `doxing_data_identifier_i` equality, peer signatures/content equality during sync.  
Actions/validations: store `sar_setup_response_i`; mark SAR active locally and then globally.  
Emitted messages: signed `shared_state_active_sar_fingerprint`.  
Next states: `Boomlet(i).Setup.AwaitingBackupCompletion`.  
Failure exits: SAR identifier mismatch, SAR signature mismatch, peer sync mismatch.  
Source anchors: `setup.md` 60–70; `setup.puml` 60–70.

#### `Boomlet(i).Setup.AwaitingBackupCompletion`
Meaning: Boomlet is ready to serve a backup request and later verify backup completion from Boomletwo.  
Stored variables relevant: all setup-persistent state, excluding current `mystery_i` from export.  
Allowed incoming events/messages: signed backup request from Iso; `backup_done_signed_by_boomletwo_i` from Iso after Boomletwo import.  
Guards/preconditions: normal-key signature valid; request magic and backup-normal-key match; later Boomletwo signature and content match.  
Actions/validations: export encrypted backup blob excluding `mystery_i`; verify backup completion and close backup procedure.  
Emitted messages: backup export to Iso; backup-complete magic to Iso.  
Next states: `Boomlet(i).Setup.AwaitingFinalBackupSync`.  
Failure exits: invalid backup request, invalid or mismatched `backup_done`.  
Source anchors: `setup.md` 75–86; `setup.puml` 75–86.

#### `Boomlet(i).Setup.AwaitingFinalBackupSync`
Meaning: local backup completed and Boomlet awaits all-peers backup-fingerprint equality.  
Stored variables relevant: `shared_state_active_backup_fingerprint`.  
Allowed incoming events/messages: all-peers backup fingerprint collection.  
Guards/preconditions: signature validity and content equality across all peers.  
Actions/validations: accept setup completion and emit `"setup_done"`.  
Emitted messages: `"setup_done"` to Niso.  
Next states: `Boomlet(i).ActiveReady`.  
Failure exits: peer sync mismatch.  
Source anchors: `setup.md` 88–94; `setup.puml` 88–94.

#### `Boomlet(i).ActiveReady`
Meaning: setup is complete and no boomerang withdrawal is active.  
Stored variables relevant: all setup-persistent state, including current `mystery_i`.  
Allowed incoming events/messages: for initiator, PSBT plus local height from Niso; for non-initiator, WT initiation bundle plus encrypted PSBT.  
Guards/preconditions: none.  
Actions/validations: branch to the appropriate withdrawal start state.  
Emitted messages: local ST challenges, approvals, or decrypted PSBTs, depending on role.  
Next states: initiator or non-initiator withdrawal entry states.  
Failure exits: none.

#### `Boomlet(i).Withdrawal.Initiator.AwaitingPSBT`
Meaning: initiator Boomlet received a PSBT from local Niso but has not yet emitted the initiator approval.  
Stored variables relevant: candidate `psbt_i`, candidate `tx_id`, `niso_i_event_block_height`.  
Allowed incoming events/messages: PSBT, ST-signed `tx_id_with_nonce`.  
Guards/preconditions: `niso_i_event_block_height >= milestone_block_0`; later ST signature validity and exact nonce-coupled equality.  
Actions/validations: derive and locally latch `tx_id`; challenge ST; on ST approval create the initiator approval and encrypted PSBT copies for peers.  
Emitted messages: ST challenge, initiator approval, encrypted PSBT collection.  
Next states: `Boomlet(i).Withdrawal.AwaitingAllApprovals`.  
Failure exits: milestone not reached, invalid ST acknowledgment, PSBT-derived `tx_id` inconsistency.  
Source anchors: `withdrawal.md` 1–8; `initiator_withdrawal.puml` 1–8.

#### `Boomlet(i).Withdrawal.NonInitiator.AwaitingWTApprovalBundle`
Meaning: non-initiator Boomlet is waiting for WT’s initiation bundle.  
Stored variables relevant: inherited setup state only.  
Allowed incoming events/messages: `wt_tx_approval`, initiator approval, encrypted PSBT, local `niso_i_event_block_height`; later ST-approved local `tx_id`.  
Guards/preconditions: WT signature valid; initiator identity belongs to peer set; initiator signature valid; milestone reached; freshness conditions hold.  
Actions/validations: decrypt PSBT, verify `tx_id`, return plaintext PSBT to Niso, later emit the peer’s own approval after local ST approval.  
Emitted messages: plaintext PSBT to Niso; local `"approved"` message to WT.  
Next states: `Boomlet(i).Withdrawal.AwaitingAllApprovals`.  
Failure exits: invalid signatures, stale WT approval, PSBT decrypt or `tx_id` mismatch.  
Source anchors: `withdrawal.md` 11–23; `non_initiator_withdrawal.puml` 11–23.

#### `Boomlet(i).Withdrawal.AwaitingAllApprovals`
Meaning: local approval has been emitted and the peer awaits the approval set required to begin commitment-time duress checking.  
Stored variables relevant: `tx_id`, local and remote approvals, `wt_tx_approval`.  
Allowed incoming events/messages: approval collections from WT.  
Guards/preconditions: all mirrored approval validations pass locally.  
Actions/validations: once the source-required approval set exists, initiate the local commitment-time duress check.  
Emitted messages: duress-check challenge to ST.  
Next states: `Boomlet(i).Withdrawal.AwaitingInitialDuressResponse`.  
Failure exits: approval-set mismatch or freshness failure.  
Source anchors: `withdrawal.md` 24–27 and 26–27n; both withdrawal diagrams.

#### `Boomlet(i).Withdrawal.AwaitingInitialDuressResponse`
Meaning: local peer has all needed approvals and is waiting for the initial duress response.  
Stored variables relevant: `duress_check_space_i`, `duress_placeholder_plaintext_i`.  
Allowed incoming events/messages: encrypted duress-response indices from ST via Niso.  
Guards/preconditions: nonce equality and successful evaluation against `duress_consent_set_i`.  
Actions/validations: set `duress_placeholder_plaintext_i` to zero-padding or `doxing_key_i`; if positive, set `duress_latched_i = true`.  
Emitted messages: initiator emits padded `"commit"`; non-initiator emits `approvals_signed_by_boomlet_i`.  
Next states: initiator to `Boomlet(i).Withdrawal.AwaitingCommitCollection`; non-initiator to `Boomlet(i).Withdrawal.NonInitiator.AwaitingWTInitiatorCommit`.  
Failure exits: malformed response or freshness failure.  
Source anchors: `withdrawal.md` 27–35n; both withdrawal diagrams; `duress.md` withdrawal section.

#### `Boomlet(i).Withdrawal.NonInitiator.AwaitingWTInitiatorCommit`
Meaning: non-initiator has sent the approvals bundle and now waits for WT’s acknowledgment of the initiator’s commit before emitting its own commit.  
Stored variables relevant: `duress_placeholder_i`, approvals bundle.  
Allowed incoming events/messages: WT-signed initiator commit from Niso with fresh local height.  
Guards/preconditions: WT signature, initiator signature, `"commit"` magic, expected `tx_id`, freshness.  
Actions/validations: create and emit the peer’s own padded `"commit"`.  
Emitted messages: local `"commit"` to WT through Niso.  
Next states: `Boomlet(i).Withdrawal.AwaitingCommitCollection`.  
Failure exits: initiator commit mismatch or freshness failure.  
Source anchors: `withdrawal.md` 35n–40; `non_initiator_withdrawal.puml` 35n–40.

#### `Boomlet(i).Withdrawal.AwaitingCommitCollection`
Meaning: peer has emitted or is participating in commit processing and waits for the full WT-signed commit collection and matching SAR-signed placeholder.  
Stored variables relevant: local commit, `saved_placeholder_for_sar_comparison_i`.  
Allowed incoming events/messages: commit collection plus SAR-signed placeholder.  
Guards/preconditions: SAR signature valid; placeholder equals the locally sent placeholder; every WT and peer signature valid; every commit magic, `tx_id`, and freshness check passes.  
Actions/validations: initialize `counter_i`, `ping_seq_num_i`, `reached_mystery_flag_i`, `reached_boomlets_collection_i`, `last_seen_block_i`; construct first ping.  
Emitted messages: first ping to WT via Niso.  
Next states: `Boomlet(i).Withdrawal.DiggingGame`.  
Failure exits: placeholder mismatch, commit mismatch, freshness failure.  
Source anchors: `withdrawal.md` 44–45; `initiator_withdrawal.puml` 44–47; `non_initiator_withdrawal.puml` 44 and convergence note.

#### `Boomlet(i).Withdrawal.DiggingGame`
Meaning: Boomlet participates in the ping-pong loop until WT has a reached ping for every peer.  
Stored variables relevant: `counter_i`, `ping_seq_num_i`, `reached_mystery_flag_i`, `reached_boomlets_collection_i`, `last_seen_block_i`, current `duress_placeholder_plaintext_i`, current `duress_latched_i`.  
Allowed incoming events/messages: WT pong plus matching SAR-signed placeholder; local optional duress-check responses through ST; final `reached_pings_collection`.  
Guards/preconditions: WT signature, SAR signature, `tx_id` equality, monotone `ping_seq_num`, freshness windows, and counter-increment boundary conditions.  
Actions/validations: maybe run repeated duress check; update placeholder; increment counter when conditions hold; record other reached peers; set local reached flag when `counter_i >= mystery_i`; bounded-update `last_seen_block_i`; create next ping; when final reached-pings collection arrives, verify it and check `hydrated_psbt` has the same `tx_id`.  
Emitted messages: repeated pings; optional ST challenges; `"withdrawal_ready_to_sign"` after final verification.  
Next states: stays here until loop exit, then `Boomlet(i).Withdrawal.ReadyToSign`.  
Failure exits: stale pong, invalid previous ping, placeholder mismatch, malformed repeated duress response, or invalid `reached_pings_collection`.  
Source anchors: `withdrawal.md` 45–62; `initiator_withdrawal.puml` 45–62; `duress.md` repeated-check rules.

#### `Boomlet(i).Withdrawal.ReadyToSign`
Meaning: all peers have reached mystery and the hydrated PSBT matches the committed `tx_id`.  
Stored variables relevant: verified `reached_pings_collection`, updated `psbt_i`.  
Allowed incoming events/messages: `"withdrawal_initialized_start_signing"` from Iso.  
Guards/preconditions: none beyond prior entry.  
Actions/validations: send PSBT, descriptor, boom pubkey share, and `pubnonce_boom` to Iso.  
Emitted messages: signing-start material to Iso.  
Next states: `Boomlet(i).Withdrawal.SigningWithIso`.  
Failure exits: none specified.  
Source anchors: `withdrawal.md` 60–66; `initiator_withdrawal.puml` 60–66.

#### `Boomlet(i).Withdrawal.SigningWithIso`
Meaning: local collaborative signing with Iso is underway.  
Stored variables relevant: PSBT, descriptor, boom share pubkey, public nonce, partial signatures, local signed PSBT copy.  
Allowed incoming events/messages: `pubnonce_normal`, `partialsig_normal`; later export request from Niso.  
Guards/preconditions: none specified beyond the local signing preconditions already met.  
Actions/validations: generate `partialsig_boom`; save `signed_psbt_i`; when Niso requests export, emit `psbt_signed_i`, clear withdrawal-specific state other than the export artifact, and regenerate `mystery_i`.  
Emitted messages: `partialsig_boom` to Iso; later `psbt_signed_i` to Niso.  
Next states: `Boomlet(i).Withdrawal.PostReset`, then `Boomlet(i).ActiveReady`.  
Failure exits: signing failure is not specified separately.  
Source anchors: `withdrawal.md` 66–71; `initiator_withdrawal.puml` 66–71.

#### `Boomlet(i).Withdrawal.PostReset` `[DERIVED]`
Meaning: local signed PSBT has been exported and Boomlet has performed the specified immediate cleanup.  
Stored variables relevant: regenerated `mystery_i`; no active withdrawal-local variables except any export artifact not yet forgotten by other actors.  
Allowed incoming events/messages: none from the same ceremony.  
Guards/preconditions: export already completed.  
Actions/validations: none further.  
Emitted messages: none.  
Next states: `Boomlet(i).ActiveReady`.  
Failure exits: none.  
Source anchors: `withdrawal.md` 71; `initiator_withdrawal.puml` 71.

### 10.6 `Boomletwo(i)` machine

#### `Boomletwo(i).Uninstalled`
Meaning: no backup applet exists yet.  
Stored variables relevant: none.  
Allowed incoming events/messages: installation command from Iso in backup mode.  
Guards/preconditions: card empty.  
Actions/validations: install applet; generate identity keypair.  
Emitted messages: `boomletwo_identity_pubkey` to Iso.  
Next states: `Boomletwo(i).InstalledUnseeded`.  
Failure exits: installation failure.  
Source anchors: `setup.md` 72–74; `setup.puml` 72–74.

#### `Boomletwo(i).InstalledUnseeded`
Meaning: backup applet exists but no Boomlet state has been imported.  
Stored variables relevant: Boomletwo identity keypair only.  
Allowed incoming events/messages: encrypted backup blob and original Boomlet identity pubkey from Iso.  
Guards/preconditions: none.  
Actions/validations: decrypt and import backup blob; generate independent local `mystery_i`; emit signed `backup_done`.  
Emitted messages: `backup_done_signed_by_boomletwo_i` to Iso.  
Next states: `Boomletwo(i).BackupImportedInactive`.  
Failure exits: backup decryption or import failure.  
Source anchors: `setup.md` 79–82; `setup.puml` 79–82.

#### `Boomletwo(i).BackupImportedInactive`
Meaning: backup state exists but Boomletwo is not the active signing hardware.  
Stored variables relevant: imported setup state and its own `mystery_i`.  
Allowed incoming events/messages: none in the specified flows.  
Guards/preconditions: none.  
Actions/validations: remain inactive.  
Emitted messages: none.  
Next states: no operational next state in this specification; activation is ancillary and out of scope.  
Failure exits: none within the specified flows.  
Source anchors: `setup.md` 81–87; `setup.puml` 81–87; `DEEPDIVE.md` Boomletwo concern.

### 10.7 `Niso(i)` machine

#### `Niso(i).Uninitialized`
Meaning: Niso has not yet been configured with network and node access.  
Stored variables relevant: none.  
Allowed incoming events/messages: user setup inputs or later user-ready events during withdrawal when already configured.  
Guards/preconditions: none.  
Actions/validations: start configuration.  
Emitted messages: `"setup_initialized"` to Boomlet once configured.  
Next states: `Niso(i).Setup.AwaitingTorIdentity`, or later withdrawal states after setup is complete.  
Failure exits: node or network configuration failure.  
Source anchors: `setup.md` 29–30; `setup.puml` 29–30.

#### `Niso(i).Setup.AwaitingTorIdentity`
Meaning: Niso is configured and waiting for Boomlet’s Tor identity bundle.  
Stored variables relevant: network, node auth, local Boomlet link.  
Allowed incoming events/messages: `peer_i_id`, Tor secret key, signed Tor address from Boomlet.  
Guards/preconditions: verify Tor address signature; reproduce the same Tor address by running the onion service.  
Actions/validations: forward verified identity bundle to ST.  
Emitted messages: identity bundle to ST.  
Next states: `Niso(i).Setup.AwaitingPeerParametersFromUser`.  
Failure exits: Tor address signature mismatch or derived-address mismatch.  
Source anchors: `setup.md` 30–33; `setup.puml` 30–33.

#### `Niso(i).Setup.AwaitingPeerParametersFromUser`
Meaning: local Tor identity is established and Niso waits for user-supplied peer addresses, WT ids, and milestones.  
Stored variables relevant: verified local identity bundle.  
Allowed incoming events/messages: `peer_addresses_collection`, `wt_ids_collection`, `milestone_block_collection`.  
Guards/preconditions: verify all peers’ signed Tor addresses and self-inclusion.  
Actions/validations: attempt Tor connections to peers; forward parameters to Boomlet; later relay ST parameter approval response and all-peers signed `boomerang_params`.  
Emitted messages: parameter bundle to Boomlet; relays to ST and peers.  
Next states: `Niso(i).Setup.AwaitingWTRegistrationInvoiceSettlement`.  
Failure exits: invalid peer signatures, connection failure, or self-inclusion failure.  
Source anchors: `setup.md` 34–45; `setup.puml` 34–45.

#### `Niso(i).Setup.AwaitingWTRegistrationInvoiceSettlement`
Meaning: `boomerang_params` are fixed and WT registration is underway.  
Stored variables relevant: current `mystery_i`, WT registration material, WT invoice details.  
Allowed incoming events/messages: WT invoice, user WT payment receipt, WT acknowledgment, peer WT-active fingerprints.  
Guards/preconditions: verify WT signature and suffix on acknowledgment; verify peer signatures/content on WT-active sync.  
Actions/validations: relay invoice to User, receipt to WT, WT acknowledgment to Boomlet, and peer-sync messages.  
Emitted messages: registration material to WT; receipt to WT; peer-sync relays.  
Next states: `Niso(i).Setup.AwaitingSARActivationAck`.  
Failure exits: unpaid WT invoice or mismatched WT acknowledgment.  
Source anchors: `setup.md` 47–59; `setup.puml` 47–59.

#### `Niso(i).Setup.AwaitingSARActivationAck`
Meaning: Niso is relaying SAR-finalization traffic and waiting for the corresponding acknowledgment and peer sync.  
Stored variables relevant: WT and SAR activation relay state.  
Allowed incoming events/messages: Boomlet SAR-init payload, WT-suffixed SAR response, peer SAR-active fingerprints.  
Guards/preconditions: verify WT signature/suffix on the SAR response; verify peer signatures/content during sync.  
Actions/validations: relay to WT, relay WT response to Boomlet, relay SAR-active fingerprints to peers and Boomlet.  
Emitted messages: SAR-init payload to WT, SAR response to Boomlet, peer-sync messages.  
Next states: `Niso(i).Setup.AwaitingBackupCompletion`.  
Failure exits: invalid WT suffix/signature or peer sync mismatch.  
Source anchors: `setup.md` 60–70; `setup.puml` 60–70.

#### `Niso(i).Setup.AwaitingBackupCompletion`
Meaning: Niso has informed the user that SAR is finalized and waits for the local backup choreography and later final backup sync.  
Stored variables relevant: none beyond inherited setup state.  
Allowed incoming events/messages: user local-ready events, Boomlet backup-sync fingerprint, peer backup fingerprints, final `"setup_done"`.  
Guards/preconditions: peer signatures/content validity during final sync.  
Actions/validations: tell Boomlet to finish setup when the user reconnects it; relay final backup fingerprints with peers; inform the user of final setup completion.  
Emitted messages: finish-setup magic to Boomlet; peer-sync relays; `"setup_done"` to User.  
Next states: `Niso(i).ActiveReady`.  
Failure exits: backup sync mismatch.  
Source anchors: `setup.md` 88–94; `setup.puml` 88–94.

#### `Niso(i).ActiveReady`
Meaning: setup is complete and Niso is the online coordinator waiting for withdrawal.  
Stored variables relevant: online peer and WT connectivity, inherited setup state.  
Allowed incoming events/messages: initiator PSBT from local user or WT initiation bundle if non-initiator.  
Guards/preconditions: none.  
Actions/validations: branch by role.  
Emitted messages: local or remote withdrawal relays.  
Next states: withdrawal entry states.  
Failure exits: none.

#### `Niso(i).Withdrawal.Initiator.AwaitingPSBT`
Meaning: initiator Niso is waiting for the user-supplied PSBT.  
Stored variables relevant: inherited setup state.  
Allowed incoming events/messages: PSBT from User.  
Guards/preconditions: observed local block height must satisfy `milestone_block_0`; `hydrate_psbt(psbt)` must not be null.  
Actions/validations: derive `tx_id`; store `niso_i_event_block_height`; forward PSBT and height to Boomlet; later relay ST `tx_id` challenge and acknowledgment; relay initiator approval to WT.  
Emitted messages: PSBT to Boomlet, ST relay messages, initiator approval bundle to WT.  
Next states: `Niso(i).Withdrawal.Initiator.AwaitingAllApprovals`.  
Failure exits: milestone not reached or unsatisfiable PSBT.  
Source anchors: `withdrawal.md` 1–10; `initiator_withdrawal.puml` 1–10.

#### `Niso(i).Withdrawal.NonInitiator.AwaitingWTInitiationBundle`
Meaning: non-initiator Niso waits for WT to forward the initiation bundle.  
Stored variables relevant: inherited setup state.  
Allowed incoming events/messages: `wt_tx_approval`, initiator approval, encrypted PSBT.  
Guards/preconditions: WT and initiator signatures valid; initiator id is in peer set; `milestone_block_0` reached; freshness checks pass.  
Actions/validations: forward to Boomlet with local current height; later present decrypted PSBT and initiator id to User; relay local ST `tx_id` challenge and acknowledgment; relay peer approval to WT.  
Emitted messages: WT bundle to Boomlet; PSBT to User; peer approval to WT.  
Next states: `Niso(i).Withdrawal.AwaitingCommitCollection`.  
Failure exits: bundle validation failure or stale WT approval.  
Source anchors: `withdrawal.md` 11–26; `non_initiator_withdrawal.puml` 11–26.

#### `Niso(i).Withdrawal.AwaitingCommitCollection`
Meaning: local peer is in the commitment phase or waiting for the WT/SAR roundtrip on commitments.  
Stored variables relevant: approval collections, local current height, local commit relay state.  
Allowed incoming events/messages: local duress-check challenge/response relays, initiator commit from WT if non-initiator, local commit from Boomlet, full commit collection from WT.  
Guards/preconditions: applicable approval/commit signature and freshness checks.  
Actions/validations: relay initial duress-check messages locally; relay initiator commit to non-initiator Boomlet; relay local commit to WT; relay full commit collection and matching SAR-signed placeholder to Boomlet.  
Emitted messages: local ST relay messages; commits to WT; commit collection to Boomlet.  
Next states: `Niso(i).Withdrawal.DiggingGameRelay`.  
Failure exits: stale commit or SAR-return mismatch detected later by Boomlet.  
Source anchors: `withdrawal.md` 27–45; both withdrawal diagrams.

#### `Niso(i).Withdrawal.DiggingGameRelay`
Meaning: Niso is the relay and local-height observer for repeated pings, pongs, optional repeated duress checks, and the final reached-pings handoff.  
Stored variables relevant: current `niso_i_event_block_height`, local peer’s last WT relay state, base `psbt_i`.  
Allowed incoming events/messages: pings from Boomlet, pongs from WT, optional duress-check challenge/response messages, `reached_pings_collection` from WT, later signed PSBT from Boomlet.  
Guards/preconditions: verify reached-pings signatures when WT breaks the loop.  
Actions/validations: forward pings to WT; forward pongs and current height to Boomlet; hydrate PSBT when WT sends `reached_pings_collection`; forward `hydrated_psbt` and reached collection to Boomlet.  
Emitted messages: relay messages only.  
Next states: `Niso(i).Withdrawal.ReadyToSign`, then `Niso(i).Withdrawal.AwaitingWTBroadcast`.  
Failure exits: invalid reached-pings collection or hydration failure.  
Source anchors: `withdrawal.md` 46–62; `initiator_withdrawal.puml` 46–62.

#### `Niso(i).Withdrawal.ReadyToSign`
Meaning: Niso has told the user to connect Boomlet to Iso and later must request the signed PSBT back from Boomlet after the user reconnects it.  
Stored variables relevant: updated PSBT and reached-pings proof.  
Allowed incoming events/messages: `"withdrawal_ready_to_sign"` from Boomlet, user reconnection magic after Iso signing, `psbt_signed_i` from Boomlet.  
Guards/preconditions: none beyond local phase consistency.  
Actions/validations: notify User to connect Boomlet to Iso; later request signed PSBT export from Boomlet; forward `psbt_signed_i` to WT.  
Emitted messages: user notification and export request to Boomlet; signed PSBT to WT.  
Next states: `Niso(i).Withdrawal.AwaitingWTBroadcast`, then `Niso(i).ActiveReady` after local reset.  
Failure exits: none specified.  
Source anchors: `withdrawal.md` 62–72; `initiator_withdrawal.puml` 62–72.

### 10.8 `WT` machine

#### `WT.Setup.CollectingPeerRegistrations`
Meaning: WT is collecting peer registration material for the fixed `boomerang_params_fingerprint`.  
Stored variables relevant: registered peer identities, Tor addresses, signed sorted peer key lists, boomerang-parameter fingerprints.  
Allowed incoming events/messages: peer registration requests from every Niso.  
Guards/preconditions: Boomlet identity signature valid over each transmitted item.  
Actions/validations: store each peer’s registration and generate per-peer WT invoice.  
Emitted messages: WT service fee payment info to each Niso.  
Next states: `WT.Setup.AwaitingWTFeeReceipts`.  
Failure exits: signature failure or inconsistent registration data.  
Source anchors: `setup.md` 47–50; `setup.puml` 47–50.

#### `WT.Setup.AwaitingWTFeeReceipts`
Meaning: WT waits for each peer’s service fee receipt.  
Stored variables relevant: pending registration invoices.  
Allowed incoming events/messages: WT payment receipts from Nisos.  
Guards/preconditions: verify payment.  
Actions/validations: on valid payment, create and send the suffixed registration acknowledgment.  
Emitted messages: suffixed signed `boomerang_params_fingerprint`.  
Next states: `WT.Setup.RegisteredActive` after sufficient registration state exists; practically overlaps with per-peer completion.  
Failure exits: unpaid invoice.  
Source anchors: `setup.md` 50–55; `setup.puml` 50–55.

#### `WT.Setup.RegisteredActive`
Meaning: WT is an active registered coordinator for the agreed peer set.  
Stored variables relevant: registration table and activation state.  
Allowed incoming events/messages: SAR finalization init payloads from peers.  
Guards/preconditions: peer registration already exists.  
Actions/validations: verify signed SAR id collection; forward encrypted identifier to SAR.  
Emitted messages: SAR finalization relay to SAR.  
Next states: `WT.Setup.AwaitingSARActivationData`.  
Failure exits: mismatched or unsigned SAR id collection.  
Source anchors: `setup.md` 55–63; `setup.puml` 55–63.

#### `WT.Setup.AwaitingSARActivationData`
Meaning: WT is mediating peer finalization with SAR.  
Stored variables relevant: per-peer SAR-finalization state.  
Allowed incoming events/messages: SAR finalization responses.  
Guards/preconditions: none beyond receipt.  
Actions/validations: suffix and sign the SAR response for the intended Boomlet; later relay peer-sync fingerprints indirectly through Nisos.  
Emitted messages: WT-suffixed SAR response to Niso.  
Next states: returns to `WT.Setup.RegisteredActive`, then no further setup role after all peers are active.  
Failure exits: none specified.  
Source anchors: `setup.md` 63–70; `setup.puml` 63–70.

#### `WT.Withdrawal.AwaitingInitiatorApproval`
Meaning: WT is ready for a new boomerang-regime withdrawal but has not yet stored the ceremony `tx_id`.  
Stored variables relevant: active peer set from setup, current most-work block height.  
Allowed incoming events/messages: initiator approval plus encrypted PSBT collection.  
Guards/preconditions: initiator signature valid, magic `"approved"`, freshness of initiator approval.  
Actions/validations: store the ceremony `tx_id`; construct `wt_tx_approval`; fan out the initiation bundle to non-initiators.  
Emitted messages: `wt_tx_approval`, initiator approval, and per-peer encrypted PSBT.  
Next states: `WT.Withdrawal.CollectingPeerApprovals`.  
Failure exits: stale or invalid initiator approval.  
Source anchors: `withdrawal.md` 8–10; `initiator_withdrawal.puml` 8–10.

#### `WT.Withdrawal.CollectingPeerApprovals`
Meaning: WT is collecting non-initiator approvals for the stored `tx_id`.  
Stored variables relevant: stored `tx_id`, initiator id, approval collection.  
Allowed incoming events/messages: peer approvals from non-initiators.  
Guards/preconditions: verify each peer signature, magic, `tx_id`, and freshness.  
Actions/validations: store peer approval; once enough approvals are present, distribute approval collections required by the sources.  
Emitted messages: approval collections to initiator and non-initiators.  
Next states: `WT.Withdrawal.CollectingCommitments`.  
Failure exits: stale or mismatched peer approval.  
Source anchors: `withdrawal.md` 22–26; `initiator_withdrawal.puml` 24–25; `non_initiator_withdrawal.puml` 22–26.

#### `WT.Withdrawal.CollectingCommitments`
Meaning: WT is processing initiator and non-initiator commits, with SAR roundtrips on each placeholder.  
Stored variables relevant: commit collection, per-peer last placeholder relay state, stored `tx_id`.  
Allowed incoming events/messages: initiator commit, non-initiator approvals bundles, non-initiator commits, SAR-signed placeholders.  
Guards/preconditions: outer and inner signatures valid, commit magic and `tx_id` match, freshness checks pass, approvals bundle content matches the expected approvals.  
Actions/validations: forward each placeholder to SAR; after SAR reply, WT-sign the matching commit; once all commits are accepted, distribute the full commit collection and each peer’s placeholder acknowledgment.  
Emitted messages: placeholder to SAR; WT-signed commits and full commit collection to peers.  
Next states: `WT.Withdrawal.DiggingGame.CollectingPings`.  
Failure exits: stale commit, invalid approvals bundle, SAR response missing for a commit.  
Source anchors: `withdrawal.md` 33–45 and 33n–43; both withdrawal diagrams.

#### `WT.Withdrawal.DiggingGame.CollectingPings`
Meaning: WT is inside the ping-pong loop and currently waiting for one ping from each peer for the next round.  
Stored variables relevant: `reached_pings_collection`, current round’s pending pings, stored `tx_id`.  
Allowed incoming events/messages: padded pings from all peers.  
Guards/preconditions: outer and inner signatures valid; magic `"ping"`; expected `tx_id`; sequence-number increment after first ping; freshness.  
Actions/validations: extract placeholder and send to SAR; if a validated ping has `reached_mystery_flag = 1` and that peer is not already recorded, record it in `reached_pings_collection`.  
Emitted messages: placeholders to SAR.  
Next states: `WT.Withdrawal.DiggingGame.DistributingPongs` after all pings for the round are present; or `WT.Withdrawal.DistributingReachedPings` if all peers are already reached.  
Failure exits: invalid ping or missing ping from one or more peers.  
Source anchors: `withdrawal.md` 46–53 and 58–60; `initiator_withdrawal.puml` 46–53 and 58–60.

#### `WT.Withdrawal.DiggingGame.DistributingPongs`
Meaning: WT has all pings for the current round and is constructing the next per-peer pongs.  
Stored variables relevant: current round’s ping collection, current WT block height.  
Allowed incoming events/messages: SAR-signed placeholders for the just-received pings.  
Guards/preconditions: SAR replies received for the placeholders WT must return.  
Actions/validations: build a per-peer pong containing other peers’ validated previous pings, sign it, encrypt it for that peer, append the matching SAR-signed placeholder, and send it to Niso.  
Emitted messages: pongs plus per-peer SAR-signed placeholders.  
Next states: back to `WT.Withdrawal.DiggingGame.CollectingPings`.  
Failure exits: missing SAR placeholder acknowledgment.  
Source anchors: `withdrawal.md` 53–59; `initiator_withdrawal.puml` 53–59.

#### `WT.Withdrawal.DistributingReachedPings`
Meaning: WT has a reached ping for every peer and can break the loop.  
Stored variables relevant: final `reached_pings_collection`.  
Allowed incoming events/messages: none additional are needed from peers to break.  
Guards/preconditions: `reached_pings_collection` has an entry for every peer id.  
Actions/validations: distribute `reached_pings_collection` to all peers.  
Emitted messages: final reached-pings collection.  
Next states: `WT.Withdrawal.CollectingSignedPSBTs`.  
Failure exits: none.  
Source anchors: `withdrawal.md` 59–60; `initiator_withdrawal.puml` 59–60.

#### `WT.Withdrawal.CollectingSignedPSBTs`
Meaning: WT is waiting for `psbt_signed_i` from all five peers.  
Stored variables relevant: collection of signed PSBTs.  
Allowed incoming events/messages: one signed PSBT per peer.  
Guards/preconditions: the sources do not enumerate an extra per-fragment validation step, so only receipt of all five is required here.  
Actions/validations: aggregate the five signed PSBTs.  
Emitted messages: none until broadcast.  
Next states: `WT.Withdrawal.Broadcasting`.  
Failure exits: missing one or more signed PSBTs.  
Source anchors: `withdrawal.md` 72–73; `initiator_withdrawal.puml` 72–73.

#### `WT.Withdrawal.Broadcasting`
Meaning: WT has all five signed PSBTs and can produce the final signed transaction.  
Stored variables relevant: signed-PSBT collection, aggregated signed transaction.  
Allowed incoming events/messages: none.  
Guards/preconditions: all five signed PSBTs received.  
Actions/validations: aggregate and relay the signed transaction to the network.  
Emitted messages: network relay of `signed_tx`.  
Next states: back to a WT-ready idle state for later ceremonies.  
Failure exits: aggregation failure or relay failure, neither of which is operationally specified further.  
Source anchors: `withdrawal.md` 73; `initiator_withdrawal.puml` 73.

### 10.9 `SAR` machine

#### `SAR.AwaitingIdentifierOnlyRegistration`
Meaning: SAR has no record yet for a given user and is waiting for the initial identifier-only registration request from Phone.  
Stored variables relevant: none for that user.  
Allowed incoming events/messages: `doxing_data_identifier_i` from Phone.  
Guards/preconditions: none.  
Actions/validations: create pending registration and send invoice.  
Emitted messages: `sar_service_fee_payment_info`.  
Next states: `SAR.AwaitingPaymentAndEncryptedDoxingData`.  
Failure exits: none specified.  
Source anchors: `setup.md` 1–3; `setup.puml` 1–3.

#### `SAR.AwaitingPaymentAndEncryptedDoxingData`
Meaning: SAR has created an invoice and waits for proof of payment plus encrypted doxing data.  
Stored variables relevant: pending registration keyed by `doxing_data_identifier_i`.  
Allowed incoming events/messages: receipt plus encrypted static and dynamic doxing data from Phone.  
Guards/preconditions: verify payment associated with the receipt.  
Actions/validations: store encrypted doxing data and associate it with the identifier; send sync acknowledgment.  
Emitted messages: sync-complete magic to Phone.  
Next states: `SAR.SyncedWithPhoneUnfinalized`.  
Failure exits: invalid payment proof.  
Source anchors: `setup.md` 5–7; `setup.puml` 5–7.

#### `SAR.SyncedWithPhoneUnfinalized`
Meaning: SAR has the phone-side registration data but has not yet been finalized with Boomlet through WT.  
Stored variables relevant: encrypted doxing records keyed by `doxing_data_identifier_i`.  
Allowed incoming events/messages: SAR finalization payload relayed by WT.  
Guards/preconditions: identifier decrypted from the WT relay must match a previously registered identifier.  
Actions/validations: build `sar_setup_response_i`, sign it, encrypt it for Boomlet, and return it via WT.  
Emitted messages: `sar_setup_response_signed_by_sar_encrypted_for_boomlet_i`.  
Next states: `SAR.FinalizedActive`.  
Failure exits: identifier not found.  
Source anchors: `setup.md` 60–64; `setup.puml` 60–64.

#### `SAR.FinalizedActive`
Meaning: SAR has a finalized association between a Boomlet identity and previously registered doxing data and is ready to process duress placeholders.  
Stored variables relevant: encrypted doxing registry, `seen_duress_iv_pairs`.  
Allowed incoming events/messages: duress placeholders from WT during commitment or ping phases.  
Guards/preconditions: decrypt placeholder with SAR private key and Boomlet identity; distinguish all-zero padding from non-zero payload.  
Actions/validations: if non-zero and new, hash plaintext to locate `doxing_data_identifier_i`, decrypt static and dynamic doxing data, and enter rescue mode; regardless, sign the placeholder and encrypt it back for the corresponding Boomlet.  
Emitted messages: SAR-signed encrypted placeholder to WT.  
Next states: remains here, or enters `SAR.SearchAndRescueTriggered` as an overlay state.  
Failure exits: malformed payload or identifier lookup failure; the general handling of repeated malformed messages is not operationalized in the authoritative setup/withdrawal flows.  
Source anchors: `withdrawal.md` 36–43; both withdrawal diagrams; `duress.md` placeholder semantics.

#### `SAR.SearchAndRescueTriggered`
Meaning: SAR has recognized a valid positive duress signal for a registered peer and has decrypted doxing data for operational use.  
Stored variables relevant: decrypted static and dynamic doxing data for the affected user.  
Allowed incoming events/messages: further placeholders for the same user, which may be duplicate or continued positive placeholders.  
Guards/preconditions: positive duress signal and identifier lookup success.  
Actions/validations: perform out-of-model rescue operations; continue returning signed placeholders so as not to alter protocol flow.  
Emitted messages: same SAR-signed placeholder acknowledgments as in non-duress handling.  
Next states: remains active for that user until off-model rescue concludes.  
Failure exits: none specified inside the protocol.  
Source anchors: `withdrawal.md` 36–43; `duress.md` duress consequences and SAR actions.

11. Transition catalog

This catalog lists the load-bearing state transitions that change control state or durable protocol variables. Pure relay steps that preserve the sender’s macro-state are mapped exhaustively in Section 17. Transition IDs are stable and chosen so a later TLA+ action can inherit the same numbering.

### 11.1 Setup transitions

**`SETUP.Phone.001`**  
From state: `Phone(i).Setup.AwaitingRegistrationInput`  
Triggering event/input: user provides `{doxing_password, sar_ids_collection_i, static_doxing_data}`  
Guards/preconditions: none  
Actions/validations: derive `doxing_key_i` and `doxing_data_identifier_i`; create SAR registration request  
Emitted messages: `Setup.SARRegistration.Init`  
State updates: store `doxing_key_i`, `doxing_data_identifier_i`  
To state: `Phone(i).Setup.AwaitingPaymentInfo`  
Failure exits: none specified  
Exact source anchors: `setup.md` 1; `setup.puml` 1

**`SETUP.SAR.002`**  
From state: `SAR.AwaitingIdentifierOnlyRegistration`  
Triggering event/input: receipt of `doxing_data_identifier_i`  
Guards/preconditions: none  
Actions/validations: open pending registration; generate invoice  
Emitted messages: `sar_service_fee_payment_info`  
State updates: pending SAR registration context  
To state: `SAR.AwaitingPaymentAndEncryptedDoxingData`  
Failure exits: none specified  
Exact source anchors: `setup.md` 2; `setup.puml` 2

**`SETUP.Phone.005`**  
From state: `Phone(i).Setup.AwaitingUserReceipt`  
Triggering event/input: user supplies SAR payment receipt  
Guards/preconditions: none  
Actions/validations: encrypt static and dynamic doxing data under `doxing_key_i`; attach `doxing_data_identifier_i`  
Emitted messages: `Setup.SARRegistration.DataAndReceipt`  
State updates: phone enters wait-for-sync state  
To state: `Phone(i).Setup.AwaitingSARSyncAck`  
Failure exits: none specified  
Exact source anchors: `setup.md` 5; `setup.puml` 5

**`SETUP.SAR.006`**  
From state: `SAR.AwaitingPaymentAndEncryptedDoxingData`  
Triggering event/input: receipt plus encrypted doxing data from Phone  
Guards/preconditions: verify payment associated with receipt  
Actions/validations: store encrypted doxing records keyed by `doxing_data_identifier_i`  
Emitted messages: SAR sync acknowledgment  
State updates: customer record created  
To state: `SAR.SyncedWithPhoneUnfinalized`  
Failure exits: invalid payment proof  
Exact source anchors: `setup.md` 6; `setup.puml` 6

**`SETUP.Peer(i).Iso.009`**  
From state: `Iso(i).Setup.Running`  
Triggering event/input: user setup inputs for offline installation  
Guards/preconditions: none  
Actions/validations: create mnemonic, derive `normal_pubkey_i`, compute `doxing_key_i`, install Boomlet  
Emitted messages: `Setup.BoomletInstall`  
State updates: session-local normal signing material  
To state: `Iso(i).Setup.Running`  
Failure exits: installation failure  
Exact source anchors: `setup.md` 9; `setup.puml` 9

**`SETUP.Peer(i).Boomlet.010`**  
From state: `Boomlet(i).Uninstalled`  
Triggering event/input: Boomlet installation payload from Iso  
Guards/preconditions: card empty  
Actions/validations: generate identity keypair, boom-share keypair, `boom_pubkey_i`, `peer_i_id`, Tor secret key  
Emitted messages: `boomlet_i_identity_pubkey`  
State updates: all setup-persistent Boomlet cryptographic state except ST pairing and consent set  
To state: `Boomlet(i).Setup.AwaitingSTPairing`  
Failure exits: installation on non-empty hardware or internal generation failure  
Exact source anchors: `setup.md` 10; `setup.puml` 10

**`SETUP.Peer(i).ST.012`**  
From state: `ST(i).Unpaired`  
Triggering event/input: receipt of `boomlet_i_identity_pubkey` from Iso  
Guards/preconditions: none  
Actions/validations: generate ST identity keypair and shared Boomlet–ST secret  
Emitted messages: `st_i_identity_pubkey`  
State updates: ST pairing state  
To state: `ST(i).Paired.Idle`  
Failure exits: none specified  
Exact source anchors: `setup.md` 11–12; `setup.puml` 11–12; `duress_setup.puml` messages 1–3

**`SETUP.Peer(i).Boomlet.014`**  
From state: `Boomlet(i).Setup.AwaitingSTPairing`  
Triggering event/input: receipt of `st_i_identity_pubkey`  
Guards/preconditions: none  
Actions/validations: compute shared secret; create first duress challenge and nonce  
Emitted messages: initial encrypted `duress_check_space_i`  
State updates: pairwise shared secret and challenge state  
To state: `Boomlet(i).Setup.AwaitingInitialConsentResponse`  
Failure exits: malformed ST identity input  
Exact source anchors: `setup.md` 14–15; `setup.puml` 14–15

**`SETUP.Peer(i).Boomlet.020`**  
From state: `Boomlet(i).Setup.AwaitingInitialConsentResponse`  
Triggering event/input: ST returns first selected indices with copied nonce  
Guards/preconditions: nonce equality  
Actions/validations: derive and store `duress_consent_set_i`; generate confirmation challenge  
Emitted messages: second encrypted `duress_check_space_i`  
State updates: `duress_consent_set_i` fixed locally  
To state: `Boomlet(i).Setup.AwaitingConsentConfirmationResponse`  
Failure exits: nonce mismatch or malformed index collection  
Exact source anchors: `setup.md` 18–20; `setup.puml` 18–20

**`SETUP.Peer(i).Boomlet.026`**  
From state: `Boomlet(i).Setup.AwaitingConsentConfirmationResponse`  
Triggering event/input: ST returns confirmation indices with copied nonce  
Guards/preconditions: nonce equality; resulting selected-number set equals `duress_consent_set_i`  
Actions/validations: complete duress setup  
Emitted messages: `"setup_duress_finished"`  
State updates: no new persistent value beyond confirmed consent set  
To state: `Boomlet(i).Setup.OfflineReadyAwaitingNiso`  
Failure exits: confirmation mismatch; retry/restart behavior ambiguous  
Exact source anchors: `setup.md` 24–27; `setup.puml` 24–27; `duress_setup.puml` messages 15–17

**`SETUP.Peer(i).Boomlet.030`**  
From state: `Boomlet(i).Setup.OfflineReadyAwaitingNiso`  
Triggering event/input: `"setup_initialized"` from Niso  
Guards/preconditions: none  
Actions/validations: derive and sign Tor address  
Emitted messages: `peer_i_id`, Tor secret, signed Tor address  
State updates: signed Tor address becomes externally shareable  
To state: `Boomlet(i).Setup.AwaitingParamSeedApproval`  
Failure exits: none specified  
Exact source anchors: `setup.md` 29–31; `setup.puml` 29–31

**`SETUP.Peer(i).Boomlet.036`**  
From state: `Boomlet(i).Setup.AwaitingParamSeedApproval`  
Triggering event/input: peer addresses, WT ids, and milestones arrive from Niso  
Guards/preconditions: all peer Tor-address signatures valid; self tuple present in peer address collection  
Actions/validations: build `boomerang_params_seed_with_nonce`; challenge ST  
Emitted messages: encrypted parameter-seed challenge to ST  
State updates: peer address collection and candidate `peer_ids_collection`  
To state: `Boomlet(i).Setup.AwaitingParamSeedApproval`  
Failure exits: invalid peer signature or self-inclusion failure  
Exact source anchors: `setup.md` 35–38; `setup.puml` 35–38

**`SETUP.Peer(i).Boomlet.042`**  
From state: `Boomlet(i).Setup.AwaitingParamSeedApproval`  
Triggering event/input: ST-signed encrypted approval of parameter seed  
Guards/preconditions: ST signature valid; challenge/response equality including nonce  
Actions/validations: construct `boomerang_descriptor`; assemble `boomerang_params`; sign local copy  
Emitted messages: signed `boomerang_params` to peers via Niso  
State updates: local candidate `boomerang_params`  
To state: `Boomlet(i).Setup.AwaitingPeerParamConsensus`  
Failure exits: ST signature mismatch, nonce mismatch, seed mismatch  
Exact source anchors: `setup.md` 40–43; `setup.puml` 40–43

**`SETUP.Peer(i).Boomlet.045`**  
From state: `Boomlet(i).Setup.AwaitingPeerParamConsensus`  
Triggering event/input: all-peers signed parameter collection  
Guards/preconditions: every peer signature valid; every content equals local `boomerang_params`  
Actions/validations: fix `boomerang_params`; inform Niso  
Emitted messages: `"setup_boomerang_params_fixed"`  
State updates: `boomerang_params` becomes immutable setup state  
To state: `Boomlet(i).Setup.AwaitingWTRegistrationAck`  
Failure exits: peer signature or content mismatch  
Exact source anchors: `setup.md` 44–46; `setup.puml` 44–46

**`SETUP.Peer(i).Boomlet.047`**  
From state: `Boomlet(i).Setup.AwaitingWTRegistrationAck`  
Triggering event/input: Niso tells Boomlet to start WT registration after params are fixed  
Guards/preconditions: none  
Actions/validations: generate `mystery_i`, initialize default `counter_i=0`, compute `boomerang_params_fingerprint`, sign sorted peer pubkeys and fingerprint  
Emitted messages: WT registration request material  
State updates: `mystery_i`, `boomerang_params_fingerprint`  
To state: `Boomlet(i).Setup.AwaitingWTRegistrationAck`  
Failure exits: none specified  
Exact source anchors: `setup.md` 46–48; `setup.puml` 46–48

**`SETUP.WT.049`**  
From state: `WT.Setup.CollectingPeerRegistrations`  
Triggering event/input: receipt of peer registration material  
Guards/preconditions: verify each boomlet identity signature on the sorted pubkey list, signed Tor address, and fingerprint  
Actions/validations: register peer and generate WT invoice  
Emitted messages: WT service fee payment info  
State updates: WT registration table  
To state: `WT.Setup.AwaitingWTFeeReceipts`  
Failure exits: invalid signature or inconsistent registration set  
Exact source anchors: `setup.md` 49–50; `setup.puml` 49–50

**`SETUP.WT.053`**  
From state: `WT.Setup.AwaitingWTFeeReceipts`  
Triggering event/input: receipt of WT service fee payment receipt  
Guards/preconditions: verify payment  
Actions/validations: create WT-suffixed signed acknowledgment of the registered fingerprint  
Emitted messages: suffixed signed `boomerang_params_fingerprint`  
State updates: per-peer WT registration completion  
To state: `WT.Setup.RegisteredActive`  
Failure exits: payment verification failure  
Exact source anchors: `setup.md` 52–55; `setup.puml` 52–55

**`SETUP.Peer(i).Boomlet.055`**  
From state: `Boomlet(i).Setup.AwaitingWTRegistrationAck`  
Triggering event/input: WT-suffixed fingerprint acknowledgment  
Guards/preconditions: WT signature valid; suffix equals `"setup_peers_registration_with_wt_completed"`; content equals local fingerprint  
Actions/validations: accept local WT activation; start all-peers WT-active sync  
Emitted messages: signed `shared_state_active_wt_fingerprint`  
State updates: local WT-active status  
To state: `Boomlet(i).Setup.AwaitingSARActivationAck`  
Failure exits: invalid WT signature, wrong suffix, fingerprint mismatch  
Exact source anchors: `setup.md` 54–59; `setup.puml` 54–59

**`SETUP.Peer(i).Boomlet.060`**  
From state: `Boomlet(i).Setup.AwaitingSARActivationAck`  
Triggering event/input: Niso indicates WT service is confirmed by peers  
Guards/preconditions: none  
Actions/validations: sign `sar_ids_collection_i`; encrypt `doxing_data_identifier_i` for SAR; emit both through WT  
Emitted messages: SAR finalization init payload  
State updates: pending SAR finalization state  
To state: `Boomlet(i).Setup.AwaitingSARActivationAck`  
Failure exits: none specified  
Exact source anchors: `setup.md` 59–62; `setup.puml` 59–62

**`SETUP.SAR.063`**  
From state: `SAR.SyncedWithPhoneUnfinalized`  
Triggering event/input: WT relays encrypted `doxing_data_identifier_i` plus `boomlet_i_identity_pubkey`  
Guards/preconditions: decrypted identifier matches a prior phone registration  
Actions/validations: build and sign `sar_setup_response_i` with identifier, static-data fingerprint, and IV  
Emitted messages: SAR setup response via WT  
State updates: peer-specific SAR finalization record  
To state: `SAR.FinalizedActive`  
Failure exits: identifier lookup failure  
Exact source anchors: `setup.md` 62–64; `setup.puml` 62–64

**`SETUP.Peer(i).Boomlet.066`**  
From state: `Boomlet(i).Setup.AwaitingSARActivationAck`  
Triggering event/input: WT-suffixed SAR finalization response  
Guards/preconditions: WT signature and suffix valid; inner SAR signature valid; returned identifier equals local `doxing_data_identifier_i`  
Actions/validations: store `sar_setup_response_i`; start all-peers SAR-active sync  
Emitted messages: signed `shared_state_active_sar_fingerprint`  
State updates: `sar_setup_response_i`, local SAR-active status  
To state: `Boomlet(i).Setup.AwaitingBackupCompletion`  
Failure exits: identifier mismatch, SAR signature mismatch, suffix mismatch  
Exact source anchors: `setup.md` 64–70; `setup.puml` 64–70

**`SETUP.Peer(i).Boomlet.077`**  
From state: `Boomlet(i).Setup.AwaitingBackupCompletion`  
Triggering event/input: signed backup request from Iso  
Guards/preconditions: verify normal-key signature, request magic, and backup-normal-key equality  
Actions/validations: export encrypted backup blob excluding current `mystery_i`; include `boomerang_params` and `sar_setup_response_i` for Iso verification  
Emitted messages: backup export to Iso  
State updates: backup session state  
To state: `Boomlet(i).Setup.AwaitingBackupCompletion`  
Failure exits: invalid backup request  
Exact source anchors: `setup.md` 76–78; `setup.puml` 76–78

**`SETUP.Peer(i).Boomletwo.081`**  
From state: `Boomletwo(i).InstalledUnseeded`  
Triggering event/input: receipt of encrypted backup blob and original Boomlet pubkey  
Guards/preconditions: none  
Actions/validations: decrypt/import backup; generate own `mystery_i`; sign `backup_done`  
Emitted messages: `backup_done_signed_by_boomletwo_i`  
State updates: imported backup state, own mystery  
To state: `Boomletwo(i).BackupImportedInactive`  
Failure exits: import failure  
Exact source anchors: `setup.md` 81–82; `setup.puml` 81–82

**`SETUP.Peer(i).Boomlet.085`**  
From state: `Boomlet(i).Setup.AwaitingBackupCompletion`  
Triggering event/input: `backup_done_signed_by_boomletwo_i` relayed by Iso  
Guards/preconditions: Boomletwo signature valid; magic, backup Boomlet pubkey, and original Boomlet pubkey match expected values  
Actions/validations: accept backup completion  
Emitted messages: `"setup_boomlet_backup_done"`  
State updates: local backup-complete status  
To state: `Boomlet(i).Setup.AwaitingFinalBackupSync`  
Failure exits: invalid `backup_done` contents or signature  
Exact source anchors: `setup.md` 83–86; `setup.puml` 83–86

**`SETUP.Peer(i).Boomlet.092`**  
From state: `Boomlet(i).Setup.AwaitingFinalBackupSync`  
Triggering event/input: all-peers backup fingerprint collection  
Guards/preconditions: all peer signatures valid; all contents equal local backup fingerprint  
Actions/validations: accept final setup synchronization  
Emitted messages: `"setup_done"`  
State updates: setup completion flag  
To state: `Boomlet(i).ActiveReady`  
Failure exits: peer sync mismatch  
Exact source anchors: `setup.md` 90–94; `setup.puml` 90–94

### 11.2 Withdrawal transitions

**`WD.Peer(0).Niso.001`**  
From state: `Niso(initiator).Withdrawal.Initiator.AwaitingPSBT`  
Triggering event/input: user submits PSBT  
Guards/preconditions: current local block height at or beyond `milestone_block_0`; `hydrate_psbt(psbt) != Null`  
Actions/validations: derive candidate `tx_id`; record `niso_0_event_block_height`; forward PSBT to Boomlet  
Emitted messages: PSBT plus block height to Boomlet  
State updates: `psbt_i`, `tx_id`, `niso_i_event_block_height`  
To state: `Niso(initiator).Withdrawal.Initiator.AwaitingAllApprovals`  
Failure exits: milestone not reached or unsatisfiable PSBT  
Exact source anchors: `withdrawal.md` 1; `initiator_withdrawal.puml` 1

**`WD.Peer(0).Boomlet.002`**  
From state: `Boomlet(initiator).Withdrawal.Initiator.AwaitingPSBT`  
Triggering event/input: PSBT plus current height from Niso  
Guards/preconditions: local height at or beyond `milestone_block_0`  
Actions/validations: derive and locally latch `tx_id`; create ST challenge carrying `tx_id_with_nonce`  
Emitted messages: encrypted `tx_id_with_nonce` to ST via Niso  
State updates: `tx_id`, local challenge state  
To state: `Boomlet(initiator).Withdrawal.Initiator.AwaitingPSBT`  
Failure exits: milestone not reached  
Exact source anchors: `withdrawal.md` 2–3; `initiator_withdrawal.puml` 2–3

**`WD.Peer(0).Boomlet.008`**  
From state: `Boomlet(initiator).Withdrawal.Initiator.AwaitingPSBT`  
Triggering event/input: ST-signed encrypted `tx_id_with_nonce` acknowledgment  
Guards/preconditions: ST signature valid; returned content equals sent challenge exactly  
Actions/validations: create initiator approval; encrypt per-peer PSBT copies for non-initiators  
Emitted messages: initiator approval and encrypted PSBT collection  
State updates: initiator approval state fixed for this ceremony  
To state: `Boomlet(initiator).Withdrawal.AwaitingAllApprovals`  
Failure exits: invalid ST signature or nonce/content mismatch  
Exact source anchors: `withdrawal.md` 6–9; `initiator_withdrawal.puml` 6–9

**`WD.WT.010`**  
From state: `WT.Withdrawal.AwaitingInitiatorApproval`  
Triggering event/input: initiator approval bundle  
Guards/preconditions: initiator signature valid; magic `"approved"`; freshness of initiator approval  
Actions/validations: store ceremony `tx_id`; create `wt_tx_approval`; fan out initiation bundle to non-initiators  
Emitted messages: `wt_tx_approval`, initiator approval, encrypted PSBT copies  
State updates: stored `tx_id`, stored initiator id, approval collection initialized  
To state: `WT.Withdrawal.CollectingPeerApprovals`  
Failure exits: invalid initiator approval or freshness failure  
Exact source anchors: `withdrawal.md` 10; `initiator_withdrawal.puml` 10

**`WD.Peer(i).Boomlet.012N`**  
From state: `Boomlet(non-initiator).Withdrawal.NonInitiator.AwaitingWTApprovalBundle`  
Triggering event/input: WT initiation bundle relayed by Niso  
Guards/preconditions: WT and initiator signatures valid; initiator id belongs to peer set; local height at or beyond `milestone_block_0`; freshness windows pass  
Actions/validations: decrypt PSBT; verify `tx_id`; return plaintext PSBT to Niso  
Emitted messages: plaintext PSBT to Niso  
State updates: local `psbt_i`, local `tx_id` candidate  
To state: `Boomlet(non-initiator).Withdrawal.NonInitiator.AwaitingWTApprovalBundle`  
Failure exits: bad signature, stale approval, decrypt failure, `tx_id` mismatch  
Exact source anchors: `withdrawal.md` 11–13; `non_initiator_withdrawal.puml` 11–13

**`WD.Peer(i).Boomlet.022N`**  
From state: `Boomlet(non-initiator).Withdrawal.NonInitiator.AwaitingWTApprovalBundle`  
Triggering event/input: ST-signed encrypted local `tx_id` acknowledgment  
Guards/preconditions: ST signature valid; exact equality to sent challenge  
Actions/validations: create local peer approval for WT  
Emitted messages: peer `"approved"` message  
State updates: non-initiator local approval now durable  
To state: `Boomlet(non-initiator).Withdrawal.AwaitingAllApprovals`  
Failure exits: invalid ST signature or freshness failure  
Exact source anchors: `withdrawal.md` 16–23; `non_initiator_withdrawal.puml` 16–23

**`WD.WT.024`**  
From state: `WT.Withdrawal.CollectingPeerApprovals`  
Triggering event/input: a non-initiator peer approval  
Guards/preconditions: peer signature valid; magic `"approved"`; expected `tx_id`; freshness relative to WT height and earlier WT approval  
Actions/validations: store the peer approval; once sufficient approvals exist, distribute the required approval collections  
Emitted messages: approval collections to initiator and non-initiators  
State updates: approval collection grows  
To state: `WT.Withdrawal.CollectingPeerApprovals`, then `WT.Withdrawal.CollectingCommitments`  
Failure exits: stale or mismatched peer approval  
Exact source anchors: `withdrawal.md` 24–26; `initiator_withdrawal.puml` 24–25; `non_initiator_withdrawal.puml` 24–26

**`WD.Peer(0).Boomlet.027`**  
From state: `Boomlet(initiator).Withdrawal.AwaitingAllApprovals`  
Triggering event/input: local approval collection validated  
Guards/preconditions: all peer approvals and WT approval pass mirrored validations  
Actions/validations: initiate the initial duress check  
Emitted messages: encrypted duress challenge to ST via Niso  
State updates: commitment-time challenge state  
To state: `Boomlet(initiator).Withdrawal.AwaitingInitialDuressResponse`  
Failure exits: approval-set inconsistency or freshness failure  
Exact source anchors: `withdrawal.md` 25–32; `initiator_withdrawal.puml` 27–32

**`WD.Peer(0).Boomlet.033`**  
From state: `Boomlet(initiator).Withdrawal.AwaitingInitialDuressResponse`  
Triggering event/input: ST returns initial duress response  
Guards/preconditions: nonce equality on duress response  
Actions/validations: evaluate response against `duress_consent_set_i`; set `duress_placeholder_plaintext_i`; if positive, latch duress; create padded initiator commit  
Emitted messages: initiator padded `"commit"` to WT via Niso  
State updates: `duress_placeholder_plaintext_i`, possibly `duress_latched_i`, local commit state  
To state: `Boomlet(initiator).Withdrawal.AwaitingCommitCollection`  
Failure exits: malformed response or freshness failure  
Exact source anchors: `withdrawal.md` 33–34; `initiator_withdrawal.puml` 33–35

**`WD.Peer(i).Boomlet.033N`**  
From state: `Boomlet(non-initiator).Withdrawal.AwaitingInitialDuressResponse`  
Triggering event/input: ST returns initial duress response  
Guards/preconditions: nonce equality  
Actions/validations: evaluate response against `duress_consent_set_i`; set placeholder plaintext; if positive, latch duress; create approvals bundle rather than commit  
Emitted messages: `approvals_signed_by_boomlet_i`  
State updates: `duress_placeholder_plaintext_i`, possibly `duress_latched_i`, approvals bundle state  
To state: `Boomlet(non-initiator).Withdrawal.NonInitiator.AwaitingWTInitiatorCommit`  
Failure exits: malformed response or freshness failure  
Exact source anchors: `withdrawal.md` 33n–34n; `non_initiator_withdrawal.puml` 33n–34n

**`WD.WT.035`**  
From state: `WT.Withdrawal.CollectingCommitments`  
Triggering event/input: initiator padded commit  
Guards/preconditions: outer initiator signature valid  
Actions/validations: separate placeholder; forward placeholder to SAR; hold inner initiator commit pending SAR return  
Emitted messages: placeholder to SAR  
State updates: initiator pending-commit state  
To state: `WT.Withdrawal.CollectingCommitments`  
Failure exits: invalid outer signature  
Exact source anchors: `withdrawal.md` 35–37; `initiator_withdrawal.puml` 35–37

**`WD.SAR.036`**  
From state: `SAR.FinalizedActive`  
Triggering event/input: duress placeholder plus Boomlet identity from WT  
Guards/preconditions: none beyond decryptability  
Actions/validations: decrypt placeholder; if non-zero and new, hash plaintext to identifier, locate encrypted doxing data, decrypt it, and enter search-and-rescue mode; regardless, sign placeholder and encrypt it back for Boomlet  
Emitted messages: SAR-signed placeholder acknowledgment to WT  
State updates: maybe add `(boomlet_identity_pubkey, iv)` to replay-suppression set; maybe enter rescue mode  
To state: `SAR.FinalizedActive` or `SAR.SearchAndRescueTriggered`  
Failure exits: malformed or unrecognized positive placeholder; exact handling unspecified  
Exact source anchors: `withdrawal.md` 36 and 42; both withdrawal diagrams; `duress.md` consequences section

**`WD.Peer(i).Boomlet.039`**  
From state: `Boomlet(non-initiator).Withdrawal.NonInitiator.AwaitingWTInitiatorCommit`  
Triggering event/input: WT-signed initiator commit relayed by Niso  
Guards/preconditions: WT and initiator signatures valid; magic `"commit"`; expected `tx_id`; freshness  
Actions/validations: create and emit local padded non-initiator commit  
Emitted messages: padded non-initiator `"commit"` to WT via Niso  
State updates: local commit state  
To state: `Boomlet(non-initiator).Withdrawal.AwaitingCommitCollection`  
Failure exits: stale or mismatched initiator commit  
Exact source anchors: `withdrawal.md` 38–40; `non_initiator_withdrawal.puml` 38–40

**`WD.Peer(i).Boomlet.045`**  
From state: `Boomlet(i).Withdrawal.AwaitingCommitCollection`  
Triggering event/input: WT delivers full commit collection plus the peer’s SAR-signed placeholder  
Guards/preconditions: SAR signature valid and returned placeholder equals the one sent; every WT and peer signature valid; every commit magic, `tx_id`, and freshness check valid  
Actions/validations: initialize `counter_i`, `ping_seq_num_i`, `reached_mystery_flag_i`, `reached_boomlets_collection_i`, and `last_seen_block_i`; create first ping  
Emitted messages: first padded `"ping"` to WT via Niso  
State updates: digging-game variables initialized  
To state: `Boomlet(i).Withdrawal.DiggingGame`  
Failure exits: placeholder mismatch or invalid commit collection  
Exact source anchors: `withdrawal.md` 44–46; `initiator_withdrawal.puml` 44–47; `non_initiator_withdrawal.puml` 44 and note

**`WD.WT.047`**  
From state: `WT.Withdrawal.DiggingGame.CollectingPings`  
Triggering event/input: first round of pings arrives  
Guards/preconditions: outer and inner ping signatures valid; magic `"ping"`; expected `tx_id`; freshness; first ping must not already claim local reached  
Actions/validations: initialize `reached_pings_collection` if first ping of the ceremony; extract placeholders; forward placeholders to SAR; record any newly reached peers  
Emitted messages: placeholders to SAR  
State updates: current-round ping set, maybe `reached_pings_collection`  
To state: `WT.Withdrawal.DiggingGame.CollectingPings`, then `WT.Withdrawal.DiggingGame.DistributingPongs`  
Failure exits: invalid ping, stale ping, or forbidden first-round reached flag  
Exact source anchors: `withdrawal.md` 46–53; `initiator_withdrawal.puml` 47–50 and loop note

**`WD.WT.050`**  
From state: `WT.Withdrawal.DiggingGame.DistributingPongs`  
Triggering event/input: all round pings and corresponding SAR placeholder acknowledgments are available  
Guards/preconditions: all required pings and SAR replies present; loop-break condition not yet satisfied  
Actions/validations: build per-peer pong containing the other peers’ validated previous pings; sign and encrypt it per peer; append the peer’s SAR-signed placeholder  
Emitted messages: per-peer pongs and placeholder acknowledgments  
State updates: none persistent beyond per-round outputs  
To state: `WT.Withdrawal.DiggingGame.CollectingPings`  
Failure exits: missing ping or missing SAR placeholder acknowledgment  
Exact source anchors: `withdrawal.md` 53–58; `initiator_withdrawal.puml` 50–51 and loop body

**`WD.Peer(i).Boomlet.051`**  
From state: `Boomlet(i).Withdrawal.DiggingGame`  
Triggering event/input: WT pong plus matching SAR-signed placeholder  
Guards/preconditions: SAR signature valid and placeholder matches; WT signature valid; `pong.tx_id == tx_id`; pong freshness valid; included previous peer pings have valid signatures, `tx_id`, and monotone `ping_seq_num`; peers already in `reached_boomlets_collection_i` must not regress  
Actions/validations: optionally run repeated duress check if PRNG condition fires; refresh placeholder; increment `counter_i` if block-height boundary condition passes; absorb newly reached peers; set local reached flag if `counter_i >= mystery_i`; bounded-update `last_seen_block_i`; create next ping  
Emitted messages: next padded ping; optionally repeated duress-check challenge to ST  
State updates: all digging-game variables  
To state: `Boomlet(i).Withdrawal.DiggingGame`  
Failure exits: stale pong, invalid prior ping, placeholder mismatch, repeated duress-response failure  
Exact source anchors: `withdrawal.md` 51–59 and 57–59; `initiator_withdrawal.puml` 51–59

**`WD.WT.060`**  
From state: `WT.Withdrawal.DiggingGame.CollectingPings`  
Triggering event/input: loop break condition becomes true  
Guards/preconditions: `reached_pings_collection` contains an entry for every peer id  
Actions/validations: distribute final `reached_pings_collection`  
Emitted messages: final reached-pings collection to all peers  
State updates: WT exits the digging game  
To state: `WT.Withdrawal.CollectingSignedPSBTs`  
Failure exits: none  
Exact source anchors: `withdrawal.md` 59–60; `initiator_withdrawal.puml` 59–60

**`WD.Peer(i).Boomlet.061`**  
From state: `Boomlet(i).Withdrawal.DiggingGame`  
Triggering event/input: `reached_pings_collection` and `hydrated_psbt_i` from Niso  
Guards/preconditions: every reached ping present and valid; `hydrated_psbt_i.derive_tx_id() == tx_id`  
Actions/validations: update stored PSBT; accept ready-to-sign condition  
Emitted messages: `"withdrawal_ready_to_sign"`  
State updates: signing-precondition state  
To state: `Boomlet(i).Withdrawal.ReadyToSign`  
Failure exits: invalid reached-pings collection or hydrated `tx_id` mismatch  
Exact source anchors: `withdrawal.md` 60–62; `initiator_withdrawal.puml` 60–62

**`WD.Peer(i).Boomlet.067`**  
From state: `Boomlet(i).Withdrawal.SigningWithIso`  
Triggering event/input: Iso sends `pubnonce_normal` and `partialsig_normal`  
Guards/preconditions: none explicitly stated beyond prior readiness  
Actions/validations: produce `partialsig_boom`; save local signed PSBT  
Emitted messages: `partialsig_boom` to Iso  
State updates: `signed_psbt_i` now exists locally  
To state: `Boomlet(i).Withdrawal.SigningWithIso`  
Failure exits: signing failure not separately specified  
Exact source anchors: `withdrawal.md` 66–68; `initiator_withdrawal.puml` 66–68

**`WD.Peer(i).Boomlet.071`**  
From state: `Boomlet(i).Withdrawal.SigningWithIso`  
Triggering event/input: Niso requests signed PSBT export  
Guards/preconditions: local `signed_psbt_i` exists  
Actions/validations: emit `psbt_signed_i`; clear withdrawal-local state except export artifact; regenerate `mystery_i`  
Emitted messages: `psbt_signed_i` to Niso  
State updates: withdrawal state cleared, fresh `mystery_i` generated  
To state: `Boomlet(i).Withdrawal.PostReset`  
Failure exits: none specified  
Exact source anchors: `withdrawal.md` 70–71; `initiator_withdrawal.puml` 70–71

**`WD.WT.Aggregate.073`**  
From state: `WT.Withdrawal.CollectingSignedPSBTs`  
Triggering event/input: WT has received `psbt_signed_i` from all five peers  
Guards/preconditions: all five signed PSBTs present  
Actions/validations: aggregate signed PSBTs; relay final signed transaction to the network  
Emitted messages: network relay of `signed_tx`  
State updates: completed ceremony output  
To state: `WT.Withdrawal.Broadcasting`, then WT idle for future ceremonies  
Failure exits: aggregation or relay failure not further specified  
Exact source anchors: `withdrawal.md` 73; `initiator_withdrawal.puml` 73

12. Loop specifications

### 12.1 Duress-setup confirmation loop

Entry condition: `duress_consent_set_i` has been derived from the first setup response and Boomlet generated the confirmation challenge.  
Loop invariant(s):
- `duress_consent_set_i` remains unchanged throughout confirmation attempts.
- The active confirmation response must be tied to the active confirmation challenge by the copied nonce.
- ST and Boomlet continue to share the same paired secret from the completed key exchange.
- Success is defined only by set equality with `duress_consent_set_i`, not by index equality or order equality.

Loop body transitions:
1. Boomlet generates and emits a fresh confirmation challenge space plus nonce.
2. ST decrypts and displays the confirmation space.
3. User selects one country per displayed column to reconstruct the consent set.
4. ST encodes indices, copies the nonce, encrypts the response, and returns it through Iso.
5. Boomlet decrypts, checks nonce equality, and evaluates whether the selected-number set equals `duress_consent_set_i`.

Counter/state updates:
- No protocol counter is incremented in the authoritative setup text.
- In `duress_setup.puml`, failure once causes a retry from message 11; failure again causes a restart from message 4. Because `setup.md` does not define the retry budget, this specification records only the conservative rule that success requires exact set equality and failure does not silently advance setup.

Break condition: Boomlet verifies that the selected-number set equals `duress_consent_set_i`.  
Post-loop state: `Boomlet(i).Setup.OfflineReadyAwaitingNiso`.  
Source anchors: `setup.md` 20–27; `setup.puml` 20–27; `duress_setup.puml` messages 11–17.

### 12.2 Ping-pong / digging-game loop

Entry condition: each peer has verified the full commit collection and its own SAR-signed placeholder, and has initialized `counter_i = 0`, `ping_seq_num_i = 0`, `reached_mystery_flag_i = 0`, `reached_boomlets_collection_i = {}`, and `last_seen_block_i = niso_i_event_block_height`.  
Loop invariant(s):
- `tx_id` is fixed and identical across all valid approvals, commits, pings, pongs, reached-pings, and hydrated PSBTs in the ceremony.
- `counter_i` is monotone nondecreasing.
- `ping_seq_num_i` is strictly increasing after the first ping.
- `reached_mystery_flag_i` is monotone: once one, never zero again within the ceremony.
- `reached_boomlets_collection_i` is monotone by peer id: once a peer is recorded as reached, it is never removed.
- WT’s `reached_pings_collection` is monotone by peer id.
- `last_seen_block_i` never decreases.
- The observable message pattern remains the same whether `duress_placeholder_plaintext_i` is zero-padding or `doxing_key_i`.
- If `duress_latched_i` is true, every subsequent placeholder from that Boomlet is generated from `doxing_key_i`, not from later non-duress input.

Loop body transitions:
1. Each peer emits a padded ping containing `{tx_id, last_seen_block_i, ping_seq_num_i, reached_mystery_flag_i}`.
2. WT validates each ping, forwards each placeholder to SAR, optionally records new reached peers, and waits until the round’s pings are complete.
3. SAR processes each placeholder, possibly triggers rescue, and returns a signed placeholder acknowledgment.
4. WT builds and distributes one pong per peer, each containing the other peers’ validated previous pings plus that peer’s matching SAR-signed placeholder.
5. Each Boomlet validates its pong and the included peer pings, maybe performs a repeated duress check, updates its placeholder, evaluates the counter-increment guard, absorbs any newly reached peers, possibly sets its own reached flag, updates `last_seen_block_i`, increments `ping_seq_num_i`, and emits the next ping.

Counter/state updates:
- `counter_i := counter_i + 1` only if the source-defined block-height boundary condition for that round holds.
- `reached_boomlets_collection_i[peer_j]` is set when peer `j` first appears with `reached_mystery_flag = 1`.
- `reached_mystery_flag_i := 1` when `counter_i >= mystery_i`.
- `last_seen_block_i := min(niso_i_event_block_height, last_seen_block_i + JUMP_IN_BLOCKS_IF_LAST_SEEN_BLOCK_LAGS_BEHIND_NISO_EVENT_BLOCK_HEIGHT_IN_BOOMLET)` when the local height advanced.
- `ping_seq_num_i := ping_seq_num_i + 1` when forming the next ping after the first.

Break condition: WT has `reached_pings_collection[peer_j]` for every peer id `peer_j` in the agreed peer set.  
Post-loop state: `Boomlet(i).Withdrawal.ReadyToSign` after `reached_pings_collection` and `hydrated_psbt_i` are locally validated.  
Source anchors: `withdrawal.md` 45–61; `initiator_withdrawal.puml` loop note and steps 45–61; `DEEPDIVE.md` withdrawal Group 6.

### 12.3 Repeated duress-check loop during withdrawal

Entry condition: Boomlet is in `Withdrawal.DiggingGame` and has just processed a pong.  
Loop invariant(s):
- A repeated duress check never changes the control-flow skeleton of the ceremony; it changes only the plaintext that is next encrypted into the duress-bearing placeholder.
- Nonce equality is required between each repeated challenge and its response.
- The repeated duress-check mechanism preserves the same consent-set semantics as the initial check.
- A positive repeated duress outcome sets or keeps `duress_latched_i = true`.

Loop body transitions:
1. Boomlet evaluates its PRNG condition. If the condition does not fire, it skips directly to placeholder regeneration from the existing `duress_placeholder_plaintext_i`.
2. If the condition fires, Boomlet generates a fresh challenge space and nonce, ST displays it, User responds, ST returns encrypted indices with copied nonce, and Boomlet evaluates the returned set against `duress_consent_set_i`.
3. Boomlet updates `duress_placeholder_plaintext_i` to zero-padding or `doxing_key_i` accordingly.
4. Boomlet encrypts the new or retained plaintext for SAR, producing the next `duress_placeholder_i`.

Counter/state updates:
- No digging-game counter increments solely because a repeated duress check occurred.
- The only state changed directly by the repeated duress loop is the placeholder-related state (`duress_placeholder_plaintext_i`, `duress_placeholder_i`, and possibly `duress_latched_i`).

Break condition: either the PRNG condition does not fire for a given pong, or the challenge/response sequence completes and a new placeholder is available.  
Post-loop state: control returns to ordinary pong-processing and next-ping generation within `Boomlet(i).Withdrawal.DiggingGame`.  
Source anchors: `withdrawal.md` 51–59; `initiator_withdrawal.puml` 51–59; `duress.md` PRNG-based interval choice; `duress_withdrawal.puml`.

13. Safety properties / invariants

The following safety properties are stated in precise English as invariant candidates for later formalization.

1. **Transaction identity consistency**. Once the initiator Boomlet accepts the PSBT and emits the initiator approval, every valid approval, commit, ping, pong, reached ping, hydrated PSBT, and signed PSBT in the same ceremony refers to the same `tx_id`. No transition that observes a different `tx_id` is valid.

2. **Setup-state inheritance**. Every withdrawal starts from setup-complete state. In particular, `boomerang_params`, `duress_consent_set_i`, peer ids, WT ids, SAR finalization state, and the current `mystery_i` used at withdrawal entry must already exist before the withdrawal machine may enter `Initiation`.

3. **Descriptor-ordering invariant**. The boomerang-regime script governed by boom keys is spendable from `milestone_block_0`, and all normal deterministic scripts become spendable only at later milestone blocks. The setup machine never constructs a descriptor that violates that ordering.

4. **Mirrored validation invariant**. Whenever the sources place the same validation in Niso and Boomlet, both validations are required. A message accepted by Niso but rejected by Boomlet does not advance the Boomlet machine; likewise, a message rejected by Niso is not presumed valid merely because Boomlet could have validated it.

5. **Signature-gated transitions only**. Any transition whose enabling condition depends on a signed object is valid only if the specified signature verification succeeds under the specified public key.

6. **Nonce-bound ST interactions only**. Any ST-mediated response that is supposed to answer a Boomlet challenge is valid only if it contains the same nonce as the challenge being answered.

7. **Freshness-bounded transition invariant**. Approval, commitment, ping, and pong transitions are valid only if their source-defined block-height freshness inequalities hold. The machine does not silently advance on stale messages.

8. **No early signing**. No actor may enter `ReadyToSign` or `Signing` before all of the following hold: all required approvals exist and were validated, all required commits exist and were validated, WT has broken the digging loop by collecting a reached ping for every peer, and the hydrated PSBT still yields the committed `tx_id`.

9. **Monotone reached-state invariant**. Within one ceremony, `reached_mystery_flag_i`, `reached_boomlets_collection_i`, and WT’s `reached_pings_collection` are monotone. There is no valid transition that removes a reached peer or resets a reached flag to zero.

10. **Counter monotonicity**. `counter_i` never decreases during a ceremony. It increases only when the explicit block-height boundary condition for incrementing holds.

11. **Ping sequence monotonicity**. After the first ping, `ping_seq_num_i` must strictly increase on each subsequent local ping. WT and peers reject non-increasing sequence numbers where the sources require that check.

12. **Placeholder authenticity**. When a peer receives a SAR-signed placeholder acknowledgment, Boomlet must be able to verify both SAR’s signature and that the acknowledged placeholder is the same placeholder it previously sent. A mismatched placeholder does not permit progress.

13. **Observational consistency of duress and non-duress flows**. A positive duress signal does not change the visible control-flow skeleton, message ordering, or overall digging duration. The only intended difference is the encrypted duress-bearing payload carried inside messages and the off-model SAR rescue consequence.

14. **Post-duress monotonicity**. Once a Boomlet has emitted a positive duress signal during a ceremony, later boomlet-emitted placeholders in that ceremony continue to carry the duress payload rather than reverting to zero-padding.

15. **Backup exclusion of current mystery**. The exported backup blob from Boomlet to Boomletwo excludes the current `mystery_i`. Boomletwo generates its own mystery after import.

16. **No regression from setup complete to pre-setup**. The specified withdrawal flow and cleanup/reset do not alter `boomerang_params`, `duress_consent_set_i`, or the agreed setup identities. They clear only withdrawal-specific state and regenerate `mystery_i`.

17. **WT break condition correctness**. WT exits the digging loop only when it has a valid reached ping for every peer id in the agreed peer set. Having all current-round pings is not by itself sufficient.

18. **Normal-regime non-interference in current machine**. No transition in the specified setup or withdrawal machine uses the deterministic normal regime. Its presence affects descriptor structure and fallback reasoning only.

14. Liveness / progress properties

The protocol intends the following progress properties, always under explicit assumptions.

### 14.1 Protocol-internal progress

- If setup starts and every required local step, payment, relay, and peer-equality check succeeds, then setup can progress from SAR sign-up through final backup synchronization to `setup_done`.
- If a boomerang-regime withdrawal starts after `milestone_block_0`, every peer continues participating, and all freshness windows continue to hold, then the withdrawal can progress from initiation through approval, commitment, digging game, signing, signed-PSBT export, WT aggregation, and local reset.
- If all five peers eventually emit a reached ping, then WT will eventually break the digging loop and distribute `reached_pings_collection`.

### 14.2 Progress requiring honest and responsive peers

- Setup parameter fixation requires that all peers eventually send matching signed `boomerang_params`.
- WT-active, SAR-active, and backup-active synchronization each require that all peers eventually emit matching signed fingerprints for the corresponding shared state.
- Withdrawal approval requires that all non-initiator peers eventually emit valid approvals.
- Withdrawal commitment requires that all non-initiator peers eventually emit valid approvals bundles and then valid commits.
- Digging-game termination requires that each peer eventually reach its local `mystery_i` and emit at least one valid reached ping that WT accepts.

### 14.3 Progress requiring WT availability

- No boomerang-regime withdrawal progress past the initiator’s local ST approval is possible without WT.
- WT must remain available to distribute `wt_tx_approval`, collect approvals and commits, drive the ping-pong loop, distribute pongs, distribute `reached_pings_collection`, and aggregate signed PSBTs.
- The design recognizes WT replacement as an ancillary procedure, so WT failure is a liveness failure in the current machine.

### 14.4 Progress requiring SAR availability

- Commitment and ping processing, as specified, include SAR placeholder forwarding and return acknowledgments. The authoritative flows do not define a branch that proceeds without SAR responses, so SAR unavailability blocks those WT transitions.
- SAR does not directly control spending authority, but SAR availability is operationally required for the specified WT/peer progress path.

### 14.5 Progress subject to freshness windows and forced determinism

- Even with honest actors, progress can fail if approval, commitment, ping, or pong messages arrive outside the source-defined freshness windows.
- Progress can also fail if the withdrawal begins too late relative to the deterministic fallback milestones, because the design itself identifies late-start forced determinism as a collapse of the intended probabilistic guarantee.
- The design intends the digging game to have finite completion because each `mystery_i` is finite, but actual progress still depends on repeated communication rounds succeeding often enough before freshness assumptions fail.
- The current machine does not specify how to recover from failed freshness or forced-determinism conditions; it only recognizes them.

15. Failure, timeout, freshness, and forced-determinism conditions

This section enumerates failure edges that are explicit or directly implied by the sources. Classification is:
- **Terminal**: current ceremony cannot progress in the specified machine.
- **Retryable**: the sources explicitly allow retry.
- **Unspecified**: a failure is identified, but no recovery is defined.

### 15.1 Setup failures

- SAR invoice not paid: terminal for current setup attempt.
- SAR payment receipt invalid: terminal.
- Phone/SAR sync acknowledgment missing: terminal or unspecified retry.
- Boomlet installation on non-empty or failed hardware: terminal.
- ST pairing failure or malformed pairing input: terminal.
- Initial duress-setup response nonce mismatch: terminal for the active check.
- Duress confirmation mismatch: retryable in `duress_setup.puml`, but exact retry budget is unspecified in authoritative text.
- Peer Tor-address signature failure: terminal.
- Niso-derived Tor address mismatch with Boomlet-signed address: terminal.
- Peer-address collection missing the local peer’s own tuple: terminal.
- ST-signed parameter-seed mismatch or signature failure: terminal.
- Peer-signed `boomerang_params` mismatch: terminal.
- WT invoice not paid: terminal.
- WT acknowledgment signature, suffix, or content mismatch: terminal.
- SAR finalization identifier mismatch: terminal.
- SAR finalization signature or WT suffix mismatch: terminal.
- Descriptor reconstruction mismatch during backup verification: terminal.
- Static doxing-data fingerprint mismatch during backup verification: terminal.
- Backup request signature, magic, or normal-key mismatch: terminal.
- Backup import decryption failure on Boomletwo: terminal.
- `backup_done` signature or content mismatch: terminal.
- All-peers WT/SAR/backup fingerprint sync mismatch: terminal.

### 15.2 Withdrawal approval failures

- `milestone_block_0` not yet reached at initiator start or non-initiator receipt: terminal for boomerang-regime start until the milestone is later reached.
- PSBT unsatisfiable or hydration returns null: terminal for that withdrawal attempt.
- Local ST-displayed `tx_id` differs from the user’s PSBT-derived `tx_id`: terminal for that peer’s participation in the current ceremony.
- ST `tx_id` response signature failure or nonce/content mismatch: terminal.
- WT approval signature failure, initiator identity not in peer set, or initiator approval signature failure: terminal.
- Approval magic mismatch or `tx_id` mismatch: terminal.
- Approval freshness failure: terminal for the current ceremony as specified.
- Missing non-initiator approval: progress failure and therefore terminal in the specified machine.

### 15.3 Commitment-phase failures

- Initial duress-check response nonce mismatch: terminal for that attempt.
- Placeholder generation/decryption failure: terminal.
- Non-initiator approvals-bundle signature failure or content mismatch: terminal.
- Initiator or non-initiator commit outer signature failure at WT: terminal for that commit.
- Commit inner signature failure, magic mismatch, `tx_id` mismatch, or freshness failure: terminal for that peer’s commit.
- SAR cannot decrypt placeholder or cannot map a positive placeholder to a registered identifier: duress handling may fail; commitment progress after such malformed input is unspecified.
- Returned SAR-signed placeholder fails signature check or does not match the placeholder previously sent: terminal locally.
- Full commit collection signature/content/freshness mismatch: terminal locally.

### 15.4 Digging-game failures

- Ping outer or inner signature failure: terminal for that ping.
- Ping magic mismatch, `tx_id` mismatch, or freshness failure: terminal for that ping.
- First ping arrives with `reached_mystery_flag = 1`: terminal for that ping according to the WT-side rule.
- Ping sequence number fails to increase after the first ping: terminal for that ping.
- Pong signature failure, magic mismatch, `tx_id` mismatch, or freshness failure: terminal for that pong.
- Included previous peer ping signature failure, magic mismatch, `tx_id` mismatch, or sequence anomaly: terminal for that pong-processing step.
- Repeated duress-check response nonce mismatch or malformed response: terminal for that duress-check instance and therefore for the local peer’s next-ping generation.
- `reached_pings_collection` missing a peer or containing an invalid reached ping at finalization: terminal locally.
- WT unavailability during the loop: terminal for progress.
- SAR unavailability for placeholders during the loop: terminal for progress in the specified flow.

### 15.5 Signing and export failures

- User does not reconnect Boomlet to Iso after ready-to-sign: progress failure; unspecified timeout handling.
- Iso cannot reconstruct signing material from mnemonic/passphrase: terminal for that peer.
- MuSig2 subprotocol failure: terminal; low-level recovery unspecified.
- User does not reconnect Boomlet to Niso after signing: progress failure; unspecified timeout handling.
- Boomlet export request not received or `psbt_signed_i` not delivered to WT: progress failure.
- WT does not receive all five signed PSBTs: terminal for final broadcast in the specified machine.
- WT aggregation or relay failure: terminal or unspecified post-failure handling.

### 15.6 Forced-determinism and structural failures

- Boomlet loss or destruction before boomerang-regime spend completes: the boomerang-regime guarantee collapses; the design falls back conceptually to later deterministic scripts. The actual operational recovery is outside this machine.
- Loss of both Boomlet and Boomletwo: recognized in `DEEPDIVE.md` as forced determinism or protocol collapse; terminal for the boomerang-regime machine.
- Withdrawal started too close to deterministic fallback milestones such that the digging game cannot complete under the intended assumptions: recognized forced-determinism threat; handling unspecified.
- A peer stops cooperating: terminal for 5-of-5 boomerang-regime progress.
- Dynamic doxing-data feed loss or tampering by Phone compromise: not a protocol-spending failure but a degradation of SAR effectiveness; recovery unspecified.
- Missing SAR acknowledgment, missing WT replacement, or prolonged peer latency: recognized as unresolved ancillary issues; recovery unspecified.

### 15.7 Timeout status

The sources mention timeouts, stale messages, and freshness windows, but they do not specify a general timeout machine. Therefore:
- freshness failures are modeled as explicit invalidating guards;
- human absence during repeated duress checks is a liveness failure, not a hidden timeout branch;
- any explicit retry exists only where a source explicitly says so;
- all other retry/abort/resume logic is unspecified.

16. Ambiguity / conflict register

**ACR-01 — Setup duress challenge structure**  
Source anchors: `setup.md` 14–26; `setup.puml` 14–26; `duress.md` setup subsection; `duress_setup.puml` messages 4–16.  
Exact ambiguity/conflict: `setup.md` and `setup.puml` model setup with a `duress_check_space` that is an array of 5 integers between 1 and 195, whereas `duress.md` and `duress_setup.puml` describe setup as a full random ordering of 1..195 followed by later five-column confirmation sets.  
Conservative interpretation used here: setup establishes a consent-set semantics, not a unique authoritative encoding. The machine therefore requires only that Boomlet present enough structured challenge material for ST to encode a five-country consent set and later confirm it.  
Why it matters for formalization: the size and structure of the challenge domain affects the state space and the exact mapping from user choices to stored consent data.  
Decision needed: choose whether setup uses a 5-element challenge, a full permutation of 1..195, or both in different rounds.

**ACR-02 — Setup duress confirmation retry policy**  
Source anchors: `setup.md` 20–27; `setup.puml` 20–27; `duress_setup.puml` messages 16–17.  
Exact ambiguity/conflict: `setup.md` implies retries but does not bound them; `duress_setup.puml` says one retry from message 11, then restart from message 4 if the retry also fails.  
Conservative interpretation used here: success requires exact set equality; failure does not advance setup; retry policy beyond “failure does not succeed” is left unresolved.  
Why it matters: retry structure changes the control graph and fairness assumptions.  
Decision needed: define an exact retry count and restart point.

**ACR-03 — Scope of “duress-bearing payload in every message”**  
Source anchors: `DEEPDIVE.md` overarching overview and solution description; `duress.md` consequences; `withdrawal.md` explicit message fields.  
Exact ambiguity/conflict: high-level text says every message after initial transaction approval carries an encrypted payload, but the operative withdrawal steps explicitly show duress placeholders in commits and pings and the returned SAR acknowledgments, not in every approval message.  
Conservative interpretation used here: duress-bearing placeholders are mandatory from the commitment phase onward, and repeated thereafter during the digging game; approval messages are not treated as payload-bearing unless a later source makes that explicit.  
Why it matters: it determines the message schema and whether SAR is contacted during the approval phase.  
Decision needed: declare exactly which message families carry placeholders.

**ACR-04 — Non-initiator pre-commit asymmetry semantics**  
Source anchors: `withdrawal.md` 33n–40; `non_initiator_withdrawal.puml` 33n–40.  
Exact ambiguity/conflict: none in the sources themselves, but this asymmetry is easy to overlook. A non-initiator does not emit its own commit immediately after the initial duress check; it first sends an approvals bundle.  
Conservative interpretation used here: the approvals bundle is a distinct message family and not a commit surrogate.  
Why it matters: collapsing initiator and non-initiator too early would incorrectly remove a causal barrier in the protocol.  
Decision needed: none, but any formal model must preserve this branch.

**ACR-05 — Post-duress monotonicity source strength**  
Source anchors: `duress.md` duress consequences; `duress_withdrawal.puml` final note.  
Exact ambiguity/conflict: the markdown says that after emitting duress signal, the duress-bearing payload in every message is replaced by the encrypted doxing key; the diagram says once one duress check is positive, all later messages bear the duress signal regardless of later user input.  
Conservative interpretation used here: a positive duress outcome latches for the remainder of the ceremony.  
Why it matters: without a latch, later user behavior could revert the placeholder and violate the design’s intended observational guarantee.  
Decision needed: explicitly state whether the latch is permanent for one ceremony.

**ACR-06 — What SAR hashes on positive duress**  
Source anchors: `duress.md` doxing data section; `withdrawal.md` 36 and 42; `non_initiator_withdrawal.puml` 42.  
Exact ambiguity/conflict: some prose says SAR hashes the resulting decrypted data; one non-initiator description phrase risks sounding like it hashes the ciphertext.  
Conservative interpretation used here: SAR hashes decrypted `duress_placeholder_plaintext`, which equals `doxing_key_i` in the positive case.  
Why it matters: hashing ciphertext instead of plaintext breaks identifier lookup.  
Decision needed: confirm the plaintext-hash rule in the definitive design text.

**ACR-07 — Setup-time initialization of `counter`**  
Source anchors: `setup.md` 47; `withdrawal.md` 45; `initiator_withdrawal.puml` 45.  
Exact ambiguity/conflict: setup says mystery generation initializes `counter` to 0, but withdrawal again initializes `counter` to 0 when the digging game starts.  
Conservative interpretation used here: `counter` is effectively withdrawal-local and is reinitialized at digging-game entry, regardless of any persistent default value stored earlier.  
Why it matters: a formal model must know whether `counter` is durable across aborted withdrawals.  
Decision needed: decide whether `counter` persists outside active withdrawal.

**ACR-08 — Exact freshness and required-minimum-distance constants**  
Source anchors: withdrawal diagrams parameter blocks; `withdrawal.md` prose freshness checks.  
Exact ambiguity/conflict: the diagrams list named constants and some example arithmetic, but no authoritative numeric values are supplied in the design files given here.  
Conservative interpretation used here: these are abstract parameters of the machine, not fixed integers.  
Why it matters: liveness and reachable-state analysis depend strongly on these constants.  
Decision needed: supply numeric values or leave them as model parameters in the later TLA+ work.

**ACR-09 — Meaning of zero-padding versus “empty padding”**  
Source anchors: `withdrawal.md` 33 and 33n; `duress.md` says all-zero data.  
Exact ambiguity/conflict: some withdrawal prose says “empty padding”, while the duress design says all-zero data of fixed size.  
Conservative interpretation used here: non-duress placeholder plaintext is fixed-size all-zero data, not a length-zero payload.  
Why it matters: replay suppression and ciphertext indistinguishability assume comparable payload sizing.  
Decision needed: define the exact non-duress placeholder plaintext shape.

**ACR-10 — Initiator identity field naming**  
Source anchors: `withdrawal.md` 10–12; withdrawal diagrams.  
Exact ambiguity/conflict: the WT approval refers to the initiator by `boomlet_0_identity_pubkey` or an `initiator_id` field; the exact serialized field name is inconsistent.  
Conservative interpretation used here: WT approval carries a field whose value uniquely names the initiator Boomlet identity and must belong to `peer_ids_collection`.  
Why it matters: the formal message schema needs a single authoritative field name.  
Decision needed: choose a canonical field name and type.

**ACR-11 — Ancillary activation of Boomletwo**  
Source anchors: `DEEPDIVE.md` concern on Boomlet loss and Boomletwo activation.  
Exact ambiguity/conflict: setup fully specifies backup creation, but activation/deactivation between Boomlet and Boomletwo is explicitly not designed.  
Conservative interpretation used here: Boomletwo remains inactive throughout this machine.  
Why it matters: any operational recovery model that tries to switch to Boomletwo would invent control states absent from the sources.  
Decision needed: design the activation protocol before formalizing backup recovery.

**ACR-12 — Failure handling after malformed SAR messages**  
Source anchors: `duress_withdrawal.puml` malformed-message branch; `duress.md`; absence from `withdrawal.md`.  
Exact ambiguity/conflict: the duress-withdrawal diagram suggests SAR may count malformed messages and eventually stop responding, but the authoritative withdrawal markdown does not operationalize that branch.  
Conservative interpretation used here: malformed-message counting is noted but not included as an operative transition in the authoritative withdrawal machine.  
Why it matters: including it would add a new SAR liveness-failure loop not supported by the higher-authority withdrawal steps.  
Decision needed: either elevate this branch into the authoritative withdrawal flow or exclude it explicitly from the next design revision.

**ACR-13 — Forced determinism handling**  
Source anchors: `DEEPDIVE.md` concerns and ancillaries.  
Exact ambiguity/conflict: the design identifies several forced-determinism scenarios but does not specify operational transition rules for them.  
Conservative interpretation used here: forced determinism is a recognized failure mode external to the current machine, not an alternate branch within it.  
Why it matters: formal models need to know whether to represent forced determinism as a safety violation, a liveness failure, or an explicit branch to another regime.  
Decision needed: define when and how the machine acknowledges collapse to deterministic behavior.

**ACR-14 — Exact shape of setup and withdrawal local display/input interactions**  
Source anchors: all ST-mediated steps; diagrams and markdowns.  
Exact ambiguity/conflict: the sources are consistent on semantic checks but not on whether every human interaction is modeled as a message, display event, or local side effect.  
Conservative interpretation used here: every ST display and every user/ST input is modeled as an explicit event.  
Why it matters: hiding these interactions would make duress and approval subprotocols under-specified.  
Decision needed: keep them explicit in the formal model unless a later design intentionally abstracts them away.

17. Source-to-machine coverage matrix

### 17.1 `setup.md` numbered-step coverage

- `setup.md` 1 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.Phone(i).001`; diagram note: `setup.puml` step 1; summary: At the start of SAR registration, Phone receives {doxing_password, sar_ids_collection, static_doxing_data} fr…
- `setup.md` 2 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.SAR.002`; diagram note: `setup.puml` step 2; summary: SAR receives doxing_data_identifier from Phone and responds with a newly generated sar_service_fee_payment_in…
- `setup.md` 3 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.Phone(i).003`; diagram note: `setup.puml` step 3; summary: Phone receives sar_service_fee_payment_info from SAR and forwards it to User.
- `setup.md` 4 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.User(i).004`; diagram note: `setup.puml` step 4; summary: User receives sar_service_fee_payment_info from Phone, verifies the details of it and pays the invoice genera…
- `setup.md` 5 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.Phone(i).005`; diagram note: `setup.puml` step 5; summary: Phone receives sar_service_fee_payment_receipts from User and forwards it to SAR alongside encrypted static_d…
- `setup.md` 6 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.SAR.006`; diagram note: `setup.puml` step 6; summary: SAR receives {sar_service_fee_payment_receipts, static_doxing_data_encrypted_by_doxing_key, doxing_data_ident…
- `setup.md` 7 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.Phone(i).007`; diagram note: `setup.puml` step 7; summary: Phone receives {magic: "setup_sar_setup_done_and_in_sync_with_phone"} from SAR and informs User that the regi…
- `setup.md` 8 -> state(s): SAR sign-up states in `User(i)`, `Phone(i)`, and `SAR`; transition(s): `SETUP.User(i).008`; diagram note: `setup.puml` step 8; summary: User receives {magic: "setup_sar_registered_and_connected_to_phone"} from Phone and proceeds to install Booml…
- `setup.md` 9 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.009`; diagram note: `setup.puml` step 9; summary: Iso receives {network, entropy_bytes, passphrase, doxing_password, sar_ids_collection} from User, creates mne…
- `setup.md` 10 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Boomlet.010`; diagram note: `setup.puml` step 10; summary: Boomlet receives {normal_pubkey_0, doxing_key, sar_ids_collection, network} from Iso during the installation.…
- `setup.md` 11 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.011`; diagram note: `setup.puml` step 11; summary: Iso receives boomlet_0_identity_pubkey from Boomlet and forwards it to ST.
- `setup.md` 12 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).ST.012`; diagram note: `setup.puml` step 12; summary: ST receives boomlet_0_identity_pubkey from Iso and responds with st_0_identity_pubkey for Boomlet to generate…
- `setup.md` 13 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.013`; diagram note: `setup.puml` step 13; summary: Iso receives st_0_identity_pubkey from ST and forwards it to Boomlet.
- `setup.md` 14 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Boomlet.014`; diagram note: `setup.puml` step 14; summary: Boomlet receives st_0_identity_pubkey from Iso. It then generates an array of 5 random integers between 1 and…
- `setup.md` 15 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.015`; diagram note: `setup.puml` step 15; summary: Iso receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Boomlet and forwards it to ST.
- `setup.md` 16 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).ST.016`; diagram note: `setup.puml` step 16; summary: ST receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Iso. Decrypts it to get duress_c…
- `setup.md` 17 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.User(i).017`; diagram note: `setup.puml` step 17; summary: User receives duress_check_space from ST. He then selects 5 countries of his choice for duress_consent_set vi…
- `setup.md` 18 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).ST.018`; diagram note: `setup.puml` step 18; summary: ST receives duress_signal_index from User. ST then creates duress_signal_index_with_nonce using the nonce fro…
- `setup.md` 19 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.019`; diagram note: `setup.puml` step 19; summary: Iso receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from ST and forwards it to Boomlet.
- `setup.md` 20 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Boomlet.020`; diagram note: `setup.puml` step 20; summary: Boomlet receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from Iso and decrypts it to get…
- `setup.md` 21 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.021`; diagram note: `setup.puml` step 21; summary: Iso receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Boomlet and forwards it to ST.
- `setup.md` 22 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).ST.022`; diagram note: `setup.puml` step 22; summary: ST receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Iso, separates the nonce and ass…
- `setup.md` 23 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.User(i).023`; diagram note: `setup.puml` step 23; summary: User receives duress_check_space from ST. He will select 1 country in each column to replicate the duress_con…
- `setup.md` 24 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).ST.024`; diagram note: `setup.puml` step 24; summary: ST receives duress_signal_index from User. ST then creates duress_signal_index_with_nonce using the nonce fro…
- `setup.md` 25 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.025`; diagram note: `setup.puml` step 25; summary: Iso receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from ST and forwards it to Boomlet.
- `setup.md` 26 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Boomlet.026`; diagram note: `setup.puml` step 26; summary: Boomlet receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from Iso. Boomlet will search f…
- `setup.md` 27 -> state(s): offline duress-setup states in `Iso(i)`, `Boomlet(i)`, and `ST(i)`; transition(s): `SETUP.Peer(i).Iso.027`; diagram note: `setup.puml` step 27; summary: Iso receives {magic: "setup_duress_finished"} from Boomlet and knowing Boomlet can be disconnected, returns m…
- `setup.md` 28 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.User(i).028`; diagram note: `setup.puml` step 28; summary: User receives mnemonic from Iso, saves it in a safe place and proceeds to shutdown Iso and connect Boomlet to…
- `setup.md` 29 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Niso.029`; diagram note: `setup.puml` step 29; summary: Niso receives {network, rpc_client_url, rpc_client_auth} from User during the installation. rpc_client_url an…
- `setup.md` 30 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Boomlet.030`; diagram note: `setup.puml` step 30; summary: Boomlet receives {magic: "setup_initialized"} from Niso. It then derives peer_0_tor_address from peer_0_tor_s…
- `setup.md` 31 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Niso.031`; diagram note: `setup.puml` step 31; summary: Niso receives {peer_0_id, peer_0_tor_secret_key, peer_0_tor_address_signed_by_boomlet_0} from Boomlet. It ver…
- `setup.md` 32 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).ST.032`; diagram note: `setup.puml` step 32; summary: ST receives {peer_0_id, peer_0_tor_address_signed_by_boomlet_0} from Niso. Since ST already knows boomlet_0_i…
- `setup.md` 33 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.User(i).033`; diagram note: `setup.puml` step 33; summary: User receives {peer_0_id, peer_0_tor_address_signed_by_boomlet_0} from ST and proceeds to share it with peers…
- `setup.md` 34 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.User(i).034`; diagram note: `setup.puml` step 34; summary: User receives {peer_i_id, peer_i_tor_address_signed_by_boomlet_i} from peers, sending his own {peer_0_id, pee…
- `setup.md` 35 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Niso.035`; diagram note: `setup.puml` step 35; summary: Niso receives {peer_addresses_collection, wt_ids_collection, milestone_block_collection} from User. It checks…
- `setup.md` 36 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Boomlet.036`; diagram note: `setup.puml` step 36; summary: Boomlet receives {peer_addresses_collection, wt_ids_collection, milestone_block_collection} from Niso. It che…
- `setup.md` 37 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Niso.037`; diagram note: `setup.puml` step 37; summary: Niso receives boomerang_params_seed_encrypted_by_boomlet_0_for_st from Boomlet and forwards it to ST.
- `setup.md` 38 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).ST.038`; diagram note: `setup.puml` step 38; summary: ST receives boomerang_params_seed_encrypted_by_boomlet_0_for_st from Niso, decrypts it to get boomerang_param…
- `setup.md` 39 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.User(i).039`; diagram note: `setup.puml` step 39; summary: User receives boomerang_params_seed from ST and checks the correctness of its Peer ids, Watchtower ids and mi…
- `setup.md` 40 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).ST.040`; diagram note: `setup.puml` step 40; summary: ST receives {magic: "setup_user_verified_peer_ids_and_wt_ids_received_with_those_registered_before"} from Use…
- `setup.md` 41 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Niso.041`; diagram note: `setup.puml` step 41; summary: Niso receives boomerang_params_seed_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_0 from ST and forward…
- `setup.md` 42 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Boomlet.042`; diagram note: `setup.puml` step 42; summary: Boomlet receives boomerang_params_seed_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_0 from Niso. Booml…
- `setup.md` 43 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Niso.043`; diagram note: `setup.puml` step 43; summary: Niso receives boomerang_params_signed_by_boomlet_0 from Boomlet and proceeds to share it with other peers' Ni…
- `setup.md` 44 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Niso.044`; diagram note: `setup.puml` step 44; summary: Niso receives boomerang_params_signed_by_boomlet_i from peers, sending boomerang_params_signed_by_boomlet_0 a…
- `setup.md` 45 -> state(s): online identity and parameter states in `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `User(i)`; transition(s): `SETUP.Peer(i).Boomlet.045`; diagram note: `setup.puml` step 45; summary: Boomlet receives boomerang_params_signed_by_all_peers from Niso. It checks the content of each peer's boomera…
- `setup.md` 46 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.046`; diagram note: `setup.puml` step 46; summary: Niso receives {magic: "setup_boomerang_params_fixed"} from Boomlet and informs it to generate the mystery val…
- `setup.md` 47 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Boomlet.047`; diagram note: `setup.puml` step 47; summary: Boomlet receives {magic: "setup_boomerang_params_fixed"} from Niso. Boomlet then generates mystery as a rando…
- `setup.md` 48 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.048`; diagram note: `setup.puml` step 48; summary: Niso receives {sorted_all_peers_boomlet_identity_pubkeys_signed_by_boomlet_0, boomerang_params_fingerprint_si…
- `setup.md` 49 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.WT.049`; diagram note: `setup.puml` step 49; summary: WT receives {boomlet_i_identity_pubkey, sorted_all_peers_boomlet_identity_pubkeys_signed_by_boomlet_i, peer_i…
- `setup.md` 50 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.050`; diagram note: `setup.puml` step 50; summary: Niso receives wt_service_fee_payment_info from WT and outputs it to User.
- `setup.md` 51 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.User(i).051`; diagram note: `setup.puml` step 51; summary: User receives wts_service_fee_payment_info from Niso, verifies the details of it and pays the invoice generat…
- `setup.md` 52 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.052`; diagram note: `setup.puml` step 52; summary: Niso receives wt_service_fee_payment_receipt from User and forwards it to WT.
- `setup.md` 53 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.WT.053`; diagram note: `setup.puml` step 53; summary: WT receives wt_service_fee_payment_receipt from Niso and verifies the payment. It then adds the suffix "setup…
- `setup.md` 54 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.054`; diagram note: `setup.puml` step 54; summary: Niso receives boomerang_params_fingerprint_suffixed_by_wt_signed_by_wt from WT. Niso verifies wt_pubkey's sig…
- `setup.md` 55 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Boomlet.055`; diagram note: `setup.puml` step 55; summary: Boomlet receives boomerang_params_fingerprint_suffixed_by_wt_signed_by_wt from Niso. Boomlet verifies wt_pubk…
- `setup.md` 56 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.056`; diagram note: `setup.puml` step 56; summary: Niso receives shared_state_active_wt_fingerprint_signed_by_boomlet_0 from Boomlet and proceeds to share it wi…
- `setup.md` 57 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.057`; diagram note: `setup.puml` step 57; summary: Niso receives shared_state_active_wt_fingerprint_signed_by_boomlet_i from peers, sending shared_state_active_…
- `setup.md` 58 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Boomlet.058`; diagram note: `setup.puml` step 58; summary: Boomlet receives shared_state_active_wt_fingerprint_signed_by_all_peers from Niso. It checks the content of e…
- `setup.md` 59 -> state(s): WT registration and WT-active sync states in `Boomlet(i)`, `Niso(i)`, and `WT`; transition(s): `SETUP.Peer(i).Niso.059`; diagram note: `setup.puml` step 59; summary: Niso receives {magic: "setup_wt_service_confirmed_by_peers"} from Boomlet and informs Boomlet to finalize SAR…
- `setup.md` 60 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Boomlet.060`; diagram note: `setup.puml` step 60; summary: Boomlet receives {magic: "setup_wt_service_confirmed_by_peers_sars_can_be_finalized"} from Niso. Boomlet then…
- `setup.md` 61 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Niso.061`; diagram note: `setup.puml` step 61; summary: Niso receives {sar_ids_collection_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, doxing_data_identifier_e…
- `setup.md` 62 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.WT.062`; diagram note: `setup.puml` step 62; summary: WT receives {sar_ids_collection_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, doxing_data_identifier_enc…
- `setup.md` 63 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.SAR.063`; diagram note: `setup.puml` step 63; summary: SAR receives {doxing_data_identifier_encrypted_by_boomlet_0_for_sar, boomlet_0_identity_pubkey} from WT. SAR …
- `setup.md` 64 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.WT.064`; diagram note: `setup.puml` step 64; summary: WT receives sar_setup_response_signed_by_sar_encrypted_by_sar_for_boomlet_0 from SAR. It then adds the suffix…
- `setup.md` 65 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Niso.065`; diagram note: `setup.puml` step 65; summary: Niso receives sar_setup_response_signed_by_sar_encrypted_by_sar_for_boomlet_0_suffixed_by_wt_signed_by_wt fro…
- `setup.md` 66 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Boomlet.066`; diagram note: `setup.puml` step 66; summary: Boomlet receives sar_setup_response_signed_by_sar_encrypted_by_sar_for_boomlet_0_suffixed_by_wt_signed_by_wt …
- `setup.md` 67 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Niso.067`; diagram note: `setup.puml` step 67; summary: Niso receives shared_state_active_sar_fingerprint_signed_by_boomlet_0 from Boomlet and proceeds to share it w…
- `setup.md` 68 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Niso.068`; diagram note: `setup.puml` step 68; summary: Niso receives shared_state_active_sar_fingerprint_signed_by_boomlet_i from peers, sending shared_state_active…
- `setup.md` 69 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Boomlet.069`; diagram note: `setup.puml` step 69; summary: Boomlet receives shared_state_active_sar_fingerprint_signed_by_all_peers from Niso. It checks the content of …
- `setup.md` 70 -> state(s): SAR activation states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `SETUP.Peer(i).Niso.070`; diagram note: `setup.puml` step 70; summary: Niso receives {magic: "setup_sar_acknowledgement_of_finalization_received"} from Boomlet and informs User to …
- `setup.md` 71 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.User(i).071`; diagram note: `setup.puml` step 71; summary: User receives {magic: "setup_sar_finalization_confirmed"} from Niso and proceeds to connect the hardware for …
- `setup.md` 72 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.072`; diagram note: `setup.puml` step 72; summary: Iso is turned on in backup mode indicated by {magic: "setup_user_is_informed_that_sar_is_set_and_can_install_…
- `setup.md` 73 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Boomletwo.073`; diagram note: `setup.puml` step 73; summary: Boomletwo gets installed indicated by {magic: "setup_backup_started"} from Iso. It generates boomletwo_Identi…
- `setup.md` 74 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.074`; diagram note: `setup.puml` step 74; summary: Iso receives boomletwo_Identity_pubkey from Boomletwo and proceeds to inform User to connect Boomlet.
- `setup.md` 75 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.User(i).075`; diagram note: `setup.puml` step 75; summary: User receives {magic: "setup_boomletwo_identity_pubkey_received_connect_boomlet_to_iso"} from Iso and proceed…
- `setup.md` 76 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.076`; diagram note: `setup.puml` step 76; summary: Iso receives {milestone_block_collection, network, mnemonic, passphrase, static_doxing_data, doxing_password}…
- `setup.md` 77 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Boomlet.077`; diagram note: `setup.puml` step 77; summary: Boomlet receives backup_request_signed_by_normal_0 from Iso, checks normal_pubkey_0's signature, checks backu…
- `setup.md` 78 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.078`; diagram note: `setup.puml` step 78; summary: Iso receives {boomlet_0_identity_pubkey, boomlet_0_backup_encrypted_by_boomlet_0_for_boomletwo, boomerang_par…
- `setup.md` 79 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.User(i).079`; diagram note: `setup.puml` step 79; summary: User receives {magic: "setup_boomlet_backup_data_received_connect_boomletwo_to_iso"} from Iso. User then proc…
- `setup.md` 80 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.080`; diagram note: `setup.puml` step 80; summary: Iso receives {magic: "setup_user_is_asked_to_connect_boomletwo_to_iso_boomletwo_connected_to_iso"} from User …
- `setup.md` 81 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Boomletwo.081`; diagram note: `setup.puml` step 81; summary: Boomletwo receives {boomlet_0_identity_pubkey, boomlet_0_backup_encrypted_by_boomlet_0_for_boomletwo} from Is…
- `setup.md` 82 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.082`; diagram note: `setup.puml` step 82; summary: Iso receives {backup_done_signed_by_boomletwo} from Boomletwo. Iso proceeds to inform User to connect Boomlet.
- `setup.md` 83 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.User(i).083`; diagram note: `setup.puml` step 83; summary: User receives {magic: "setup_boomlet_backup_done_connect_boomlet_to_iso"} from Iso and connects Boomlet to Is…
- `setup.md` 84 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.084`; diagram note: `setup.puml` step 84; summary: Iso receives {magic: "setup_user_is_asked_to_connect_boomlet_to_iso_boomlet_connected_to_iso"} from User and …
- `setup.md` 85 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Boomlet.085`; diagram note: `setup.puml` step 85; summary: Boomlet receives {backup_done_signed_by_boomletwo} from Iso. It verifies boomletwo_identity_pubkey's signatur…
- `setup.md` 86 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.Peer(i).Iso.086`; diagram note: `setup.puml` step 86; summary: Iso receives {magic: "setup_boomlet_backup_done"} from Boomlet and proceeds to inform User that the backup pr…
- `setup.md` 87 -> state(s): backup states in `Iso(i)`, `Boomlet(i)`, and `Boomletwo(i)`; transition(s): `SETUP.User(i).087`; diagram note: `setup.puml` step 87; summary: User receives {magic: "setup_boomlet_backup_completed_boomlet_closed_ready_to_finish_setup"} from Iso. User p…
- `setup.md` 88 -> state(s): final setup synchronization states in `Niso(i)` and `Boomlet(i)`; transition(s): `SETUP.Peer(i).Niso.088`; diagram note: `setup.puml` step 88; summary: Niso receives {magic: "setup_user_is_informed_that_boomlet_is_closed"} from User and proceeds to tell Boomlet…
- `setup.md` 89 -> state(s): final setup synchronization states in `Niso(i)` and `Boomlet(i)`; transition(s): `SETUP.Peer(i).Boomlet.089`; diagram note: `setup.puml` step 89; summary: Boomlet receives {magic: "setup_boomlet_closed_finish_setup"} from Niso and proceeds to generate and hash sha…
- `setup.md` 90 -> state(s): final setup synchronization states in `Niso(i)` and `Boomlet(i)`; transition(s): `SETUP.Peer(i).Niso.090`; diagram note: `setup.puml` step 90; summary: Niso receives shared_state_active_backup_fingerprint_signed_by_boomlet_0 from Boomlet and proceeds to share i…
- `setup.md` 91 -> state(s): final setup synchronization states in `Niso(i)` and `Boomlet(i)`; transition(s): `SETUP.Peer(i).Niso.091`; diagram note: `setup.puml` step 91; summary: Niso receives shared_state_active_backup_fingerprint_signed_by_boomlet_i from peers, sending shared_state_act…
- `setup.md` 92 -> state(s): final setup synchronization states in `Niso(i)` and `Boomlet(i)`; transition(s): `SETUP.Peer(i).Boomlet.092`; diagram note: `setup.puml` step 92; summary: Boomlet receives shared_state_active_backup_fingerprint_signed_by_all_peers from Niso. It checks the content …
- `setup.md` 93 -> state(s): final setup synchronization states in `Niso(i)` and `Boomlet(i)`; transition(s): `SETUP.Peer(i).Niso.093`; diagram note: `setup.puml` step 93; summary: Niso receives {magic: "setup_done"} from Boomlet and proceeds to inform User that setup is finished.
- `setup.md` 94 -> state(s): final setup synchronization states in `Niso(i)` and `Boomlet(i)`; transition(s): `SETUP.User(i).094`; diagram note: `setup.puml` step 94; summary: User receives {magic: "setup_done"} from Niso.

### 17.2 `withdrawal.md` numbered-step coverage

- `withdrawal.md` 1 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).Niso.001`; diagram note: `initiator_withdrawal.puml` step 1; summary: Niso receives psbt from User. Niso checks that most_work_bitcoin_block_height has passed milestone_block_0 fr…
- `withdrawal.md` 2 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).Boomlet.002`; diagram note: `initiator_withdrawal.puml` step 2; summary: Boomlet receives {psbt, niso_0_event_block_height} from Niso and checks to see if the niso_0_event_block_heig…
- `withdrawal.md` 3 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).Niso.003`; diagram note: `initiator_withdrawal.puml` step 3; summary: Niso receives tx_id_with_nonce_encrypted_by_boomlet_0_for_st from Boomlet and forwards it to ST.
- `withdrawal.md` 4 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).ST.004`; diagram note: `initiator_withdrawal.puml` step 4; summary: ST receives tx_id_with_nonce_encrypted_by_boomlet_0_for_st from Niso, decrypts it, separates the nonce and se…
- `withdrawal.md` 5 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.User(i).005`; diagram note: `initiator_withdrawal.puml` step 5; summary: User receives tx_id from ST and checks to see if it matches that of the psbt he generated. User then informs …
- `withdrawal.md` 6 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).ST.006`; diagram note: `initiator_withdrawal.puml` step 6; summary: ST receives {magic: "withdrawal_initiator_peer_approved_that_txid_received_is_the_same_as_the_one_derived_fro…
- `withdrawal.md` 7 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).Niso.007`; diagram note: `initiator_withdrawal.puml` step 7; summary: Niso receives tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_0 from ST and forwards it to Boomlet.
- `withdrawal.md` 8 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).Boomlet.008`; diagram note: `initiator_withdrawal.puml` step 8; summary: Boomlet receives tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_0 from Niso, decrypts it, verifies…
- `withdrawal.md` 9 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.Peer(i).Niso.009`; diagram note: `initiator_withdrawal.puml` step 9; summary: Niso receives {peer_0_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, psbt_encrypted_collectio…
- `withdrawal.md` 10 -> state(s): initiator start/approval states in `User(initiator)`, `Niso(initiator)`, `Boomlet(initiator)`, `ST(initiator)`, and `WT`; transition(s): `WD.WT.010`; diagram note: `initiator_withdrawal.puml` step 10; summary: WT receives {peer_0_tx_approval_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt, psbt_encrypted_collection:…
- `withdrawal.md` 11 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.011`; diagram note: `non_initiator_withdrawal.puml` step 11; summary: Non-initiator Niso receives {wt_tx_approval_signed_by_wt, peer_0_tx_approval_signed_by_boomlet_0, psbt_encryp…
- `withdrawal.md` 12 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Boomlet.012`; diagram note: `non_initiator_withdrawal.puml` step 12; summary: Non-initiator Boomlet receives {wt_tx_approval_signed_by_wt, peer_0_tx_approval_signed_by_boomlet_0, psbt_enc…
- `withdrawal.md` 13 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.013`; diagram note: `non_initiator_withdrawal.puml` step 13; summary: Non-initiator Niso receives psbt from Non-initiator non-initiator Boomlet. Non-initiator Niso checks that psb…
- `withdrawal.md` 14 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.User(i)(i).014`; diagram note: `non_initiator_withdrawal.puml` step 14; summary: Non-initiator User receives {psbt, initiator_peer_id} from non-initiator Niso. Non-initiator User then inform…
- `withdrawal.md` 15 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.015`; diagram note: `non_initiator_withdrawal.puml` step 15; summary: Non-initiator Niso receives {magic: "withdrawal_non_initiator_peer_approved_the_withdrawal_psbt"} from non-in…
- `withdrawal.md` 16 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Boomlet.016`; diagram note: `non_initiator_withdrawal.puml` step 16; summary: Non-initiator Boomlet receives {magic: "withdrawal_peer_agreement_with_psbt_received"} from non-initiator Nis…
- `withdrawal.md` 17 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.017`; diagram note: `non_initiator_withdrawal.puml` step 17; summary: Non-initiator Niso receives tx_id_with_nonce_encrypted_by_boomlet_1_for_st from non-initiator Boomlet and for…
- `withdrawal.md` 18 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).ST.018`; diagram note: `non_initiator_withdrawal.puml` step 18; summary: Non-initiator ST receives tx_id_with_nonce_encrypted_by_boomlet_1_for_st from non-initiator Niso. Non-initiat…
- `withdrawal.md` 19 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.User(i)(i).019`; diagram note: `non_initiator_withdrawal.puml` step 19; summary: Non-initiator User receives tx_id from non-initiator ST. Non-initiator User checks to see tx_id matches the o…
- `withdrawal.md` 20 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).ST.020`; diagram note: `non_initiator_withdrawal.puml` step 20; summary: Non-initiator ST receives {magic: "withdrawal_non_initiator_peer_approved_that_txid_received_is_the_same_as_t…
- `withdrawal.md` 21 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.021`; diagram note: `non_initiator_withdrawal.puml` step 21; summary: Non-initiator Niso receives tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_1 from non-initiator ST…
- `withdrawal.md` 22 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Boomlet.022`; diagram note: `non_initiator_withdrawal.puml` step 22; summary: Non-initiator Boomlet receives {tx_id_with_nonce_signed_by_st_encrypted_by_st_for_boomlet_1, niso_1_event_blo…
- `withdrawal.md` 23 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.023`; diagram note: `non_initiator_withdrawal.puml` step 23; summary: Non-initiator Niso receives peer_1_tx_approval_signed_by_boomlet_1_encrypted_by_boomlet_1_for_wt from non-ini…
- `withdrawal.md` 24 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.WT.024`; diagram note: `non_initiator_withdrawal.puml` step 24; summary: WT receives peer_1_tx_approval_signed_by_boomlet_1_encrypted_by_boomlet_1_for_wt from non-initiator Niso, dec…
- `withdrawal.md` 25 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.025`; diagram note: `non_initiator_withdrawal.puml` step 25; summary: Niso receives {Collection<peer_i_tx_approval_signed_by_boomlet_i> [0 <= i <= 4], wt_tx_approval_signed_by_wt}…
- `withdrawal.md` 26 -> state(s): non-initiator approval states in `User(i)`, `Niso(i)`, `Boomlet(i)`, `ST(i)`, and `WT`; transition(s): `WD.Peer(i).Niso.026`; diagram note: `non_initiator_withdrawal.puml` step 26; summary: Non-initiator Niso receives {Collection<peer_i_tx_approval_signed_by_boomlet_i> [1 <= i <= 4]} from WT. Non-i…
- `withdrawal.md` 27 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Boomlet.027`; diagram note: `non_initiator_withdrawal.puml` step 27; summary: Boomlet receives {Collection<peer_i_tx_approval_signed_by_boomlet_i> [1 <= i <= 4], wt_tx_approval_signed_by_…
- `withdrawal.md` 27n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Boomlet.027N`; diagram note: `non_initiator_withdrawal.puml` step 27n; summary: Non-initiator Boomlet receives {Collection<peer_i_tx_approval_signed_by_boomlet_i> [1 <= i <= 4], niso_1_even…
- `withdrawal.md` 28 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.028`; diagram note: `non_initiator_withdrawal.puml` step 28; summary: Niso receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Boomlet and forwards it to ST.
- `withdrawal.md` 28n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.028N`; diagram note: `non_initiator_withdrawal.puml` step 28n; summary: Non-initiator Niso receives duress_check_space_with_nonce_encrypted_by_boomlet_1_for_st from non-initiator Bo…
- `withdrawal.md` 29 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).ST.029`; diagram note: `non_initiator_withdrawal.puml` step 29; summary: ST receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Niso, decrypts it to get duress_…
- `withdrawal.md` 29n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).ST.029N`; diagram note: `non_initiator_withdrawal.puml` step 29n; summary: Non-initiator ST receives duress_check_space_with_nonce_encrypted_by_boomlet_1_for_st from non-initiator Niso…
- `withdrawal.md` 30 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.User(i).030`; diagram note: `non_initiator_withdrawal.puml` step 30; summary: User receives duress_check_space from ST. If he is not being coerced he will select 1 country in each column …
- `withdrawal.md` 30n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.User(i)(i).030N`; diagram note: `non_initiator_withdrawal.puml` step 30n; summary: Non-initiator User receives duress_check_space from non-initiator ST. If he is not being coerced he will sele…
- `withdrawal.md` 31 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).ST.031`; diagram note: `non_initiator_withdrawal.puml` step 31; summary: ST receives duress_signal_index from User. ST then creates duress_signal_index_with_nonce using the nonce fro…
- `withdrawal.md` 31n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).ST.031N`; diagram note: `non_initiator_withdrawal.puml` step 31n; summary: Non-initiator ST receives duress_signal_index from non-initiator User. Non-initiator ST then creates duress_s…
- `withdrawal.md` 32 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.032`; diagram note: `non_initiator_withdrawal.puml` step 32; summary: Niso receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from ST and forwards it to Boomlet.
- `withdrawal.md` 32n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.032N`; diagram note: `non_initiator_withdrawal.puml` step 32n; summary: Non-initiator Niso receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_1 from non-initiator S…
- `withdrawal.md` 33 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.SAR.033`; diagram note: `non_initiator_withdrawal.puml` step 33; summary: Boomlet receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from Niso. Boomlet will search …
- `withdrawal.md` 33n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.SAR.033N`; diagram note: `non_initiator_withdrawal.puml` step 33n; summary: Non-initiator Boomlet receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_1 from non-initiato…
- `withdrawal.md` 34 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.034`; diagram note: `non_initiator_withdrawal.puml` step 34; summary: Niso receives peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt f…
- `withdrawal.md` 34n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.034N`; diagram note: `non_initiator_withdrawal.puml` step 34n; summary: Non-initiator Niso receives approvals_signed_by_boomlet_1 from non-initiator Boomlet and forwards it to WT.
- `withdrawal.md` 35 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.035`; diagram note: `non_initiator_withdrawal.puml` step 35; summary: WT receives peer_0_tx_commit_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt fro…
- `withdrawal.md` 35n -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.035N`; diagram note: `non_initiator_withdrawal.puml` step 35n; summary: WT receives approvals_signed_by_boomlet_1 from non-initiator Niso. WT verifies boomlet_1_identity_pubkey's si…
- `withdrawal.md` 36 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.SAR.036`; diagram note: `non_initiator_withdrawal.puml` step 36; summary: SAR receives {duress_placeholder, boomlet_0_identity_pubkey} from WT. It decrypts duress_placeholder using bo…
- `withdrawal.md` 37 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.037`; diagram note: `non_initiator_withdrawal.puml` step 37; summary: WT receives duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet_0 from SAR and continues processing…
- `withdrawal.md` 38 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.038`; diagram note: `non_initiator_withdrawal.puml` step 38; summary: Non-initiator Niso receives peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt from WT. Non-initiator Niso upd…
- `withdrawal.md` 39 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Boomlet.039`; diagram note: `non_initiator_withdrawal.puml` step 39; summary: Non-initiator Boomlet receives {peer_0_tx_commit_signed_by_boomlet_0_signed_by_wt, niso_1_event_block_height}…
- `withdrawal.md` 40 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.040`; diagram note: `non_initiator_withdrawal.puml` step 40; summary: Non-initiator Niso receives peer_1_tx_commit_signed_by_boomlet_1_padded_signed_by_boomlet_1_encrypted_by_boom…
- `withdrawal.md` 41 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.041`; diagram note: `non_initiator_withdrawal.puml` step 41; summary: WT receives peer_1_tx_commit_signed_by_boomlet_1_padded_signed_by_boomlet_1_encrypted_by_boomlet_1_for_wt fro…
- `withdrawal.md` 42 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.SAR.042`; diagram note: `non_initiator_withdrawal.puml` step 42; summary: SAR receives {duress_placeholder, boomlet_1_identity_pubkey} from WT. It decrypts duress_placeholder using bo…
- `withdrawal.md` 43 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.043`; diagram note: `non_initiator_withdrawal.puml` step 43; summary: WT receives duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet_1 from SAR and continues processing…
- `withdrawal.md` 44 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.044`; diagram note: `non_initiator_withdrawal.puml` step 44; summary: Niso receives {Collection<peer_i_tx_commit_signed_by_boomlet_i_signed_by_wt> [0 <= i <= 4], duress_placeholde…
- `withdrawal.md` 45 -> state(s): commitment states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Boomlet.045`; diagram note: `initiator_withdrawal.puml` step 45; summary: Boomlet receives {Collection<peer_i_tx_commit_signed_by_boomlet_i_signed_by_wt> [0 <= i <= 4], niso_0_event_b…
- `withdrawal.md` 46 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.046`; diagram note: `initiator_withdrawal.puml` step 46; summary: Niso receives peer_0_ping_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt from B…
- `withdrawal.md` 47 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.047`; diagram note: `initiator_withdrawal.puml` step 47; summary: WT receives peer_0_ping_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt from Nis…
- `withdrawal.md` 48 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.SAR.048`; diagram note: `initiator_withdrawal.puml` step 48; summary: SAR receives {duress_placeholder, boomlet_0_identity_pubkey} from WT. It decrypts duress_placeholder using bo…
- `withdrawal.md` 49 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.049`; diagram note: `initiator_withdrawal.puml` step 49; summary: WT receives duress_placeholder_signed_by_sar_encrypted_by_sar_for_boomlet_0 from SAR and continues processing…
- `withdrawal.md` 50 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.050`; diagram note: `initiator_withdrawal.puml` step 50; summary: Niso receives {pong_0_signed_by_wt_encrypted_by_wt_for_boomlet_0, duress_placeholder_signed_by_sar_encrypted_…
- `withdrawal.md` 51 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Boomlet.051`; diagram note: `initiator_withdrawal.puml` step 51; summary: Boomlet receives {pong_0_signed_by_wt_encrypted_by_wt_for_boomlet_0, niso_0_event_block_height, duress_placeh…
- `withdrawal.md` 52 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.052`; diagram note: `initiator_withdrawal.puml` step 52; summary: Niso receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Boomlet and forwards it to ST.
- `withdrawal.md` 53 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).ST.053`; diagram note: `initiator_withdrawal.puml` step 53; summary: ST receives duress_check_space_with_nonce_encrypted_by_boomlet_0_for_st from Niso, decrypts it to get duress_…
- `withdrawal.md` 54 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.User(i).054`; diagram note: `initiator_withdrawal.puml` step 54; summary: User receives duress_check_space from ST. If he is not being coerced he will select 1 country in each column …
- `withdrawal.md` 55 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).ST.055`; diagram note: `initiator_withdrawal.puml` step 55; summary: ST receives duress_signal_index from User. ST then creates duress_signal_index_with_nonce using the nonce fro…
- `withdrawal.md` 56 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.056`; diagram note: `initiator_withdrawal.puml` step 56; summary: Niso receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from ST and forwards it to Boomlet.
- `withdrawal.md` 57 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Boomlet.057`; diagram note: `initiator_withdrawal.puml` step 57; summary: Boomlet receives duress_signal_index_with_nonce_encrypted_by_st_for_boomlet_0 from Niso. Boomlet will search …
- `withdrawal.md` 58 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.058`; diagram note: `initiator_withdrawal.puml` step 58; summary: Niso receives peer_0_ping_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt from B…
- `withdrawal.md` 59 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.WT.059`; diagram note: `initiator_withdrawal.puml` step 59; summary: WT receives peer_0_ping_signed_by_boomlet_0_padded_signed_by_boomlet_0_encrypted_by_boomlet_0_for_wt from Nis…
- `withdrawal.md` 60 -> state(s): digging-game states in `Boomlet(i)`, `Niso(i)`, `WT`, and `SAR`; transition(s): `WD.Peer(i).Niso.060`; diagram note: `initiator_withdrawal.puml` step 60; summary: Niso receives reached_pings_collection from WT. Niso verifies each peer's peer_i_reached_ping_signed_by_booml…
- `withdrawal.md` 61 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Boomlet.061`; diagram note: `initiator_withdrawal.puml` step 61; summary: Boomlet receives {reached_pings_collection, hydrated_psbt} from Niso. Boomlet first checks the validity of ea…
- `withdrawal.md` 62 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Niso.062`; diagram note: `initiator_withdrawal.puml` step 62; summary: Niso receives {magic: "withdrawal_ready_to_sign"} from Boomlet and proceeds to inform User to connect Boomlet…
- `withdrawal.md` 63 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.User(i).063`; diagram note: `initiator_withdrawal.puml` step 63; summary: User receives {magic: "withdrawal_ready_to_sign_received_connect_boomlet_to_iso"} from Niso and proceeds to c…
- `withdrawal.md` 64 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Iso.064`; diagram note: `initiator_withdrawal.puml` step 64; summary: Iso receives {network, mnemonic, passphrase} from User and proceeds to inform Boomlet that they can start col…
- `withdrawal.md` 65 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Boomlet.065`; diagram note: `initiator_withdrawal.puml` step 65; summary: Boomlet receives {magic: "withdrawal_initialized_start_signing"} from Iso and proceeds to share with it the i…
- `withdrawal.md` 66 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Iso.066`; diagram note: `initiator_withdrawal.puml` step 66; summary: Iso receives {psbt, boomerang_descriptor, boomlet_0_boom_musig2_pubkey_share, pubnonce_boom} from Boomlet. Is…
- `withdrawal.md` 67 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Boomlet.067`; diagram note: `initiator_withdrawal.puml` step 67; summary: Boomlet receives {pubnonce_normal, partialsig_normal} from Iso, proceeds to produce its own partial signature…
- `withdrawal.md` 68 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Iso.068`; diagram note: `initiator_withdrawal.puml` step 68; summary: Iso receives partialsig_boom from Boomlet. Iso also keeps signed psbt but informs User that he can connect Bo…
- `withdrawal.md` 69 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.User(i).069`; diagram note: `initiator_withdrawal.puml` step 69; summary: User receives {magic: "withdrawal_psbt_signature_created_connect_boomlet_to_niso"} from Iso and proceeds to c…
- `withdrawal.md` 70 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Niso.070`; diagram note: `initiator_withdrawal.puml` step 70; summary: Niso receives {magic: "withdrawal_peer_is_informed_that_boomlet_should_be_connected_to_niso"} from User and p…
- `withdrawal.md` 71 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Boomlet.071`; diagram note: `initiator_withdrawal.puml` step 71; summary: Boomlet receives {magic: "withdrawal_signing_finished_export_signed_psbt"} from Niso and proceeds to respond …
- `withdrawal.md` 72 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.Peer(i).Niso.072`; diagram note: `initiator_withdrawal.puml` step 72; summary: Niso receives psbt_signed_0 from Boomlet and forwards it to WT.
- `withdrawal.md` 73 -> state(s): ready-to-sign, signing, export, and broadcast states; transition(s): `WD.WT.073`; diagram note: `initiator_withdrawal.puml` step 73; summary: WT receives psbt_signed_0 from Niso and psbt_signed_i [1 <= i <= 4] from Peers. WT aggregates the `signed_psb…

### 17.3 `duress.md` load-bearing rule coverage

- `duress.md` “duress mechanism does not cover setup stage” -> state(s): global phase boundary between `Global.Setup.*` and `Global.Withdrawal.*`; invariant(s): setup never emits operational duress placeholders; assumption(s): setup may still configure `duress_consent_set_i` but is not itself coercion-protected.
- `duress.md` doxing-data definitions -> variable(s): `doxing_key_i`, `doxing_data_identifier_i`, `sar_registry`, dynamic/static encrypted doxing records; actor machine(s): `Phone(i)` and `SAR`.
- `duress.md` core five-country consent-set rule -> variable(s): `duress_consent_set_i`; state(s): `Boomlet(i).Setup.AwaitingInitialConsentResponse`, `Boomlet(i).Setup.AwaitingConsentConfirmationResponse`, `Boomlet(i).Withdrawal.AwaitingInitialDuressResponse`, `Boomlet(i).Withdrawal.DiggingGame`; invariant(s): exact-set comparison rather than ordered comparison.
- `duress.md` “user can signal duress and non-duress in any duress-check instance” -> transition(s): `WD.Peer(i).Boomlet.033`, `WD.Peer(i).Boomlet.033N`, `WD.Peer(i).Boomlet.051`; loop spec(s): Sections 12.2 and 12.3.
- `duress.md` replay resistance requirement -> guard(s): nonce equality for ST-mediated checks; SAR replay suppression using `(boomlet_identity_pubkey, iv)` tracking.
- `duress.md` no observable-flow divergence on duress -> invariant(s): Section 13 item 13; actor behavior(s): commit and digging-game transitions do not branch visibly on positive versus negative duress except for placeholder plaintext.
- `duress.md` positive signal consequences -> variable(s): `duress_placeholder_plaintext_i`, `duress_latched_i`; actor machine(s): `Boomlet(i)`, `WT`, `SAR`; transition(s): commitment and repeated-check transitions.
- `duress.md` repeated random duress checks chosen by Boomlet PRNG -> loop(s): Section 12.3; transition(s): `WD.Peer(i).Boomlet.051`.
- `duress.md` attacker assumptions -> assumption(s): Section 5 and Section 15; not translated into protocol transitions except where they justify trust boundaries.
- `duress.md` ST secrecy assumptions -> assumption(s): Section 5; actor-local machine `ST(i)`; ambiguity note(s): Section 16 ACR-14.

### 17.4 `DEEPDIVE.md` load-bearing architectural and failure-mode statement coverage

- Two-regime descriptor structure -> Sections 1, 4, 5, 6, and 13; variable(s): `boomerang_descriptor`, `boomerang_params`.
- Boomerang regime as 5-of-5 using boom keys before deterministic scripts -> Sections 1, 6, 8, and 13.
- Setup establishes state inherited by withdrawal -> Sections 1, 3, 8, 9, 13.
- WT as coordinator/liveness anchor and block-height root of trust -> Sections 1, 4, 5, 8, 10.8, 14, and 15.
- SAR as duress recipient/rescue trigger -> Sections 1, 4, 5, 7, 10.9, 13, and 15.
- Mirrored validations in Niso and Boomlet -> Sections 3, 7, 10.5, 10.7, and 13.
- Backup path with Boomletwo and exclusion of current mystery -> Sections 1, 6, 7, 10.5, 10.6, and 13.
- Deterministic fallback as present but not operationalized -> Sections 1, 5, 8, 13, 15, and 16.
- Forced-determinism threat -> Sections 1, 14, 15, and 16 ACR-13.
- Ancillary procedures explicitly recognized but out of scope -> Sections 5 and 16.
- Human-coercion design goal and observational consistency -> Sections 1, 5, 7, 12, and 13.
- Concern about phone compromise or dynamic doxing-feed loss -> Sections 4, 5, 6, and 15.
- Concern about hardware loss and one-active-backup discipline -> Sections 4, 5, 6, 15, and 16 ACR-11.
- Concern about setup-instance uniqueness and replay hardening -> Sections 3, 13, 15, and 16.
- Economic/deterrence intent -> Section 1 and liveness assumptions only; not translated into operative transitions.

18. TLA+-readiness summary

### 18.1 Minimal state-set summary

A first formal model does not need to encode every user-device interaction as a separate action if it keeps the following state sets explicit:

- Global phase: `PreSetup`, `Setup.SARSignup`, `Setup.DuressSetup`, `Setup.OnlineIdentityAndParams`, `Setup.WTRegistration`, `Setup.SARActivation`, `Setup.Backup`, `Setup.FinalSynchronization`, `ActiveReady`, `Withdrawal.Initiation`, `Withdrawal.Approval`, `Withdrawal.Commitment`, `Withdrawal.DiggingGame`, `Signing`, `Broadcast`, `PostWithdrawalReset`.
- Per-peer role state: initiator early-withdrawal states versus non-initiator early-withdrawal states, converging at commit-collection verification.
- Persistent setup state: `boomerang_params`, `duress_consent_set_i`, `doxing_key_i`, `doxing_data_identifier_i`, `sar_setup_response_i`, current `mystery_i`, and peer/WT/SAR activation flags.
- Withdrawal-local state: `tx_id`, local PSBT state, approval collection, commit collection, current placeholder state, `counter_i`, `ping_seq_num_i`, `reached_mystery_flag_i`, `reached_boomlets_collection_i`, `last_seen_block_i`, WT `reached_pings_collection`, and signed-PSBT collection.
- Message frontier state: whether the currently relevant approval, commit, ping, pong, or finalization message has been sent, received, and validated by the intended receiver.

That state set is already sufficient to express the key safety obligations: fixed `tx_id`, monotone reaching, no early signing, and observational equivalence of duress and non-duress flows.

### 18.2 Variables that matter most in TLA+

The variables that most strongly determine the later formal model are these:

1. `boomerang_params`
2. `boomerang_descriptor`
3. `milestone_block_collection`
4. `duress_consent_set_i`
5. `mystery_i`
6. `tx_id`
7. `peer_tx_approval_collection`
8. `peer_tx_commit_collection`
9. `duress_placeholder_plaintext_i`
10. `duress_latched_i` `[DERIVED]`
11. `counter_i`
12. `ping_seq_num_i`
13. `reached_mystery_flag_i`
14. `reached_boomlets_collection_i`
15. `last_seen_block_i`
16. WT `reached_pings_collection`
17. `niso_i_event_block_height` and WT `most_work_bitcoin_block_height`
18. `psbt_i`, `hydrated_psbt_i`, and `signed_psbt_i`

If a first TLA+ model abstracts away real cryptography, these variables still have to remain because they carry the machine’s protocol meaning. In contrast, low-level signature bytes, exact ciphertext bytes, or exact QR encodings can be abstracted into symbolic values and guards without losing the core control logic.

### 18.3 Top 10 unresolved issues most likely to change the formal model

1. Whether setup duress uses a five-element challenge or a full permutation of 1..195.
2. The exact retry/restart policy for failed setup confirmation.
3. The exact set of message families that always carry a duress-bearing placeholder.
4. Whether positive duress is explicitly modeled as a permanent per-ceremony latch variable.
5. The exact placeholder plaintext used in non-duress cases: all-zero fixed-size block versus some other empty-padding representation.
6. The exact serialized field names and schemas for WT approval, commit, ping, and pong messages.
7. The definitive numeric values of all freshness and distance constants.
8. Whether `counter_i` persists across aborted withdrawals or is purely ceremony-local.
9. How malformed SAR messages and missing SAR responses are meant to affect progress in the authoritative withdrawal flow.
10. How forced determinism is supposed to appear in the state machine, if at all, before a later deterministic-regime or ancillary-recovery model is introduced.

### 18.4 Recommended first TLA+ slice

The first TLA+ slice should start **after setup**, from a state in which:
- `boomerang_params` are already fixed,
- each peer has `duress_consent_set_i`, `doxing_key_i`, and `mystery_i`,
- `milestone_block_0` has already been reached,
- the initiator is about to submit a PSBT.

That first slice should model:
1. local `tx_id` fixation,
2. all-approval collection,
3. initial duress check,
4. initiator/non-initiator commitment asymmetry,
5. the digging-game variable updates,
6. the WT all-peers termination condition,
7. readiness to sign.

It should abstract cryptography to guards such as `ValidSig`, `DecryptsToExpected`, and symbolic placeholder values, and it should treat ST interactions as explicit environment choices constrained by the consent-set rule. That slice is the smallest one that still covers the design’s distinctive properties: fixed transaction identity, repeated duress opportunity, hidden positive signaling, unpredictable delay, and WT-coordinated all-peers termination.
