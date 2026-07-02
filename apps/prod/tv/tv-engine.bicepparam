using '../../../bicep/tv-engine.bicep'

param environment = 'prod'

param appName = 'tv-engine'
param appGroup = 'tv'

// Bumped by the monorepo release pipeline; prod deploys are reviewer-gated.
param imageTag = '0.2.1'

// TODO: set once the TV Sanity project exists (sanity.io/manage).
param sanityProjectId = ''

// TODO: point at a packaged "be right back" asset in this env's hls container.
param slateHlsUrl = ''
