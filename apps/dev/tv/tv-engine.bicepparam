using '../../../bicep/tv-engine.bicep'

param environment = 'dev'

param appName = 'tv-engine'
param appGroup = 'tv'

// Bumped automatically by the monorepo release pipeline (patch-bicepparam.sh).
param imageTag = '0.2.1'

// TODO: set once the TV Sanity project exists (sanity.io/manage). Until then
// the engine runs schedule-less and can only serve slate.
param sanityProjectId = ''

// Produced by the first tv-packager-dev run (2026-07-02) from a generated
// SMPTE-bars clip; with no Sanity project wired yet the engine loops this,
// which makes the dev channel broadcast slate 24/7.
param slateHlsUrl = 'https://vesperp4tvdevst.blob.core.windows.net/hls/slate/master.m3u8'
