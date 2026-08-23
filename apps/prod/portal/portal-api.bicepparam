using '../../../bicep/app.bicep'

param environment = 'prod'

// This app group's own component identity (drives the Container App name, the
// ACR repo, the DB server name `portal-prod-<region>-db`, and the database name).
param appName = 'portal-api'
param appGroup = 'portal'
param databaseName = 'portal'

// This subscription is offer-restricted for Postgres Flexible Server in eastus2
// AND eastus; centralus is the nearest confirmed-available region. Compute stays
// in eastus2; the DB lives in centralus.
param postgresLocation = 'centralus'

// Bumped automatically by the prod-promotion workflow (patch-bicepparam.sh).
param imageTag = '0.8.3'

// Admin password for this app's Postgres server, read from Key Vault at deploy
// time by the deploy identity (Key Vault Secrets User). Seeded per the runbook.
param postgresAdminPassword = az.getSecret(
  '1e180171-becb-40cd-a4a0-52351087be66',
  'vesperp4-prod-rg',
  'vesperp4-prod-kv',
  'portal-pg-admin-password'
)

// Custom domain (api.portal.vesperp4.com) + Microsoft OIDC sign-in — pinned
// AFTER the out-of-band runbook (README §"portal-api custom domain + Entra app
// registration (out-of-band)") completes for this env; same two-phase pattern
// as the SWA custom domains. Uncomment and fill in with the recorded values:
param apiCustomDomainCertificateId = '/subscriptions/1e180171-becb-40cd-a4a0-52351087be66/resourceGroups/vesperp4-prod-rg/providers/Microsoft.App/managedEnvironments/vesperp4-prod-cae/managedCertificates/mc-vesperp4-prod--api-portal-vespe-6809'
param oidcClientId = 'aa2064af-8e60-40ab-8be8-28fa7ccd6ca1'
param oidcTenantId = '72b8c91b-4089-4b60-996f-922c73865584'

// Branded transactional sender, noreply@vesperp4.com (roadmap item #5). Domain,
// SPF, DKIM and DKIM2 all report Verified, so the flag below links the domain and
// cuts the sender over. Setting it back to false reverts to the Azure-managed
// sender without a re-verification, which is why that domain stays linked.
// Dev has no equivalent: dev.vesperp4.com is a CNAME and cannot hold the records.
param acsCustomDomainName = 'vesperp4.com'
param acsCustomDomainVerified = true

// Alerting, phase 2. The action group is created by platform/prod.bicepparam;
// naming it here is what creates this app's rules (see bicep/modules/app-alerts.bicep).
// Deploy the platform FIRST: the rules reference this action group by resource ID and
// Azure rejects a rule whose action group does not exist yet.
//
// Clearing this line removes the rules and leaves the app otherwise untouched.
param alertsActionGroupName = 'vesperp4-prod-ag'

// The ACS delivery-status rule stays off until its table has rows. Azure validates
// alert queries at deploy time, and ACSEmailStatusUpdateOperational does not exist
// until the diagnostic setting added in this change has been live long enough to
// emit some. Confirm with `ACSEmailStatusUpdateOperational | take 10`, then flip.
param acsDeliveryAlertEnabled = false
