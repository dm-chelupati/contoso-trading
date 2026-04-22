param location string
param suffix string
param tags object
param envId string
param acrServer string
param acrName string
@secure()
param acrPassword string
param aiConnStr string
param dbConnStr string
param sbName string
param dtEnvVars array = []
param dtSecrets array = []

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'order-svc-${suffix}'
  location: location
  tags: union(tags, { 'azd-service-name': 'order-service' })
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: envId
    configuration: {
      secrets: concat([
        { name: 'acr-password', value: acrPassword }
        { name: 'db-conn', value: dbConnStr }
      ], dtSecrets)
      registries: [
        { server: acrServer, username: acrName, passwordSecretRef: 'acr-password' }
      ]
      ingress: { external: false, targetPort: 8080 }
    }
    template: {
      containers: [
        {
          name: 'order-service'
          image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat([
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aiConnStr }
            { name: 'DATABASE_URL', secretRef: 'db-conn' }
            { name: 'SERVICEBUS_NAMESPACE', value: sbName }
          ], dtEnvVars)
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 5 }
    }
  }
}

output url string = 'https://${app.properties.configuration.ingress.fqdn}'
