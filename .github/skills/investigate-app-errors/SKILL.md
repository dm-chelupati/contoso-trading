# Investigate Application Errors

You are investigating an alert triggered by Dynatrace or a ServiceNow incident. Follow these steps end-to-end — from triage through mitigation and incident closure.

## Step 1: Acknowledge the incident
If a ServiceNow incident ID is provided (e.g. INC0010009):
- Use `AcknowledgeServiceNowIncident` to transition the incident to In Progress.
- Use `PostServiceNowDiscussionEntry` to post an initial note: "Investigation started by SRE Agent. Collecting telemetry from Dynatrace and Azure."

If no ServiceNow incident is provided, skip this step.

## Step 2: Understand the alert
Read the alert payload from the HTTP trigger or incident description. Identify:
- The affected service (e.g. order-service, gateway, payment-service)
- Error type (4xx vs 5xx) and HTTP routes affected
- Time window when the issue was reported

## Step 3: Confirm the issue is real
Use Dynatrace MCP tools to query traces and error rates for the affected service.
- Resolve the service entity ID using `dynatrace_get-entity-id`
- Query error spans: `fetch spans | filter dt.entity.service == "<ID>" | filter http.response.status_code >= 500`
- Query error logs: `fetch logs | filter dt.entity.service == "<ID>" | filter loglevel == "ERROR"`
- Check error rate over time with 5-minute bucketing to determine if it is sustained (not a single blip)
- Plot error rate chart using `PlotAreaChartWithCorrelation` to visualize the pattern

Also check via Azure CLI:
- `az containerapp list` — running status of all Container Apps
- `az postgres flexible-server show` — database state (Ready, Restarting, etc.)
- `az servicebus namespace show` — message bus health

## Step 4: Check for recent changes
Use Azure CLI to check recent deployments and infrastructure changes:
- `az containerapp revision list` — recent revisions, creation times, replica counts, traffic weights
- `az containerapp revision show` — replica count and running state for suspicious revisions
- Check Azure activity logs for config changes in the target resource group over last 24 hours
- If a GitHub repo is connected, check recent commits/PRs around the error start time

Correlate the error start time with deployment or change timestamps.

## Step 5: Identify root cause from source code and infrastructure
If the error traces point to a specific endpoint or service:
- Read the source code for that endpoint in the codeRefs/ directory
- Check error-handling patterns, database connection management, timeout configs
- Check infrastructure config (Bicep/Terraform) for resource sizing, connection limits
- For database errors: check `max_connections` parameter, server SKU, connection pooling
- For queue errors: check Service Bus queue metrics, dead-letter counts

Build a concrete evidence chain: error message → code path → infrastructure constraint → triggering event.

## Step 6: Update ServiceNow with findings
If a ServiceNow incident ID is present:
- Use `PostServiceNowDiscussionEntry` to post a detailed investigation summary including:
  - **Root Cause**: What failed and why (with error codes, resource names)
  - **Timeline**: When errors started, what changed, key events (UTC timestamps)
  - **Evidence**: Data sources queried (Dynatrace traces/logs, Azure CLI findings)
  - **Impact**: Which endpoints/services are affected, error rate
  - **Mitigation Plan**: What actions will be taken to restore service
- Use `UpdateServiceNowIncident` to set relevant fields:
  - `category` and `subcategory` based on the root cause (e.g. "software"/"database")
  - Any other relevant classification fields

## Step 7: Execute mitigation
Based on the root cause, **execute** concrete mitigation actions (don't just suggest them):

**Scaling issues** (e.g. connection exhaustion, resource limits):
- Scale down replicas: `az containerapp update --min-replicas <n> --max-replicas <n>`
- Wait for dependent services (e.g. database) to recover
- Verify with `az postgres flexible-server show --query state` or equivalent

**Deployment-related issues** (e.g. bad code deploy):
- Identify the last known good revision from `az containerapp revision list`
- Route traffic to the good revision: `az containerapp ingress traffic set --revision-weight <good-rev>=100`

**Configuration issues** (e.g. wrong environment variable, missing secret):
- Identify the misconfiguration from Container App env vars or secrets
- Propose the fix command (write operations require user confirmation in non-autonomous mode)

**Infrastructure issues** (e.g. database down, queue unavailable):
- Check dependent resource health and restart if needed
- Verify connectivity from the application side after recovery

After executing mitigation:
- Query Dynatrace for the most recent 5–15 minute window to confirm error rate has dropped to zero
- Verify all dependent services are healthy via Azure CLI

## Step 8: Create GitHub issue
Create a GitHub issue with:
- **Summary**: One-line description of what failed and root cause
- **Impact**: Services affected, error rate, user impact
- **Timeline**: When it started, key events, when mitigated (all UTC)
- **Evidence**: Charts, Dynatrace queries used, Azure CLI findings, error messages
- **Root Cause**: Detailed analysis backed by data
- **Mitigation Applied**: What was done to restore service
- **Remediation**: Short-term and long-term follow-up actions to prevent recurrence

Tag the issue with relevant labels (e.g. incident, database, P3, service-name).

## Step 9: Resolve ServiceNow incident
If a ServiceNow incident ID is present:
- Use `AcknowledgeServiceNowIncident` first if not already acknowledged
- Use `PostServiceNowDiscussionEntry` to post a final resolution summary including:
  - Mitigation actions taken and their results
  - Link to the GitHub issue for follow-up
  - Confirmation that errors have stopped (with Dynatrace evidence)
- Use `ResolveServiceNowIncident` to close the incident with resolution notes
- Verify the incident was resolved by calling `GetServiceNowIncident` and checking the state
- If state did not transition (e.g. due to missing required fields), use `UpdateServiceNowIncident` to populate required fields (assigned_to, category, subcategory) and retry resolution

## Step 10: Save learnings to memory
After the incident is fully resolved:
- Update or create a memory file under `memories/synthesizedKnowledge/` documenting:
  - The incident pattern (symptoms, root cause, evidence sources)
  - Mitigation and prevention steps
  - Key queries and commands that were useful
- Update the `debugging.md` index with a link to the new pattern file
- This ensures future incidents with similar symptoms are resolved faster
