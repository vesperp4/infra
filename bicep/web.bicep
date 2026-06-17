targetScope = 'resourceGroup'

// =============================================================================
// Per-app web component: an Azure Static Web App that hosts a site's frontend.
// Deployed by the same image-bump/deploy pipeline as the API components, but it
// has no Postgres server and no DB role — the deploy workflow detects the
// absence of a postgresServerName output and skips the onboarding step.
//
// Content is NOT shipped here: the monorepo's deploy workflow uploads the built
// static output to this resource using its deployment token.
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

@description('Component name — matches apps/<env>/<appGroup>/<appName>.bicepparam')
param appName string = 'mainsite-web'

@description('Region for the Static Web App (region-restricted service)')
param location string = 'eastus2'

@allowed(['Free', 'Standard'])
param sku string = 'Free'

@description('Subdomain custom domains to bind (e.g. www). See staticwebapp.bicep; apex is bound out-of-band.')
param customDomains array = []

var swaName = '${appName}-${environment}'

module web 'modules/staticwebapp.bicep' = {
  name: '${appName}-swa'
  params: {
    name: swaName
    location: location
    sku: sku
    customDomains: customDomains
  }
}

output staticWebAppName string = web.outputs.name
output defaultHostname string = web.outputs.defaultHostname
