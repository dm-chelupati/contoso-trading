# Dynatrace DQL Reference

## How to find service entity IDs
Use the Dynatrace MCP tool `get-entity-id` with the service display name to resolve entity IDs at runtime. Do NOT hardcode entity IDs — they change across environments.

## DQL Query Patterns

### Get error spans (last 2 hours)
```dql
fetch spans, from:now()-2h
| filter dt.entity.service == "<ENTITY_ID>"
| filter http.response.status_code >= 500
| sort timestamp desc
| limit 20
| fields timestamp, span.name, http.request.method, http.response.status_code, trace_id
```

### Error rate timeseries
```dql
fetch spans, from:now()-2h
| filter dt.entity.service == "<ENTITY_ID>"
| summarize total=count(), errors=countIf(http.response.status_code >= 500), by:{bin(timestamp, 5m)}
| sort timestamp asc
```

### All spans for a service (success + error)
```dql
fetch spans, from:now()-2h
| filter dt.entity.service == "<ENTITY_ID>"
| summarize total=count(), by:{http.response.status_code}
| sort total desc
```

### Logs for a service
```dql
fetch logs, from:now()-2h
| filter dt.entity.service == "<ENTITY_ID>"
| filter loglevel == "ERROR"
| sort timestamp desc
| limit 20
| fields timestamp, content, loglevel
```

### Exception messages in logs
```dql
fetch logs, from:now()-2h
| filter dt.entity.service == "<ENTITY_ID>"
| filter loglevel == "ERROR" or loglevel == "FATAL"
| filter contains(content, "exception") or contains(content, "Exception") or contains(content, "error")
| sort timestamp desc
| limit 20
| fields timestamp, content
```

### Distributed traces with errors
```dql
fetch spans, from:now()-2h
| filter http.response.status_code >= 500
| summarize errorCount=count(), by:{dt.entity.service, span.name}
| sort errorCount desc
| limit 10
```

## DQL Syntax Rules
- ALWAYS use `countIf(condition)` — NEVER use `sum(if(condition, 1, 0))`
- Time range: `fetch spans, from:now()-2h`
- HTTP status: `http.response.status_code`
- Service filter: `dt.entity.service == "SERVICE-XXXXX"`
- Time bucketing: `by:{bin(timestamp, 5m)}`
- String contains: `contains(field, "value")` — case-sensitive
- Use `get-entity-id` MCP tool to resolve service names to entity IDs before querying

