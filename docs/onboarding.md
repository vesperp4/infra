# Onboarding — Start Here (infra)

Welcome to the **infrastructure** side of Vesper P4. 👋

This repo is different from the website repo. The website (`mono`) is about *what the site looks
like and does*. **This repo is about the actual cloud machines the site runs on** — the servers,
the database, the networking, the permissions. It's called **infrastructure**.

This guide assumes you've already done some coding and can use a terminal and Git (if not, start
with the [website onboarding guide](https://github.com/vesperp4/mono/blob/main/docs/onboarding.md)
first — it teaches those basics). What it does **not** assume is that you know anything about
"the cloud," Azure, or Infrastructure-as-Code. We'll build that up from zero.

If a word is unfamiliar, check the [Glossary](./glossary.md).

> ## ⚠️ Read this before touching anything
>
> Unlike the website repo, **the things described here are real and cost real money.** A change
> merged here can create, modify, or *delete* live cloud resources — including the production
> database. There is no "it's just my laptop" safety net for applied changes.
>
> **You will not break anything by reading, branching, or opening a Pull Request.** Those are
> safe — encouraged, even. The danger is only when a change is *applied* to the cloud, and that
> happens through reviewed, approved automation (and for production, a required human approval).
> So: explore freely, but never run `az` commands that change/delete resources, or merge a PR,
> without a maintainer's say-so. When unsure, ask first.

---

## 1. What is "the cloud," really?

"The cloud" just means **someone else's computers in a data center that you rent over the
internet** instead of buying and running your own. We rent ours from **Microsoft Azure**.

Instead of buying a physical server, plugging in a hard drive, and installing a database, you ask
Azure: "give me a small server here, a database there, and connect them." Azure creates those
**resources** and bills us for what we use.

The pieces we rent from Azure:

```
        Visitor → vesperp4.com
                     │
   ┌─────────────────┴───────────────────────────────────┐
   │  Azure (Microsoft's cloud)                           │
   │                                                      │
   │   Static Web App ......... hosts the frontend (web)  │
   │   Container App .......... runs the backend (api)    │
   │   PostgreSQL server ...... the database (db)         │
   │   Container Registry ..... stores the api's image    │
   │   Key Vault .............. stores secrets/passwords  │
   │   Managed Identities ..... "who is allowed to do     │
   │                             what" — no passwords      │
   └──────────────────────────────────────────────────────┘
```

Each of those is an Azure **resource**. This repo's whole job is to describe those resources in
code so they can be created consistently and changed safely.

---

## 2. What is "Infrastructure-as-Code"?

You *could* create all those resources by clicking buttons in the Azure web portal. People used to
do that. The problem: nobody remembers exactly what they clicked, you can't review it, and you
can't reliably recreate it.

**Infrastructure-as-Code (IaC)** means writing the cloud setup down as files in a Git repo. The
benefits are the same as for any code:

- **Reviewable** — changes go through Pull Requests, just like the website.
- **Repeatable** — the same files produce the same setup every time.
- **Versioned** — you can see who changed what, and roll back.

