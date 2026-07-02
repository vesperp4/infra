targetScope = 'resourceGroup'

// =============================================================================
// tv-packager: a manual-trigger Container Apps Job that packages one uploaded
// recording (MP4 in the `recordings` container) into the channel's fixed HLS
// rendition ladder in the `hls` container. Pay-per-execution; nothing always-on.
//
// Started per asset with env overrides:
//   az containerapp job start -n tv-packager-<env> -g vesperp4-<env>-rg \
//     --env-vars INPUT_URL=<blob-url> OUTPUT_URL=<hls-container-url> ASSET_ID=<id>
//
// Blob access is the app identity via azcopy MSI login; the Storage Blob Data
// Contributor grant on the TV storage account is applied OUT-OF-BAND (see
// tv-engine.bicep outputs — the deploy identity can't write role assignments).
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

@description('App/image name (matches apps/<env>/<appGroup>/<appName>.bicepparam and the ACR repo)')
param appName string = 'tv-packager'

@description('App group — locates the shared TV storage account (created by tv-engine.bicep)')
param appGroup string = 'tv'

@description('Image tag to deploy — bumped by the monorepo release pipeline')
param imageTag string

param location string = resourceGroup().location

@description('Shared resource group holding the ACR and runtime identities')
param sharedResourceGroupName string = 'vesperp4-shared-rg'

param acrName string = 'vesperp4acr'

@description('Runtime managed identity name (ACR pull + blob data plane)')
param appIdentityName string = 'id-app-${environment}'

@description('ffmpeg needs headroom; the job only bills while running')
param cpu string = '2'
param memory string = '4Gi'

@description('Max seconds per packaging run (long recordings take a while at veryfast)')
param replicaTimeoutSeconds int = 5400

var caeName = 'vesperp4-${environment}-cae'
var jobName = '${appName}-${environment}'
var storageName = 'vesperp4${appGroup}${environment}st'

// ---------- Shared resources ----------

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

// Created by tv-engine.bicep (the tv group's anchor stack).
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

// ---------- The packaging job ----------

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: jobName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: replicaTimeoutSeconds
      replicaRetryLimit: 1
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: appIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'packager'
          image: '${acr.properties.loginServer}/${appName}:${imageTag}'
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          // INPUT_URL / ASSET_ID are supplied per execution (job start
          // --env-vars); OUTPUT_URL defaults to this env's hls container.
          env: [
            { name: 'AZCOPY_AUTO_LOGIN_TYPE', value: 'MSI' }
            { name: 'AZCOPY_MSI_CLIENT_ID', value: appIdentity.properties.clientId }
            { name: 'OUTPUT_URL', value: '${storage.properties.primaryEndpoints.blob}hls' }
          ]
        }
      ]
    }
  }
}

output jobName string = job.name
