targetScope = 'subscription'

// =============================================================================
// Vesper P4 infra bootstrap — identity & foundation
//
// Provisions the one-time foundation the deploy pipeline relies on:
//   - resource groups (shared / dev / prod)
//   - a shared Azure Container Registry
//   - per-environment Key Vaults
//   - user-assigned managed identities with GitHub OIDC federated credentials
//     (no client secrets) and least-privilege RBAC
//
// Deploy once, manually, by an admin (see README.md). The per-environment app
// resources (Postgres, Container Apps) are deployed separately by the pipeline.
// =============================================================================

@description('Azure region for all resources')
param location string = 'eastus2'

@description('GitHub organization / owner')
param githubOrg string = 'vesperp4'

@description('Monorepo that builds and pushes images')
param appRepo string = 'mono'

@description('Infra repo that deploys environments')
param infraRepo string = 'infra'

@description('Globally-unique ACR name')
param acrName string = 'vesperp4acr'

@description('GitHub environment used by the monorepo build job (federated subject)')
param acrPushEnvironment string = 'azure-acr'

@description('Object ID of the infra-admins Entra group (seeds Key Vault secrets)')
param adminsGroupObjectId string = '2642f52a-cec5-4c40-bbf5-2d3e8c51ad33'

// ---------- Names ----------

var sharedRgName = 'vesperp4-shared-rg'
var devRgName = 'vesperp4-dev-rg'
var prodRgName = 'vesperp4-prod-rg'
var devKvName = 'vesperp4-dev-kv'
var prodKvName = 'vesperp4-prod-kv'

// ---------- Built-in role definition GUIDs ----------

var roles = {
  acrPush: '8311e382-0749-4cb8-b61a-304f252e45ec'
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  kvSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  kvSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
}

// ---------- Resource groups ----------

resource sharedRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: sharedRgName
  location: location
}

resource devRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: devRgName
  location: location
}

resource prodRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: prodRgName
  location: location
}

// ---------- Shared registry ----------

module acr 'modules/acr.bicep' = {
  name: 'acr'
  scope: sharedRg
  params: {
    name: acrName
    location: location
  }
}

// ---------- Per-environment Key Vaults ----------

module devKv 'modules/keyvault.bicep' = {
  name: 'kv-dev'
  scope: devRg
  params: {
    name: devKvName
    location: location
  }
}

module prodKv 'modules/keyvault.bicep' = {
  name: 'kv-prod'
  scope: prodRg
  params: {
    name: prodKvName
    location: location
  }
}

// ---------- GitHub-federated identities (CI) ----------

module idAcrPush 'modules/managed-identity.bicep' = {
  name: 'id-github-acr-push'
  scope: sharedRg
  params: {
    name: 'id-github-acr-push'
    location: location
    federatedCredentials: [
      {
        name: 'mono-build'
        subject: 'repo:${githubOrg}/${appRepo}:environment:${acrPushEnvironment}'
      }
    ]
  }
}

module idDeployDev 'modules/managed-identity.bicep' = {
  name: 'id-github-deploy-dev'
  scope: sharedRg
  params: {
    name: 'id-github-deploy-dev'
    location: location
    federatedCredentials: [
      {
        name: 'infra-dev'
        subject: 'repo:${githubOrg}/${infraRepo}:environment:dev'
      }
    ]
  }
}

module idDeployProd 'modules/managed-identity.bicep' = {
  name: 'id-github-deploy-prod'
  scope: sharedRg
  params: {
    name: 'id-github-deploy-prod'
    location: location
    federatedCredentials: [
      {
        name: 'infra-prod'
        subject: 'repo:${githubOrg}/${infraRepo}:environment:production'
      }
    ]
  }
}

// ---------- Container App runtime identities (no GitHub federation) ----------

module idAppDev 'modules/managed-identity.bicep' = {
  name: 'id-app-dev'
  scope: sharedRg
  params: {
    name: 'id-app-dev'
    location: location
  }
}

module idAppProd 'modules/managed-identity.bicep' = {
  name: 'id-app-prod'
  scope: sharedRg
  params: {
    name: 'id-app-prod'
    location: location
  }
}

// ---------- RBAC: ACR ----------

