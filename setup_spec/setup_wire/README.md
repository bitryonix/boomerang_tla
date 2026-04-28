# `BoomerangSetupWire.tla` Guide

## Table of Contents

- [Purpose](#purpose)
- [Shape Of The Model](#shape-of-the-model)
- [Source Correspondence](#source-correspondence)
- [Precise Definition Points](#precise-definition-points)
- [Structural Checks](#structural-checks)
- [Definition Boundaries](#definition-boundaries)
- [Verification](#verification)


## Purpose

[Back to TOC](#table-of-contents)


`setup_spec/setup_wire/BoomerangSetupWire.tla` is a definition-oriented, wire-faithful setup model derived from `boomerang_design` repository.

It is not a curated TLC harness. Its job is to define the setup transcript precisely enough to compare against the design corpus, including the full 5-peer shape, ordered WT/SAR identity collections, and the full `1..195` duress-check vocabulary.

Source priority:

1. `setup/setup_diagram_without_states.puml`
2. `setup/README.md`
3. the external design corpus's `SPEC.md`, section 9, only when the setup sources need narrative context

## Shape Of The Model

[Back to TOC](#table-of-contents)


- one local peer's complete setup ceremony from the `peer_0` viewpoint
- fixed 5-peer profile
- exact PlantUML setup wrapper names as message `kind` values
- actor hops represented as a canonical sequence of `WireHop` records
- peer fan-out and peer fan-in exchanges expanded into explicit per-peer hops
- symbolic cryptographic wrappers that preserve signer, recipient, IV, payload, and content binding
- full duress setup structure with 5 columns and every column a permutation of `1..195`
- ordered WT candidate collection, with the first WT selected as the active WT
- ordered per-peer SAR collection, with each peer's first SAR selected as its primary setup/finalization SAR
- SAR setup finalization is primary-SAR-only; the transcript does not fan out finalization to secondary SAR ids

## Source Correspondence

[Back to TOC](#table-of-contents)


The module's `CanonicalWireMessageKinds` set mirrors the PlantUML setup message surface. The setup trace is assembled as:

- `SarSignupTrace`
- `DuressSetupTrace`
- `BoomerangParamsSetupTrace`
- `WatchtowerActivationTrace`
- `SarActivationTrace`
- `BackupActivationTrace`

Together these define `CanonicalSetupTranscript`, the exact happy-path setup transcript for `LOCAL_PEER`.

The bidirectional PlantUML peer exchanges are represented as concrete sends in both directions. For example, peer-address exchange, boomerang-params agreement, WT active-state sync, SAR active-state sync, and backup-state sync are expanded across the other four peers.

## Precise Definition Points

[Back to TOC](#table-of-contents)


WT and SAR identities:

- `WTIdsOrder` is the ordered collection of agreed WT candidates.
- `WTIdsCollection` preserves that order.
- `ActiveWTLabel == WTIdsOrder[1]`, matching the design note that the first WT is attempted first.
- `SARIdsOrder[p]` is the ordered collection of SAR identities privately selected by peer `p`.
- `SARIdsCollection(p)` preserves that order.
- `PrimarySARLabel(p) == SARIdsOrder[p][1]`.
- `SARActor(p)`, `SARPubkey(p)`, and `SARId(p)` refer to that primary SAR.
- WT forwards setup finalization for peer `p` only to `SARId(p)`, while the complete `SARIdsCollection(p)` remains part of the peer's registered setup inputs.

Purpose derivation:

- `BoomerangPurpose` records the design rule: first 2 bytes of `sha256("boomerang")`, value `cb86`, decimal `52102`, hardened.
- `PurposeRootXpriv0` records the corresponding paths `m/cb86'` and `m/52102h`.

WT active-state agreement:

- `SharedStateActiveWT` is `SharedStateBoomerangParams`.
- Its fingerprint commits to both `boomerang_params` and `magic: "setup_wt_service_initialized"`, matching the PlantUML and setup prose.

SAR finalization:

- SAR finalization is primary-SAR-only for each peer.
- SAR setup response binds `doxing_data_identifier`, the fingerprint of static doxing data encrypted by `doxing_key`, and the IV used for that static doxing encryption.
- WT suffixing uses `setup_sar_acknowledgement_of_finalization_received`.

Backup:

- `BoomletBackupPlaintext` explicitly carries `excluded_fields = {"mystery"}` and `mystery_exported = FALSE`.
- `BackupPlaintextExcludesMystery` checks that active Boomlet mystery is not exported into the backup payload.

## Structural Checks

[Back to TOC](#table-of-contents)


The module exposes predicates that describe internal consistency of the canonical transcript:

- `WireSurfaceOnlyCanonical`
- `TraceIsCanonicalPrefix`
- `PeerAddressesCollectionValid`
- `DuressEnrollmentConfirmed`
- `DescriptorUsesAgreedSetupInputs`
- `ActiveServiceSelectionsMatchCollections`
- `BoomerangParamsAgreementValid`
- `WTRegistrationSignaturesValid`
- `WTAcknowledgementBindsBoomerangParams`
- `SARFinalizationBindsRegisteredDoxingData`
- `BackupDoneValid`
- `SetupDoneAfterBackupConsensus`
- `SetupMathematicalConsistency`

These predicates are definitional checks for the transcript. They are intentionally not packaged as a tractable TLC regression harness.

## Definition Boundaries

[Back to TOC](#table-of-contents)


The module is precise about setup message shape, actor-to-actor hops, symbolic crypto layering, selected WT/SAR identities, and state fingerprints.

It intentionally remains symbolic about:

- byte-level serialization
- concrete Schnorr, MuSig2, AES, ECDH, SHA256, and Tor implementations
- payment-network mechanics
- hardware installation internals
- retry, timeout, and failure branches not present in the happy-path setup diagram

Those are not TLC abstractions in this file; they are the current design boundary of the setup definition.

## Verification

[Back to TOC](#table-of-contents)


Run SANY from the repository root:

```bash
java -cp tools/tla2tools.jar tla2sany.SANY setup_spec/setup_wire/BoomerangSetupWire.tla
```

Check the PlantUML message surface against `CanonicalWireMessageKinds`:

```bash
python3 - <<'PY'
import re, zipfile, pathlib

with zipfile.ZipFile("boomerang_design.zip") as z:
    puml = z.read("setup/setup_diagram_without_states.puml").decode()

tla = pathlib.Path("setup_spec/setup_wire/BoomerangSetupWire.tla").read_text()

puml_kinds = []
for line in puml.splitlines():
    if "<b>Setup" in line:
        match = re.search(r"<b>(Setup[A-Za-z0-9_]+)", line)
        if match:
            puml_kinds.append(match.group(1))

canonical_block = re.search(
    r"CanonicalWireMessageKinds ==\n\s*\{(.*?)\n\s*\}",
    tla,
    re.S,
).group(1)
canonical_kinds = re.findall(r'"(Setup[^"]+)"', canonical_block)

print("PlantUML unique message kinds:", len(set(puml_kinds)))
print("TLA canonical message kinds:", len(set(canonical_kinds)))
print("Missing in TLA:", sorted(set(puml_kinds) - set(canonical_kinds)))
print("Extra in TLA:", sorted(set(canonical_kinds) - set(puml_kinds)))
PY
```

Expected message-surface result:

```text
PlantUML unique message kinds: 94
TLA canonical message kinds: 94
Missing in TLA: []
Extra in TLA: []
```
