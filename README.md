# vesperp4 infra

Infrastructure-as-Code for Vesper P4 on **Azure**: containerized backends on
**Azure Container Apps** (each with its own PostgreSQL), and frontends on
**Azure Static Web Apps**. This repo is the source of truth for what runs in
each environment and is deployed via GitHub Actions using **OIDC workload
identity federation** (no stored secrets).

> **New to cloud / Infrastructure-as-Code?** Start with the
> [**Onboarding guide**](./docs/onboarding.md) — it explains Azure, Bicep, and how this repo
> works from scratch, and how to make changes safely. Unfamiliar terms are in the
> [Glossary](./docs/glossary.md).

## Layout

```
infra/
├── bootstrap/            One-time identity & foundation (see bootstrap/README.md)
│   ├── main.bicep        Subscription-scope: RGs, ACR, Key Vaults, managed
│   │                     identities + federated creds + least-privilege RBAC
│   └── modules/
├── bicep/
│   ├── platform.bicep    Per-env SHARED platform: Container Apps environment
│   │                     (+ Log Analytics). Compute substrate only.
│   ├── app.bicep         API component: its OWN PostgreSQL server + database +
│   │                     the Container App
│   ├── web.bicep         Web component: an Azure Static Web App (no database)
│   └── modules/          postgres, containerapps-env, containerapp, staticwebapp
├── platform/            <env>.bicepparam — shared platform params per env
├── apps/
│   ├── dev/             <app-group>/<component>.bicepparam (api: pinned imageTag)
│   └── prod/            <app-group>/<component>.bicepparam (web: SWA, no imageTag)
├── scripts/
│   └── onboard-app-db.sh  Idempotent passwordless DB-role grant (run by CI)
└── .github/workflows/
    ├── deploy-platform.yaml   Deploys the shared platform per env
    └── deploy-app.yaml        Discovers + deploys app stacks; onboards DB roles
```

## Adding a new component

Drop a `apps/dev/<app-group>/<component>.bicepparam` and its prod counterpart.
`deploy-app.yaml` discovers it by convention and deploys its stack — no workflow
edits. There are two component kinds:

- **API** (`using '../../../bicep/app.bicep'`): set `appName`, `appGroup`,
  `imageTag`, and the Key Vault `postgresAdminPassword`. The deploy also onboards
  the DB role. Seed its `<app-group>-pg-admin-password` secret in the env Key Vault.
- **Web** (`using '../../../bicep/web.bicep'`): set `environment` (and optionally
  `appName`/`location`). Provisions an Azure **Static Web App** — no PostgreSQL,
  so `deploy-app.yaml` skips the DB-onboard step (it keys off the absence of a
  `postgresServerName` output). The SWA is created **unlinked from GitHub**; the
  monorepo's `mainsite-web-deploy.yaml` builds the site and uploads it via the
  SWA deploy token (BYO deploy). Custom domains are attached out-of-band (DNS).

## Shared platform vs per-app

The Container Apps environment is **shared per environment**; PostgreSQL is
**dedicated per app** for maximum isolation. So:

- `bicep/platform.bicep` stands up the Container Apps **environment** (the shared
  compute substrate) once per env. It rarely changes.
- `bicep/app.bicep` deploys **one app**: its **own** PostgreSQL Flexible Server +
  database, plus its Container App. Adding a second app = a new
  `apps/<env>/<app-group>/<component>.bicepparam` (its own server name, database, and Key Vault
  password secret). Apps never share a database server.

## Order of operations

1. **Bootstrap** the identity/foundation once (admin-run) — `bootstrap/README.md`.
2. **Wire GitHub** environments + secrets/variables from the bootstrap outputs.
3. **Seed** each app's Postgres password secret into the env Key Vault — secret
   name `<app-group>-pg-admin-password` (e.g. `mainsite-pg-admin-password`).
4. **Deploy the platform** per env (`deploy-platform.yaml`, or `mise`/`az` locally).
5. **Deploy apps** — the monorepo bumps `apps/<env>/<app-group>/<component>.bicepparam` and merging
   triggers `deploy-app.yaml`, which deploys the stack and **onboards the DB role
   automatically** (no manual SQL).

## PostgreSQL auth — passwordless first

Each app's server is created with **Entra auth enabled** and the `infra-admins`
group as the Entra administrator. Password auth is left **enabled as an escape
hatch** (the `pgadmin` password lives in Key Vault as `<app-group>-pg-admin-password`);
flip `passwordAuth: 'Disabled'` in `modules/postgres.bicep` to harden once the app
is on tokens.

The Container App ships **no DB password**. It authenticates with an Entra token
from its managed identity (`id-app-<env>`): the app reads `PGHOST/PGUSER/PGDATABASE`
and `AZURE_CLIENT_ID` from the environment and uses a freshly-minted token as the
password.

**DB-role onboarding is automated.** Each server gets two Entra admins: the
`infra-admins` group (humans) and the CI **deploy identity** (`id-github-deploy-<env>`).
After deploying an app stack, `deploy-app.yaml` runs `scripts/onboard-app-db.sh`,
which — as the deploy identity — creates the least-privilege Postgres role mapped to
`id-app-<env>` (`pgaadauth_create_principal_with_oid`) and grants it on the database.
It's idempotent (re-runs harmlessly) and opens a temporary firewall rule for the
runner's IP (GitHub runners aren't covered by `AllowAzureServices`), removed on exit.

