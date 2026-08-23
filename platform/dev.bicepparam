using '../bicep/platform.bicep'

param environment = 'dev'

// Alert delivery to Slack, via the alerts-relay Cloudflare Worker (monorepo:
// apps/ops/alerts-relay). Two-phase, like the ACS branded sender:
//
//   Phase 1: deploy the Worker, then store its full URL (including the
//            `?token=...`, which is what authenticates the caller) in this env's
//            Key Vault as `alerts-relay-url`. Uncomment below and deploy. That
//            creates the action group and nothing else; no alert exists yet.
//   Phase 2: set `alertsActionGroupName = 'vesperp4-dev-ag'` in each app's
//            .bicepparam to switch that app's rules on.
//
// Commenting this back out removes the action group and silences every rule,
// which is the intended kill switch.
//
// param alertsRelayUrl = az.getSecret(
//   '1e180171-becb-40cd-a4a0-52351087be66',
//   'vesperp4-dev-rg',
//   'vesperp4-dev-kv',
//   'alerts-relay-url'
// )
