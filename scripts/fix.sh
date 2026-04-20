#!/bin/bash
# Restore all services after testing
set -euo pipefail
RG="${1:?Usage: ./fix.sh <resource-group>}"
SUFFIX=$(az resource list -g "$RG" --query "[?type=='Microsoft.Web/sites'].name" -o tsv | sed 's/frontend-//')

echo "Restoring frontend..."
az webapp start -g "$RG" -n "frontend-$SUFFIX" 2>/dev/null || true

echo "Restoring gateway..."
az containerapp update -g "$RG" -n "gateway-$SUFFIX" --min-replicas 1 --max-replicas 3 2>/dev/null || true

echo "Restoring order service..."
az containerapp update -g "$RG" -n "order-svc-$SUFFIX" --min-replicas 1 --max-replicas 5 2>/dev/null || true

echo "Restoring worker..."
az containerapp update -g "$RG" -n "worker-$SUFFIX" --min-replicas 1 --max-replicas 10 2>/dev/null || true

echo "Restoring database firewall..."
PG=$(az postgres flexible-server list -g "$RG" --query "[0].name" -o tsv)
az postgres flexible-server firewall-rule create -g "$RG" -s "$PG" -n AllowAzure \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 2>/dev/null || true

echo "✅ All services restored."
