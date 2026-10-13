// Availability alerting for the shared PostgreSQL Flexible Server.
//
// Why: the existing `coldova-postgres-unavailable` alert is an Activity Log alert on the
// `flexibleServers/stop/action` operation, so it only fires for an explicit ARM stop. During
// incident 9c9bce28 (2026-10-13) the platform metric `is_db_alive` dropped from 1 to 0 at 06:17Z
// (the Activity Log alert fired at 06:23Z) and stayed at 0 until the server was started (06:26Z).
// A metric alert on `is_db_alive` detects unavailability from any cause (stop, crash, failover,
// maintenance), not only an ARM stop. With Maximum < 1 over PT5M it fires once the server has
// been down for a full 5-minute window.
//
// This module only adds alerting. It does NOT start/restart the server; runtime recovery stays a
// bounded operational action (see the PostgreSQL availability runbook), not an IaC setting.

param serverName string
param tags object

@description('Optional action group resource ID to notify. Leave empty to create the alert without notifications.')
param actionGroupId string = ''

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' existing = {
  name: serverName
}

resource dbAliveAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${serverName}-is-db-alive'
  location: 'global'
  tags: tags
  properties: {
    description: 'PostgreSQL ${serverName} is not alive (is_db_alive < 1). Check ARM state and the Activity Log first; see the PostgreSQL availability runbook.'
    severity: 1
    enabled: true
    scopes: [ server.id ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'DbNotAlive'
          metricNamespace: 'Microsoft.DBforPostgreSQL/flexibleServers'
          metricName: 'is_db_alive'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Maximum'
        }
      ]
    }
    actions: empty(actionGroupId) ? [] : [
      { actionGroupId: actionGroupId }
    ]
  }
}

output dbAliveAlertId string = dbAliveAlert.id
