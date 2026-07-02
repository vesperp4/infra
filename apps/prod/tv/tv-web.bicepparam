using '../../../bicep/web.bicep'

param environment = 'prod'

// TV site frontend, future https://vesperp4.tv. The apex is bound OUT-OF-BAND
// (dns-txt-token + Cloudflare CNAME-flattening — same runbook as vesperp4.com;
// see staticwebapp.bicep header). Add `www.vesperp4.tv` here via
// cname-delegation once the Cloudflare zone exists:
//   param customDomains = [{ name: 'www.vesperp4.tv' }]
param appName = 'tv-web'
