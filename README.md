# vesperp4 infra

Infrastructure-as-Code for the Vesper P4 backend on **Azure Container Apps**.
This repo is the source of truth for what runs in each environment and is
deployed via GitHub Actions using **OIDC workload identity federation** (no
stored secrets).

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
│   ├── app.bicep         Per-app: its OWN PostgreSQL server + database + the
│   │                     Container App
│   └── modules/          postgres, containerapps-env, containerapp
├── env/
│   ├── dev/              platform.bicepparam + <app>.bicepparam (pinned imageTag)
│   └── prod/             platform.bicepparam + <app>.bicepparam (pinned imageTag)
└── .github/workflows/
    ├── deploy-platform.yaml   Deploys the shared platform per env
    └── deploy-app.yaml        Deploys an app on its pinned image tag
```

## Shared platform vs per-app

The Container Apps environment is **shared per environment**; PostgreSQL is
**dedicated per app** for maximum isolation. So:

- `bicep/platform.bicep` stands up the Container Apps **environment** (the shared
  compute substrate) once per env. It rarely changes.
- `bicep/app.bicep` deploys **one app**: its **own** PostgreSQL Flexible Server +
  database, plus its Container App. Adding a second app = a new
  `env/<env>/<app>.bicepparam` (its own server name, database, and Key Vault
  password secret). Apps never share a database server.

## Order of operations

1. **Bootstrap** the identity/foundation once (admin-run) — `bootstrap/README.md`.
2. **Wire GitHub** environments + secrets/variables from the bootstrap outputs.
3. **Seed** each app's Postgres password secret into the env Key Vault — secret
   name `<app>-pg-admin-password` (e.g. `vesperp4-api-pg-admin-password`).
4. **Deploy the platform** per env (`deploy-platform.yaml`, or `mise`/`az` locally).
5. **Onboard the app's Entra DB role** on that app's server (passwordless — see below).
6. **Deploy apps** — the monorepo bumps `env/<env>/<app>.bicepparam` and merging
   triggers `deploy-app.yaml`.

## PostgreSQL auth — passwordless first

Each app's server is created with **Entra auth enabled** and the `infra-admins`
group as the Entra administrator. Password auth is left **enabled as an escape
hatch** (the `pgadmin` password lives in Key Vault as `<app>-pg-admin-password`);
flip `passwordAuth: 'Disabled'` in `modules/postgres.bicep` to harden once the app
is on tokens.

The Container App ships **no DB password**. It authenticates with an Entra token
from its managed identity (`id-app-<env>`): the app reads `PGHOST/PGUSER/PGDATABASE`
and `AZURE_CLIENT_ID` from the environment and uses a freshly-minted token as the
password.

For the app identity to connect, an admin runs this **once per env/database**,
connected to the server as an `infra-admins` member:

```sql
-- creates a least-privilege Postgres role mapped to the app's managed identity
SELECT * FROM pgaadauth_create_principal('id-app-dev', false, false);
GRANT ALL PRIVILEGES ON DATABASE vesperp4_api TO "id-app-dev";
```

> App-side: the Rust service uses its managed identity to fetch a token for
> `https://ossrdbms-aad.database.windows.net/.default` and passes it as the
> connection password (sqlx custom connect options). The dev team wires this.

## Conventions

- Region `eastus2`, subscription `1e180171-becb-40cd-a4a0-52351087be66`.
- Compiled JSON is gitignored. `mise run lint` compiles all Bicep + params locally.
- Actions are SHA-pinned. Prod deploys are gated by the `production` GitHub
  environment's required reviewers.

## Related

- Identity/foundation rationale: [`bootstrap/README.md`](./bootstrap/README.md)
- Human identity & access (groups, break-glass): monorepo `iac/azure/entra/`
- Pipeline overview: monorepo `docs/cicd-pipeline.md` and `docs/infra-repo-spec.md`
