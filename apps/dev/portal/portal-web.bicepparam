using '../../../bicep/web.bicep'

param environment = 'dev'

param appName = 'portal-web'

// Per-env FQDN scheme: portal = `portal.` prefix on the env baseDomain
// (dev baseDomain = dev.vesperp4.com). A subdomain, so it binds cleanly via
// cname-delegation — add a grey-cloud CNAME `portal.dev` → this SWA's
// defaultHostname in the vesperp4.com Cloudflare zone.
param customDomains = [
  { name: 'portal.dev.vesperp4.com' }
]
