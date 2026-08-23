// =============================================================================
// The one place alerts leave Azure.
//
// Azure Monitor has no Slack receiver. The `webhook` receiver POSTs Azure's own
// JSON and a Slack Incoming Webhook only accepts Slack's, so the URI below
// points at the alerts-relay Cloudflare Worker (monorepo:
// apps/ops/alerts-relay), which translates and forwards.
//
// `useCommonAlertSchema` is deliberately true and must stay true: the relay only
// parses the common schema, and the legacy payloads differ per signal type.
//
// The relay URL carries its auth token in the query string, because a webhook
// receiver takes a URI and cannot set headers. That makes the whole URL a
// secret; it comes from Key Vault via the .bicepparam, never from git.
// =============================================================================

@description('Action group name, e.g. vesperp4-prod-ag')
param name string

@description('Up to 12 characters; Azure puts this in SMS/email subject lines')
@maxLength(12)
param shortName string

@description('Full alerts-relay URL including ?token=... , read from Key Vault in the .bicepparam')
@secure()
param relayUrl string

// Action groups are a global resource type; `location` must be the literal
// 'global' regardless of where the alert rules that use them live.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: name
  location: 'global'
  properties: {
    groupShortName: shortName
    enabled: true
    webhookReceivers: [
      {
        name: 'slack-relay'
        serviceUri: relayUrl
        useCommonAlertSchema: true
      }
    ]
  }
}

output id string = actionGroup.id
output name string = actionGroup.name
