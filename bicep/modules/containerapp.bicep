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
param targetPort int = 3001

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
          env: [
            { name: 'PGHOST', value: pgHost }
            { name: 'PGUSER', value: pgUser }
            { name: 'PGDATABASE', value: pgDatabase }
            { name: 'PGPORT', value: '5432' }
            { name: 'PGSSLMODE', value: 'require' }
            { name: 'AZURE_CLIENT_ID', value: appIdentityClientId }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: targetPort
              }
              periodSeconds: 30
            }
            {
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
