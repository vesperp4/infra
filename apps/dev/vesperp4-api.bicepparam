using '../../bicep/app.bicep'

param environment = 'dev'

// This subscription is offer-restricted for Postgres Flexible Server in eastus2
// AND eastus; centralus is the nearest confirmed-available region. Compute stays
// in eastus2; the DB lives in centralus.
param postgresLocation = 'centralus'

// Bumped automatically by the monorepo release pipeline (patch-bicepparam.sh).
param imageTag = '0.2.1'

// Admin password for this app's Postgres server, read from Key Vault at deploy
// time by the deploy identity (Key Vault Secrets User). Seeded per the runbook.
param postgresAdminPassword = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-dev-rg',
  'vesperp4-dev-kv',
  'vesperp4-api-pg-admin-password'
)
