# Glossary (infra)

Plain-English definitions for the cloud, Azure, and Infrastructure-as-Code terms in this repo. No
prior cloud knowledge assumed. Read [onboarding.md](./onboarding.md) first if you're new here.

For general coding/Git terms (branch, commit, Pull Request, CI/CD), see the website repo's
[glossary](https://github.com/vesperp4/mono/blob/main/docs/glossary.md). This page covers the
infra-specific vocabulary.

Terms are grouped by topic, then alphabetical within each group.

---

## Cloud & Azure basics

**Cloud** — Renting computers in someone else's data center over the internet instead of buying
and running your own. We rent from Microsoft Azure.

**Azure** — Microsoft's cloud platform. All our servers, databases, and networking live here.

**Resource** — A single thing you rent from Azure: a database, a server, a registry, a vault.
Everything in this repo describes resources.

**Resource Group (RG)** — A folder that groups related Azure resources together (e.g. everything
for the `dev` environment). Makes them easy to manage and delete as a unit.

**Subscription** — The Azure account that everything is billed to and lives under. Ours is
`1e180171-becb-40cd-a4a0-52351087be66`.

**Region** — The physical location of a data center (e.g. `eastus2`, `centralus`). Resources are
created in a specific region; some services are only offered in certain regions.

**Tenant** — The organization's identity boundary in Microsoft's directory (Entra ID). Defines who
the "company" is for login and permissions purposes.

**Environment** — A complete parallel copy of the system for a purpose. `dev` is for testing;
`prod` is the real, public one. Same templates, different parameter values.

---

## The resources we run

**Azure Static Web App (SWA)** — The service that hosts the **frontend** (`web`). It serves the
website's pages globally. Ours is deployed "bring-your-own": the website repo builds the site and
uploads it with a deploy token.

**Azure Container App** — The service that runs the **backend** (`api`) as a container. It scales
the running program up and down automatically.

**Container Apps Environment** — The shared "substrate" that Container Apps run inside. We have one
per environment; multiple apps share it. Built by `platform.bicep`.

**PostgreSQL Flexible Server** — The managed **database** service. "Flexible Server" is Azure's
deployment type that gives more control over size and configuration. Each app gets its own.

**Azure Container Registry (ACR)** — A private storage locker for **container images** (the
packaged backend). The website repo pushes new images here; Container Apps pull from it.

**Key Vault** — A secure store for **secrets** — passwords, keys, tokens. Code references a secret
by name instead of hard-coding the value. Our database admin passwords live here.

**Log Analytics** — Azure's service that collects logs and metrics, so you can see what the running
apps are doing. Stood up alongside the platform.

---

## Identity & security (who-can-do-what)

**Identity** — "Who" is making a request to Azure. Could be a person, or a piece of automation.
Azure checks an identity's permissions before allowing any action.

**Entra ID** — Microsoft's identity system (formerly "Azure Active Directory"). It's the directory
of users, groups, and machine identities, and the login system behind everything.

**Managed Identity** — A machine identity that Azure manages for you, with **no password to store
or leak**. Our backend uses one to prove who it is when talking to the database.

**Federated Identity / OIDC** — A trust relationship that lets GitHub Actions log into Azure
**without any stored secret**. Azure trusts tokens issued by GitHub for our specific repo. (OIDC =
"OpenID Connect," the standard that makes this work.)

**RBAC (Role-Based Access Control)** — Azure's permission system: you grant an identity a *role*
(like "can read secrets in this vault") scoped to specific resources. We follow **least
privilege** — grant only what's needed.

**Least privilege** — A security principle: give every identity the *minimum* permissions it needs,
and nothing more. Limits the damage if something is compromised.

**Passwordless auth** — Connecting to a service (here, the database) using a short-lived identity
token instead of a stored password. More secure because there's no password to steal.

**Secret** — A sensitive value (password, key, token) that must not appear in code. Stored in Key
Vault and referenced by name.

**Break-glass** — An emergency "in case everything else fails" access path (e.g. a kept-aside admin
login). Used only when normal access is broken.

---

## Infrastructure-as-Code & Bicep

**Infrastructure-as-Code (IaC)** — Describing cloud resources in version-controlled files instead
of clicking buttons in a portal. Makes the setup reviewable, repeatable, and rollback-able.

**Bicep** — Azure's language for writing IaC. A Bicep file *describes* the resources you want;
Azure makes reality match. Friendlier than the older JSON format (ARM).

**`.bicep` (template)** — The reusable blueprint — "an app needs a database and a container." Written
once, used for many apps.

**`.bicepparam` (parameters)** — The specific values plugged into a template for one case — "this
app is `mainsite`, in `dev`, image tag `0.2.2`." One template, many param files.

**Module** — A smaller, reusable Bicep file that a bigger template pulls in (e.g. a `postgres`
module used by `app.bicep`). Like a function for infrastructure.

**ARM / ARM template** — Azure Resource Manager, the underlying engine that actually creates
resources, and its older JSON file format. Bicep compiles down to ARM JSON. We gitignore the
compiled JSON.

**Deploy / Deployment** — Applying a Bicep template so Azure creates or updates resources to match
it.

**Drift** — When the real cloud resources no longer match what the code says (usually because
someone changed something by hand in the portal). Avoid it — always change the code, not the
portal.

**Idempotent** — A operation you can run repeatedly with the same end result and no harm. Our
deploys and the DB-onboard script are idempotent — re-running them is safe.

---

## Tooling & workflow

**Azure CLI (`az`)** — The command-line tool for talking to Azure. Installed via mise. Used by the
workflows to deploy, and by maintainers to inspect resources.

**mise** — The tool-version manager that installs the exact `az`, Bicep, and other versions this
repo needs (from `mise.toml`). Same tool the website repo uses.

**`mise run lint`** — Compiles every Bicep and param file locally to check validity. Catches errors
**without touching the cloud**. Run it before every PR.

**GitHub Actions** — The automation that applies our infrastructure. Workflows live in
`.github/workflows/`. `deploy-platform.yaml` applies the platform; `deploy-app.yaml` applies apps.

**Workflow** — A defined automation job (a YAML file) triggered by an event like "a PR merged to
`main`."

**SHA-pinned action** — Referencing a GitHub Action by its exact commit hash (not a moving tag) so
it can't change underneath us. A supply-chain safety measure; all our actions are pinned.

**Required reviewer / environment gate** — A GitHub setting that pauses a deploy until a named human
approves. Our `prod` environment uses this so production never deploys unattended.

---

## See also

- [onboarding.md](./onboarding.md) — the hand-holding walkthrough for this repo.
- [../README.md](../README.md) — the technical reference (layout, conventions, auth model).
- [../bootstrap/README.md](../bootstrap/README.md) — the foundation layer in depth.
- Website repo [glossary](https://github.com/vesperp4/mono/blob/main/docs/glossary.md) — general
  coding, Git, and web-stack terms.