module raAcrPush 'modules/ra-acr.bicep' = {
  name: 'ra-acr-push'
  scope: sharedRg
  params: {
    acrName: acr.outputs.name
    principalId: idAcrPush.outputs.principalId
    roleDefinitionId: roles.acrPush
  }
}

module raAcrPullDev 'modules/ra-acr.bicep' = {
  name: 'ra-acr-pull-dev'
  scope: sharedRg
  params: {
    acrName: acr.outputs.name
    principalId: idAppDev.outputs.principalId
    roleDefinitionId: roles.acrPull
  }
}

module raAcrPullProd 'modules/ra-acr.bicep' = {
  name: 'ra-acr-pull-prod'
  scope: sharedRg
  params: {
    acrName: acr.outputs.name
    principalId: idAppProd.outputs.principalId
    roleDefinitionId: roles.acrPull
  }
}

// ---------- RBAC: resource groups (deploy identities) ----------

module raDeployDevRg 'modules/ra-rg.bicep' = {
  name: 'ra-deploy-dev-rg'
  scope: devRg
  params: {
    principalId: idDeployDev.outputs.principalId
    roleDefinitionId: roles.contributor
  }
}

module raDeployProdRg 'modules/ra-rg.bicep' = {
  name: 'ra-deploy-prod-rg'
  scope: prodRg
  params: {
    principalId: idDeployProd.outputs.principalId
    roleDefinitionId: roles.contributor
  }
}

// ---------- RBAC: Key Vaults ----------

// Deploy identities read the Postgres password at deploy time.
module raDeployDevKv 'modules/ra-kv.bicep' = {
  name: 'ra-deploy-dev-kv'
  scope: devRg
  params: {
    kvName: devKv.outputs.name
    principalId: idDeployDev.outputs.principalId
    roleDefinitionId: roles.kvSecretsUser
  }
}

module raDeployProdKv 'modules/ra-kv.bicep' = {
  name: 'ra-deploy-prod-kv'
  scope: prodRg
  params: {
    kvName: prodKv.outputs.name
    principalId: idDeployProd.outputs.principalId
    roleDefinitionId: roles.kvSecretsUser
  }
}

// App runtime identities read the Postgres password at runtime.
module raAppDevKv 'modules/ra-kv.bicep' = {
  name: 'ra-app-dev-kv'
  scope: devRg
  params: {
    kvName: devKv.outputs.name
    principalId: idAppDev.outputs.principalId
    roleDefinitionId: roles.kvSecretsUser
  }
}

module raAppProdKv 'modules/ra-kv.bicep' = {
  name: 'ra-app-prod-kv'
  scope: prodRg
  params: {
    kvName: prodKv.outputs.name
    principalId: idAppProd.outputs.principalId
    roleDefinitionId: roles.kvSecretsUser
  }
}

// Admins seed/rotate the Postgres password secret.
module raAdminsDevKv 'modules/ra-kv.bicep' = {
  name: 'ra-admins-dev-kv'
  scope: devRg
  params: {
    kvName: devKv.outputs.name
    principalId: adminsGroupObjectId
    roleDefinitionId: roles.kvSecretsOfficer
    principalType: 'Group'
  }
}

module raAdminsProdKv 'modules/ra-kv.bicep' = {
  name: 'ra-admins-prod-kv'
  scope: prodRg
  params: {
    kvName: prodKv.outputs.name
    principalId: adminsGroupObjectId
    roleDefinitionId: roles.kvSecretsOfficer
    principalType: 'Group'
  }
}

// ---------- Outputs (wire these into GitHub secrets/vars) ----------

output tenantId string = tenant().tenantId
output subscriptionId string = subscription().subscriptionId
output acrLoginServer string = acr.outputs.loginServer
output acrNameOut string = acr.outputs.name

output idAcrPushClientId string = idAcrPush.outputs.clientId
output idDeployDevClientId string = idDeployDev.outputs.clientId
output idDeployProdClientId string = idDeployProd.outputs.clientId

output idAppDevResourceId string = idAppDev.outputs.id
output idAppProdResourceId string = idAppProd.outputs.id
output idAppDevClientId string = idAppDev.outputs.clientId
output idAppProdClientId string = idAppProd.outputs.clientId

output devKeyVaultName string = devKv.outputs.name
output prodKeyVaultName string = prodKv.outputs.name
