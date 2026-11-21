#!/usr/bin/env python3
"""
inbound_invoice_listener.py — Pattern A: Zero-Touch Inbound Fleet Invoice Listener.
Simulates an automated enterprise pipeline (e.g. Power Automate / Mailbox Watcher / SharePoint Webhook)
that detects an Ayvens vendor consolidated bill arrival, ingests lines into FleetForce, executes
the threshold audit engine, and fires Microsoft Teams alert notifications without manual user intervention.
"""

import sys
import json
import subprocess
import requests
from datetime import datetime

TARGET_ORG = "fleetforce-dev-13"

def get_salesforce_credentials():
    print("[1/4] Authenticating with Salesforce FleetOps via CLI session...")
    org_cmd = ["sf", "org", "display", "--json", "-o", TARGET_ORG]
    org_out = subprocess.check_output(org_cmd, stderr=subprocess.DEVNULL)
    org_res = json.loads(org_out)["result"]

    token_cmd = ["sf", "org", "auth", "show-access-token", "-o", TARGET_ORG, "--json"]
    token_out = subprocess.check_output(token_cmd, stderr=subprocess.DEVNULL)
    token_res = json.loads(token_out)["result"]

    return {
        "instance_url": org_res["instanceUrl"],
        "namespace": org_res.get("namespace", "fleetforce"),
        "access_token": token_res["accessToken"]
    }

def simulate_inbound_arrival():
    print("\n[2/4] Intercepting inbound vendor transmission from Ayvens (UK / FL)...")
    doc_number = f"AYV-UK-AUTO-{datetime.now().strftime('%y%m%d%H%M')}"
    
    # Sample simulated transmission of monthly vehicle lines
    csv_payload = (
        "line_number,license_plate,driver_payroll,cost_center_code,category,concerning,recharge_type,net_amount,vat_amount,gross_amount,notes\n"
        "101,KB23HKA,7306751,CC-001,Monthly Payment,Contract,Fixed Lease,450.00,90.00,540.00,Authorized fleet lease\n"
        "102,MS22KDK,7358029,CC-002,Monthly Payment,Contract,Fixed Lease,420.00,84.00,504.00,Authorized field vehicle\n"
        "103,UNKNOWN_GHOST_1,,CC-003,Monthly Payment,Contract,Fixed Lease,620.00,124.00,744.00,Unregistered asset alert\n"
        "104,KB23HKA,7306751,CC-001,Recharge,Damage,Body Repair,3200.00,640.00,3840.00,Heavy damage repair recharge\n"
    )
    print(f"   Detected Billing Document #{doc_number} (Format: CSV / EDI 810)")
    return doc_number, csv_payload

def ingest_to_fleetforce(creds, doc_number, csv_payload):
    print("\n[3/4] Dispatching payload to FleetForce REST ingestion endpoint...")
    ns = creds["namespace"] + "/" if creds["namespace"] else ""
    endpoint = f"{creds['instance_url']}/services/apexrest/{ns}fleet/v1/reconciliation/import"

    headers = {
        "Authorization": f"Bearer {creds['access_token']}",
        "Content-Type": "application/json"
    }

    body = {
        "billingDocNumber": doc_number,
        "vendorName": "Ayvens UK Inbound EDI",
        "currencyIso": "GBP",
        "csvData": csv_payload
    }

    resp = requests.post(endpoint, headers=headers, json=body)
    if resp.status_code != 200:
        print(f"❌ Ingestion failed: {resp.status_code} - {resp.text}")
        sys.exit(1)

    data = resp.json()["data"]
    print("✔ Ingestion & Audit Engine Completed Successfully:")
    print(f"   Invoice Record ID: {data['invoiceId']}")
    print(f"   Lines Ingested:    {data['linesInserted']}")
    
    summary = data["summary"]
    sym = summary.get("currencySymbol", "£")
    print(f"   Total Gross:       {sym}{summary['totalGross']:,.2f}")
    print(f"   Clean Lines:       {summary['cleanCount']} ({summary['cleanPercentage']}%)")
    print(f"   Exceptions:        {summary['exceptionCount']} lines")
    print(f"   Threshold Breaches:{len(summary.get('breachedThresholds', []))}")

    return data

def verify_push_alert(data):
    print("\n[4/4] Outbound Notification Engine (Teams / Copilot):")
    summary = data["summary"]
    breaches = summary.get("breachedThresholds", [])
    if breaches:
        print("   🚨 Platform Event 'Fleet_Audit_Event__e' fired!")
        print("   📢 Teams Adaptive Card (v1.4) enqueued via FleetTeamsNotificationQueueable:")
        for b in breaches:
            print(f"      - [{b['severity']}] {b['ruleName']}: {b['message']}")
        print("   🔗 Copilot deep-link prompt activated.")
    else:
        print("   ✔ No governance threshold breaches. Payment auto-cleared.")

    print("\n=======================================================")
    print("🎉 PATTERN A: ZERO-TOUCH INGESTION PIPELINE DEMO COMPLETE")
    print("=======================================================\n")

if __name__ == "__main__":
    creds = get_salesforce_credentials()
    doc_num, payload = simulate_inbound_arrival()
    result = ingest_to_fleetforce(creds, doc_num, payload)
    verify_push_alert(result)
