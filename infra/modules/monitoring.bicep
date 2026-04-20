param location string
param suffix string
param tags object

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${suffix}'
  location: location
  tags: tags
  properties: { sku: { name: 'PerGB2018' }
    retentionInDays: 30 }
}

resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: { Application_Type: 'web'
    WorkspaceResourceId: law.id }
}

output lawId string = law.id
output lawClientId string = law.properties.customerId
output lawClientKey string = law.listKeys().primarySharedKey
output aiConnStr string = ai.properties.ConnectionString
output aiName string = ai.name
