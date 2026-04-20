param location string
param suffix string
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${suffix}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: true }
}

output acrLoginServer string = acr.properties.loginServer
output acrName string = acr.name

output acrPassword string = acr.listCredentials().passwords[0].value
