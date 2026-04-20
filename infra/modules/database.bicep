param location string
param suffix string
param tags object

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: 'pg-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard_B1ms'
    tier: 'Burstable' }
  properties: {
    version: '15'
    administratorLogin: 'appadmin'
    administratorLoginPassword: 'Tr@ding${uniqueString(suffix)}!'
    storage: { storageSizeGB: 32 }
  }
}

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: server
  name: 'tradingdb'
}

resource fw 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = {
  parent: server
  name: 'AllowAzure'
  properties: { startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0' }
}

output connStr string = 'Host=${server.properties.fullyQualifiedDomainName};Database=tradingdb;Username=appadmin;Password=Tr@ding${uniqueString(suffix)}!'
