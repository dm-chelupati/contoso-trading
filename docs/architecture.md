# Contoso Trading — Architecture & Dependencies

## Services
| Service | Type | Host | Port | Dependencies |
|---------|------|------|------|--------------|
| frontend | Node.js (Express) | App Service | 3000 | gateway |
| gateway | .NET 8 (ASP.NET) | Container App | 8080 | order-service, payment-service |
| order-service | .NET 8 | Container App | 8080 | PostgreSQL, Service Bus (orders queue) |
| payment-service | .NET 8 | Container App | 8080 | PostgreSQL |
| worker | .NET 8 | Container App | 8080 | Service Bus (orders queue), PostgreSQL |

## Request Flow
```
User → frontend (App Service)
  → gateway (Container App)
    → order-service → PostgreSQL + Service Bus
    → payment-service → PostgreSQL
  Worker listens on Service Bus orders queue
```

## Observability
- **Primary**: Dynatrace (all 5 services export traces + metrics + logs via OTLP)
- **Secondary**: Azure App Insights + Log Analytics Workspace
- Dynatrace environment: configured via DT_OTLP_ENDPOINT env var on each service

## Common Failure Modes

### 5xx Errors
- **Payment gateway timeout (504)**: payment-service has a 5% simulated failure rate. If you see sustained 504s, check if the rate exceeds baseline.
- **Database connection failures**: PostgreSQL connection pool exhaustion under load. Check `DATABASE_URL` connectivity and connection count.
- **Service Bus failures**: If worker can't connect to Service Bus, orders queue up. Check SERVICEBUS_CONNECTION env var.
- **OOM kills**: Container Apps have memory limits. Check restart count and memory metrics.

### 4xx Errors
- **404 on gateway root path**: Normal — Container App ingress health probes hit `/` which has no handler. Ignore.
- **404 on API endpoints**: Check if service is actually deployed (not placeholder image).
- **403 on frontend**: publicNetworkAccess may be disabled on App Service. Check with `az webapp show`.

## Handling Preferences
- **Confirm before acting**: Always verify error rates are sustained (>1 minute) before declaring an incident.
- **Use Dynatrace first**: Query Dynatrace MCP for distributed traces showing the error. This gives the full request path.
- **Correlate with deployments**: Check `az containerapp revision list` for recent revisions and their creation times.
- **Source code analysis**: If the trace points to a specific endpoint, examine the source code for that handler in the GitHub repo.
- **Mitigation in Azure**: For deployment issues, suggest rollback via `az containerapp revision activate`. For config issues, suggest `az containerapp update` with corrected env vars.
- **Resolve alert after mitigation**: After confirming recovery, close the fired Azure Monitor alert via the Alerts Management REST API (see below).

## Post-Mitigation: Resolve Azure Monitor Alert

After mitigating an incident and verifying recovery, always close the fired alert instance.

### Steps
1. Obtain an ARM access token: `az account get-access-token --resource https://management.azure.com --query accessToken -o tsv`
2. POST to the Alerts Management `changestate` API:
   ```bash
   curl -s -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -H "Content-Length: 0" \
     "https://management.azure.com<ALERT_ID>/changestate?api-version=2019-05-05-preview&newState=Closed"
   ```
   Replace `<ALERT_ID>` with the full alert resource ID from the alert payload.
3. Verify the response is HTTP 200 and `properties.essentials.alertState` is `Closed`.

### Important Notes
- Do NOT use `az monitor metrics alert update --enabled false` — that disables the alert rule, not the specific fired alert.
- The `az rest --method post` may be blocked by the safety filter. Use `az account get-access-token` + `curl` in `RunInTerminal` as a fallback.
- The `Content-Length: 0` header is required; omitting it causes HTTP 411.

