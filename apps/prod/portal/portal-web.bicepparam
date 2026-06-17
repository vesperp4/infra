using '../../../bicep/web.bicep'

param environment = 'prod'

param appName = 'portal-web'

// `portal.vesperp4.com` is bound OUT-OF-BAND, not via this param — same as the
// mainsite apex. Reason: declaring it here makes ARM poll the SWA's async
// operation-status resource, which lives at SUBSCRIPTION/location scope
// (`/subscriptions/.../Microsoft.Web/locations/<loc>/staticSitesOperationStatuses/...`).
// The deploy identity (`id-github-deploy-prod`) is only Contributor at the
// resource-group scope, so that read returns Forbidden and the deployment hangs
// forever — even though the bind itself succeeds. The domain is already bound and
// `Ready` (grey-cloud CNAME `portal` → this SWA's defaultHostname); leaving it
// out of the template keeps it that way (incremental deploys don't prune it). To
// codify it in bicep instead, grant the deploy identities Reader at subscription
// scope (read covers the op-status), then re-add `customDomains` here.
