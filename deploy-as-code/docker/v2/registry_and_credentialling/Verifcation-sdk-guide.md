# Verifying Sunbird RC Credentials

How to verify a credential from its QR code using `@sunbird-rc/verification-sdk`.

repo: https://github.com/Sunbird-RC/verification-sdk

## How it works

The QR contains a ZIP holding one file, `certificate.json` — the signed W3C Verifiable Credential. To verify it:

1. **Scan** the QR.
2. **Unzip** it and read `certificate.json`.
3. **Resolve** the issuer's DID document.
4. **Verify** with the SDK.

## Install

```bash
npm install jszip @sunbird-rc/verification-sdk
```

## Complete example

```javascript
import JSZip from "jszip";
import { downloadRevocationList, verifyCredential } from "@sunbird-rc/verification-sdk";

async function verifyFromQr(scanned) {
  // 1. Unzip the QR payload. The scan result is a binary string — read it as
  //    raw bytes (do NOT UTF-8 decode), or the unzip will fail.
  const bytes = Uint8Array.from(scanned, (c) => c.charCodeAt(0) & 0xff);
  const zip = await JSZip.loadAsync(bytes);
  const credential = JSON.parse(await zip.file("certificate.json").async("string"));

  // 2. Resolve the issuer's DID document.
  const issuerDid =
    typeof credential.issuer === "string" ? credential.issuer : credential.issuer.id;
  const issuerDidDoc = await (
    await fetch(`https://<identity-service>/did/resolve/${issuerDid}`)
  ).json();

  // 3. Download the revocation list (optional — skip it and nothing is checked).
  const revocationList = await downloadRevocationList(
    "https://<credential-service>/credentials/revocation-list",
    issuerDid
  );

  // 4. Verify.
  return await verifyCredential(issuerDidDoc, credential, revocationList);
}
```

`verifyCredential` returns an object, not a boolean:

```javascript
// { status: "OK" | "NOK", checks: [{ active, revoked, expired, proof }] }
const result = await verifyFromQr(scanned);
if (result.status === "OK") { /* valid */ }
```

`status` is `OK` only when `proof`, `revoked`, and `expired` all pass.

## Resolving the issuer DID

The SDK verifies the signature against the issuer's public key, which lives in the issuer's **DID document**. The SDK does not fetch this for you — you pass it in as `issuerDidDoc`.

- **Where the DID comes from:** `credential.issuer` (a string, or an object with `.id`).
- **How to resolve it:** `GET {identity-service}/did/resolve/{issuerDid}`. This is a public GET (no auth) and returns the DID document directly — no wrapper.
- **What you get back:** a document like `{ "@context": [...], "id": "<issuerDid>", "verificationMethod": [ ... ], "assertionMethod": [...] }`. Pass this whole object to `verifyCredential`.
- The SDK uses `verificationMethod[0]` as the signing key, which is the single key Sunbird puts in the issuer DID document — so no key selection is needed on your side.
- The endpoint tolerates a `#key` fragment (it strips anything after `#`), so passing the full `proof.verificationMethod` also resolves; using `credential.issuer` is the clean path.

```javascript
const issuerDid =
  typeof credential.issuer === "string" ? credential.issuer : credential.issuer.id;
const issuerDidDoc = await (
  await fetch(`https://<identity-service>/did/resolve/${issuerDid}`)
).json();
```

## The revocation list

Revocation tells you whether the issuer has invalidated a credential after issuing it. It is a separate, optional fetch — if you omit it, the SDK treats every credential as not-revoked.

- **Endpoint:** `GET {credential-service}/credentials/revocation-list?issuerId={issuerDid}`.
- **How `downloadRevocationList` calls it:** it appends `?issuerId=` for you. It does **not** paginate — one request returns page 1, which the server caps at 1000 entries by default.
- **Large issuers:** if an issuer could have more than 1000 revoked credentials, fetch further pages yourself (`...&page=2&limit=1000`) and concatenate the arrays before passing them in.
- **How the match works:** `verifyCredential` flags the credential as revoked if any list entry's `id` equals `credential.id`. Pass the array straight through as the third argument.

```javascript
import { downloadRevocationList } from "@sunbird-rc/verification-sdk";

const revocationList = await downloadRevocationList(
  "https://<credential-service>/credentials/revocation-list",
  issuerDid
);
// then: verifyCredential(issuerDidDoc, credential, revocationList)
```

## Things to know

- **Read the scan as raw bytes**, not UTF-8 text — this is the most common cause of unzip failures.
- **You must resolve the issuer DID yourself**; the SDK takes the resolved DID document as input and won't fetch it.
- **Revocation is opt-in.** If you don't pass a `revocationList`, every credential is treated as not-revoked.
- **`active` is always `null`** (not computed), and `expired` passes for credentials with no `expirationDate`.
- **Signing suite:** Your credentials use `Ed25519Signature2020`, which the SDK supports — so verification works as-is. The SDK also supports `Ed25519Signature2018` and `RsaSignature2018`. It does **not** support `DataIntegrityProof` (e.g. `eddsa-rdfc-2022`); if issuance ever moves to that model, verification will fail with *"Suite for signature type not found"* and you'll need an SDK upgrade.
