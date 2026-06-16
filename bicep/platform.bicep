targetScope = 'resourceGroup'

// =============================================================================
// Per-environment shared platform: the Container Apps environment (and its Log
// Analytics workspace) that ALL apps in this environment share. Compute only —
// each app brings its own PostgreSQL server + database (see app.bicep).
//
// Deployed per environment (dev/prod) into that env's resource group. Rarely
// changes — not part of the per-app image-bump pipeline.
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

param location string = resourceGroup().location

var caeName = 'vesperp4-${environment}-cae'
var lawName = 'vesperp4-${environment}-log'

module cae 'modules/containerapps-env.bicep' = {
  name: 'containerapps-env'
  params: {
    name: caeName
    location: location
    logAnalyticsName: lawName
  }
}

output containerAppsEnvironmentName string = cae.outputs.name