> App-side: the Rust service uses its managed identity to fetch a token for
> `https://ossrdbms-aad.database.windows.net/.default` and passes it as the
> connection password (sqlx custom connect options). The dev team wires this.

## portal-api custom domain + Entra app registration (out-of-band)

The portal API binds `api.portal.dev.vesperp4.com` (dev) and
`api.portal.vesperp4.com` (prod) with **Azure managed certificates**, so the
session cookie (`.portal.<root>`) is same-site with the portal SWA. Managed-cert
binding is inherently **two-phase** — the cert can't exist before the hostname
is added and validated — so, like the SWA custom domains, it's bound
out-of-band and then **pinned** in the env's `portal-api.bicepparam` so ARM PUT
redeploys don't strip the binding. Run steps 1–4 **per env**; step 5 (the app
registration) is done once and shared.

### 1. Cloudflare DNS

Both records **DNS-only (grey cloud)** — required for managed-cert issuance
*and* renewal; an orange-cloud proxy hides the CNAME from Azure's validation.

```bash
# The verification ID for the asuid TXT record:
az containerapp show -n portal-api-<env> -g vesperp4-<env>-rg \
  --query properties.customDomainVerificationId -o tsv
```

| Type | Name | Value |
|---|---|---|
| CNAME | `api.portal.dev` (dev) / `api.portal` (prod) | the Container App's default FQDN (`az containerapp show ... --query properties.configuration.ingress.fqdn`) |
| TXT | `asuid.api.portal.dev` (dev) / `asuid.api.portal` (prod) | the `customDomainVerificationId` above |

### 2. Add the hostname

```bash
az containerapp hostname add -n portal-api-<env> -g vesperp4-<env>-rg \
  --hostname api.portal.dev.vesperp4.com   # prod: api.portal.vesperp4.com
```

### 3. Create the managed certificate (on the shared environment)

```bash
az containerapp env certificate create -g vesperp4-<env>-rg \
  --name vesperp4-<env>-cae \
  --hostname api.portal.dev.vesperp4.com \
  --validation-method CNAME
```

Issuance takes a few minutes; note the certificate's **resource ID** from the
output (or `az containerapp env certificate list`).

### 4. Bind, then pin

```bash
az containerapp hostname bind -n portal-api-<env> -g vesperp4-<env>-rg \
  --hostname api.portal.dev.vesperp4.com \
  --certificate <cert resource ID>
```

Then record the cert resource ID as `apiCustomDomainCertificateId` in
`apps/<env>/portal/portal-api.bicepparam` — that's what keeps the binding
declared on subsequent deploys.

### 5. Entra app registration (once, in the vesperp4 tenant)

```bash
az ad app create --display-name "VESPER P4 Member Portal" \
  --sign-in-audience AzureADMultipleOrgs \
  --web-redirect-uris \
    https://api.portal.vesperp4.com/api/v1/auth/oidc/callback \
    https://api.portal.dev.vesperp4.com/api/v1/auth/oidc/callback \
    http://localhost:8080/api/v1/auth/oidc/callback
```

- Add the **`email` optional claim** to the ID token (Entra portal → Token
  configuration, or `az ad app update --id <appId>` with `optionalClaims`).
- **No client secret.** Create a **federated identity credential** per env on
  the app registration, trusting the app runtime identities:

  ```bash
  # subject = the identity's principalId:
  az identity show -n id-app-<env> -g vesperp4-shared-rg --query principalId -o tsv

  az ad app federated-credential create --id <appId> --parameters '{
    "name": "id-app-<env>",
    "issuer": "https://login.microsoftonline.com/4cb021ac-682f-419c-9bf1-dba159e55bb9/v2.0",
    "subject": "<principalId>",
    "audiences": ["api://AzureADTokenExchange"]
  }'
  ```

- Pin the registration's **appId** as `oidcClientId` in both envs' param files.

`oidcTenantId` is **PUPR's tenant GUID, not the vesperp4 tenant** — members
sign in with their `@pupr.edu` accounts. Discover it from the issuer in:

```bash
curl -s https://login.microsoftonline.com/pupr.edu/.well-known/openid-configuration
```

> **PUPR-side consent caveat:** if PUPR restricts user consent, the first
> sign-in fails until a PUPR admin grants tenant-wide consent at
> `https://login.microsoftonline.com/<pupr-tenant>/adminconsent?client_id=<appId>`.
> The magic-link flow works regardless, so sign-in isn't blocked on PUPR IT.

## Conventions

- Region `eastus2`, subscription `1e180171-becb-40cd-a4a0-52351087be66`.
- Compiled JSON is gitignored. **`mise` is the front door** — run `mise tasks` for the list;
  `mise run lint` compiles all Bicep + params, and `mise run check` also lints workflows and
  shell scripts. Run `mise run check` before pushing.
- Actions are SHA-pinned. Prod deploys are gated by the `prod` GitHub
  environment's required reviewers.

## Related

- Identity/foundation rationale: [`bootstrap/README.md`](./bootstrap/README.md)
- Human identity & access (groups, break-glass): monorepo `docs/entra-identity.md`
- Pipeline overview: monorepo `docs/cicd-pipeline.md` and `docs/infra-repo-spec.md`
