# Dynatrace DQL Reference

## Service Entity IDs
Update this file with your service entity IDs from Dynatrace.

| Service | Entity ID | Display Name |
|---------|-----------|-------------|
| frontend | SERVICE-D41D10F471E5CCC2 | nginx frontend-* on port 3000 |
| gateway | SERVICE-1841B6C0EC3A3659 | gateway |
| order-service | SERVICE-98A1541771EE582C | order-service |
| payment-service | SERVICE-4F0A69343E18903B | payment-service |
| worker | SERVICE-3895AA8548E9AE53 | worker |

## Verified DQL Queries

### Get error spans (last 2 hours)
```dql
fetch spans, from:now()-2h
| filter service.id == "SERVICE-XXXXXXXXXXXXXXXX"
| filter isNotNull(http.response.status_code) and http.response.status_code >= 500
| sort start_time desc
| limit 20
| fields start_time, span.name, http.request.method, http.response.status_code, trace_id
```

### Error rate timeseries
```dql
fetch spans, from:now()-2h
| filter service.id == "SERVICE-XXXXXXXXXXXXXXXX"
| makeTimeseries interval:5m, { total=count(), errors=countIf(isNotNull(http.response.status_code) and http.response.status_code >= 500) }
| sort timeframe[start]
```

### Logs for a service
```dql
fetch logs, from:now()-2h
| filter service.id == "SERVICE-XXXXXXXXXXXXXXXX"
| filter loglevel == "ERROR"
| sort timestamp desc
| limit 20
| fields timestamp, content, loglevel
```

## DQL Syntax Rules
- ALWAYS use `countIf(condition)` — NEVER use `sum(if(condition, 1, 0))`
- Time range: `fetch spans, from:now()-2h`
- HTTP status: `http.response.status_code`
- Service filter: `service.id == "SERVICE-XXXXX"`
- Time bucketing: `makeTimeseries interval:5m, {total=count(), errors=countIf(...)}` then `sort timeframe[start]`

