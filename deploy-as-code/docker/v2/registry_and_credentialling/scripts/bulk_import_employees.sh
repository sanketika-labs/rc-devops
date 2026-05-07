#!/usr/bin/env bash
# bulk_import_employees.sh
# Reads employee CSV, creates Employee records in RC registry, issues W3C VCs.
#
# Usage:
#   bash scripts/bulk_import_employees.sh [OPTIONS]
#
#   --file PATH          CSV file to import (default: employees.csv or BULK_IMPORT_FILE)
#   --dry-run            Validate rows without making API calls
#   --no-credentials     Create employees only, skip credential issuance
#   --skip-rows N        Skip first N data rows (resume after interruption)
#   --session SESSION_ID JSESSIONID cookie value (creates one record per employee instead of two)
#   --registry-url URL   Registry base URL (default: http://localhost:8081)
#   --credential-url URL Credential service URL (default: http://localhost:3001)
#   --issuer-did DID     Issuer DID (default: from .env ISSUER_DID)
#   --schema-id ID       Schema ID (default: from .env SCHEMA_ID)
#   --schema-version VER Schema version (default: 1.0.0)
#
# Requires: curl, jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        val="${val%\"}"
        val="${val#\"}"
        val="${val%\'}"
        val="${val#\'}"
        export "$key=$val"
    done < <(grep -v '^#' "$ENV_FILE" | grep -v '^$')
fi

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_FILE="${BULK_IMPORT_FILE:-employees.csv}"
DEFAULT_REGISTRY_URL="${REGISTRY_URL:-http://localhost:8081}"
DEFAULT_CREDENTIAL_URL="${CREDENTIAL_URL:-http://localhost:3001}"

DRY_RUN=false
NO_CREDENTIALS=false
SKIP_ROWS=0
SESSION_ID="${JSESSIONID:-}"
INPUT_FILE="$DEFAULT_FILE"
REGISTRY_URL="$DEFAULT_REGISTRY_URL"
CREDENTIAL_URL="$DEFAULT_CREDENTIAL_URL"
ISSUER_DID="${ISSUER_DID:-}"
SCHEMA_ID="${SCHEMA_ID:-}"
SCHEMA_VERSION="${SCHEMA_VERSION:-1.0.0}"

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
usage() {
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)           INPUT_FILE="$2";     shift 2 ;;
        --dry-run)        DRY_RUN=true;        shift   ;;
        --no-credentials) NO_CREDENTIALS=true; shift   ;;
        --skip-rows)      SKIP_ROWS="$2";      shift 2 ;;
        --session)        SESSION_ID="$2";     shift 2 ;;
        --registry-url)   REGISTRY_URL="$2";   shift 2 ;;
        --credential-url) CREDENTIAL_URL="$2"; shift 2 ;;
        --issuer-did)     ISSUER_DID="$2";     shift 2 ;;
        --schema-id)      SCHEMA_ID="$2";      shift 2 ;;
        --schema-version) SCHEMA_VERSION="$2"; shift 2 ;;
        --help|-h)        usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required. Install with:  apt-get install jq"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: File not found: $INPUT_FILE"
    exit 1
fi

if [[ "$DRY_RUN" == false ]]; then
    MISSING=()
    [[ -z "$ISSUER_DID" ]] && MISSING+=("--issuer-did (or ISSUER_DID in .env)")
    [[ -z "$SCHEMA_ID"  ]] && MISSING+=("--schema-id (or SCHEMA_ID in .env)")
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        echo "ERROR: Missing required configuration:"
        for m in "${MISSING[@]}"; do echo "  $m"; done
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Parse CSV header — find column indices by name
# ---------------------------------------------------------------------------
HEADER_LINE=$(head -n 1 "$INPUT_FILE" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
IFS=',' read -r -a HEADERS <<< "$HEADER_LINE"

for i in "${!HEADERS[@]}"; do
    HEADERS[$i]=$(echo "${HEADERS[$i]}" | xargs)
done

IDX_CEDULA=-1; IDX_TYPE=-1;     IDX_NAME=-1;     IDX_POSITION=-1
IDX_SALARY=-1; IDX_DEPT=-1;     IDX_COMPANY=-1;  IDX_STATUS=-1
IDX_ADMISSION=-1; IDX_EXIT=-1

for i in "${!HEADERS[@]}"; do
    case "${HEADERS[$i]}" in
        PersonalIdentification) IDX_CEDULA=$i    ;;
        TypeIdentification)     IDX_TYPE=$i      ;;
        Name)                   IDX_NAME=$i      ;;
        PositionName)           IDX_POSITION=$i  ;;
        Salary)                 IDX_SALARY=$i    ;;
        DepartmentName)         IDX_DEPT=$i      ;;
        CompanyName)            IDX_COMPANY=$i   ;;
        Status)                 IDX_STATUS=$i    ;;
        AdmissionDate)          IDX_ADMISSION=$i ;;
        ExitDate)               IDX_EXIT=$i      ;;
    esac
done

