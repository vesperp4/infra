@description('Flexible Server name (globally unique, 3-63 lowercase alphanumeric/hyphen)')
param name string

@description('Azure region')
param location string

@description('PostgreSQL major version')
param version string = '17'

@description('Compute SKU name (e.g. Standard_B1ms)')
param skuName string = 'Standard_B1ms'

@description('Compute SKU tier')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'Burstable'

@description('Storage size in GB')
param storageSizeGB int = 32

@description('Built-in admin login (escape hatch; passwordless Entra auth is preferred)')
param administratorLogin string

@description('Admin password (sourced from Key Vault in the .bicepparam)')
@secure()
param administratorLoginPassword string

@description('Object ID of the Entra principal made server admin (passwordless)')
param aadAdminObjectId string

@description('Display name of the Entra admin principal')
param aadAdminName string

@description('Type of the Entra admin principal')
@allowed(['User', 'Group', 'ServicePrincipal'])
param aadAdminPrincipalType string = 'Group'

param tenantId string = tenant().tenantId

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: name
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: version
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    // Passwordless-first: Entra auth is the preferred path; password auth stays
    // enabled as an escape hatch and can be set to 'Disabled' to harden.
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
      tenantId: tenantId
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    // TODO(hardening): move to private access (VNet/delegated subnet) for prod.
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Entra administrator — humans/admins (or an app principal) authenticate via
// token instead of a password. The dev team grants the app's managed identity a
// least-privilege role from here (see README: pgaadauth_create_principal).
resource aadAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: pg
  name: aadAdminObjectId
  properties: {
    principalType: aadAdminPrincipalType
    principalName: aadAdminName
    tenantId: tenantId
  }
}

// Allow access from Azure services (Container Apps egress) over public networking.
// Per-app databases are created by each app's own stack (see modules/database.bicep).
resource allowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pg
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
  dependsOn: [aadAdmin]
}

output fqdn string = pg.properties.fullyQualifiedDomainName
output name string = pg.name
