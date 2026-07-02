using '../../../bicep/web.bicep'

param environment = 'dev'

// TV site frontend (player + schedule). Content is uploaded by the monorepo's
// tv-web-deploy workflow via this SWA's deployment token (GitHub environment
// `azure-swa-tv`). No custom domain in dev — default hostname only.
param appName = 'tv-web'
