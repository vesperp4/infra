using '../../../bicep/app.bicep'

param environment = 'dev'

// This app group's own component identity (drives the Container App name, the
// ACR repo, the DB server name `portal-dev-<region>-db`, and the database name).
param appName = 'portal-api'
param appGroup = 'portal'
param databaseName = 'portal'

// This subscription is offer-restricted for Postgres Flexible Server in eastus2
// AND eastus; centralus is the nearest confirmed-available region. Compute stays
// in eastus2; the DB lives in centralus.
param postgresLocation = 'centralus'

// Bumped automatically by the monorepo release pipeline (patch-bicepparam.sh).
param imageTag = '0.6.0'

// Admin password for this app's Postgres server, read from Key Vault at deploy
// time by the deploy identity (Key Vault Secrets User). Seeded per the runbook.
param postgresAdminPassword = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-dev-rg',
  'vesperp4-dev-kv',
  'portal-pg-admin-password'
)

// Custom domain (api.portal.dev.vesperp4.com) + Microsoft OIDC sign-in — pinned
// AFTER the out-of-band runbook (README §"portal-api custom domain + Entra app
// registration (out-of-band)") completes for this env; same two-phase pattern
// as the SWA custom domains. Uncomment and fill in with the recorded values:
// param apiCustomDomainCertificateId = '<managed-cert resource ID from the runbook>'
// param oidcClientId = '<appId of the "VESPER P4 Member Portal" app registration>'
// param oidcTenantId = '<PUPR tenant GUID — see the runbook, NOT the vesperp4 tenant>'
