using '../../../bicep/app.bicep'

param environment = 'prod'

// This app group's own component identity (drives the Container App name, the
// ACR repo, the DB server name `portal-prod-<region>-db`, and the database name).
param appName = 'portal-api'
param appGroup = 'portal'
param databaseName = 'portal'

// This subscription is offer-restricted for Postgres Flexible Server in eastus2
// AND eastus; centralus is the nearest confirmed-available region. Compute stays
// in eastus2; the DB lives in centralus.
param postgresLocation = 'centralus'

// Bumped automatically by the prod-promotion workflow (patch-bicepparam.sh).
param imageTag = '0.8.2'

// Admin password for this app's Postgres server, read from Key Vault at deploy
// time by the deploy identity (Key Vault Secrets User). Seeded per the runbook.
param postgresAdminPassword = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-prod-rg',
  'vesperp4-prod-kv',
  'portal-pg-admin-password'
)

// Custom domain (api.portal.vesperp4.com) + Microsoft OIDC sign-in — pinned
// AFTER the out-of-band runbook (README §"portal-api custom domain + Entra app
// registration (out-of-band)") completes for this env; same two-phase pattern
// as the SWA custom domains. Uncomment and fill in with the recorded values:
param apiCustomDomainCertificateId = '/subscriptions/1e180171-becb-40cd-a4a0-52351087be66/resourceGroups/vesperp4-prod-rg/providers/Microsoft.App/managedEnvironments/vesperp4-prod-cae/managedCertificates/mc-vesperp4-prod--api-portal-vespe-6809'
param oidcClientId = 'aa2064af-8e60-40ab-8be8-28fa7ccd6ca1'
param oidcTenantId = '72b8c91b-4089-4b60-996f-922c73865584'
