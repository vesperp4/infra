targetScope = 'resourceGroup'

// =============================================================================
// Per-app stack: one Container App + its own database on the shared per-env
// PostgreSQL server (see platform.bicep). Deployed by the image-bump pipeline —
// the monorepo pins `imageTag` per environment in env/<env>/<app>.bicepparam.
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

@description('App/image name (matches env/<env>/<appName>.bicepparam and the ACR repo)')
param appName string = 'vesperp4-api'

@description('Image tag to deploy — bumped by the monorepo release pipeline')
param imageTag string

@description('Database name for this app on the shared server')
param databaseName string = 'vesperp4_api'

param location string = resourceGroup().location

@description('Shared resource group holding the ACR and runtime identities')
param sharedResourceGroupName string = 'vesperp4-shared-rg'

param acrName string = 'vesperp4acr'

@description('Runtime managed identity name (ACR pull + Entra DB token)')
param appIdentityName string = 'id-app-${environment}'

param minReplicas int = (environment == 'prod') ? 1 : 0
param maxReplicas int = (environment == 'prod') ? 3 : 1

var pgServerName = 'vesperp4-${environment}-pg'
var caeName = 'vesperp4-${environment}-cae'
var containerAppName = '${appName}-${environment}'

// ---------- Shared resources (created by bootstrap / platform.bicep) ----------

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: appIdentityName
  scope: resourceGroup(sharedResourceGroupName)
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
  scope: resourceGroup(sharedResourceGroupName)
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

// ---------- This app's database on the shared server ----------

module database 'modules/database.bicep' = {
  name: '${appName}-database'
  params: {
    serverName: pgServerName
    databaseName: databaseName
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
    pgHost: '${pgServerName}.postgres.database.azure.com'
    // Entra role name the dev team creates for the app identity (see README).
    pgUser: appIdentityName
    pgDatabase: database.outputs.name
    minReplicas: minReplicas
    maxReplicas: maxReplicas
  }
}

output apiUrl string = 'https://${app.outputs.fqdn}'
