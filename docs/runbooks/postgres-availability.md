# Runbook: PostgreSQL availability (`contoso-postgres-unavailable`)

**Applies to:** Azure Monitor alert `contoso-postgres-unavailable` on the PostgreSQL Flexible Server
`pg-<suffix>` (resource group `rg-contoso-swe`, PG 15, Standard_B1ms, HA disabled).
Downstream impact: `order-service`, `payment-service` and `worker` lose database connectivity; the
gateway returns `500`/`502` on `/api/orders` and `/api/payments` while `/health` keeps returning `200`.

> The gateway `/health` route does **not** touch the database. Never use it alone as proof that the
> data path is healthy — always check `/api/orders` and `/api/payments` (or their telemetry) too.

## 1. Diagnose

1. **ARM state**

   ```bash
   az postgres flexible-server show -g rg-contoso-swe -n pg-<suffix> \
     --subscription <subscription-id> --query state -o tsv
   ```

   `Stopped` → go to *Recover*. `Ready` → only proceed if telemetry (step 3) independently proves
   database connectivity is failing.

2. **Who/what changed the server** — Activity Log on the server resource. Look for
   `Microsoft.DBforPostgreSQL/flexibleServers/stop/action` (and its caller) or a Resource Health
   `Downtime` event with `cause = UserInitiated` / `PlatformInitiated`.

3. **Application telemetry** (App Insights is workspace-based → query the Log Analytics workspace):

   ```kusto
   // Npgsql connection failures (signature of a stopped/unreachable server)
   AppExceptions
   | where TimeGenerated > ago(1h)
   | where OuterMessage has ":5432"
   | summarize n = count(), firstSeen = min(TimeGenerated), lastSeen = max(TimeGenerated)
       by ExceptionType
   ```

   Expected signature while the server is down: `System.TimeoutException` (occasionally
   `System.Net.Sockets.SocketException`) with message `Failed to connect to <server-ip>:5432`.

   ```kusto
   // Gateway -> order/payment dependency health (exclude the Dynatrace OTLP exporter noise)
   AppDependencies
   | where TimeGenerated > ago(1h)
   | where Target !has "dynatrace"
   | summarize total = count(), failed = countif(Success == false) by bin(TimeGenerated, 5m), Target
   | order by TimeGenerated desc
   ```

   > **KQL gotcha:** do not alias a column as `last` (e.g. `last = max(TimeGenerated)`); the query
   > fails with a generic "An error occurred while querying Log Analytics" error. Use `lastSeen`.
   >
   > **Noise:** `AppDependencies` rows targeting `*.live.dynatrace.com` fail at 100% independently of
   > this incident — exclude them.

## 2. Recover (bounded)

Only one action is in scope: **start** the server when ARM reports `Stopped`, or **restart** it when ARM
reports `Ready` but telemetry proves the application cannot connect.

```bash
az postgres flexible-server start -g rg-contoso-swe -n pg-<suffix> --subscription <subscription-id>
```

Do **not** change credentials, firewall rules, networking, IAM, SKU, storage, backups, HA, schema, or
data as part of this runbook. Do not encode a start/restart into IaC — it is a runtime action.

Typical duration: start completes in ~2–4 minutes; application errors clear within ~1–2 minutes after
ARM reports `Ready` (Npgsql reconnects on the next request; no app restart needed).

## 3. Validate

All three must hold:

1. ARM `state` is `Ready`.
2. No new `:5432` exceptions in `AppExceptions` and `failed == 0` for order/payment dependencies over a
   window of at least a few minutes **starting after** ARM reported `Ready`.
3. The public gateway responds `200` on `/api/orders` and `/api/payments` (not only `/health`):

   ```kusto
   AppRequests
   | where TimeGenerated > ago(10m)
   | summarize total = count(), failed = countif(Success == false), codes = make_set(ResultCode) by Name
   ```

   If you probe the gateway directly with `curl`, a `403` with an `x-deny-reason` response header comes
   from an egress proxy on the calling host, not from the gateway — use the telemetry query instead.

## 4. Rollback

Starting the server is non-destructive. If the stop was intentional (planned maintenance / cost
saving), coordinate with the caller in the Activity Log and stop it again:

```bash
az postgres flexible-server stop -g rg-contoso-swe -n pg-<suffix> --subscription <subscription-id>
```

## 5. Follow-up

- If the stop was not intentional, find the caller in the Activity Log and consider a resource lock or
  an Azure Policy / RBAC change to restrict `flexibleServers/stop/action`.
- Note: Azure automatically restarts a Flexible Server 7 days after it was stopped.
