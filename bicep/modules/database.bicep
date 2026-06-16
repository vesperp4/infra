@description('Name of the existing shared Flexible Server (same resource group)')
param serverName string

@description('Database name for this app')
param databaseName string

// Reference the shared per-environment server; each app owns only its database.
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

output name string = db.name
