using '../../bicep/app.bicep'

param environment = 'dev'

// Bumped automatically by the monorepo release pipeline (patch-bicepparam.sh).
param imageTag = '0.1.0'

// Admin password for this app's Postgres server, read from Key Vault at deploy
// time by the deploy identity (Key Vault Secrets User). Seeded per the runbook.
param postgresAdminPassword = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-dev-rg',
  'vesperp4-dev-kv',
  'vesperp4-api-pg-admin-password'
)
