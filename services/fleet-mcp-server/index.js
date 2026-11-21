#!/usr/bin/env node
/**
 * @file index.js
 * @description Enterprise Model Context Protocol (MCP) Server for Salesforce FleetForce.
 * Bridges Microsoft 365 Copilot, Claude Desktop, and Antigravity into FleetForce Financial Reconciliation & Governance.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema
} from "@modelcontextprotocol/sdk/types.js";
import { execSync } from "child_process";

// Configuration & Cache
let cachedOrgInfo = null;
let cachedAccessToken = null;
let tokenExpiresAt = 0;

/**
 * Retrieves authenticated Salesforce session details.
 * Uses environment variables if set, otherwise queries active Salesforce CLI session.
 */
function getSalesforceAuth() {
  const now = Date.now();
  if (cachedOrgInfo && cachedAccessToken && now < tokenExpiresAt) {
    return { ...cachedOrgInfo, accessToken: cachedAccessToken };
  }

  const envInstanceUrl = process.env.SALESFORCE_INSTANCE_URL;
  const envAccessToken = process.env.SALESFORCE_ACCESS_TOKEN;
  const envNamespace = process.env.SALESFORCE_NAMESPACE || "fleetforce";

  if (envInstanceUrl && envAccessToken) {
    cachedOrgInfo = { instanceUrl: envInstanceUrl, namespace: envNamespace };
    cachedAccessToken = envAccessToken;
    tokenExpiresAt = now + 10 * 60 * 1000;
    return { ...cachedOrgInfo, accessToken: cachedAccessToken };
  }

  // Use sf CLI to discover org credentials
  try {
    const targetOrg = process.env.SF_TARGET_ORG || "fleetforce-dev-13";
    const orgRaw = execSync(`sf org display --json -o ${targetOrg}`, {
      stdio: ["pipe", "pipe", "ignore"]
    });
    const orgParsed = JSON.parse(orgRaw.toString()).result;

    const tokenRaw = execSync(
      `sf org auth show-access-token -o ${targetOrg} --json`,
      { stdio: ["pipe", "pipe", "ignore"] }
    );
    const tokenParsed = JSON.parse(tokenRaw.toString()).result;

    cachedOrgInfo = {
      instanceUrl: orgParsed.instanceUrl,
      namespace: orgParsed.namespace || "fleetforce",
      username: orgParsed.username
    };
    cachedAccessToken = tokenParsed.accessToken;
    tokenExpiresAt = now + 15 * 60 * 1000; // cache for 15 minutes

    return { ...cachedOrgInfo, accessToken: cachedAccessToken };
  } catch (error) {
    throw new Error(
      `Failed to resolve Salesforce credentials: ${error.message}`
    );
  }
}

/**
 * Invokes the FleetForce Apex REST endpoint.
 */
async function callApexRest(subPath, method = "GET", body = null) {
  const auth = getSalesforceAuth();
  const nsPrefix = auth.namespace ? `${auth.namespace}/` : "";
  const endpoint = `${auth.instanceUrl}/services/apexrest/${nsPrefix}fleet/v1/reconciliation/${subPath}`;

  const headers = {
    Authorization: `Bearer ${auth.accessToken}`,
    "Content-Type": "application/json"
  };

  const options = { method, headers };
  if (body) {
    options.body = JSON.stringify(body);
  }

  const res = await fetch(endpoint, options);
  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Salesforce Apex REST error [${res.status}]: ${errorText}`);
  }

  return await res.json();
}

/**
 * Invokes standard Salesforce REST SOQL endpoint.
 */
async function callSoql(query) {
  const auth = getSalesforceAuth();
  const queryParam = encodeURIComponent(query);
  const endpoint = `${auth.instanceUrl}/services/data/v60.0/query?q=${queryParam}`;

  const res = await fetch(endpoint, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${auth.accessToken}`,
      "Content-Type": "application/json"
    }
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`SOQL execution error [${res.status}]: ${errorText}`);
  }

  return await res.json();
}

// Instantiate MCP Server
const server = new Server(
  {
    name: "fleetforce-mcp-server",
    version: "1.0.0"
  },
  {
    capabilities: {
      tools: {},
      prompts: {}
    }
  }
);

