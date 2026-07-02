using '../../../bicep/tv-packager.bicep'

param environment = 'prod'

param appName = 'tv-packager'
param appGroup = 'tv'

// Bumped by the monorepo release pipeline; prod deploys are reviewer-gated.
param imageTag = '0.2.0'
