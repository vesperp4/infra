using '../../../bicep/web.bicep'

param environment = 'prod'

param appName = 'portal-web'

// Custom domain is bound in a PHASE 2, not on first create: cname-delegation
// validates against an existing CNAME → this SWA's defaultHostname, but neither
// exists yet for a greenfield SWA. Bootstrap order:
//   1. deploy bare (this) → SWA created, note its defaultHostname
//   2. add a grey-cloud CNAME `portal` → that defaultHostname in the
//      vesperp4.com Cloudflare zone (subdomain, so no apex dns-txt-token dance)
//   3. re-add `customDomains = [ { name: 'portal.vesperp4.com' } ]` here → the
//      next deploy validates and binds it idempotently
// (mainsite-web's `www` bound on first deploy only because its CNAME pre-existed
// from the prior site.)
