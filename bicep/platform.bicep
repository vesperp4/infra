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

@description('''Full alerts-relay URL including its ?token=… , read from this env's
Key Vault in the .bicepparam. Empty (the default) creates no action group, which
in turn leaves every alert rule in app.bicep uncreated. Alerting is opt-in per
environment and turning it off is a one-line revert.''')
@secure()
param alertsRelayUrl string = ''

var caeName = 'vesperp4-${environment}-cae'
var lawName = 'vesperp4-${environment}-log'
var actionGroupName = 'vesperp4-${environment}-ag'

module cae 'modules/containerapps-env.bicep' = {
  name: 'containerapps-env'
  params: {
    name: caeName
    location: location
    logAnalyticsName: lawName
  }
}

// Alert delivery for this environment. Named here rather than in app.bicep so
// every app in the env shares one route out to Slack.
module alerts 'modules/alerts-action-group.bicep' = if (!empty(alertsRelayUrl)) {
  name: 'alerts-action-group'
  params: {
    name: actionGroupName
    shortName: 'p4${environment}'
    relayUrl: alertsRelayUrl
  }
}

output containerAppsEnvironmentName string = cae.outputs.name

// Safe-dereferenced off the conditional module rather than derived from
// `alertsRelayUrl`: reading a secure param in an output trips the
// outputs-should-not-contain-secrets linter, even to produce a non-secret name.
@description('Set this as `alertsActionGroupName` in each app .bicepparam to switch its alert rules on; empty while alerting is off for this env.')
output actionGroupName string = alerts.?outputs.name ?? ''
