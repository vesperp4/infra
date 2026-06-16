@description('Globally-unique Key Vault name (3-24 chars)')
param name string

@description('Azure region')
param location string

@description('Entra tenant ID')
param tenantId string = tenant().tenantId

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    // RBAC data-plane authorization (no access policies); access is granted via
    // Key Vault Secrets User/Officer role assignments.
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    // TODO(hardening): restrict with a private endpoint + firewall for prod.
    publicNetworkAccess: 'Enabled'
  }
}

output id string = kv.id
output name string = kv.name
