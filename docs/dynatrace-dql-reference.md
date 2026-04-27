# Dynatrace DQL Reference

## Service Entity IDs
Update this file with your service entity IDs from Dynatrace.

| Service | Entity ID | Display Name |
|---------|-----------|-------------|
| EDIT_ME | SERVICE-XXXXXXXXXXXXXXXX | your-service |

## Verified DQL Queries

### Get error spans (last 2 hours)
```dql
fetch spans, from:now()-2h
| filter dt.entity.service == "SERVICE-XXXXXXXXXXXXXXXX"
| filter http.response.status_code >= 500
| sort timestamp desc
| limit 20
| fields timestamp, span.name, http.request.method, http.response.status_code, trace_id
```

### Error rate timeseries
```dql
fetch spans, from:now()-2h
| filter dt.entity.service == "SERVICE-XXXXXXXXXXXXXXXX"
| summarize total=count(), errors=countIf(http.response.status_code >= 500), by:{bin(timestamp, 5m)}
| sort timestamp asc
```

### Logs for a service
```dql
fetch logs, from:now()-2h
| filter dt.entity.service == "SERVICE-XXXXXXXXXXXXXXXX"
| filter loglevel == "ERROR"
| sort timestamp desc
| limit 20
| fields timestamp, content, loglevel
```

## DQL Syntax Rules
- ALWAYS use `countIf(condition)` — NEVER use `sum(if(condition, 1, 0))`
- Time range: `fetch spans, from:now()-2h`
- HTTP status: `http.response.status_code`
- Service filter: `dt.entity.service == "SERVICE-XXXXX"`
- Time bucketing: `by:{bin(timestamp, 5m)}`

