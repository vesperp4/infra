@description('Globally-unique ACR name (alphanumeric, 5-50 chars)')
param name string

@description('Azure region')
param location string

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    // No admin user: pulls/pushes go through managed-identity RBAC only.
    adminUserEnabled: false
  }
}

output id string = acr.id
output loginServer string = acr.properties.loginServer
output name string = acr.name
