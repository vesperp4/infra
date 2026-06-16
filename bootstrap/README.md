# `bootstrap/` — identity & foundation

One-time foundation that everything else in this repo (and the monorepo's image
build) relies on. It establishes **how GitHub Actions authenticates to Azure**
and the **least-privilege access** each workflow gets — with **no client
secrets** anywhere.

This is the "Azure + Entra prod-ready" layer. It complements the human-identity
work documented in the monorepo at `iac/azure/entra/` (groups, break-glass,
Security Defaults). That doc covers *people*; this covers *workloads*.

---

## What it creates

| Resource group | Holds |
|---|---|
| `vesperp4-shared-rg` | ACR + all managed identities |
| `vesperp4-dev-rg` | dev Key Vault (dev app resources later) |
| `vesperp4-prod-rg` | prod Key Vault (prod app resources later) |

**Managed identities (user-assigned) + least-privilege RBAC:**

| Identity | Federated subject (GitHub OIDC) | Roles |
|---|---|---|
| `id-github-acr-push` | `repo:vesperp4/mono:environment:azure-acr` | `AcrPush` on ACR |
| `id-github-deploy-dev` | `repo:vesperp4/infra:environment:dev` | `Contributor` on `vesperp4-dev-rg`, `Key Vault Secrets User` on dev KV |
| `id-github-deploy-prod` | `repo:vesperp4/infra:environment:prod` | `Contributor` on `vesperp4-prod-rg`, `Key Vault Secrets User` on prod KV |
| `id-app-dev` | *(runtime only — no GitHub federation)* | `AcrPull` on ACR, `Key Vault Secrets User` on dev KV |
| `id-app-prod` | *(runtime only)* | `AcrPull` on ACR, `Key Vault Secrets User` on prod KV |

The `infra-admins` group additionally gets `Key Vault Secrets Officer` on both
vaults so admins can seed/rotate the Postgres password.

---

## Why this shape

- **User-assigned managed identities, not app registrations.** UAMIs +
  `federatedIdentityCredentials` are ARM resources, so the whole identity layer
  is Bicep (auditable, reviewable, idempotent) — unlike Graph-only app
  registrations. Matches the monorepo `iac/azure/entra` §7 rule: *per-workload
  managed identities, not shared SPs.*
- **OIDC federation = no secrets.** GitHub mints a short-lived token per run;
  Azure trusts it via the federated credential. There is **no client secret** to
  store, rotate, or leak.
- **Environment-scoped subjects.** Each credential is pinned to a specific repo
  **and** GitHub environment (`environment:dev`, `environment:prod`,
  `environment:azure-acr`). A workflow can only assume an identity from the exact
  environment it's authorized for — and the `prod` environment carries a
  reviewer gate, so prod deploys require human approval before the token is even
  issued.
- **Least privilege, per purpose + per env.** Push is `AcrPush` on the registry
  only. Deploy is `Contributor` on **one** environment's resource group — never
  subscription-wide, never cross-environment. Runtime app identities only get
  `AcrPull` + secret-read. No identity can assign roles.
- **Key Vault for the DB secret.** The Postgres admin password lives in a
  per-env Key Vault (RBAC-authorized, purge-protected). The deploy identity
  reads it at deploy time; the Container App reads it at runtime via its own
  identity. The password is never in Git, params, or workflow logs.

---

## Deploy (one-time, by an admin)

Requires an `infra-admins` member (Owner on the subscription) logged in:

```bash
az login
az account set --subscription 1e180171-becb-40cd-a4a0-52351087be66

# Preview:
az deployment sub what-if \
  --location eastus2 \
  --template-file bootstrap/main.bicep \
  --parameters bootstrap/main.bicepparam

# Apply:
az deployment sub create \
  --name vesperp4-bootstrap \
  --location eastus2 \
  --template-file bootstrap/main.bicep \
  --parameters bootstrap/main.bicepparam
```

Idempotent — re-running converges drift.

---

## After deploying — wiring (one-time)

Grab the deployment outputs:

```bash
az deployment sub show --name vesperp4-bootstrap --query properties.outputs -o json
```

### 1. Seed the Postgres password into Key Vault

```bash
# dev
az keyvault secret set --vault-name vesperp4-dev-kv  --name postgres-admin-password --value "$(openssl rand -base64 24)"
# prod
az keyvault secret set --vault-name vesperp4-prod-kv --name postgres-admin-password --value "$(openssl rand -base64 24)"
```

### 2. Create GitHub environments

- **monorepo (`vesperp4/mono`)**: environment **`azure-acr`** (no gate needed).
  Add `environment: azure-acr` to the `build-and-push` job in
  `.github/workflows/website-api-build.yaml` so its OIDC subject matches.
- **infra repo (`vesperp4/infra`)**: environments **`dev`** (no gate) and
  **`prod`** (required reviewers).

### 3. Set GitHub secrets / variables (from outputs)

| Repo | Scope | Name | Value (output) |
|---|---|---|---|
| mono | repo secret | `AZURE_TENANT_ID` | `tenantId` |
| mono | repo secret | `AZURE_SUBSCRIPTION_ID` | `subscriptionId` |
| mono | repo secret | `AZURE_CLIENT_ID` | `idAcrPushClientId` |
| mono | repo var | `ACR_NAME` / `ACR_LOGIN_SERVER` | `acrNameOut` / `acrLoginServer` |
| infra | `dev` env secret | `AZURE_CLIENT_ID` | `idDeployDevClientId` |
| infra | `prod` env secret | `AZURE_CLIENT_ID` | `idDeployProdClientId` |
| infra | repo secret | `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` | `tenantId` / `subscriptionId` |

The per-environment `AZURE_CLIENT_ID` is what makes each deploy use its own
least-privilege identity.

> Note: the app runtime identities (`idAppDev/Prod`, by `*ResourceId`) are
> consumed later by the per-env app Bicep (Container App `userAssignedIdentities`).

---

## Refs

- Workload identity federation (GitHub → Azure): <https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-github>
- UAMI federated credentials: <https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-config-app-trust-managed-identity>
- Azure RBAC best practices: <https://learn.microsoft.com/en-us/azure/role-based-access-control/best-practices>
- Key Vault RBAC: <https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide>
- GitHub OIDC subject claims: <https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect>
