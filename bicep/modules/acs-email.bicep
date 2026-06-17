// =============================================================================
// Azure Communication Services + Email, with a free Azure-managed sender domain.
//
// Gives the app a passwordless way to send transactional mail (membership
// verification): the app's managed identity mints an Entra token for the ACS
// data plane — same identity it uses for Postgres, no access key or KV secret.
//
// The Azure-managed domain sends from `DoNotReply@<guid>.azurecomm.net` with no
// DNS work and instant verification (Azure owns azurecomm.net). To move to a
// branded `vesperp4.com` sender later, swap to a `CustomerManaged` domain and
// add the SPF/DKIM records — no app change, just this module + DNS + the
// `senderAddress` it outputs.
// =============================================================================

@description('Base name for the ACS + Email resources, e.g. portal-dev')
param namePrefix string

@description('Data residency for ACS metadata (not where mail is sent from)')
param dataLocation string = 'United States'

@description('Object (principal) ID of the app managed identity granted send access')
param senderPrincipalId string

@allowed(['ServicePrincipal', 'Group', 'User'])
param senderPrincipalType string = 'ServicePrincipal'

// Whether to codify the send-access role assignment here. Off by default: the
// CI deploy identity is only resource-group Contributor, which lacks
// `Microsoft.Authorization/roleAssignments/write`, so letting the pipeline
// create it fails with AuthorizationFailed. Grant it out-of-band instead (see
// the `az role assignment create` in the module/app outputs), or flip this to
// true once the deploy identity has User Access Administrator on the RG.
@description('Codify the ACS send-access role assignment (requires roleAssignments/write at deploy time)')
param grantSenderRole bool = false

// ACS has no granular data-plane role for email send via Entra; the documented
// requirement is Contributor, scoped here to just this one ACS resource.
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: '${namePrefix}-email'
  location: 'global'
  properties: {
    dataLocation: dataLocation
  }
}

// `AzureManagedDomain` is the required literal name for a free Azure-managed
// sender domain; Azure provisions the `<guid>.azurecomm.net` and its SPF/DKIM.
resource domain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: emailService
  name: 'AzureManagedDomain'
  location: 'global'
  properties: {
    domainManagement: 'AzureManaged'
    userEngagementTracking: 'Disabled'
  }
}

// The data-plane resource the app talks to. Linking the domain authorizes it as
// a sender for this ACS resource.
resource acs 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: '${namePrefix}-acs'
  location: 'global'
  properties: {
    dataLocation: dataLocation
    linkedDomains: [
      domain.id
    ]
  }
}

resource senderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantSenderRole) {
  name: guid(acs.id, senderPrincipalId, contributorRoleId)
  scope: acs
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: senderPrincipalId
    principalType: senderPrincipalType
  }
}

@description('ACS data-plane origin for the email send API')
output endpoint string = 'https://${acs.properties.hostName}'

@description('Verified sender address (DoNotReply@<guid>.azurecomm.net)')
output senderAddress string = 'DoNotReply@${domain.properties.fromSenderDomain}'

@description('Resource ID of the ACS resource (scope for the out-of-band role grant)')
output acsResourceId string = acs.id
