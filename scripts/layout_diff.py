#!/usr/bin/env python3
"""
layout_diff.py — Generate layout-vs-field diff Markdown for Fleetforce objects.

Usage:
    python3 scripts/layout_diff.py [object_api_name ...]

If no args given, runs all OBJECTS defined in the OBJECTS list below.
Output goes to docs/layouts/<Object>__layout-diff.md
"""

import sys
import os
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime

# ── Configuration ──────────────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).parent.parent
OBJECTS_DIR = REPO_ROOT / "force-app/main/default/objects"
LAYOUTS_DIR = REPO_ROOT / "force-app/main/default/layouts"
OUTPUT_DIR  = REPO_ROOT / "docs/layouts"

# Salesforce namespace used in the org
NS = "fleetforce"

# System/audit fields to exclude from "missing" counts
SYSTEM_FIELDS = {
    "Id", "Name", "CreatedDate", "CreatedById", "CreatedBy",
    "LastModifiedDate", "LastModifiedById", "LastModifiedBy",
    "SystemModstamp", "IsDeleted", "LastActivityDate",
    "LastViewedDate", "LastReferencedDate", "OwnerId",
    "RecordTypeId", "MasterRecordId", "CurrencyIsoCode",
}

# Objects to process (bare API name without namespace prefix)
OBJECTS = [
    "Fleet_Asset__c",
    "Reservation__c",
    "Telemetry_Violation__c",
    "Service_Ticket__c",
    "Fleet_Branch__c",
]

# XML namespace for Salesforce metadata
SF_NS = "http://soap.sforce.com/2006/04/metadata"
XMLNS = f"{{{SF_NS}}}"

# ── Helpers ────────────────────────────────────────────────────────────────────

def strip_ns(tag):
    """Remove XML namespace prefix from a tag name."""
    return tag.replace(XMLNS, "")


def parse_fields(obj_name):
    """
    Parse all field XML files for an object.
    Returns list of dicts: {api_name, label, type, required}
    """
    fields_dir = OBJECTS_DIR / obj_name / "fields"
    if not fields_dir.exists():
        return []

    fields = []
    for xml_file in sorted(fields_dir.glob("*.field-meta.xml")):
        tree = ET.parse(xml_file)
        root = tree.getroot()

        api_name = xml_file.stem.replace(".field-meta", "")
        label    = root.findtext(f"{XMLNS}label") or api_name
        ftype    = root.findtext(f"{XMLNS}type") or "Unknown"
        req_el   = root.findtext(f"{XMLNS}required")
        required = req_el and req_el.lower() == "true"

        fields.append({
            "api_name": api_name,
            "label":    label,
            "type":     ftype,
            "required": required,
        })

    return fields


def parse_layout(obj_name):
    """
    Find the layout file for an object and parse its sections/items.
    Returns (layout_filename, sections_list) where sections_list is:
        [ { label, columns, items: [ field_api_name_or_None ] } ]
    Items include both field references and spacers (None).
    """
    # Find matching layout files (there may be multiple)
    pattern = f"{obj_name}-*Layout*.layout-meta.xml"
    layout_files = sorted(LAYOUTS_DIR.glob(pattern))

    if not layout_files:
        # Try without "Layout" keyword
        pattern2 = f"{obj_name}-*.layout-meta.xml"
        layout_files = sorted(LAYOUTS_DIR.glob(pattern2))

    if not layout_files:
        return [], []

    results = []
    for layout_file in layout_files:
        tree = ET.parse(layout_file)
        root = tree.getroot()

        sections = []
        for section_el in root.findall(f"{XMLNS}layoutSections"):
            label_el   = section_el.find(f"{XMLNS}label")
            style_el   = section_el.find(f"{XMLNS}style")
            sec_label  = label_el.text if label_el is not None else "(unlabeled)"
            style      = style_el.text if style_el is not None else "TwoColumnsTopToBottom"
            columns    = 1 if "OneColumn" in style else 2

            items = []
            for col_el in section_el.findall(f"{XMLNS}layoutColumns"):
                for item_el in col_el.findall(f"{XMLNS}layoutItems"):
                    behavior_el = item_el.find(f"{XMLNS}behavior")
                    field_el    = item_el.find(f"{XMLNS}field")
                    behavior    = behavior_el.text if behavior_el is not None else ""
                    if behavior == "Blank":
                        items.append(None)  # spacer
                    elif field_el is not None:
                        # Strip namespace from field ref (e.g. fleetforce__Status__c → Status__c)
                        field_ref = field_el.text or ""
                        bare = re.sub(rf"^{NS}__", "", field_ref)
                        items.append(bare)

            sections.append({
                "label":   sec_label,
                "columns": columns,
                "items":   items,
            })

        results.append((layout_file.name, sections))

    return results


def all_placed_fields(layout_results):
    """Return a set of all field api_names that appear on any section of any layout."""
    placed = set()
    for _, sections in layout_results:
        for sec in sections:
            for item in sec["items"]:
                if item:
                    placed.add(item)
    return placed


