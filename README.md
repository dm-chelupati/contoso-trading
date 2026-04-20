# Contoso Trading

Multi-service order processing platform for testing Azure SRE Agent. Deploys 5 services with a database, message queue, and monitoring — then break things and see if the agent can diagnose them.

## Architecture

```
User → Frontend (App Service) → Gateway (Container App) → Order Service → PostgreSQL
                                                        → Payment Service → PostgreSQL
                                                        → Service Bus → Worker
```

| Service | Type | Role |
|---------|------|------|
| Frontend | App Service (Node.js) | User-facing web UI |
| Gateway | Container App (.NET) | Routes requests to backend services |
| Order Service | Container App (.NET) | Creates orders, publishes to queue |
| Payment Service | Container App (.NET) | Processes payments |
| Worker | Container App (.NET) | Consumes queue, completes orders |
| Database | PostgreSQL Flexible Server | Shared order + payment data |
| Service Bus | Standard tier | Async order processing pipeline |
| Monitoring | Log Analytics + App Insights | Telemetry from all services |

## Deploy

```bash
azd up
```

## Break-it Scenarios

After deploying, create realistic failures for the SRE Agent to investigate:

```bash
# Frontend goes down — users can't access the portal
./scripts/break.sh <resource-group> stop-frontend

# Order service dies — orders API returns 502
./scripts/break.sh <resource-group> kill-order-service

# Database blocked — both orders and payments return 500
./scripts/break.sh <resource-group> block-db

# Worker stops — orders created but never completed (queue backs up)
./scripts/break.sh <resource-group> scale-down-worker

# Gateway dies — frontend can't reach any backend
./scripts/break.sh <resource-group> kill-gateway
```

## Restore

```bash
./scripts/fix.sh <resource-group>
```
