targetScope = 'resourceGroup'

// =============================================================================
// Per-app stack: this app's OWN PostgreSQL Flexible Server + database, plus its
// Container App on the shared per-env Container Apps environment (platform.bicep).
// Each app is fully isolated at the database-server level. Deployed by the
// image-bump pipeline — the monorepo pins `imageTag` per env in the .bicepparam.
// =============================================================================

@allowed(['dev', 'prod'])
param environment string

@description('App/image name (matches apps/<env>/<appGroup>/<appName>.bicepparam and the ACR repo)')
param appName string = 'portal-api'

@description('App group — the site this component belongs to; names the shared DB server')
param appGroup string = 'portal'

@description('Image tag to deploy — bumped by the monorepo release pipeline')
param imageTag string

@description('Database name on the app server')
param databaseName string = 'portal'

param location string = resourceGroup().location

@description('Region for the Postgres Flexible Server — split out because some subscriptions are offer-restricted for Postgres in the compute region (e.g. eastus2)')
param postgresLocation string = location

@description('Shared resource group holding the ACR and runtime identities')
param sharedResourceGroupName string = 'vesperp4-shared-rg'

param acrName string = 'vesperp4acr'

@description('Runtime managed identity name (ACR pull + Entra DB token)')
param appIdentityName string = 'id-app-${environment}'

@description('Object ID of the Entra group made Postgres admin (passwordless)')
param adminsGroupObjectId string = '2642f52a-cec5-4c40-bbf5-2d3e8c51ad33'

@description('Built-in Postgres admin login (escape hatch; Entra auth is preferred)')
param postgresAdminLogin string = 'pgadmin'

@description('Postgres admin password — sourced from Key Vault in the .bicepparam')
@secure()
param postgresAdminPassword string

param postgresSkuName string = 'Standard_B1ms'

@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param postgresSkuTier string = 'Burstable'

param postgresStorageSizeGB int = 32

@description('Allow built-in Postgres password sign-in. Default false (passwordless Entra only); flip to true in a bicepparam for transient break-glass, then revert.')
param postgresPasswordAuthEnabled bool = false

param minReplicas int = (environment == 'prod') ? 1 : 0
param maxReplicas int = (environment == 'prod') ? 3 : 1

@description('''Resource ID of the managed certificate for api.portal.<rootDomain>.
The hostname + certificate are created out-of-band (README: "portal-api custom
domain + Entra app registration"), then the cert ID is recorded here to pin the
binding. Empty (the default) keeps existing envs deploying unchanged on the
default *.azurecontainerapps.io FQDN.''')
param apiCustomDomainCertificateId string = ''

@description('Entra app registration (client) ID for Microsoft OIDC sign-in — pinned from the runbook; empty leaves OIDC disabled')
param oidcClientId string = ''

@description('Tenant GUID the API validates OIDC sign-ins against — PUPR\'s tenant, NOT the vesperp4 tenant (see the runbook for discovery)')
param oidcTenantId string = ''

// Public domain layout is deterministic: prod lives at the apex, dev under the
// `dev.` subdomain. The portal web app hosts the signup/confirm pages, so the
// verification link (PUBLIC_BASE_URL) points there. Only the portal origin
// calls this API from the browser — the mainsite does not (its "join" links to
// the portal; contact is a mailto). CORS is credentialed, so the allowlist must
// stay portal-only: adding the mainsite would let any script there read a
// signed-in member's data with the session cookie. Bound out-of-band as SWA
// custom domains (see README).
var rootDomain = (environment == 'prod') ? 'vesperp4.com' : 'dev.vesperp4.com'
var portalOrigin = 'https://portal.${rootDomain}'
// The API's custom domain sits under the portal subtree so the session cookie
// can be same-site with the portal SWA: `.portal.<root>` covers both
// portal.<root> and api.portal.<root>. Deliberately NOT `.vesperp4.com` — the
// mainsite and TV origins must never see the portal session cookie.
var apiDomain = 'api.portal.${rootDomain}'
var cookieDomain = '.portal.${rootDomain}'

var caeName = 'vesperp4-${environment}-cae'
// DB region is part of the server name: self-documenting, and collision-proof
// when the DB region differs from compute (Azure caches a name->region mapping
// in the RG, so a failed create in one region blocks recreating it in another).
var pgName = '${appGroup}-${environment}-${postgresLocation}-db'
var containerAppName = '${appName}-${environment}'

