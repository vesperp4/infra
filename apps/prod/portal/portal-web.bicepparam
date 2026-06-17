using '../../../bicep/web.bicep'

param environment = 'prod'

param appName = 'portal-web'

// Phase 2 (the SWA + its CNAME now both exist): bind the prod portal subdomain.
// `portal.vesperp4.com` is a grey-cloud CNAME → this SWA's defaultHostname in the
// vesperp4.com Cloudflare zone, which cname-delegation validates at deploy time
// (idempotent on redeploy). A subdomain, so no apex dns-txt-token dance.
param customDomains = [
  { name: 'portal.vesperp4.com' }
]
