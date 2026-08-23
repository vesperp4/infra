using '../bicep/platform.bicep'

param environment = 'prod'

// Alert delivery to Slack, via the alerts-relay Cloudflare Worker (monorepo:
// apps/ops/alerts-relay). Two-phase, like the ACS branded sender:
//
//   Phase 1: deploy the Worker, then store its full URL (including the
//            `?token=...`, which is what authenticates the caller) in this env's
//            Key Vault as `alerts-relay-url`. Uncomment below and deploy. That
//            creates the action group and nothing else; no alert exists yet.
//   Phase 2: set `alertsActionGroupName = 'vesperp4-prod-ag'` in each app's
//            .bicepparam to switch that app's rules on.
//
// Commenting this back out removes the action group and silences every rule,
// which is the intended kill switch.
//
// Phase 1 done: the Worker is deployed at
// vesperp4-alerts-relay.vesper-p4.workers.dev and the secret is seeded.
param alertsRelayUrl = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-prod-rg',
  'vesperp4-prod-kv',
  'alerts-relay-url'
)