// ---------- Shared resources (bootstrap + platform.bicep) ----------

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: appIdentityName
  scope: resourceGroup(sharedResourceGroupName)
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
  scope: resourceGroup(sharedResourceGroupName)
}

// CI deploy identity — added as a Postgres Entra admin so the deploy workflow
// can onboard the app's DB role (see scripts/onboard-app-db.sh).
resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-github-deploy-${environment}'
  scope: resourceGroup(sharedResourceGroupName)
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

// ---------- This app's dedicated PostgreSQL server + database ----------

module postgres 'modules/postgres.bicep' = {
  name: '${appGroup}-postgres'
  params: {
    name: pgName
    location: postgresLocation
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    passwordAuthEnabled: postgresPasswordAuthEnabled
    databaseName: databaseName
    skuName: postgresSkuName
    skuTier: postgresSkuTier
    storageSizeGB: postgresStorageSizeGB
    aadAdminObjectId: adminsGroupObjectId
    aadAdminName: 'infra-admins'
    aadAdminPrincipalType: 'Group'
    deployAdminObjectId: deployIdentity.properties.principalId
    deployAdminName: deployIdentity.name
  }
}

// ---------- Transactional email (Azure Communication Services) ----------

module acsEmail 'modules/acs-email.bicep' = {
  name: '${appGroup}-acs-email'
  params: {
    namePrefix: '${appGroup}-${environment}'
    senderPrincipalId: appIdentity.properties.principalId
    // Send-access role is granted out-of-band — the CI deploy identity is only
    // RG Contributor and can't write role assignments. See README for the
    // `az role assignment create` (scope = acsResourceId output).
    grantSenderRole: false
  }
}

// ---------- The Container App ----------

module app 'modules/containerapp.bicep' = {
  name: '${appName}-containerapp'
  params: {
    name: containerAppName
    location: location
    environmentId: cae.id
    registryServer: acr.properties.loginServer
    image: '${acr.properties.loginServer}/${appName}:${imageTag}'
    appIdentityResourceId: appIdentity.id
    appIdentityClientId: appIdentity.properties.clientId
    pgHost: postgres.outputs.fqdn
    // Entra role name the dev team creates for the app identity (see README).
    pgUser: appIdentityName
    pgDatabase: postgres.outputs.databaseName
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    // Passwordless ACS email — endpoint + verified sender from the module above.
    acsEndpoint: acsEmail.outputs.endpoint
    acsSenderAddress: acsEmail.outputs.senderAddress
    // Verification links point at this env's portal; only the portal origin is
    // CORS-allowed so the SWA→API browser calls work (credentialed — keep it
    // portal-only; see the domain-layout note above).
    publicBaseUrl: portalOrigin
    corsAllowedOrigins: portalOrigin
    // Custom domain — hostname + managed cert are bound out-of-band (README
    // runbook); the module only declares the binding once the cert ID is
    // pinned in this env's .bicepparam, so both are safe to pass always.
    customDomainName: apiDomain
    customDomainCertificateId: apiCustomDomainCertificateId
    // Microsoft OIDC sign-in — passed always for simplicity; the API only
    // enables OIDC when all of its OIDC vars are set (module guards emission
    // on oidcClientId). No client secret: federated credential on the app
    // registration via the same managed identity.
    oidcClientId: oidcClientId
    oidcTenantId: oidcTenantId
    oidcRedirectUri: 'https://${apiDomain}/api/v1/auth/oidc/callback'
    cookieDomain: cookieDomain
  }
}

// Prefer the custom domain once its cert is pinned; the default FQDN otherwise.
output apiUrl string = empty(apiCustomDomainCertificateId)
  ? 'https://${app.outputs.fqdn}'
  : 'https://${apiDomain}'
output containerAppName string = app.outputs.name
output postgresFqdn string = postgres.outputs.fqdn
output postgresServerName string = postgres.outputs.name
output databaseName string = postgres.outputs.databaseName
output acsEndpoint string = acsEmail.outputs.endpoint
output acsSenderAddress string = acsEmail.outputs.senderAddress
// Out-of-band send-access grant (deploy identity can't write role assignments):
//   az role assignment create --assignee <appIdentity clientId> \
//     --role Contributor --scope <acsResourceId>
output acsResourceId string = acsEmail.outputs.acsResourceId
