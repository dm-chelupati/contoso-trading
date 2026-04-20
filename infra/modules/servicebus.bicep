param location string
param suffix string
param tags object

resource sb 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'sb-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard'
    tier: 'Standard' }
  properties: {
    disableLocalAuth: true
  }
}

resource ordersQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: sb
  name: 'orders'
  properties: { maxDeliveryCount: 5
    lockDuration: 'PT1M' }
}

resource paymentsQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: sb
  name: 'payments'
  properties: { maxDeliveryCount: 5
    lockDuration: 'PT1M' }
}

output sbName string = sb.name
output sbId string = sb.id