if [[ $IDX_CEDULA -eq -1 ]]; then
    echo "ERROR: Required column 'PersonalIdentification' not found"
    echo "Found columns: ${HEADERS[*]}"
    exit 1
fi

# ---------------------------------------------------------------------------
# W3C VC @context
# ---------------------------------------------------------------------------
VC_CONTEXT='[
  "https://www.w3.org/2018/credentials/v1",
  {
    "@context": {
      "id": "@id",
      "schema": "https://schema.org/",
      "@version": 1.1,
      "Employee": {
        "@id": "https://github.com/sunbird-specs/vc-specs#Employee",
        "@context": {
          "id": "@id",
          "name": "schema:Text",
          "status": "schema:Text",
          "@version": 1.1,
          "position": "schema:Text",
          "@protected": true,
          "dateOfHire": "schema:Text",
          "institution": "schema:Text",
          "department": "schema:Text",
          "personalIdentification": "schema:Text",
          "documentType": "schema:Text",
          "organizationalUnit": "schema:Text"
        }
      },
      "@protected": true
    }
  },
  "https://w3id.org/security/suites/ed25519-2020/v1"
]'

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
TOTAL=$(awk 'END{print NR-1}' "$INPUT_FILE")
echo "Loading CSV: $INPUT_FILE ..."
echo "  $TOTAL data rows, ${#HEADERS[@]} columns: ${HEADERS[*]}"
echo ""

[[ $SKIP_ROWS -gt 0 ]] && echo "Skipping first $SKIP_ROWS rows (resuming)"$'\n'

CREATED=0; SKIPPED=0; PARSE_ERR=0; CRED_OK=0; CRED_FAIL=0
ROW_NUM=1
DATA_ROW=0

