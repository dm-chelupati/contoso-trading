param location string
param suffix string
param tags object
param aiConnStr string
param apiUrl string

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-${suffix}'
  location: location
  tags: tags
  sku: { name: 'S1' }
  kind: 'linux'
  properties: { reserved: true }
}

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: 'frontend-${suffix}'
  location: location
  tags: union(tags, { 'azd-service-name': 'frontend' })
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      healthCheckPath: '/health'
      appCommandLine: 'node server.js'
      appSettings: [
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: aiConnStr }
        { name: 'GATEWAY_URL'
    value: apiUrl }
      ]
    }
  }
}

output url string = 'https://${app.properties.defaultHostName}'
