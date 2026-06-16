targetScope = 'resourceGroup'

// =============================================================================
// Per-environment shared platform: the PostgreSQL Flexible Server and the
// Container Apps environment that ALL apps in this environment share. Each app
// adds its own database + Container App via its own stack (app.bicep).
//
// Deployed per environment (dev/prod) into that env's resource group. Rarely
// changes — not part of the per-app image-bump pipeline.
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

param location string = resourceGroup().location

@description('Built-in Postgres admin login (escape hatch; Entra auth is preferred)')
param postgresAdminLogin string = 'pgadmin'

@description('Postgres admin password — sourced from Key Vault in the .bicepparam')
@secure()
param postgresAdminPassword string

param postgresSkuName string = 'Standard_B1ms'

@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param postgresSkuTier string = 'Burstable'

param postgresStorageSizeGB int = 32

@description('Object ID of the Entra group made Postgres admin (passwordless)')
param adminsGroupObjectId string = '2642f52a-cec5-4c40-bbf5-2d3e8c51ad33'

var pgName = 'vesperp4-${environment}-pg'
var caeName = 'vesperp4-${environment}-cae'
var lawName = 'vesperp4-${environment}-log'

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    name: pgName
    location: location
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    skuName: postgresSkuName
    skuTier: postgresSkuTier
    storageSizeGB: postgresStorageSizeGB
    aadAdminObjectId: adminsGroupObjectId
    aadAdminName: 'infra-admins'
    aadAdminPrincipalType: 'Group'
  }
}

module cae 'modules/containerapps-env.bicep' = {
  name: 'containerapps-env'
  params: {
    name: caeName
    location: location
    logAnalyticsName: lawName
  }
}

output postgresServerName string = postgres.outputs.name
output postgresFqdn string = postgres.outputs.fqdn
output containerAppsEnvironmentName string = cae.outputs.name
