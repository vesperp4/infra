targetScope = 'resourceGroup'

// =============================================================================
// Azure Static Web App for a site's web component. BYO deploy: the resource is
// created WITHOUT GitHub linkage (provider stays 'None'); content is pushed by
// the monorepo's deploy workflow using this app's deployment token. Custom
// domains are attached out-of-band (DNS validation at an external registrar).
// =============================================================================

@description('Static Web App resource name')
param name string

@description('Azure region — SWA is only offered in a subset of regions (e.g. eastus2, centralus, westus2, westeurope, eastasia)')
param location string

@allowed(['Free', 'Standard'])
param sku string = 'Free'

resource swa 'Microsoft.Web/staticSites@2023-12-01' = {
  name: name
  location: location
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    // No repositoryUrl/branch/token: keeps the app unlinked from GitHub so the
    // BYO token-upload workflow (deploy) is the single source of content.
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

output name string = swa.name
output defaultHostname string = swa.properties.defaultHostname