def section_for_field(field_api, layout_results):
    """Return the section label where a field first appears, or '—'."""
    for _, sections in layout_results:
        for sec in sections:
            if field_api in sec["items"]:
                return sec["label"]
    return "—"


def is_system(api_name):
    return api_name in SYSTEM_FIELDS or not api_name.endswith("__c")


# ── Report generator ───────────────────────────────────────────────────────────

def generate_diff(obj_name):
    fields        = parse_fields(obj_name)
    layout_results = parse_layout(obj_name)
    placed        = all_placed_fields(layout_results)

    # Separate custom fields from system fields
    custom_fields = [f for f in fields if not is_system(f["api_name"])]

    missing = [f for f in custom_fields if f["api_name"] not in placed]
    on_layout = [f for f in custom_fields if f["api_name"] in placed]

    total   = len(custom_fields)
    placed_count = len(on_layout)
    missing_count = len(missing)
    num_layouts = len(layout_results)

    lines = []
    lines.append(f"# Layout Diff — `{NS}__{obj_name}`")
    lines.append(f"_Generated {datetime.now().strftime('%Y-%m-%d %H:%M')} · source: live org (fleetforce-dev-8)_")
    lines.append("")

    # Stats
    total_sections = sum(len(secs) for _, secs in layout_results)
    stats = f"**{placed_count} of {total} custom fields placed · {total_sections} sections across {num_layouts} layout(s) · {missing_count} fields missing**"
    lines.append(stats)
    lines.append("")

    # ── Layout files found ──
    if not layout_results:
        lines.append("> ⚠️ No layout file found for this object.")
        lines.append("")
    else:
        lines.append(f"**Layout file(s):** {', '.join(f'`{n}`' for n, _ in layout_results)}")
        lines.append("")

    # ── Missing fields (top of doc — that's the point) ──
    lines.append("## ❌ Fields NOT on layout")
    if not missing:
        lines.append("_All custom fields are placed on the layout._")
    else:
        lines.append(f"_{missing_count} field(s) missing:_")
        lines.append("")
        lines.append("| Field API Name | Label | Type | Required |")
        lines.append("|----------------|-------|------|----------|")
        for f in sorted(missing, key=lambda x: x["api_name"]):
            req = "✓" if f["required"] else ""
            lines.append(f"| `{f['api_name']}` | {f['label']} | {f['type']} | {req} |")
    lines.append("")

    # ── Current section structure ──
    lines.append("## Current sections (in order)")
    for layout_name, sections in layout_results:
        if num_layouts > 1:
            lines.append(f"### `{layout_name}`")
        if not sections:
            lines.append("_No sections found._")
            continue
        for i, sec in enumerate(sections, 1):
            col_label = "1 column" if sec["columns"] == 1 else "2 columns"
            lines.append(f"{i}. **{sec['label']}** ({col_label})")
            for item in sec["items"]:
                if item is None:
                    lines.append("   - _(spacer)_")
                else:
                    # Look up label
                    match = next((f for f in custom_fields if f["api_name"] == item), None)
                    if match:
                        lines.append(f"   - `{item}` — {match['label']}")
                    else:
                        # Could be a standard field (Name, Owner, etc.)
                        lines.append(f"   - `{item}`")
        lines.append("")

    # ── Full field coverage table ──
    lines.append("## Full field coverage")
    lines.append("")
    lines.append("| Field API Name | Label | Type | Required | On Layout | Section |")
    lines.append("|----------------|-------|------|----------|-----------|---------|")

    # Sort: missing first, then alphabetical
    def sort_key(f):
        on = f["api_name"] in placed
        return (0 if not on else 1, f["api_name"])

    for f in sorted(custom_fields, key=sort_key):
        on = f["api_name"] in placed
        on_str  = "✓" if on else "✗"
        req_str = "✓" if f["required"] else ""
        sec_str = section_for_field(f["api_name"], layout_results) if on else "—"
        lines.append(f"| `{f['api_name']}` | {f['label']} | {f['type']} | {req_str} | {on_str} | {sec_str} |")

    lines.append("")

    return "\n".join(lines), stats, missing_count, total


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    targets = sys.argv[1:] if len(sys.argv) > 1 else OBJECTS
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"\n{'─'*60}")
    print(f"  Layout Diff Report — Bucket 1 objects")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print(f"{'─'*60}\n")

    for obj in targets:
        content, stats, missing, total = generate_diff(obj)
        out_file = OUTPUT_DIR / f"{obj}-layout-diff.md"
        out_file.write_text(content)
        flag = " ⚠️" if missing > 0 else " ✅"
        print(f"  {obj}{flag}")
        print(f"    {stats.strip('*')}")
        print(f"    → {out_file.relative_to(REPO_ROOT)}")
        print()

    print(f"{'─'*60}")
    print(f"  Done. {len(targets)} file(s) written to docs/layouts/")
    print(f"{'─'*60}\n")


if __name__ == "__main__":
    main()
