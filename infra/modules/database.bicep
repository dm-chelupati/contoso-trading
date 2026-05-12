param location string
param suffix string
param tags object

// WARNING: The admin password is derived from uniqueString() and baked into the
// Container App secret at deploy time. If the password is rotated manually on the
// PostgreSQL server, every dependent Container App secret must be updated and a new
// revision created — otherwise services will fail with 28P01 (auth failed).
//
// TODO: Migrate to Azure Key Vault for credential storage so that:
//   1. Passwords are never in Bicep / source control.
//   2. Key Vault secret rotation + Container App Key Vault references keep
//      credentials in sync automatically.
//   See: https://learn.microsoft.com/azure/container-apps/manage-secrets

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
