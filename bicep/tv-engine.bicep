targetScope = 'resourceGroup'

// =============================================================================
// TV channel core stack: the tv app group's media storage (recordings + public
// HLS) and the tv-engine Container App — an Eyevinn Channel Engine that
// stitches the 24/7 linear channel from HLS manifests (no transcoding; a
// fraction of a vCPU). Schedule comes from the TV Sanity project; live slots
// point at Cloudflare Stream Live playlists. See monorepo docs/tv-architecture.md.
//
// No Postgres, no ACS — this stack is intentionally not app.bicep. The playout
// session is stateful, so replicas are pinned to exactly 1 (min = max).
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

@description('App/image name (matches apps/<env>/<appGroup>/<appName>.bicepparam and the ACR repo)')
param appName string = 'tv-engine'

@description('App group — names the shared TV storage account')
param appGroup string = 'tv'

@description('Image tag to deploy — bumped by the monorepo release pipeline')
param imageTag string

param location string = resourceGroup().location

@description('Shared resource group holding the ACR and runtime identities')
param sharedResourceGroupName string = 'vesperp4-shared-rg'

param acrName string = 'vesperp4acr'

@description('Runtime managed identity name (ACR pull; also the packager blob identity)')
param appIdentityName string = 'id-app-${environment}'

@description('TV Sanity project id (public read). Empty => engine starts with schedule queries disabled (slate only). TODO: set once the Sanity project exists.')
param sanityProjectId string = ''

param sanityDataset string = 'production'

@description('"Be right back" HLS master playlist used on schedule gaps/errors. Empty only for bring-up; set before the channel is considered live.')
param slateHlsUrl string = ''

// Dev channel runs lean; prod gets the standard small footprint.
param cpu string = (environment == 'prod') ? '0.5' : '0.25'
param memory string = (environment == 'prod') ? '1Gi' : '0.5Gi'

var caeName = 'vesperp4-${environment}-cae'
var containerAppName = '${appName}-${environment}'
// Storage name: lowercase alphanumeric, <=24 chars, globally unique.
var storageName = 'vesperp4${appGroup}${environment}st'

// ---------- Shared resources (bootstrap + platform.bicep) ----------

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

// ---------- TV media storage (shared by tv-engine + tv-packager) ----------

module storage 'modules/storage.bicep' = {
  name: '${appGroup}-storage'
  params: {
    name: storageName
    location: location
    // '*' until the real player origins are locked in (vesperp4.tv + dev host);
    // HLS content is public-read anyway, so CORS here is not a security boundary.
    corsAllowedOrigins: ['*']
  }
}

// ---------- The Channel Engine Container App ----------

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
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
          name: 'engine'
          image: '${acr.properties.loginServer}/${appName}:${imageTag}'
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: concat(
            [
              { name: 'PORT', value: '8080' }
              { name: 'SANITY_DATASET', value: sanityDataset }
            ],
            empty(sanityProjectId) ? [] : [
              { name: 'SANITY_PROJECT_ID', value: sanityProjectId }
            ],
            empty(slateHlsUrl) ? [] : [
              { name: 'SLATE_HLS_URL', value: slateHlsUrl }
            ]
          )
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/'
                port: 8080
              }
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 8080
              }
              periodSeconds: 10
            }
          ]
        }
      ]
      // Stateful playout session: exactly one replica, always on.
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output apiUrl string = 'https://${app.properties.configuration.ingress.fqdn}'
output containerAppName string = app.name
output storageAccountName string = storage.outputs.name
output hlsEndpoint string = '${storage.outputs.blobEndpoint}hls'
// Out-of-band RBAC grant (deploy identity can't write role assignments) — the
// packager job writes HLS packages with the app identity via azcopy MSI:
//   az role assignment create --assignee <id-app-<env> clientId> \
//     --role "Storage Blob Data Contributor" --scope <storageAccountId>
output storageAccountId string = storage.outputs.id
