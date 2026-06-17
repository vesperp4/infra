using '../../../bicep/web.bicep'

param environment = 'prod'

// Subdomain bindings — validated via cname-delegation against the existing
// `www` CNAME → this SWA's defaultHostname. Idempotent on redeploy.
//
// NOTE: the apex `vesperp4.com` is intentionally NOT listed here. Apex needs
// `dns-txt-token` validation (a per-binding TXT token) and Cloudflare flattens
// the apex CNAME, so it can't be codified. It's bound out-of-band:
//   az staticwebapp hostname set -n mainsite-web-prod -g vesperp4-prod-rg \
//     --hostname vesperp4.com --validation-method dns-txt-token
// then set the returned token as a TXT record on the apex in Cloudflare.
param customDomains = [
  { name: 'www.vesperp4.com' }
]
