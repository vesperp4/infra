using '../../../bicep/web.bicep'

param environment = 'dev'

param appName = 'portal-web'

// No custom domain in dev — same as dev mainsite-web; dev testing uses the
// *.azurestaticapps.net defaultHostname. (cname-delegation can't validate a
// binding until the CNAME exists, and the CNAME can't point anywhere until this
// SWA exists — so a greenfield SWA is created bare. If a dev FQDN is wanted
// later, add a grey-cloud CNAME `portal.dev` → this SWA's defaultHostname, then
// re-introduce `customDomains` here.)
