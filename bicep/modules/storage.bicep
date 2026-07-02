targetScope = 'resourceGroup'

// =============================================================================
// Storage account for a media pipeline: private `recordings` container (source
// uploads) + public-read `hls` container (packaged renditions served to
// players, fronted by Cloudflare). CORS allows browser HLS fetches (hls.js
// requests segments cross-origin from the site domain).
//
// RBAC (e.g. Storage Blob Data Contributor for the packager job's identity) is
// granted OUT-OF-BAND — the CI deploy identity is RG Contributor only and
// cannot write role assignments. See the consuming stack's outputs/README.
// =============================================================================

@description('Storage account name (3-24 lowercase alphanumeric, globally unique)')
@minLength(3)
@maxLength(24)
param name string

param location string

@description('Origins allowed to fetch blobs from the browser (player origins)')
param corsAllowedOrigins array = ['*']

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    // Required for the `hls` container's anonymous blob reads; `recordings`
    // stays private (container-level ACLs below).
    allowBlobPublicAccess: true
    allowSharedKeyAccess: false // identity-only data plane (azcopy MSI)
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: corsAllowedOrigins
          allowedMethods: ['GET', 'HEAD', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

resource recordings 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'recordings'
  properties: {
    publicAccess: 'None'
  }
}

resource hls 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'hls'
  properties: {
    publicAccess: 'Blob' // anonymous read per-blob; no container listing
  }
}

output name string = storage.name
output id string = storage.id
output blobEndpoint string = storage.properties.primaryEndpoints.blob
