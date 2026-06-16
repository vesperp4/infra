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
│   ├── main.bicepparam
│   └── modules/
└── (next) bicep/ + env/  Per-environment app resources (Postgres, Container Apps)
                          and the deploy workflow — added after bootstrap.
```

## Order of operations

1. **Bootstrap** the identity/foundation once (admin-run) — `bootstrap/README.md`.
2. **Wire GitHub** environments + secrets/variables from the bootstrap outputs.
3. **Per-env app resources** + `deploy.yaml` (next milestone) reconcile each
   environment from a pinned image tag, which the monorepo bumps on release.

## Conventions

- Region `eastus2`, subscription `1e180171-becb-40cd-a4a0-52351087be66`.
- Bicep mirrors the monorepo `iac/azure/bicep` style. Compiled JSON is gitignored.
- `mise run lint` compiles all Bicep locally (no deploy). `mise run bootstrap-whatif`
  previews against Azure (requires `az login`).

## Related

- Identity/foundation rationale: [`bootstrap/README.md`](./bootstrap/README.md)
- Human identity & access (groups, break-glass): monorepo `iac/azure/entra/`
- Pipeline overview: monorepo `docs/cicd-pipeline.md` and `docs/infra-repo-spec.md`