// Define MCP Tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "get_invoice_reconciliation_summary",
        description:
          "Fetches high-level financial reconciliation KPIs, spend totals, match rate, and active governance threshold breaches for a fleet vendor invoice.",
        inputSchema: {
          type: "object",
          properties: {
            billingDocNumber: {
              type: "string",
              description: "Vendor billing document number (e.g. '731513513')."
            },
            invoiceId: {
              type: "string",
              description:
                "Salesforce Fleet_Invoice__c record Id (optional if billingDocNumber is provided)."
            }
          }
        }
      },
      {
        name: "query_reconciliation_exceptions",
        description:
          "Queries specific invoice exception lines that triggered threshold breaches or require operational follow-up (e.g. Unallocated spend, Driver recharges, Fines, Lines > £5k, Missing EoC credits).",
        inputSchema: {
          type: "object",
          properties: {
            billingDocNumber: {
              type: "string",
              description: "Vendor billing document number (e.g. '731513513')."
            },
            exceptionType: {
              type: "string",
              enum: [
                "All",
                "Unallocated",
                "Unregistered_Vehicles",
                "Unmapped_Driver",
                "Recharges_and_Fines",
                "High_Value_Lines",
                "Missing_EoC_Credits",
                "Disputed"
              ],
              description:
                "Filter exception lines by specific category or audit flag."
            },
            limit: {
              type: "number",
              description:
                "Maximum number of exception lines to return (default 20, max 100)."
            }
          },
          required: ["billingDocNumber"]
        }
      },
      {
        name: "get_cost_center_variance",
        description:
          "Retrieves cost center spend allocation and unallocated variance for an invoice, showing which business units carry the highest spend and anomalies.",
        inputSchema: {
          type: "object",
          properties: {
            billingDocNumber: {
              type: "string",
              description: "Vendor billing document number (e.g. '731513513')."
            }
          },
          required: ["billingDocNumber"]
        }
      },
      {
        name: "delegate_line_task",
        description:
          "Delegates an invoice exception line to an operational task in Salesforce, moving it to the 'In Progress' queue and notifying the assigned team member.",
        inputSchema: {
          type: "object",
          properties: {
            lineId: {
              type: "string",
              description: "Salesforce Fleet_Invoice_Line__c record ID."
            },
            subject: {
              type: "string",
              description: "Subject of the follow-up task."
            },
            priority: {
              type: "string",
              enum: ["High", "Normal", "Low"],
              description: "Priority of the task."
            },
            dueDateDays: {
              type: "number",
              description: "Days from today until task due date (default 3)."
            },
            instructions: {
              type: "string",
              description:
                "Specific investigation notes or instructions for the assignee."
            }
          },
          required: ["lineId", "subject"]
        }
      },
      {
        name: "resolve_line_exception",
        description:
          "Resolves an invoice line exception in Salesforce, closing associated tasks and marking the item as Clean/Reconciled.",
        inputSchema: {
          type: "object",
          properties: {
            lineId: {
              type: "string",
              description: "Salesforce Fleet_Invoice_Line__c record ID."
            },
            resolutionNotes: {
              type: "string",
              description:
                "Explanation of resolution, audit trail justification, or payroll deduction approval."
            }
          },
          required: ["lineId", "resolutionNotes"]
        }
      },
      {
        name: "execute_fleet_soql",
        description:
          "Executes a governed, read-only SOQL SELECT query against FleetForce objects.",
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "SOQL SELECT query string."
            }
          },
          required: ["query"]
        }
      },
      {
        name: "get_dispute_memo",
        description:
          "Generates an executive commercial dispute letter to the leasing vendor itemizing unallocated and contested line items on an invoice.",
        inputSchema: {
          type: "object",
          properties: {
            billingDocNumber: {
              type: "string",
              description: "Vendor billing document number (e.g. '731513513')."
            }
          },
          required: ["billingDocNumber"]
        }
      },
      {
        name: "import_vendor_invoice",
        description:
          "Ingests and audits an Ayvens/vendor invoice file (CSV text or structured JSON rows), automatically resolving assets, drivers, and cost centers.",
        inputSchema: {
          type: "object",
          properties: {
            billingDocNumber: {
              type: "string",
              description: "Vendor billing document number (e.g. '731513514')."
            },
            vendorName: {
              type: "string",
              description: "Vendor name (e.g. 'Ayvens UK')."
            },
            currencyIso: {
              type: "string",
              enum: ["GBP", "EUR", "USD"],
              description: "Billing currency (default 'GBP')."
            },
            csvData: {
              type: "string",
              description: "Raw CSV content of the invoice schedule."
            },
            lines: {
              type: "array",
              description:
                "Array of structured line item objects if passing JSON."
            }
          },
          required: ["billingDocNumber"]
        }
      }
    ]
  };
});

