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
param imageTag = '0.5.0'

// Admin password for this app's Postgres server, read from Key Vault at deploy
// time by the deploy identity (Key Vault Secrets User). Seeded per the runbook.
param postgresAdminPassword = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-prod-rg',
  'vesperp4-prod-kv',
  'portal-pg-admin-password'
)
