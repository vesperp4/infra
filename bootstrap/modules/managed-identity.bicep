@description('Name of the user-assigned managed identity')
param name string

@description('Azure region')
param location string

@description('''
GitHub OIDC federated credentials to attach. Each item: { name, subject }.
Leave empty for runtime-only identities (e.g. Container App identities that are
assumed by Azure, not by GitHub).
''')
param federatedCredentials array = []

var issuer = 'https://token.actions.githubusercontent.com'
var audience = 'api://AzureADTokenExchange'

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
}

// Federated credentials must be created serially (Azure rejects parallel writes
// to the same identity), hence @batchSize(1).
@batchSize(1)
resource fic 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [
  for cred in federatedCredentials: {
    parent: uami
    name: cred.name
    properties: {
      issuer: issuer
      subject: cred.subject
      audiences: [audience]
    }
  }
]

output id string = uami.id
output principalId string = uami.properties.principalId
output clientId string = uami.properties.clientId
output name string = uami.name