while IFS=',' read -r -a FIELDS; do
    ROW_NUM=$(( ROW_NUM + 1 ))
    DATA_ROW=$(( DATA_ROW + 1 ))

    [[ $DATA_ROW -le $SKIP_ROWS ]] && continue

    _f() { echo "${FIELDS[${1:-0}]:-}" | tr -d '\r' | xargs; }

    CEDULA=$(_f $IDX_CEDULA)
    NAME=$(_f $IDX_NAME)
    TYPE=$(_f $IDX_TYPE)
    POSITION=$(_f $IDX_POSITION)
    DEPT=$(_f $IDX_DEPT)
    COMPANY=$(_f $IDX_COMPANY)
    STATUS_VAL=$(_f $IDX_STATUS)
    SALARY_RAW=$(_f $IDX_SALARY)
    ADMISSION=$(_f $IDX_ADMISSION)
    EXIT_DATE=$(_f $IDX_EXIT)

    ADMISSION="${ADMISSION:0:10}"
    EXIT_DATE="${EXIT_DATE:0:10}"

    if [[ -z "$CEDULA" ]]; then
        # Silently skip blank lines (e.g., the sentinel newline added to handle
        # CSV files with no trailing newline on the last row).
        if [[ -n "${FIELDS[*]// /}" ]]; then
            echo "[PARSE ERR row $ROW_NUM] Missing PersonalIdentification (cedula)"
            PARSE_ERR=$(( PARSE_ERR + 1 ))
        else
            DATA_ROW=$(( DATA_ROW - 1 ))
        fi
        continue
    fi

    SALARY=$(printf "%.0f" "${SALARY_RAW:-0}" 2>/dev/null || echo "0")

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN $ROW_NUM/$((TOTAL+1))] $CEDULA — $NAME"
        CREATED=$(( CREATED + 1 ))
        continue
    fi

    # Build employee JSON (flat — /invite endpoint expects no wrapper)
    EMP_JSON=$(jq -nc \
        --arg cedula    "$CEDULA" \
        --arg type      "${TYPE:-Cedula}" \
        --arg name      "$NAME" \
        --arg position  "$POSITION" \
        --arg dept      "$DEPT" \
        --arg company   "$COMPANY" \
        --arg status    "$STATUS_VAL" \
        --arg salary    "$SALARY" \
        --arg admission "$ADMISSION" \
        '{
            personalIdentification: $cedula,
            typeIdentification: $type,
            fullName: $name,
            role: "employee",
            positionName: $position,
            departmentName: $dept,
            companyName: $company,
            salary: $salary,
            admissionDate: $admission,
            statusName: $status
        }')

    if [[ -n "$EXIT_DATE" && "$EXIT_DATE" != "NULL" && "$EXIT_DATE" != "NONE" ]]; then
        EMP_JSON=$(echo "$EMP_JSON" | jq --arg exit "$EXIT_DATE" '.contractExpiration = $exit')
    fi

    # Check for existing employee before creating to handle re-runs safely
    _COOKIE_ARGS=()
    [[ -n "$SESSION_ID" ]] && _COOKIE_ARGS=(-H "Cookie: JSESSIONID=$SESSION_ID")
    EXIST_RESP=$(curl -s -X POST "$REGISTRY_URL/api/v1/Employee/search" \
        -H "Content-Type: application/json" \
        "${_COOKIE_ARGS[@]}" \
        -d "{\"filters\":{\"personalIdentification\":{\"eq\":\"$CEDULA\"}}}" 2>/dev/null)
    EXIST_COUNT=$(echo "$EXIST_RESP" | jq -r '.totalCount // 0' 2>/dev/null)
    if [[ "${EXIST_COUNT:-0}" -gt 0 ]]; then
        echo "[SKIP $ROW_NUM/$((TOTAL+1))] $CEDULA already exists"
        SKIPPED=$(( SKIPPED + 1 ))
        continue
    fi

    # POST employee via invite endpoint
    # When SESSION_ID is provided the request is authenticated — creates one record per employee.
    # Without SESSION_ID the invite endpoint creates two records (Employee + invite claim entity).
    RESP=$(curl -s -w "\n%{http_code}" -X POST "$REGISTRY_URL/api/v1/Employee/invite" \
        -H "Content-Type: application/json" \
        "${_COOKIE_ARGS[@]}" \
        -d "$EMP_JSON" 2>/dev/null)

    HTTP_CODE=$(echo "$RESP" | tail -1)
    BODY=$(echo "$RESP" | head -n -1)

    if [[ "$HTTP_CODE" == "409" ]]; then
        echo "[SKIP $ROW_NUM/$((TOTAL+1))] $CEDULA already exists"
        SKIPPED=$(( SKIPPED + 1 ))
        continue
    fi

    if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
        echo "[FAIL $ROW_NUM/$((TOTAL+1))] $CEDULA — HTTP $HTTP_CODE: $(echo "$BODY" | head -c 120)"
        continue
    fi

    OSID=$(echo "$BODY" | jq -r '.result.Employee.osid // .Employee.osid // .result.osid // .osid // empty' 2>/dev/null)
    echo "[OK   $ROW_NUM/$((TOTAL+1))] $CEDULA — $NAME  (osid=$OSID)"
    CREATED=$(( CREATED + 1 ))

    # Issue credential
    if [[ "$NO_CREDENTIALS" == true || -z "$OSID" ]]; then
        continue
    fi

    ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    CRED_JSON=$(jq -nc \
        --arg osid     "$OSID" \
        --arg issuer   "$ISSUER_DID" \
        --arg name     "$NAME" \
        --arg cedula   "$CEDULA" \
        --arg company  "$COMPANY" \
        --arg position "$POSITION" \
        --arg dept     "$DEPT" \
        --arg hire     "$ADMISSION" \
        --arg schema   "$SCHEMA_ID" \
        --arg version  "$SCHEMA_VERSION" \
        --arg issued   "$ISSUANCE_DATE" \
        --argjson ctx  "$VC_CONTEXT" \
        '{
            credential: {
                "@context": $ctx,
                type: ["VerifiableCredential","Employee"],
                issuer: $issuer,
                issuanceDate: $issued,
                expirationDate: "2030-12-31T00:00:00.000Z",
                credentialSubject: {
                    id: ("did:rcw:"+$osid),
                    type: "Employee",
                    name: $name,
                    personalIdentification: $cedula,
                    institution: $company,
                    position: $position,
                    department: $dept,
                    status: "active",
                    dateOfHire: $hire
                },
                credentialSchema: {id: $schema, type: "JsonSchemaValidator2018"}
            },
            credentialSchemaId: $schema,
            credentialSchemaVersion: $version,
            tags: ["employee", $osid]
        }')

    CRED_RESP=$(curl -s -w "\n%{http_code}" -X POST "$CREDENTIAL_URL/credentials/issue" \
        -H "Content-Type: application/json" \
        -d "$CRED_JSON" 2>/dev/null)

    CRED_CODE=$(echo "$CRED_RESP" | tail -1)
    CRED_BODY=$(echo "$CRED_RESP" | head -n -1)

    if [[ "$CRED_CODE" == "200" || "$CRED_CODE" == "201" ]]; then
        CRED_ID=$(echo "$CRED_BODY" | jq -r '.credential.id // .id // "?"' 2>/dev/null)
        echo "  [CRED] issued $CRED_ID"
        CRED_OK=$(( CRED_OK + 1 ))
    else
        echo "  [CRED FAIL] $CEDULA — HTTP $CRED_CODE: $(echo "$CRED_BODY" | head -c 100)"
        CRED_FAIL=$(( CRED_FAIL + 1 ))
    fi

    sleep 0.05

done < <(tail -n +2 "$INPUT_FILE"; echo)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
if [[ "$DRY_RUN" == true ]]; then
    echo "DRY RUN complete — $CREATED rows parsed, $PARSE_ERR parse errors"
else
    echo "Import complete:"
    echo "  Employees created : $CREATED"
    echo "  Already existed   : $SKIPPED"
    echo "  Parse errors      : $PARSE_ERR"
    if [[ "$NO_CREDENTIALS" == false ]]; then
        echo "  Credentials issued: $CRED_OK"
        echo "  Credential errors : $CRED_FAIL"
    fi
fi
echo "============================================================"
