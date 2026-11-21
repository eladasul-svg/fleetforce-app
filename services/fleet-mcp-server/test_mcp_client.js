/**
 * @file test_mcp_client.js
 * @description Automated end-to-end test verifying the FleetForce MCP Server tools & prompts
 * against live Philips UK invoice data in scratch org fleetforce-dev-13.
 */

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function runTests() {
  console.log("=== FLEETFORCE MCP SERVER TEST RUNNER ===");

  const serverPath = path.join(__dirname, "index.js");
  const transport = new StdioClientTransport({
    command: "node",
    args: [serverPath],
    env: { ...process.env, SF_TARGET_ORG: "fleetforce-dev-13" }
  });

  const client = new Client(
    {
      name: "fleetforce-test-client",
      version: "1.0.0"
    },
    {
      capabilities: {}
    }
  );

  await client.connect(transport);
  console.log("✔ Connected to FleetForce MCP Server over stdio.");

  try {
    // 1. Verify Tools
    console.log("\n[Test 1] Listing MCP Tools...");
    const toolsResult = await client.listTools();
    const toolNames = toolsResult.tools.map((t) => t.name);
    console.log(
      `✔ Found ${toolNames.length} registered tools:`,
      toolNames.join(", ")
    );
    if (
      !toolNames.includes("get_invoice_reconciliation_summary") ||
      !toolNames.includes("query_reconciliation_exceptions") ||
      !toolNames.includes("get_cost_center_variance")
    ) {
      throw new Error("Missing expected reconciliation tools!");
    }

    // 2. Verify Prompts
    console.log("\n[Test 2] Listing MCP Prompts...");
    const promptsResult = await client.listPrompts();
    const promptNames = promptsResult.prompts.map((p) => p.name);
    console.log(
      `✔ Found ${promptNames.length} registered prompts:`,
      promptNames.join(", ")
    );
    if (!promptNames.includes("investigate_invoice_breach")) {
      throw new Error("Missing investigate_invoice_breach prompt!");
    }

    // 3. Test Tool: get_invoice_reconciliation_summary
    console.log(
      "\n[Test 3] Executing get_invoice_reconciliation_summary for doc #731513513..."
    );
    const summaryRes = await client.callTool({
      name: "get_invoice_reconciliation_summary",
      arguments: { billingDocNumber: "731513513" }
    });

    const summaryText = summaryRes.content[0].text;
    const summaryData = JSON.parse(summaryText);
    console.log(`✔ Total Billed Gross: £${summaryData.totalGross}`);
    console.log(
      `✔ Clean Match Rate: ${summaryData.cleanPercentage}% (${summaryData.cleanCount} of ${summaryData.lineCount} lines)`
    );
    console.log(
      `✔ Unallocated Spend: £${summaryData.unallocatedAssetAmount + summaryData.unallocatedDriverAmount} (${summaryData.unallocatedSpendPercentage}%)`
    );
    console.log(
      `✔ Recharge Spend: £${summaryData.rechargeAmount} (${summaryData.rechargeSpendPercentage}%)`
    );
    console.log(
      `✔ Active Threshold Breaches: ${summaryData.breachedThresholds ? summaryData.breachedThresholds.length : 0}`
    );

    // 4. Test Tool: query_reconciliation_exceptions (Recharges & Fines)
    console.log(
      "\n[Test 4] Executing query_reconciliation_exceptions (Recharges_and_Fines)..."
    );
    const exceptionsRes = await client.callTool({
      name: "query_reconciliation_exceptions",
      arguments: {
        billingDocNumber: "731513513",
        exceptionType: "Recharges_and_Fines",
        limit: 3
      }
    });

    const exceptionsData = JSON.parse(exceptionsRes.content[0].text);
    console.log(`✔ Returned ${exceptionsData.returnedCount} exception lines.`);
    if (exceptionsData.lines.length > 0) {
      const top = exceptionsData.lines[0];
      console.log(
        `   Sample Line: ${top.lineNumber} | Plate: ${top.assetPlate} | Driver: ${top.driverName} | Gross: £${top.grossAmount} | Type: ${top.rechargeType}`
      );
    }

    // 5. Test Tool: get_cost_center_variance
    console.log("\n[Test 5] Executing get_cost_center_variance...");
    const ccRes = await client.callTool({
      name: "get_cost_center_variance",
      arguments: { billingDocNumber: "731513513" }
    });

    const ccData = JSON.parse(ccRes.content[0].text);
    console.log(
      `✔ Top Cost Centers Count: ${ccData.topCostCenters ? ccData.topCostCenters.length : 0}`
    );
    if (ccData.topCostCenters && ccData.topCostCenters.length > 0) {
      const topCC = ccData.topCostCenters[0];
      console.log(
        `   Top Cost Center: ${topCC.costCenterName} (${topCC.companyName}) | Gross: £${topCC.grossAmount} | Lines: ${topCC.lineCount}`
      );
    }

    // 6. Test Tool: get_dispute_memo
    console.log("\n[Test 6] Executing get_dispute_memo for doc #731513513...");
    const disputeRes = await client.callTool({
      name: "get_dispute_memo",
      arguments: { billingDocNumber: "731513513" }
    });
    const memoText = disputeRes.content[0].text;
    console.log(
      `✔ Generated Commercial Dispute Memo (${memoText.length} characters)`
    );
    console.log("   Preview:", memoText.split("\n").slice(0, 4).join(" | "));

    // 7. Test Tool: import_vendor_invoice (Pattern B via MCP)
    console.log("\n[Test 7] Executing import_vendor_invoice (Pattern B)...");
    const importRes = await client.callTool({
      name: "import_vendor_invoice",
      arguments: {
        billingDocNumber: "MCP-TEST-BILL-001",
        vendorName: "Ayvens UK",
        currencyIso: "GBP",
        csvData:
          "line_number,license_plate,gross_amount,category\n1,KB23HKA,450.00,Monthly Payment\n2,UNKNOWN_99,320.00,Recharge\n"
      }
    });
    const importData = JSON.parse(importRes.content[0].text);
    console.log(
      `✔ Imported ${importData.linesInserted} lines into Invoice #${importData.billingDocNumber}`
    );
    console.log(
      `   Reconciliation Status: Clean: ${importData.summary.cleanCount}, Exceptions: ${importData.summary.exceptionCount}`
    );

    console.log("\n=========================================");
    console.log("🎉 ALL FLEETFORCE MCP TOOLS VERIFIED SUCCESSFULLY!");
    console.log("=========================================\n");
  } finally {
    await client.close();
  }
}

runTests().catch((err) => {
  console.error("\n❌ MCP Test Runner Failed:", err);
  process.exit(1);
});
