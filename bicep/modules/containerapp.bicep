@description('Container App name')
param name string

@description('Azure region')
param location string

@description('Managed environment resource ID')
param environmentId string

@description('ACR login server (e.g. vesperp4acr.azurecr.io)')
param registryServer string

@description('Full image reference including tag')
param image string

@description('Resource ID of the user-assigned identity used for ACR pull + runtime')
param appIdentityResourceId string

@description('Client ID of that identity (so DefaultAzureCredential picks it for tokens)')
param appIdentityClientId string

@description('Container listen port')
param targetPort int = 8080

@description('PostgreSQL host (FQDN)')
param pgHost string

@description('PostgreSQL user — the Entra role name created for the app identity')
param pgUser string

@description('PostgreSQL database name')
param pgDatabase string

param minReplicas int = 0
param maxReplicas int = 1
param cpu string = '0.5'
param memory string = '1Gi'

@description('Azure Communication Services data-plane origin (empty disables ACS; app falls back to log-only email)')
param acsEndpoint string = ''

@description('Verified ACS sender address, e.g. DoNotReply@<guid>.azurecomm.net')
param acsSenderAddress string = ''

@description('Origin the verification link points at — the portal web app hosting /confirm (empty => app default, prod portal)')
param publicBaseUrl string = ''

@description('Comma-separated browser origins allowed to call the API (empty => app default, the portal origin)')
param corsAllowedOrigins string = ''

@description('Custom domain to bind on ingress (empty => default *.azurecontainerapps.io FQDN only)')
param customDomainName string = ''

@description('Resource ID of the managed certificate for customDomainName — created out-of-band per the README runbook, then pinned here')
param customDomainCertificateId string = ''

@description('Entra app registration (client) ID for Microsoft OIDC sign-in (empty => app leaves OIDC disabled)')
param oidcClientId string = ''

@description('Tenant GUID the API validates OIDC sign-ins against — the members\' home tenant, not this subscription\'s')
param oidcTenantId string = ''

@description('OIDC callback URL — must match a web redirect URI on the app registration')
param oidcRedirectUri string = ''

@description('Domain attribute for the session cookie (empty => host-only cookie)')
param cookieDomain string = ''

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        // The hostname and its managed certificate are created OUT-OF-BAND
        // (README runbook: DNS records, `az containerapp hostname add/bind`,
        // `az containerapp env certificate create`) because managed-cert
        // issuance is inherently two-phase. Once the cert ID is pinned in
        // params, declaring the binding here keeps ARM PUT redeploys from
        // stripping it. Omitted entirely until both values are set.
        customDomains: (empty(customDomainName) || empty(customDomainCertificateId)) ? null : [
          {
            name: customDomainName
            bindingType: 'SniEnabled'
            certificateId: customDomainCertificateId
          }
        ]
      }
      // Pull via managed identity (AcrPull granted in bootstrap) — no registry secret.
      registries: [
        {
          server: registryServer
          identity: appIdentityResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          // Passwordless: the app obtains an Entra token via its managed identity
          // (AZURE_CLIENT_ID) and uses it as the Postgres password. No secret here.
          // The same identity mints an ACS token for sending email, so ACS needs
          // only its endpoint + sender — no key. Empty endpoint => log-only email.
          env: concat([
            { name: 'PGHOST', value: pgHost }
            { name: 'PGUSER', value: pgUser }
            { name: 'PGDATABASE', value: pgDatabase }
            { name: 'PGPORT', value: '5432' }
            { name: 'PGSSLMODE', value: 'require' }
            { name: 'AZURE_CLIENT_ID', value: appIdentityClientId }
          ], empty(acsEndpoint) ? [] : [
            { name: 'ACS_ENDPOINT', value: acsEndpoint }
            { name: 'ACS_SENDER_ADDRESS', value: acsSenderAddress }
          ], empty(publicBaseUrl) ? [] : [
            { name: 'PUBLIC_BASE_URL', value: publicBaseUrl }
          ], empty(corsAllowedOrigins) ? [] : [
            { name: 'CORS_ALLOWED_ORIGINS', value: corsAllowedOrigins }
          // Microsoft OIDC sign-in — no client secret anywhere: the client
          // credential is a federated identity credential on the app
          // registration, exchanged at runtime via the same managed identity
          // (AZURE_CLIENT_ID). The app only enables OIDC when all vars are set.
          ], empty(oidcClientId) ? [] : [
            { name: 'OIDC_CLIENT_ID', value: oidcClientId }
            { name: 'OIDC_TENANT_ID', value: oidcTenantId }
            { name: 'OIDC_REDIRECT_URI', value: oidcRedirectUri }
          ], empty(cookieDomain) ? [] : [
            { name: 'COOKIE_DOMAIN', value: cookieDomain }
          ])
          probes: [
            {
              // Process-only: /livez does no DB I/O, so a transient Postgres
              // blip can't fail liveness and trigger a restart storm of
              // healthy replicas. DB health gates traffic via readiness below.
              type: 'Liveness'
              httpGet: {
                path: '/livez'
                port: targetPort
              }
              periodSeconds: 30
            }
            {
              // DB-aware: /health returns 503 when Postgres is unreachable, so
              // the revision is pulled from rotation until the DB recovers
              // instead of being killed.
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: targetPort
              }
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output name string = app.name