// Handle Tool Execution
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "get_invoice_reconciliation_summary": {
        const queryParam = args.billingDocNumber
          ? `docNumber=${encodeURIComponent(args.billingDocNumber)}`
          : `invoiceId=${encodeURIComponent(args.invoiceId)}`;
        const result = await callApexRest(`summary?${queryParam}`);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result.data, null, 2)
            }
          ]
        };
      }

      case "query_reconciliation_exceptions": {
        const filterType = args.exceptionType || "All";
        const limit = args.limit || 20;
        const queryParam = `docNumber=${encodeURIComponent(args.billingDocNumber)}&type=${encodeURIComponent(filterType)}&limit=${limit}`;
        const result = await callApexRest(`exceptions?${queryParam}`);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result.data, null, 2)
            }
          ]
        };
      }

      case "get_cost_center_variance": {
        const queryParam = `docNumber=${encodeURIComponent(args.billingDocNumber)}`;
        const result = await callApexRest(`cost-centers?${queryParam}`);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result.data, null, 2)
            }
          ]
        };
      }

      case "delegate_line_task": {
        const result = await callApexRest("delegate", "POST", {
          lineId: args.lineId,
          subject: args.subject,
          priority: args.priority || "Normal",
          instructions: args.instructions || ""
        });
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2)
            }
          ]
        };
      }

      case "resolve_line_exception": {
        const result = await callApexRest("resolve", "POST", {
          lineId: args.lineId,
          resolutionNotes: args.resolutionNotes
        });
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2)
            }
          ]
        };
      }

      case "execute_fleet_soql": {
        if (!args.query.trim().toLowerCase().startsWith("select")) {
          throw new Error("Only read-only SELECT queries are permitted.");
        }
        const result = await callSoql(args.query);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result.records, null, 2)
            }
          ]
        };
      }

      case "get_dispute_memo": {
        const queryParam = `docNumber=${encodeURIComponent(args.billingDocNumber)}`;
        const result = await callApexRest(`dispute-memo?${queryParam}`);
        return {
          content: [
            {
              type: "text",
              text: result.data || result.message
            }
          ]
        };
      }

      case "import_vendor_invoice": {
        const result = await callApexRest("import", "POST", {
          billingDocNumber: args.billingDocNumber,
          vendorName: args.vendorName || "Ayvens UK",
          currencyIso: args.currencyIso || "GBP",
          csvData: args.csvData,
          lines: args.lines
        });
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(result.data, null, 2)
            }
          ]
        };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      isError: true,
      content: [
        {
          type: "text",
          text: `Tool Execution Error [${name}]: ${error.message}`
        }
      ]
    };
  }
});

// Define MCP Prompts
server.setRequestHandler(ListPromptsRequestSchema, async () => {
  return {
    prompts: [
      {
        name: "investigate_invoice_breach",
        description:
          "Executes an investigation into a threshold breach on a vendor invoice and produces executive recommendations.",
        arguments: [
          {
            name: "billingDocNumber",
            description: "Invoice billing document number (e.g. 731513513)",
            required: true
          },
          {
            name: "ruleName",
            description:
              "The name of the breached rule (e.g. Operational Recharge Surge)",
            required: true
          }
        ]
      },
      {
        name: "draft_vendor_dispute_notice",
        description:
          "Drafts a formal dispute letter citing specific unallocated or unverified lines on a vendor invoice.",
        arguments: [
          {
            name: "billingDocNumber",
            description: "Invoice billing document number (e.g. 731513513)",
            required: true
          }
        ]
      }
    ]
  };
});

// Handle Get Prompt
server.setRequestHandler(GetPromptRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "investigate_invoice_breach") {
    return {
      description: `Investigate reconciliation breach: ${args.ruleName} on bill #${args.billingDocNumber}`,
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: `Please investigate the reconciliation breach '${args.ruleName}' on vendor invoice doc #${args.billingDocNumber}.
1. Call 'get_invoice_reconciliation_summary' to inspect the total variance, match rate, and active threshold violations.
2. Call 'query_reconciliation_exceptions' matching the rule category (e.g. 'Recharges_and_Fines' or 'Unallocated') to list top outlier vehicles and drivers.
3. Call 'get_cost_center_variance' to see which business units bear the costs.
4. Synthesize a concise executive breakdown explaining:
   - Root cause of the variance.
   - Top 3 vehicles/drivers contributing to the breach.
   - Recommended next actions (e.g. payroll deductions, task assignments, or vendor disputes).`
          }
        }
      ]
    };
  }

  if (name === "draft_vendor_dispute_notice") {
    return {
      description: `Draft commercial dispute notice for invoice doc #${args.billingDocNumber}`,
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text: `Please draft a formal commercial dispute notice for vendor invoice doc #${args.billingDocNumber}.
1. Call 'query_reconciliation_exceptions' with exceptionType 'Unregistered_Vehicles' and 'Disputed' to extract unverified line items.
2. Structure the letter with:
   - Invoice Reference & Date.
   - Summary of disputed amount and count of unverified vehicles.
   - Table of top unallocated vehicle lines (Line #, License Plate, Billed Amount, Rejection Reason).
   - Demand for credit memo / invoice reissue prior to payment release.`
          }
        }
      ]
    };
  }

  throw new Error(`Unknown prompt: ${name}`);
});

// Start Server via Stdio
async function run() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("FleetForce MCP Server running on stdio.");
}

run().catch((error) => {
  console.error("Fatal MCP Server startup error:", error);
  process.exit(1);
});
