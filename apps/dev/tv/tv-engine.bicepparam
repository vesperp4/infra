using '../../../bicep/tv-engine.bicep'

param environment = 'dev'

param appName = 'tv-engine'
param appGroup = 'tv'

// Bumped automatically by the monorepo release pipeline (patch-bicepparam.sh).
param imageTag = '0.2.1'

// TODO: set once the TV Sanity project exists (sanity.io/manage). Until then
// the engine runs schedule-less and can only serve slate.
param sanityProjectId = ''

// TODO: point at a packaged "be right back" asset in this env's hls container
// once the first packager run has produced one.
param slateHlsUrl = ''
