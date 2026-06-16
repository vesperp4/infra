@description('Name of the existing Key Vault (in this resource group)')
param kvName string

@description('Principal (managed identity / group) object ID to grant the role')
param principalId string

@description('Built-in role definition GUID')
param roleDefinitionId string

@description('Principal type')
@allowed(['ServicePrincipal', 'Group', 'User'])
param principalType string = 'ServicePrincipal'

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, principalId, roleDefinitionId)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}
