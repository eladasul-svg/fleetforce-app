# FleetForce Model Context Protocol (MCP) Server

Enterprise Model Context Protocol (MCP) server bridging **Microsoft 365 Copilot**, **Claude Desktop**, and **Antigravity** into Salesforce FleetForce.

---

## 1. Capabilities & Tools

| Tool Name                            | Type  | Description                                                                                                                                                                         |
| :----------------------------------- | :---- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `get_invoice_reconciliation_summary` | Read  | Retrieves high-level financials (£ billed gross, net, VAT), match rate %, unallocated spend, and active threshold breaches.                                                         |
| `query_reconciliation_exceptions`    | Read  | Queries exception lines filtered by type (`Unallocated`, `Unregistered_Vehicles`, `Unmapped_Driver`, `Recharges_and_Fines`, `High_Value_Lines`, `Missing_EoC_Credits`, `Disputed`). |
| `get_cost_center_variance`           | Read  | Aggregates spend and unallocated variance across Business Units and Cost Centers.                                                                                                   |
| `delegate_line_task`                 | Write | Creates a standard Salesforce `Task` assigned to an exception line and shifts it to the In Progress queue.                                                                          |
| `resolve_line_exception`             | Write | Closes the open `Task` and marks the line as `Resolved` / `Clean`.                                                                                                                  |
| `execute_fleet_soql`                 | Read  | Governed read-only SOQL query runner against FleetForce objects.                                                                                                                    |

---

## 2. Pre-Packaged Investigation Prompts

- **`investigate_invoice_breach`:** Step-by-step triage workflow invoked when a fleet manager clicks _"Investigate with Copilot ↗"_ from a Microsoft Teams Adaptive Card alert.
- **`draft_vendor_dispute_notice`:** Generates formal commercial dispute correspondence backed by specific unverified vehicle line items.

---

## 3. Configuration & Quick Start

### A. Prerequisites

- Node.js >= 18
- Salesforce CLI (`sf`) authenticated to the target org (e.g. `fleetforce-dev-13`) OR environment variables:
  - `SALESFORCE_INSTANCE_URL`: `https://your-org.my.salesforce.com`
  - `SALESFORCE_ACCESS_TOKEN`: `00D...`
  - `SALESFORCE_NAMESPACE`: `fleetforce`

### B. Install & Run Tests

```bash
cd services/fleet-mcp-server
npm install
npm test
```

### C. Connect to Microsoft 365 Copilot

1. Open **Microsoft Copilot Studio** (`copilotstudio.microsoft.com`).
2. Create or open your Declarative Copilot Agent.
3. Import the OpenAPI specification located at [`copilot/openapi.yaml`](file:///Users/elad.asulin/fleetforce-app/copilot/openapi.yaml).
4. Configure OAuth 2.0 with the FleetForce Connected App credentials.
5. Deploy into enterprise Microsoft Teams channels.

### D. Connect to Claude Desktop or Antigravity

Add to your `claude_desktop_config.json` or Antigravity MCP settings:

```json
{
  "mcpServers": {
    "fleetforce": {
      "command": "node",
      "args": [
        "/Users/elad.asulin/fleetforce-app/services/fleet-mcp-server/index.js"
      ],
      "env": {
        "SF_TARGET_ORG": "fleetforce-dev-13"
      }
    }
  }
}
```
