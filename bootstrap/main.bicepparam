using './main.bicep'

param location = 'eastus2'
param githubOrg = 'vesperp4'
param appRepo = 'mono'
param infraRepo = 'infra'
param acrName = 'vesperp4acr'
param acrPushEnvironment = 'azure-acr'

// infra-admins Entra group (from iac/azure/entra in the monorepo). Override if
// the group object ID changes.
param adminsGroupObjectId = '2642f52a-cec5-4c40-bbf5-2d3e8c51ad33'
