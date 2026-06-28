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

// Scheduled query rule: alert only on actual 5xx errors (not 404s from scanners)
resource orders5xxAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'contoso-orders-5xx-${suffix}'
  location: location
  tags: tags
  properties: {
    displayName: 'Orders API 5xx Errors'
    description: 'Alerts when the Orders API returns actual 5xx server errors. Excludes 4xx client errors (e.g. 404 scanner probes) to avoid false positives.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      ai.id
    ]
    criteria: {
      allOf: [
        {
          query: 'requests | where toint(resultCode) >= 500 and toint(resultCode) < 600'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
  }
}

output lawId string = law.id
output lawClientId string = law.properties.customerId
output lawClientKey string = law.listKeys().primarySharedKey
output aiConnStr string = ai.properties.ConnectionString
output aiName string = ai.name
