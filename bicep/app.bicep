targetScope = 'resourceGroup'

// =============================================================================
// Per-app stack: this app's OWN PostgreSQL Flexible Server + database, plus its
// Container App on the shared per-env Container Apps environment (platform.bicep).
// Each app is fully isolated at the database-server level. Deployed by the
// image-bump pipeline — the monorepo pins `imageTag` per env in the .bicepparam.
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

@description('App/image name (matches apps/<env>/<appGroup>/<appName>.bicepparam and the ACR repo)')
param appName string = 'portal-api'

@description('App group — the site this component belongs to; names the shared DB server')
param appGroup string = 'portal'

@description('Image tag to deploy — bumped by the monorepo release pipeline')
param imageTag string

@description('Database name on the app server')
param databaseName string = 'portal'

param location string = resourceGroup().location

@description('Region for the Postgres Flexible Server — split out because some subscriptions are offer-restricted for Postgres in the compute region (e.g. eastus2)')
param postgresLocation string = location

@description('Shared resource group holding the ACR and runtime identities')
param sharedResourceGroupName string = 'vesperp4-shared-rg'

param acrName string = 'vesperp4acr'

@description('Runtime managed identity name (ACR pull + Entra DB token)')
param appIdentityName string = 'id-app-${environment}'

@description('Object ID of the Entra group made Postgres admin (passwordless)')
param adminsGroupObjectId string = '2642f52a-cec5-4c40-bbf5-2d3e8c51ad33'

@description('Built-in Postgres admin login (escape hatch; Entra auth is preferred)')
param postgresAdminLogin string = 'pgadmin'

@description('Postgres admin password — sourced from Key Vault in the .bicepparam')
@secure()
param postgresAdminPassword string

param postgresSkuName string = 'Standard_B1ms'

@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param postgresSkuTier string = 'Burstable'

param postgresStorageSizeGB int = 32

param minReplicas int = (environment == 'prod') ? 1 : 0
param maxReplicas int = (environment == 'prod') ? 3 : 1

var caeName = 'vesperp4-${environment}-cae'
// DB region is part of the server name: self-documenting, and collision-proof
// when the DB region differs from compute (Azure caches a name->region mapping
// in the RG, so a failed create in one region blocks recreating it in another).
var pgName = '${appGroup}-${environment}-${postgresLocation}-db'
var containerAppName = '${appName}-${environment}'

// ---------- Shared resources (bootstrap + platform.bicep) ----------

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: appIdentityName
  scope: resourceGroup(sharedResourceGroupName)
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
  scope: resourceGroup(sharedResourceGroupName)
}

// CI deploy identity — added as a Postgres Entra admin so the deploy workflow
// can onboard the app's DB role (see scripts/onboard-app-db.sh).
resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-github-deploy-${environment}'
  scope: resourceGroup(sharedResourceGroupName)
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

// ---------- This app's dedicated PostgreSQL server + database ----------

module postgres 'modules/postgres.bicep' = {
  name: '${appGroup}-postgres'
  params: {
    name: pgName
    location: postgresLocation
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    databaseName: databaseName
    skuName: postgresSkuName
    skuTier: postgresSkuTier
    storageSizeGB: postgresStorageSizeGB
    aadAdminObjectId: adminsGroupObjectId
    aadAdminName: 'infra-admins'
    aadAdminPrincipalType: 'Group'
    deployAdminObjectId: deployIdentity.properties.principalId
    deployAdminName: deployIdentity.name
  }
}

// ---------- The Container App ----------

module app 'modules/containerapp.bicep' = {
  name: '${appName}-containerapp'
  params: {
    name: containerAppName
    location: location
    environmentId: cae.id
    registryServer: acr.properties.loginServer
    image: '${acr.properties.loginServer}/${appName}:${imageTag}'
    appIdentityResourceId: appIdentity.id
    appIdentityClientId: appIdentity.properties.clientId
    pgHost: postgres.outputs.fqdn
    // Entra role name the dev team creates for the app identity (see README).
    pgUser: appIdentityName
    pgDatabase: postgres.outputs.databaseName
    minReplicas: minReplicas
    maxReplicas: maxReplicas
  }
}

output apiUrl string = 'https://${app.outputs.fqdn}'
output postgresFqdn string = postgres.outputs.fqdn
output postgresServerName string = postgres.outputs.name
output databaseName string = postgres.outputs.databaseName
