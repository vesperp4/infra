targetScope = 'resourceGroup'

// =============================================================================
// Azure Static Web App for a site's web component. BYO deploy: the resource is
// created WITHOUT GitHub linkage (provider stays 'None'); content is pushed by
// the monorepo's deploy workflow using this app's deployment token.
//
// Custom domains: SUBDOMAINS (e.g. www.example.com) are codified here via
// `cname-delegation`, which Azure validates against an existing CNAME pointing
// at this app's defaultHostname — so they redeploy idempotently with no manual
// step. APEX/root domains are NOT declared here: they require `dns-txt-token`
// validation (a per-binding TXT token that can't be expressed declaratively),
// and Cloudflare apex CNAME-flattening hides the CNAME so cname-delegation
// can't see it either. Bind the apex out-of-band (`az staticwebapp hostname
// set --validation-method dns-txt-token` + a TXT record). See the param file.
// =============================================================================

@description('Static Web App resource name')
param name string

@description('Azure region — SWA is only offered in a subset of regions (e.g. eastus2, centralus, westus2, westeurope, eastasia)')
param location string

@allowed(['Free', 'Standard'])
param sku string = 'Free'

@description('''Subdomain custom domains to bind, each `{ name: '<fqdn>' }`. Each
name must already have a CNAME → this app's defaultHostname in DNS (validated at
deploy time via cname-delegation). Apex domains are bound out-of-band; see the
module header.''')
param customDomains array = []

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

// Subdomain bindings. cname-delegation self-validates against the existing
// CNAME, so this is idempotent against an already-bound domain.
resource domains 'Microsoft.Web/staticSites/customDomains@2023-12-01' = [
  for d in customDomains: {
    parent: swa
    name: d.name
    properties: {
      validationMethod: 'cname-delegation'
    }
  }
]

output name string = swa.name
output defaultHostname string = swa.properties.defaultHostname
