// Role assignment scoped to the resource group this module is deployed into.
@description('Principal (managed identity / group) object ID to grant the role')
param principalId string

@description('Built-in role definition GUID')
param roleDefinitionId string

@description('Principal type')
@allowed(['ServicePrincipal', 'Group', 'User'])
param principalType string = 'ServicePrincipal'

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}
