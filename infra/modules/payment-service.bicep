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

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'payment-svc-${suffix}'
  location: location
  tags: union(tags, { 'azd-service-name': 'payment-service' })
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: envId
    configuration: {
      secrets: [
        { name: 'acr-password', value: acrPassword }
        { name: 'db-conn', value: dbConnStr }
      ]
      registries: [
        { server: acrServer, username: acrName, passwordSecretRef: 'acr-password' }
      ]
      ingress: { external: false, targetPort: 8080 }
    }
    template: {
      containers: [
        {
          name: 'payment-service'
          image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: [
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aiConnStr }
            { name: 'DATABASE_URL', secretRef: 'db-conn' }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output url string = 'https://${app.properties.configuration.ingress.fqdn}'
