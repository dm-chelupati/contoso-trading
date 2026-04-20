param location string
param suffix string
param tags object
param lawClientId string
param lawClientKey string

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'env-${suffix}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: lawClientId
        sharedKey: lawClientKey
      }
    }
  }
}

output envId string = env.id
