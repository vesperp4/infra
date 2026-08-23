// =============================================================================
// Observability for one app: ACS diagnostic logs, plus the log-query alerts that
// close the gap the 2026-08-19 portal triage exposed.
//
// The gap, in one sentence: the API sends transactional mail fire-and-forget
// behind a fixed 202 (deliberately: it closes an account-enumeration oracle),
// so a completely broken mail path is externally indistinguishable from a
// healthy API. `/health` stayed green, every probe returned 200, and no user
// could complete signup. The ACS resource had NO diagnostic settings at all, so
// "was this message delivered" was unanswerable after the fact.
//
// Everything here is additive and off by default where it can break a deploy:
//   - ACS diagnostics: on by default. Additive, cheap, and the whole point.
//   - Alert rules: created only when `actionGroupId` is supplied.
//   - The ACS delivery-status rule: off until its query is confirmed against a
//     workspace that actually has rows (see its param).
// =============================================================================

@description('Log Analytics workspace resource ID that backs the queries')
param workspaceId string

@description('Region for the alert rules; must be the workspace region')
param location string

@description('Action group to notify. Empty (the default) creates no alert rules at all.')
param actionGroupId string = ''

@description('ACS resource name in this resource group, e.g. portal-prod-acs')
param acsName string

@description('Container App name whose console logs are queried, e.g. portal-api-prod')
param containerAppName string

@description('Send ACS diagnostic logs to Log Analytics. Additive; there is no reason to turn this off.')
param acsDiagnosticsEnabled bool = true

@description('''Alert when ACS reports a non-delivered message. Off by default: the
ACSEmailStatusUpdateOperational table only exists once diagnostics have been on
long enough to emit rows, and Azure validates the query at deploy time, so
enabling it too early fails the deployment. Turn on after confirming in the
workspace:
  ACSEmailStatusUpdateOperational | take 10''')
param acsDeliveryAlertEnabled bool = false

var alertsEnabled = !empty(actionGroupId)

resource acs 'Microsoft.Communication/communicationServices@2023-04-01' existing = {
  name: acsName
}

// `allLogs` rather than a hand-listed set of categories: ACS has added email
// categories over time, and a category name that does not exist is a deploy
// error rather than a no-op.
resource acsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (acsDiagnosticsEnabled) {
  name: 'to-log-analytics'
  scope: acs
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

// The app already logs this line and nothing was listening:
//   tracing::error!(target: "email", …, "verification email send failed")
// Matching on "send failed" rather than the full sentence also catches the
// magic-link path, which logs its own variant.
resource emailSendFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (alertsEnabled) {
  name: '${containerAppName}-email-send-failed'
  location: location
  properties: {
    displayName: '${containerAppName}: transactional email send failed'
    description: 'The API logged a failed mail send. Signup and magic-link sign-in are silently broken for the affected users; the endpoints still answer 202.'
    severity: 1
    enabled: true
    scopes: [workspaceId]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: 'ContainerAppConsoleLogs_CL | where ContainerAppName_s == "${containerAppName}" | where Log_s has "send failed"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
  }
}

// Entra returned access_denied and interaction_required to the OIDC callback on
// consecutive days in August 2026 and nobody noticed until a triage went looking.
// PUPR owns the tenant, so these are usually a consent or conditional-access
// change on their side, and worth knowing about the day it happens.
resource oidcCallbackErrors 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (alertsEnabled) {
  name: '${containerAppName}-oidc-callback-error'
  location: location
  properties: {
    displayName: '${containerAppName}: OIDC callback returned an error'
    description: 'Entra returned an error to the OIDC callback. Microsoft SSO sign-in is failing; the magic-link path may still work.'
    severity: 2
    enabled: true
    scopes: [workspaceId]
    evaluationFrequency: 'PT30M'
    windowSize: 'PT30M'
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: 'ContainerAppConsoleLogs_CL | where ContainerAppName_s == "${containerAppName}" | where Log_s has "OIDC callback"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
  }
}

// The authoritative answer to "was it delivered", which the app itself cannot
// give: the send is fire-and-forget and ACS reports the outcome asynchronously.
resource acsDeliveryFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (alertsEnabled && acsDeliveryAlertEnabled) {
  name: '${acsName}-delivery-failed'
  location: location
  properties: {
    displayName: '${acsName}: message not delivered'
    description: 'ACS reported a terminal non-delivery. Start here, not at HTTP status codes: the API returns 202 either way.'
    severity: 1
    enabled: true
    scopes: [workspaceId]
    evaluationFrequency: 'PT30M'
    windowSize: 'PT30M'
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: 'ACSEmailStatusUpdateOperational | where DeliveryStatus !in ("Delivered", "Expanded")'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupId]
    }
  }
}