We write our IaC in a language called **Bicep** (Azure's own IaC language). A Bicep file is a
*description* of resources — "I want a PostgreSQL server named X, in region Y, of size Z" — and
Azure makes reality match the description.

There are two kinds of files you'll see:

- **`.bicep`** — a *template*: the reusable blueprint ("an app needs a database and a container").
- **`.bicepparam`** — *parameters*: the specific values for one case ("this app is `mainsite`, in
  `dev`, using image tag `0.2.2`"). One template, many param files.

You never run these by hand in normal work — **GitHub Actions applies them for you** when a change
is merged.

---

## 3. The mental model: bootstrap → platform → apps

Our infrastructure is built in three layers, from most-foundational to most-frequently-changed.
Understanding these three boxes is 80% of understanding this repo.

```
┌──────────────────────────────────────────────────────────────┐
│ 1. BOOTSTRAP   (bootstrap/)        Built ONCE, by an admin.   │
│    The foundation: resource groups, the container registry,   │
│    Key Vaults, and the identities + permissions that let      │
│    automation deploy everything else. Rarely touched.         │
└──────────────────────────────────────────────────────────────┘
                          │ everything below relies on it
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ 2. PLATFORM   (bicep/platform.bicep)   One per environment.   │
│    The shared "compute substrate" — the Container Apps        │
│    environment where backends run. Rarely changes.            │
└──────────────────────────────────────────────────────────────┘
                          │ apps run on top of it
                          ▼
┌──────────────────────────────────────────────────────────────┐
│ 3. APPS   (apps/<env>/<group>/<component>.bicepparam)         │
│    The actual services. This is what changes often — e.g.     │
│    deploying a new version of the backend, or adding a app.   │
└──────────────────────────────────────────────────────────────┘
```

And **environments**: we run two parallel copies of layers 2–3:

- **`dev`** — for testing. Safe-ish to experiment with (still real, still costs money).
- **`prod`** — the real thing behind vesperp4.com. Changes here require a human approval.

---

## 4. A tour of the repo

```
infra/
├── bootstrap/          Layer 1 — one-time foundation (admin-run).
│   ├── main.bicep      Resource groups, registry, Key Vaults, identities, permissions.
│   └── modules/        Smaller building blocks used by main.bicep.
│
├── bicep/              The reusable TEMPLATES (blueprints).
│   ├── platform.bicep  Layer 2 — the shared Container Apps environment.
│   ├── app.bicep       An "api" component: its own database + a Container App.
│   ├── web.bicep       A "web" component: an Azure Static Web App (no database).
│   └── modules/        postgres, containerapp, containerapps-env, staticwebapp.
│
├── platform/           PARAMETERS for the platform, one per env (dev/prod).
│
├── apps/               Layer 3 — PARAMETERS for each app, grouped by env.
│   ├── dev/mainsite/   mainsite-api.bicepparam, mainsite-web.bicepparam
│   └── prod/mainsite/  same, for production
│
├── scripts/
│   └── onboard-app-db.sh   Grants the app permission to use its database (run by CI).
│
└── .github/workflows/
    ├── deploy-platform.yaml   Applies the platform layer.
    └── deploy-app.yaml        Applies app stacks + runs the DB-onboard script.
```

The pattern to internalize: **`bicep/*.bicep` are the blueprints; `apps/**` and `platform/*` are
the filled-in values; the workflows in `.github/` apply them.**

---

## 5. How a change actually reaches the cloud

Nobody types deploy commands against production. Here's the real flow for, say, shipping a new
version of the backend:

```
The website repo builds a new api image and pushes it to the registry
                          │
                          ▼
It opens a PR HERE that bumps the imageTag in apps/dev/mainsite/mainsite-api.bicepparam
                          │
                  (review + merge)
                          ▼
Merging triggers deploy-app.yaml, which:
   1. logs into Azure with a passwordless federated identity (no stored secrets)
   2. runs the Bicep → Azure updates the dev resources to match
   3. runs onboard-app-db.sh → grants the app access to its database
                          │
                          ▼
        Promotion to prod is a separate, approval-gated step
```

The key safety properties:

- **No secrets are stored** — automation logs in via *OIDC federated identity* (a trust
  relationship between GitHub and Azure), not a saved password.
- **Least privilege** — the automation can only touch what it's been granted.
- **Prod is gated** — a production deploy waits for a required human reviewer.

A fuller pipeline picture is in the website repo's
[`docs/cicd-pipeline.md`](https://github.com/vesperp4/mono/blob/main/docs/cicd-pipeline.md).

---

## 6. Setting up locally (to read and lint, not to deploy)

You don't need cloud access just to work on the files. Setup mirrors the website repo and uses
[**mise**](https://mise.jdx.dev) to install the right tool versions (the Azure CLI, Bicep, etc.):

```bash
git clone https://github.com/vesperp4/infra.git
cd infra
mise trust && mise install      # installs az, bicep, and friends from mise.toml
```

**`mise` is the front door** — run `mise tasks` to see everything. The two you'll use most:

```bash
mise run lint     # compile every Bicep + param file (no cloud access needed)
mise run check    # lint + workflow lint + shell-script lint — run before pushing
```

Run `mise run check` before opening a PR. It catches syntax errors and bad references locally. It
does **not** deploy anything — it just checks the files make sense.

> **Do I need an Azure login?** Only to *apply* changes, which you normally won't do by hand.
> `mise run lint` / `mise run check` work with no Azure account at all. If you ever do need to log in to look around,
> a maintainer will grant you read access and walk you through `az login` — but **never run
> `az` commands that create, change, or delete resources** unless a maintainer asks you to.

---

## 7. Making a change

The Git workflow is identical to the website repo: branch off `main`, commit with a Conventional
Commit message, push, open a Pull Request, get one approval, merge. (See the website repo's
[onboarding §7](https://github.com/vesperp4/mono/blob/main/docs/onboarding.md) if that flow is new
to you.)

The most common infra change is **adding a new component**. You don't edit any workflow — you just
drop in a new param file and the automation discovers it by convention:

- **A new backend (api):** add `apps/dev/<group>/<component>.bicepparam` (and the `prod`
  counterpart) using `'../../../bicep/app.bicep'`. It gets its own PostgreSQL database. You'll also
  need a maintainer to seed its database password into Key Vault first.
- **A new frontend (web):** same, but using `'../../../bicep/web.bicep'`. It's a Static Web App
  with no database.

The README's ["Adding a new component"](../README.md#adding-a-new-component) section has the exact
details. Always `mise run check` before pushing.

---

## 8. When something looks wrong

- **`mise run lint` fails.** Read the error — Bicep points at the file and line. Usually a typo or
  a referenced value that doesn't exist.
- **A deploy failed in GitHub Actions.** Open the failed run, expand the red step. Common causes:
  a Key Vault secret wasn't seeded, or an image tag doesn't exist in the registry yet.
- **You think a real resource is misconfigured.** Don't "fix" it by clicking in the Azure portal —
  that makes reality drift from the code. Fix the Bicep, open a PR. The repo is the source of
  truth.
- **Anything involving production, deletion, or money.** Stop and ask a maintainer. Always.

---

## 9. Where to go next

- [**Glossary**](./glossary.md) — plain-English definitions of every Azure/IaC term here.
- [**README.md**](../README.md) — the technical reference: layout, conventions, the auth model.
- [**bootstrap/README.md**](../bootstrap/README.md) — why the foundation layer is built the way it
  is (identities, permissions, break-glass).
- The website repo's
  [**cicd-pipeline.md**](https://github.com/vesperp4/mono/blob/main/docs/cicd-pipeline.md) — the
  end-to-end build-and-deploy pipeline that drives this repo.

Welcome aboard. Read first, ask questions, and treat the cloud with respect. 🛡️
