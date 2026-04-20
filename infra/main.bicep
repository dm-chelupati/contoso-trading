targetScope = 'subscription'

@description('Environment name')
param environmentName string

@description('Primary location')
param location string = 'eastus2'

var tags = { 'azd-env-name': environmentName }
var rgName = 'rg-${environmentName}'
var suffix = uniqueString(subscription().subscriptionId, rgName)

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
  tags: tags
}

// ── Monitoring (all services log here) ──

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Container Registry ──

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Service Bus (order → payment → worker async pipeline) ──

module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Database (shared PostgreSQL) ──

module database 'modules/database.bicep' = {
  name: 'database'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags }
}

// ── Container App Environment (shared by all backend services) ──

module containerEnv 'modules/container-env.bicep' = {
  name: 'container-env'
  scope: rg
  params: { location: location
    suffix: suffix
    tags: tags
    lawClientId: monitoring.outputs.lawClientId
    lawClientKey: monitoring.outputs.lawClientKey }
}

// ── Frontend (App Service — user-facing web UI) ──

module frontend 'modules/frontend.bicep' = {
  name: 'frontend'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    aiConnStr: monitoring.outputs.aiConnStr
    apiUrl: gateway.outputs.url
  }
}

// ── Gateway (Container App — routes to backend services) ──

module gateway 'modules/gateway.bicep' = {
  name: 'gateway'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    orderServiceUrl: orderService.outputs.url
    paymentServiceUrl: paymentService.outputs.url
  }
}

// ── Order Service (Container App — creates orders, publishes to queue) ──

module orderService 'modules/order-service.bicep' = {
  name: 'order-service'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    dbConnStr: database.outputs.connStr
    sbName: serviceBus.outputs.sbName
  }
}

// ── Payment Service (Container App — processes payments) ──

module paymentService 'modules/payment-service.bicep' = {
  name: 'payment-service'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    dbConnStr: database.outputs.connStr
  }
}

// ── Worker (Container App — processes queue messages, completes orders) ──

module worker 'modules/worker-service.bicep' = {
  name: 'worker'
  scope: rg
  params: {
    location: location
    suffix: suffix
    tags: tags
    envId: containerEnv.outputs.envId
    acrServer: registry.outputs.acrLoginServer
    acrName: registry.outputs.acrName
    acrPassword: registry.outputs.acrPassword
    aiConnStr: monitoring.outputs.aiConnStr
    dbConnStr: database.outputs.connStr
    sbName: serviceBus.outputs.sbName
  }
}

// ── Outputs ──

output RESOURCE_GROUP string = rg.name
output FRONTEND_URL string = frontend.outputs.url
output GATEWAY_URL string = gateway.outputs.url
output AI_NAME string = monitoring.outputs.aiName
output ACR_NAME string = registry.outputs.acrName
output ACR_LOGIN_SERVER string = registry.outputs.acrLoginServer
