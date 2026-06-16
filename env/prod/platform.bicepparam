using '../../bicep/platform.bicep'

param environment = 'prod'

// Postgres admin password is read from Key Vault at deploy time by the deploy
// identity (Key Vault Secrets User). Seed it once per the bootstrap runbook.
param postgresAdminPassword = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-prod-rg',
  'vesperp4-prod-kv',
  'postgres-admin-password'
)
