## Registry and Credentialling 2.0


# Steps to setup registry 2.0 :

## System requirements

- 4 Cores
- 16 GB RAM
- Min 100 GB disk

## Prerequisites 

- This guide assumes some familiarity with basic linux commands. If not, [here](https://ubuntu.com/tutorials/command-line-for-beginners#1-overview) is a great place to start.
- Don't copy-paste the $ signs, they indicate that what follows is a terminal command

## Terminal emulator
- Linux and MacOS will have a terminal installed already. For Windows, it is recommended that you use git-bash, which you can install from [here](https://git-scm.com/download/win).
- Type echo Hi in the terminal once it is installed. If installed correctly, you should see Hi appear when you hit enter.

## Docker

- Installation instructions for Docker can be found [here](https://docs.docker.com/engine/install/).
- Run docker -v in terminal to check if docker has been installed correctly:

```bash 
   docker -v
```

## Docker Compose
- Installation instructions can be found [here](https://docs.docker.com/compose/install/).
- Run docker-compose version in the terminal to check if docker-compose has been installed correctly:

```bash
docker-compose version
```


## Installation

### 1. Configure environment variables

Copy the example env file and fill in the required values:

```bash
cp .env.example .env
```

Edit `.env` and set the following secrets before starting any services:

| Variable | Description |
|---|---|
| `POSTGRES_PASSWORD` | Password for the main `postgres` DB user |
| `KRATOS_DB_PASSWORD` | Password for the `kratos` DB user |
| `HYDRA_DB_PASSWORD` | Password for the `hydra` DB user |
| `KETO_DB_PASSWORD` | Password for the `keto` DB user |
| `HYDRA_SYSTEM_SECRET` | Hydra system secret — generate with `openssl rand -base64 32` |
| `HYDRA_COOKIE_SECRET` | Hydra cookie secret — generate with `openssl rand -base64 32` |
| `HYDRA_PAIRWISE_SALT` | Salt for OIDC pairwise subject identifiers |
| `RC_CLIENT_SECRET` | OAuth2 client secret for `rc-client` — generate with `openssl rand -base64 32` |
| `VAULT_TOKEN` | Root token for Hashicorp Vault — **leave blank**, auto-populated by `make compose-init` on first run |
| `RC_ADMIN_BASE_URL` | Public base URL of the rc-admin UI (e.g. `http://localhost:3000`) |
| `WEB_DID_BASE_URL` | Public HTTPS URL where DID documents will be hosted (e.g. `https://alice.github.io/rc-did-documents`) — see step 3 below |
| `ISSUER_DID` | DID of the credential issuer — generated after services are running (see step 8) |
| `SCHEMA_ID` | ID of the credential schema — generated after services are running (see step 8) |
| `TEMPLATE_ID` | ID of the certificate template — generated after services are running (see step 8) |

You can generate all three in one go:

```bash
echo "HYDRA_SYSTEM_SECRET=$(openssl rand -base64 32)"
echo "HYDRA_COOKIE_SECRET=$(openssl rand -base64 32)"
echo "RC_CLIENT_SECRET=$(openssl rand -base64 32)"
```

### 2. Configure ORY Kratos (OIDC provider)

This setup uses [ORY Kratos](https://www.ory.sh/kratos/) for identity management and [ORY Hydra](https://www.ory.sh/hydra/) as the OAuth2/OIDC server.

Edit `ory/kratos/kratos.yml` and replace the OIDC provider placeholders with your actual values:

```yaml
providers:
  - id: cuenta-digital
    client_id: <CLIENT_ID>       # replace with your OIDC client ID
    client_secret: <CLIENT_SECRET>  # replace with your OIDC client secret
    issuer_url: https://your-oidc-provider.example.com
```

Also replace the `<COOKIE_SECRET>` and `<CIPHER_SECRET>` placeholders in the `secrets` section:

```yaml
secrets:
  cookie:
    - <COOKIE_SECRET>
  cipher:
    - <CIPHER_SECRET>
```

Generate secure values with:

```bash
openssl rand -base64 32   # run once for COOKIE_SECRET
openssl rand -base64 32   # run again for CIPHER_SECRET
```

### 3. Set up GitHub Pages for DID hosting (Optional)

Digital credentials require a publicly accessible DID (Decentralized Identifier) document hosted at a stable HTTPS URL. GitHub Pages is the simplest option.

**3.1 Create a public GitHub repository**
- Go to [github.com/new](https://github.com/new)
- Repository name: `rc-did-documents` (or any name you prefer)
- Visibility: **Public**
- Click **Create repository**

**3.2 Enable GitHub Pages**
- Go to repository **Settings → Pages**
- Under **Source**, select **Deploy from a branch**
- Branch: `main` · Folder: `/ (root)`
- Click **Save**

**3.3 Note your DID base URL**

```
https://<YOUR_GITHUB_USERNAME>.github.io/<YOUR_REPO_NAME>
```

Example: `https://alice.github.io/rc-did-documents`

Set this as `WEB_DID_BASE_URL` in your `.env` file before starting services.

### 4. Configure Vault

- We are using [Hashicorp Vault](https://www.vaultproject.io/) as the keystore manager.

### 5. Add your credential schemas

Place your credential schema JSON files in the `schemas/` directory. An example schema (`Employee.json`) is provided as a reference.

### 6. Start all services

```bash
make compose-init
```

This command does the following in order:

1. Starts the **Vault** container only and waits for it to be ready
2. Checks Vault state:
   - **Fresh install** — initialises Vault, generates **5 unseal keys** and a **root token**, saves them to `keys.txt`, then unseals using the first 3 keys and enables the KV v2 secrets engine at path `kv`, and auto-writes `VAULT_TOKEN` into `.env`
   - **Already initialised + `keys.txt` exists** — unseals using existing keys from `keys.txt`, skips KV engine creation
   - **Already initialised + `keys.txt` missing** — exits immediately with a `CRITICAL ERROR`. You must restore `keys.txt` or wipe `vault-data/` to reset (see [Reset](#reset--start-from-scratch))
3. Starts all remaining services via `docker-compose up -d`

> **Keep `keys.txt` safe** — it contains the unseal keys and root token. Do not commit it to version control.

> **Note:** Vault comes up sealed on every restart. Re-run `make compose-init` to unseal it — as long as `keys.txt` is present it will unseal without reinitialising.

> **Alternatively**, unseal manually:
> ```bash
> docker-compose up -d vault
> docker-compose exec vault vault operator unseal <Unseal Key 1>
> docker-compose exec vault vault operator unseal <Unseal Key 2>
> docker-compose exec vault vault operator unseal <Unseal Key 3>
> docker-compose up -d
> ```

### 7. Verify services are running

```bash
docker-compose ps
```

### 8. Access the registry

- Registry Swagger: `http://localhost:8081/api/docs/swagger.json`
- Hydra public endpoint: `http://localhost:4444`
- Kratos public endpoint: `http://localhost:4433`
- rc-admin UI: `http://localhost:4000`

### 9. Generate Issuer DID, Schema and Template

Once all services are running, use the provided Postman collection to generate the required identifiers.

> **Postman collection:** _Link to be added_

The collection will guide you through:

**Step 9.1 — Generate Issuer DID**
- Run the **Generate DID** request in the collection
- Copy the returned DID (e.g. `did:rcw:abc123...`)
- The identity service will also generate a DID document — download it

**Step 9.2 — Host the DID document on GitHub Pages**
- Add the DID document file to your `rc-did-documents` GitHub repository
- The file must be accessible at:
  ```
  https://<YOUR_GITHUB_USERNAME>.github.io/<YOUR_REPO_NAME>/<DID_IDENTIFIER>
  ```
- Commit and push — GitHub Pages will publish it automatically within a few minutes

**Step 9.3 — Generate Credential Schema**
- Run the **Create Schema** request in the collection
- Copy the returned `schemaId`

**Step 9.4 — Generate Certificate Template**
- Run the **Create Template** request in the collection
- Copy the returned `templateId`

**Step 9.5 — Update `.env` and restart**

Set the values in your `.env` file:

```env
ISSUER_DID=did:rcw:<your-issuer-did>
SCHEMA_ID=<your-schema-id>
TEMPLATE_ID=<your-template-id>
```

Then restart the rc-admin service to pick up the changes:

```bash
docker-compose up -d rc-admin
```

## Reset / start from scratch

Use these commands only when you want to wipe all data and restart:

```bash
docker-compose down
sudo rm -rf db-data/ vault-data/ keys.txt
```

> **Important:** Always delete `keys.txt` together with `vault-data/`. If `vault-data/` is removed but `keys.txt` is kept (or vice versa), the script will detect a mismatch and exit with a `CRITICAL ERROR` on the next run.
