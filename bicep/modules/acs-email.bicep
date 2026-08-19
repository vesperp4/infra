// =============================================================================
// Azure Communication Services + Email, with a free Azure-managed sender domain.
//
// Gives the app a passwordless way to send transactional mail (membership
// verification): the app's managed identity mints an Entra token for the ACS
// data plane — same identity it uses for Postgres, no access key or KV secret.
//
// The Azure-managed domain sends from `DoNotReply@<guid>.azurecomm.net` with no
// DNS work and instant verification (Azure owns azurecomm.net). It stays linked
// permanently as a fallback sender.
//
// Setting `customDomainName` additionally provisions a `CustomerManaged` domain
// for a branded sender (noreply@vesperp4.com). That is deliberately a TWO-PHASE
// change, because Azure only emits the DNS records to publish once the domain
// resource exists:
//
//   Phase 1: set `customDomainName`. The domain resource is created, unverified,
//            unlinked, unused. Live mail is unaffected.
//   Phase 2: publish the emitted records, verify all four record types, then set
//            `customDomainVerified = true` to link the domain and cut the sender
//            over. Reversible by flipping the flag back.
//
// Read the records Azure generated, for phase 2:
//   az communication email domain show --domain-name <customDomainName> \
//     --email-service-name <namePrefix>-email --resource-group <rg> \
//     --query properties.verificationRecords
// Then verify each type (Domain, SPF, DKIM, DKIM2) once published:
//   az communication email domain initiate-verification \
//     --domain-name <customDomainName> --email-service-name <namePrefix>-email \
//     --resource-group <rg> --verification-type <type>
//
// No app change in either phase: the app just reads `senderAddress`.
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

// Branded sender. Left empty the module behaves exactly as before. Note this
// must be a name that can hold TXT records: `dev.vesperp4.com` is already a
// CNAME to the Static Web App, and DNS forbids a CNAME coexisting with other
// record types, so dev cannot use its own rootDomain and stays Azure-managed.
@description('Custom sender domain, e.g. vesperp4.com. Empty keeps the Azure-managed sender only.')
param customDomainName string = ''

@description('Mailbox part of the branded sender, e.g. `noreply` gives noreply@<customDomainName>')
param senderUsername string = 'noreply'

@description('Display name shown on the branded sender address')
param senderDisplayName string = 'Vesper P4'

@description('''Flip to true ONLY after the custom domain reports Verified for all four
record types (Domain, SPF, DKIM, DKIM2). Until then the domain resource exists but is
neither linked nor used, so mail keeps flowing from the Azure-managed sender.''')
param customDomainVerified bool = false

// Gate for every custom-sender side effect: linking, the sender username, and
// the address the app is handed. Both conditions, so setting the domain name
// alone can never change what the running app sends as.
var useCustomSender = !empty(customDomainName) && customDomainVerified

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
resource managedDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: emailService
  name: 'AzureManagedDomain'
  location: 'global'
  properties: {
    domainManagement: 'AzureManaged'
    userEngagementTracking: 'Disabled'
  }
}

// Customer-managed sender domain. The resource name IS the domain. Creating it
// is inert: Azure generates the verification records to publish and nothing more
// until each record type is verified out-of-band.
resource customDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = if (!empty(customDomainName)) {
  parent: emailService
  // Guarded so a condition-false deploy (dev, which has no usable sender domain)
  // never yields an empty resource-id segment if ARM evaluates the name anyway.
  name: empty(customDomainName) ? 'unused.invalid' : customDomainName
  location: 'global'
  properties: {
    domainManagement: 'CustomerManaged'
    userEngagementTracking: 'Disabled'
  }
}

// Without this, a custom domain still only sends as `DoNotReply@<domain>`; the
// mailbox part is its own resource. Created only at cutover so phase 1 stays
// inert.
resource customSender 'Microsoft.Communication/emailServices/domains/senderUsernames@2023-04-01' = if (useCustomSender) {
  parent: customDomain
  name: senderUsername
  properties: {
    username: senderUsername
    displayName: senderDisplayName
  }
}

// The data-plane resource the app talks to. Linking the domain authorizes it as
// a sender for this ACS resource.
resource acs 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: '${namePrefix}-acs'
  location: 'global'
  properties: {
    dataLocation: dataLocation
    // The managed domain stays linked after cutover, so a custom-domain problem
    // is a one-line revert of `customDomainVerified` rather than a redeploy.
    linkedDomains: useCustomSender
      ? [managedDomain.id, customDomain.id]
      : [managedDomain.id]
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

@description('Verified sender address: the branded one once cut over, else DoNotReply@<guid>.azurecomm.net')
output senderAddress string = useCustomSender
  ? '${senderUsername}@${customDomainName}'
  : 'DoNotReply@${managedDomain.properties.fromSenderDomain}'

@description('Email Communication Service name (needed by the az verification commands above)')
output emailServiceName string = emailService.name

@description('Resource ID of the ACS resource (scope for the out-of-band role grant)')
output acsResourceId string = acs.id
