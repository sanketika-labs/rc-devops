# Bulk Employee Import — Setup Guide

Imports employees from a CSV file into the Sunbird RC registry and issues a W3C Verifiable Credential for each employee.

---

## Prerequisites

- Docker + Docker Compose installed
- `curl` and `jq` (`apt-get install jq`)
- CSV file with columns: `PersonalIdentification`, `TypeIdentification`, `Name`, `PositionName`, `Salary`, `DepartmentName`, `CompanyName`, `Status`, `AdmissionDate`, `ExitDate`

---

## Step 1 — Create admin user

Create an Employee record with `role: admin`. This user will own subsequent operations via the OAuth2 flow.

```sh
curl -s -X POST http://{{host}}/api/v1/Employee/invite \
  -H "Content-Type: application/json" \
  -d '{
    "Employee": {
      "fullName": "Administrador",
      "personalIdentification": "00100100100",
      "typeIdentification": "Cedula",
      "email": "<<EMAIL>>",
      "role": "admin",
      "positionName": "ADMINISTRADOR DEL SISTEMA",
      "departmentName": "DEPARTAMENTO DE TECNOLOGIA",
      "companyName": "Ministerio de Administracion Publica",
      "salary": "0",
      "admissionDate": "2024-01-01",
      "statusName": "Activo"
    }
  }'
```

Please update <<EMAIL>> with the admin email. The role field **must** be "admin". Replace `personalIdentification` with the admin’s real cédula—this is the identifier used for SSO login matching.

---

## Step 2 — Generate Issuer DID

Run once to create the issuer DID used to sign credentials.

```sh
curl --location 'http://{{host}}/did/generate' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "content": [
      {
        "alsoKnownAs": ["admin@example.org"],
        "services": [],
        "method": "web"
      }
    ]
  }'
```

The response contains a `did` field — copy it. This is your `ISSUER_DID`.

---

## Step 3 — Create credential schema

Run once to register the Employee credential schema. Replace `<ISSUER_DID>` with the value from Step 2.

```sh
curl -s -X POST http://{{host}}/credential-schema \
  -H "Content-Type: application/json" \
  -d '{
    "schema": {
      "type": "https://w3c-ccg.github.io/vc-json-schemas/",
      "version": "1.0.0",
      "name": "Employee",
      "author": "<ISSUER_DID>",
      "authored": "2024-01-01T00:00:00Z",
      "schema": {
        "$schema": "https://json-schema.org/draft/2019-09/schema",
        "description": "Employee Credential",
        "type": "object",
        "properties": {
          "name":                   { "type": "string" },
          "personalIdentification": { "type": "string" },
          "institution":            { "type": "string" },
          "position":               { "type": "string" },
          "department":             { "type": "string" },
          "status":                 { "type": "string" },
          "dateOfHire":             { "type": "string" }
        },
        "required": ["name", "personalIdentification"],
        "additionalProperties": false
      }
    },
    "tags": ["employee"],
    "status": "DRAFT"
  }'
```

The response contains `schema.id` — copy it. This is your `SCHEMA_ID`.

---

## Step 4 — Update .env

Open `.env` and set these three values:

```env
ISSUER_DID=<did-from-step-2>
SCHEMA_ID=<schema-id-from-step-3>
SCHEMA_VERSION=1.0.0
```

Example:
```env
ISSUER_DID=did:web:example.org:rc:a1b2c3d4-e5f6-7890-abcd-ef1234567890:b2c3d4e5-f6a7-8901-bcde-f12345678901
SCHEMA_ID=did:schema:c3d4e5f6-a7b8-9012-cdef-123456789012
SCHEMA_VERSION=1.0.0
```

---

## Step 5 — Recreate registry and rc-admin

The registry and rc-admin services need to pick up the updated `ISSUER_DID` and `SCHEMA_ID` from `.env`:

```sh
docker compose up -d --force-recreate registry rc-admin
```

Wait until both show `healthy` again before proceeding.

---

## Step 6 —  Adding Employee Records

```sh
bash scripts/bulk_import_employees.sh \
  --file "/path/to/employees.csv"
```

---

## Additional flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Validate all rows without making any API calls |
| `--no-credentials` | Create employees only, skip credential issuance |
| `--skip-rows N` | Skip first N rows — use to resume an interrupted run |
| `--registry-url URL` | Registry base URL (default: `http://localhost:8081`) |
| `--credential-url URL` | Credential service URL (default: `http://localhost:3001`) |

**Validate before running:**
```sh
bash scripts/bulk_import_employees.sh --dry-run --file employees.csv
```

**Resume after interruption (e.g., failed at row 300):**
```sh
bash scripts/bulk_import_employees.sh \
  --skip-rows 300 \
  --file employees.csv
```

---

## Expected output

```
Loading /path/to/employees.csv ...
  1068 data rows, 10 columns: [...]

[OK   2/1069] 001234567890 — JOHN DOE  (osid=1-abc123...)
  [CRED] issued did:cred:xyz...
[OK   3/1069] 009876543210 — JANE SMITH  (osid=1-def456...)
  [CRED] issued did:cred:abc...
...

============================================================
Import complete:
  Employees created : 200
  Already existed   : 0
  Parse errors      : 0
  Credentials issued: 200
  Credential errors : 0
============================================================
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `HTTP Error 409` | Employee already exists | Script skips automatically |
| `HTTP Error 500` on credential | Schema not created yet | Complete Steps 2–5 first |
| `jq: command not found` | Missing dependency | `apt-get install jq` |
| `Missing ISSUER_DID` | `.env` not configured | Complete Step 4 |
