#!/bin/bash
# Break-it scenarios for testing SRE Agent
# Run a scenario, then ask the agent what happened.
set -euo pipefail

RG="${1:?Usage: ./break.sh <resource-group> <scenario>}"
SCENARIO="${2:?Scenarios: stop-frontend | kill-order-service | block-db | scale-down-worker | kill-gateway}"
SUFFIX=$(az resource list -g "$RG" --query "[?type=='Microsoft.Web/sites'].name" -o tsv | sed 's/frontend-//')

case $SCENARIO in
  stop-frontend)
    az webapp stop -g "$RG" -n "frontend-$SUFFIX"
    echo "✅ Frontend stopped."
    echo "Ask agent: 'Users can't access the trading portal'"
    ;;
  kill-order-service)
    az containerapp update -g "$RG" -n "order-svc-$SUFFIX" --min-replicas 0 --max-replicas 0
    echo "✅ Order service scaled to 0."
    echo "Ask agent: 'Orders API returning 502 errors'"
    ;;
  block-db)
    PG=$(az postgres flexible-server list -g "$RG" --query "[0].name" -o tsv)
    az postgres flexible-server firewall-rule delete -g "$RG" -s "$PG" -n AllowAzure -y 2>/dev/null || true
    echo "✅ Database firewall blocked."
    echo "Ask agent: 'Both orders and payments returning 500 errors'"
    ;;
  scale-down-worker)
    az containerapp update -g "$RG" -n "worker-$SUFFIX" --min-replicas 0 --max-replicas 0
    echo "✅ Worker scaled to 0. Queue will back up."
    echo "Ask agent: 'Orders are being placed but not getting completed'"
    ;;
  kill-gateway)
    az containerapp update -g "$RG" -n "gateway-$SUFFIX" --min-replicas 0 --max-replicas 0
    echo "✅ Gateway scaled to 0."
    echo "Ask agent: 'Frontend can't reach any backend APIs'"
    ;;
  *)
    echo "Unknown: $SCENARIO"
    echo "Available: stop-frontend | kill-order-service | block-db | scale-down-worker | kill-gateway"
    exit 1
    ;;
esac
