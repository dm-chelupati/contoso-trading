# Runbook: PostgreSQL availability (order / payment 5xx)

Applies to the Coldova deployment of contoso-trading:

| Item | Value |
|---|---|
| Subscription | `4e6f68bd-b1ea-415f-a65b-ef4a41c9e124` |
| Resource group | `rg-coldova-guarded-demo` |
| PostgreSQL Flexible Server | `pg-63bbdsqq2m2co` (B1ms, PG 15) |
| App Insights | `ai-63bbdsqq2m2co` |
| Log Analytics | `law-63bbdsqq2m2co` |
| DB consumers | `order-svc-*`, `payment-svc-*`, `worker-*` (via Container Apps secret `db-conn`) |

Typical triggering alerts: **Contoso Order Processing Runtime Failures** (App Insights failed
requests) or any PostgreSQL availability alert.

## Key symptom pattern

`/health` on every service is a **liveness-only** endpoint (`Results.Ok(...)`, no DB call — see
`order-service/Program.cs`, `payment-service/Program.cs`, `gateway/Program.cs`). When PostgreSQL is
down you will therefore see:

- `GET /orders`, `GET /payments` -> **500** (order/payment services)
- `GET /api/orders` -> 500, `GET /api/payments` -> **502** (gateway)
- `GET /health` -> **200** everywhere

Container Apps stay `Running` and health probes stay green, so the platform will **not** restart or
flag anything. Do not conclude "the app is healthy" from `/health` or `runningStatus`.

## 1. Diagnose (read-only)

```bash
SUB=4e6f68bd-b1ea-415f-a65b-ef4a41c9e124
RG=rg-coldova-guarded-demo
PG_ID=/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.DBforPostgreSQL/flexibleServers/pg-63bbdsqq2m2co

# a) ARM state (Ready | Stopped | Starting | Stopping ...)
az postgres flexible-server show -g $RG -n pg-63bbdsqq2m2co --subscription $SUB --query state -o tsv

# b) Who/what changed it
az monitor activity-log list --resource-group $RG --offset 2h --subscription $SUB \
  --query "[?contains(operationName.value,'flexibleServers')].{t:eventTimestamp,op:operationName.value,s:status.value,caller:caller}" -o table

# c) DB-level availability (strongest signal; apps emit no SQL dependency telemetry)
az monitor metrics list --resource $PG_ID --metrics is_db_alive connections_failed connections_succeeded \
  --interval PT1M --offset 30m --aggregation Maximum Total -o table
```

Interpretation:
- `is_db_alive` emits explicit **0** while the server is stopped; `connections_succeeded` emits no data.
- `connections_failed` stays 0 during a stop (clients never reach the server), so it is **not** a stop signal.
  A rise in `connections_failed` with `is_db_alive=1` points to auth/credential problems instead
  (separate, proposal-only process — do not rotate credentials as part of this runbook).

Application evidence (Log Analytics):

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(30m)
| where Log_s has_any ("Database error", "Failed to connect", "NpgsqlException")
| summarize n = count(), lastSeen = max(TimeGenerated) by ContainerAppName_s
```

Expected during an outage: `Database error on GET /orders: Failed to connect to <server-ip>:5432`
(`Npgsql.NpgsqlException (0x80004005)`). Note: avoid the alias `last` in KQL here; use `lastSeen`.

Request evidence (App Insights):

```kusto
requests
| where timestamp > ago(1h)
| summarize total = count(), failed = countif(success == false) by bin(timestamp, 1m), name, resultCode
| order by timestamp desc
```

## 2. Decide

| ARM state | App evidence | Action |
|---|---|---|
| `Stopped` | any | Start the server (step 3). |
| `Ready` | Npgsql connect failures in current logs **and** `is_db_alive=0` | Restart the server (step 3). |
| `Ready` | no DB errors, `is_db_alive=1` | Do **not** restart. Investigate the app/gateway instead. |
| `Starting`/`Stopping`/`Updating` | any | Wait for the operation to finish, then re-evaluate. |

Never change credentials, firewall rules, networking, IAM, SKU, storage, backup, HA, schema or data as
part of availability recovery.

## 3. Recover

Start (server `Stopped`):

```bash
az postgres flexible-server start -g $RG -n pg-63bbdsqq2m2co --subscription $SUB
```

Restart (server `Ready` but proven unreachable):

```bash
az postgres flexible-server restart -g $RG -n pg-63bbdsqq2m2co --subscription $SUB
```

A B1ms start takes about 2-3 minutes. Npgsql connection pools reconnect automatically, so **no
container app restart is needed**.

## 4. Verify (all three required)

1. `az postgres flexible-server show ... --query state` returns `Ready`.
2. PG metrics: `is_db_alive` = 1 and a `connections_succeeded` burst (~40 in the first minute is
   typical as pools re-open). Platform metrics lag ~1-2 minutes, so re-query if the latest minute is still 0.
3. App: the LAW query above shows no `Database error` after the start time, and App Insights `requests` for
   `GET /api/orders` / `GET /api/payments` return 200 with `failed = 0`.
   A public probe of the gateway (`https://<gateway-fqdn>/api/orders`) should return 200. Use
   `/api/orders` rather than `/health` because `/health` does not exercise the DB.

## 5. Rollback

Starting/restarting a server only returns it to its pre-incident running state; there is nothing to roll
back. If the stop was intentional (e.g. a cost-saving or maintenance window), coordinate with the
caller from the activity log and stop it again with `az postgres flexible-server stop` after the window
is agreed.

## 6. Follow-up

- Record the activity-log caller and reason for the stop.
- Consider a readiness endpoint that checks DB connectivity (e.g. `/health/ready`) so DB loss is visible
  to probes and dashboards. Keep `/health` liveness-only so a DB outage does not cause restart loops.

## Incident history

| Date (UTC) | Alert | Cause | Detection -> recovery |
|---|---|---|---|
| 2026-10-13 | Contoso Order Processing Runtime Failures (`2072db85-ee58-4730-bd13-d91a91b0f000`) | Manual `flexibleServers/stop/action` at 13:52:16 | Alert 13:56:11; started by SRE Agent ~13:59; healthy 13:59:44 |
