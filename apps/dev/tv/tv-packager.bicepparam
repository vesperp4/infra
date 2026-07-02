using '../../../bicep/tv-packager.bicep'

param environment = 'dev'

param appName = 'tv-packager'
param appGroup = 'tv'

// Bumped automatically by the monorepo release pipeline (patch-bicepparam.sh).
param imageTag = '0.2.0'
