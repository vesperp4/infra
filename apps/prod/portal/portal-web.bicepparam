using '../../../bicep/web.bicep'

param environment = 'prod'

param appName = 'portal-web'

// Per-env FQDN scheme: portal = `portal.` prefix on the env baseDomain
// (prod baseDomain = vesperp4.com). A subdomain, so it binds cleanly via
// cname-delegation — add a grey-cloud CNAME `portal` → this SWA's
// defaultHostname in the vesperp4.com Cloudflare zone. (Unlike the mainsite
// apex, no dns-txt-token dance is needed for a subdomain.)
param customDomains = [
  { name: 'portal.vesperp4.com' }
]
