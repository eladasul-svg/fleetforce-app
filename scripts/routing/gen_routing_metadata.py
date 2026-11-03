"""Generates the R2 routing metadata into force-app/main/default (run once; output is committed)."""

from __future__ import annotations

import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(sys.argv[1]) / "force-app/main/default"
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'
HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def tag(name: str, value) -> str:
    if isinstance(value, bool):
        value = "true" if value else "false"
    return f"    <{name}>{escape(str(value))}</{name}>\n"


# -------------------------------------------------------------------------------------------------
# Field builders. Each returns (fullName, xml body lines, meta) where meta drives perms and layouts.
# -------------------------------------------------------------------------------------------------


class F:
    def __init__(self, name, label, ftype, desc="", required=False, **kw):
        self.name, self.label, self.type, self.desc, self.required, self.kw = name, label, ftype, desc, required, kw

    @property
    def is_md(self):
        return self.type == "MasterDetail"

    @property
    def needs_fls(self):
        # Master-detail and required fields cannot appear in fieldPermissions.
        return not self.is_md and not self.required

    @property
    def editable(self):
        return not self.kw.get("readonly", False)

    def xml(self) -> str:
        k = self.kw
        out = [HEAD, f"<CustomField {NS}>\n", tag("fullName", self.name)]
        if self.type in ("Checkbox",):
            out.append(tag("defaultValue", k.get("default", False)))
        if self.type == "Lookup":
            out.append(tag("deleteConstraint", k.get("delete", "SetNull")))
        if self.desc:
            out.append(tag("description", self.desc))
        if self.type == "Location":
            out.append(tag("displayLocationInDecimal", True))
        if k.get("external_id"):
            out.append(tag("externalId", True))
        if k.get("help"):
            out.append(tag("inlineHelpText", k["help"]))
        out.append(tag("label", self.label))
        if self.type in ("Text",):
            out.append(tag("length", k.get("length", 255)))
        if self.type in ("LongTextArea",):
            out.append(tag("length", k.get("length", 32768)))
        if self.type in ("Number",):
            out.append(tag("precision", k.get("precision", 10)))
        if self.type in ("Lookup", "MasterDetail"):
            out.append(tag("referenceTo", k["ref"]))
            out.append(tag("relationshipLabel", k["rel_label"]))
            out.append(tag("relationshipName", k["rel"]))
        if self.is_md:
            out.append(tag("relationshipOrder", 0))
            out.append(tag("reparentableMasterDetail", k.get("reparentable", False)))
        if self.type not in ("MasterDetail", "Checkbox", "LongTextArea"):
            out.append(tag("required", self.required))
        if self.type in ("Number",):
            out.append(tag("scale", k.get("scale", 0)))
        if self.type == "Location":
            out.append(tag("scale", 7))
        if self.type not in ("LongTextArea",):
            out.append(tag("trackTrending", False))
        out.append(tag("type", self.type))
        if self.type in ("Text",) and k.get("unique"):
            out.append(tag("unique", True))
        if self.type in ("LongTextArea",):
            out.append(tag("visibleLines", k.get("lines", 5)))
        if self.type in ("Picklist", "MultiselectPicklist"):
            out.append("    <valueSet>\n        <restricted>true</restricted>\n")
            out.append("        <valueSetDefinition>\n            <sorted>false</sorted>\n")
            default = k.get("default")
            for v in k["values"]:
                out.append(
                    "            <value>\n"
                    f"                <fullName>{escape(v)}</fullName>\n"
                    f"                <default>{'true' if v == default else 'false'}</default>\n"
                    f"                <label>{escape(v)}</label>\n"
                    "            </value>\n"
                )
            out.append("        </valueSetDefinition>\n    </valueSet>\n")
        if self.type == "MultiselectPicklist":
            out.append(tag("visibleLines", 4))
        if self.is_md:
            out.append(tag("writeRequiresMasterRead", False))
        out.append("</CustomField>\n")
        return "".join(out)


def text(name, label, desc="", length=255, **kw):
    return F(name, label, "Text", desc, length=length, **kw)


def num(name, label, desc="", precision=10, scale=0, **kw):
    return F(name, label, "Number", desc, precision=precision, scale=scale, **kw)


def dt(name, label, desc="", **kw):
    return F(name, label, "DateTime", desc, **kw)


def pick(name, label, values, desc="", default=None, **kw):
    return F(name, label, "Picklist", desc, values=values, default=default, **kw)


def lookup(name, label, ref, rel, rel_label, desc="", **kw):
    return F(name, label, "Lookup", desc, ref=ref, rel=rel, rel_label=rel_label, **kw)


def md(name, label, ref, rel, rel_label, desc=""):
    return F(name, label, "MasterDetail", desc, ref=ref, rel=rel, rel_label=rel_label)


def loc(name, label, desc=""):
    return F(name, label, "Location", desc)


def longtext(name, label, desc="", length=32768, lines=5):
    return F(name, label, "LongTextArea", desc, length=length, lines=lines)


SKILLS = ["Refrigerated", "Lift Gate", "Wheelchair Ramp", "Tow Hitch", "Hazmat", "Forklift", "Heavy Lift"]
VEHICLE_FEATURES = ["Refrigerated", "Lift Gate", "Wheelchair Ramp", "Tow Hitch"]

OBJECTS = {
    "Route_Job__c": {
        "label": "Route Job",
        "plural": "Route Jobs",
        "desc": "One business need to route, e.g. deliver an order or relocate a car. Demand side: its "
        "visits say where; the optimizer decides which route serves it.",
        "name": ("Job Number", "AutoNumber", "JOB-{00000}"),
        "sharing": "ReadWrite",
        "tab": "Custom98: Truck",
        "fields": [
            pick("Type__c", "Type", ["Delivery", "Pickup", "Pickup and Delivery", "Service", "Relocation",
                                     "Inspection", "Cleaning", "Charging"], default="Delivery"),
            pick("Status__c", "Status", ["New", "Ready", "Planned", "In Progress", "Completed", "Failed",
                                         "Cancelled"], default="New"),
            F("Service_Date__c", "Service Date", "Date", "Planning day."),
            lookup("Branch__c", "Branch", "Fleet_Branch__c", "Route_Jobs", "Route Jobs", "Planning depot."),
            num("Priority__c", "Priority", "0-100; higher is planned first when not everything fits (VROOM priority).",
                precision=3),
            lookup("Account__c", "Account", "Account", "Route_Jobs", "Route Jobs", "Customer, optional."),
            lookup("Contact__c", "Contact", "Contact", "Route_Jobs", "Route Jobs", "Customer contact, optional."),
            lookup("Subject_Asset__c", "Subject Asset", "Fleet_Asset__c", "Subject_Route_Jobs", "Route Jobs (as subject)",
                   "The car being moved (car sharing relocation), optional."),
            text("Source_Object__c", "Source Object", "Where the job came from, e.g. Reservation__c, Service_Ticket__c, "
                 "ServiceAppointment, Order, Case.", length=80),
            text("Source_Record_Id__c", "Source Record Id", "Id of the source record.", length=18),
            F("Required_Skills__c", "Required Skills", "MultiselectPicklist",
              "Matched against driver qualifications and vehicle features.", values=SKILLS),
            lookup("Planned_Route__c", "Planned Route", "Route__c", "Planned_Jobs", "Planned Jobs",
                   "Set by the optimizer."),
            text("External_Id__c", "External Id", "For upserts from integrations.", external_id=True, unique=True),
            longtext("Notes__c", "Notes", "Free text. The assistant extracts access notes and service time from it."),
            text("Unassigned_Reason__c", "Unassigned Reason",
                 "Why the last optimization could not plan this job (skills, capacity, time window, no room)."),
        ],
    },
    "Job_Visit__c": {
        "label": "Job Visit",
        "plural": "Job Visits",
        "desc": "One place a job needs: 1 for a service or delivery, 2 for a pickup and drop. Points to the "
        "waypoint that serves it once a plan exists.",
        "name": ("Visit Number", "AutoNumber", "VIS-{00000}"),
        "sharing": "ControlledByParent",
        "fields": [
            md("Route_Job__c", "Route Job", "Route_Job__c", "Visits", "Visits"),
            pick("Role__c", "Role", ["Pickup", "Delivery", "Service"], default="Delivery"),
            loc("Location__c", "Location", "Required for routing."),
            text("Address__c", "Address", "Display and geocoding."),
            dt("Window_Start__c", "Window Start", "Optional; VROOM time window start."),
            dt("Window_End__c", "Window End", "Optional; VROOM time window end."),
            F("Hard_Window__c", "Hard Window", "Checkbox",
              "When checked, missing the window needs a dispatcher's approval.", default=False),
            num("Service_Minutes__c", "Service Minutes", "Time on site.", precision=5),
            num("Load_1__c", "Load 1", "Load change in capacity dimension 1 (see Capacity Dimension).", precision=12, scale=2),
            num("Load_2__c", "Load 2", "Load change in capacity dimension 2.", precision=12, scale=2),
            num("Load_3__c", "Load 3", "Load change in capacity dimension 3.", precision=12, scale=2),
            lookup("Waypoint__c", "Waypoint", "Waypoint__c", "Job_Visits", "Job Visits", "The stop that serves this visit."),
            pick("Status__c", "Status", ["Pending", "Done", "Failed"], default="Pending"),
            F("Access_Notes__c", "Access Notes", "TextArea", 'e.g. "Back gate, code 1234".'),
        ],
    },
    "Route_Plan__c": {
        "label": "Route Plan",
        "plural": "Route Plans",
        "desc": "One planning run for one depot and one day. Holds the routes the optimizer produced.",
        "name": ("Route Plan Name", "Text", None),
        "sharing": "ReadWrite",
        "tab": "Custom13: Box",
        "fields": [
            F("Plan_Date__c", "Plan Date", "Date"),
            lookup("Depot_Branch__c", "Depot Branch", "Fleet_Branch__c", "Route_Plans", "Route Plans"),
            pick("Status__c", "Status", ["Draft", "Optimizing", "Optimized", "Published", "In Progress", "Completed",
                                         "Cancelled"], default="Draft"),
            pick("Provider__c", "Provider", ["FleetForce Routing", "Openrouteservice", "Google"],
                 default="FleetForce Routing"),
            pick("Objective__c", "Objective", ["Min Duration", "Min Distance", "Min Vehicles", "Balanced"],
                 default="Min Duration"),
            num("Revision__c", "Revision", "Goes up on every re-optimization.", precision=6),
            dt("Last_Optimized_At__c", "Last Optimized At"),
            num("Unassigned_Count__c", "Unassigned Count", "Jobs the solver could not fit.", precision=6),
            num("Total_Distance_Km__c", "Total Distance (km)", precision=10, scale=2),
            num("Total_Duration_Min__c", "Total Duration (min)", precision=10),
            longtext("Solver_Summary__c", "Solver Summary", "Raw solver summary (JSON), for debugging.", length=131072),
            longtext("Error__c", "Error", "Last callout error.", lines=3),
        ],
    },
    "Route__c": {
        "label": "Route",
        "plural": "Routes",
        "desc": "One vehicle and one driver for one shift within a route plan.",
        "name": ("Route Name", "Text", None),
        "sharing": "ControlledByParent",
        "tab": "Custom62: Ship",
        "fields": [
            md("Route_Plan__c", "Route Plan", "Route_Plan__c", "Routes", "Routes"),
            lookup("Fleet_Asset__c", "Fleet Asset", "Fleet_Asset__c", "Routes", "Routes"),
            lookup("Driver__c", "Driver", "Contact", "Routes", "Routes"),
            lookup("Allocation__c", "Allocation", "Allocation__c", "Routes", "Routes",
                   "Created on publish, so the motorpool sees the van as in use."),
            pick("Status__c", "Status", ["Planned", "Published", "In Progress", "Completed", "Cancelled"],
                 default="Planned"),
            loc("Start_Location__c", "Start Location", "Defaults to the depot."),
            loc("End_Location__c", "End Location", "Defaults to the depot; blank for an open trip."),
            dt("Shift_Start__c", "Shift Start", "From Schedule Assignment, or the plan default."),
            dt("Shift_End__c", "Shift End"),
            dt("Planned_Start__c", "Planned Start", "From the solver."),
            dt("Planned_End__c", "Planned End", "From the solver."),
            num("Planned_Distance_Km__c", "Planned Distance (km)", precision=10, scale=2),
            num("Planned_Duration_Min__c", "Planned Duration (min)", precision=10),
            dt("Actual_Start__c", "Actual Start"),
            dt("Actual_End__c", "Actual End"),
            num("Revision__c", "Revision", precision=6),
            longtext("Geometry__c", "Geometry", "Encoded polyline for the map.", length=131072, lines=3),
        ],
    },
    "Waypoint__c": {
        "label": "Waypoint",
        "plural": "Waypoints",
        "desc": "Every stop a route makes, whatever the reason: job stops, breaks, charging, depot reloads.",
        "name": ("Waypoint Number", "AutoNumber", "WPT-{000000}"),
        "sharing": "ControlledByParent",
        "fields": [
            md("Route__c", "Route", "Route__c", "Waypoints", "Waypoints"),
            num("Sequence__c", "Sequence", "Current order on the route.", precision=5),
            pick("Type__c", "Type", ["Start", "End", "Job Stop", "Break", "Refuel", "Charge", "Depot Reload",
                                     "Driver Added"], default="Job Stop"),
            loc("Location__c", "Location"),
            lookup("Branch__c", "Branch", "Fleet_Branch__c", "Waypoints", "Waypoints", "When the stop is a depot."),
            dt("Planned_Arrival__c", "Planned Arrival", "From the solver."),
            dt("Planned_Departure__c", "Planned Departure", "From the solver."),
            dt("ETA__c", "ETA", "Refreshed in-day."),
            dt("ETA_Updated_At__c", "ETA Updated At"),
            dt("Actual_Arrival__c", "Actual Arrival", "Driver app or geofence."),
            dt("Actual_Departure__c", "Actual Departure"),
            pick("Status__c", "Status", ["Planned", "En Route", "Arrived", "Completed", "Skipped", "Failed"],
                 default="Planned"),
            F("Locked__c", "Locked", "Checkbox", "Stays pinned during re-optimization (started or promised stops).",
              default=False),
            num("Service_Minutes__c", "Service Minutes", precision=5),
            num("Wait_Minutes__c", "Wait Minutes", precision=5),
            num("Leg_Distance_Km__c", "Leg Distance (km)", "Leg from the previous waypoint.", precision=8, scale=2),
            num("Leg_Duration_Min__c", "Leg Duration (min)", "Leg from the previous waypoint.", precision=6),
            num("Late_Minutes__c", "Late Minutes", "How far past its time window the planned arrival is.", precision=6),
            text("Solver_Step_Id__c", "Solver Step Id", "Id the solver used for this stop (visit or break).", length=40),
            text("Reason__c", "Reason", "Why it was added or skipped."),
        ],
    },
    "Route_Event__c": {
        "label": "Route Event",
        "plural": "Route Events",
        "desc": "Append-only audit trail of what happened to a plan or route and who did it. Never updated or "
        "deleted (enforced by RouteEventTrigger).",
        "name": ("Event Number", "AutoNumber", "EVT-{000000}"),
        "sharing": "ReadWrite",
        "tab": "Custom55: Paper",
        "fields": [
            lookup("Route_Plan__c", "Route Plan", "Route_Plan__c", "Route_Events", "Route Events"),
            lookup("Route__c", "Route", "Route__c", "Route_Events", "Route Events"),
            lookup("Waypoint__c", "Waypoint", "Waypoint__c", "Route_Events", "Route Events"),
            pick("Type__c", "Type", ["Delay Reported", "Window Changed", "Stop Skipped", "Stop Added", "Reoptimized",
                                     "Optimized", "Published", "Handoff Proposed", "Handoff Approved",
                                     "Proposal Rejected", "Arrived", "Departed", "Optimization Failed"]),
            pick("Actor_Type__c", "Actor Type", ["Driver", "Dispatcher", "Assistant", "System"], default="System"),
            lookup("Actor_User__c", "Actor User", "User", "Route_Events", "Route Events"),
            lookup("Assistant_Session__c", "Assistant Session", "Assistant_Session__c", "Route_Events", "Route Events",
                   "When the change came through the assistant."),
            longtext("Payload__c", "Payload", "Before and after difference (JSON).", length=131072),
            dt("Occurred_At__c", "Occurred At"),
        ],
    },
}

ASSET_FIELDS = [
    num("Payload_Kg__c", "Payload (kg)", "Load the vehicle can carry. Gross weight is not payload.", precision=8, scale=1),
    num("Cargo_Volume_M3__c", "Cargo Volume (m³)", "Usable cargo volume.", precision=6, scale=2),
    num("Pallet_Capacity__c", "Pallet Capacity", "Standard pallets the cargo area holds.", precision=3),
    F("Vehicle_Features__c", "Vehicle Features", "MultiselectPicklist",
      "Equipment the routing optimizer matches against a job's Required Skills.", values=VEHICLE_FEATURES),
]


def object_xml(api: str, o: dict) -> str:
    label, ntype, fmt = o["name"]
    name = f"    <nameField>\n{tag('displayFormat', fmt).replace('    <', '        <') if fmt else ''}" \
           f"        <label>{escape(label)}</label>\n        <type>{ntype}</type>\n    </nameField>\n"
    sharing = o["sharing"]
    external = "ControlledByParent" if sharing == "ControlledByParent" else "Private"
    return (
        HEAD + f"<CustomObject {NS}>\n"
        + tag("allowInChatterGroups", False)
        + tag("deploymentStatus", "Deployed")
        + tag("description", o["desc"])
        + tag("enableActivities", False)
        + tag("enableBulkApi", True)
        + tag("enableFeeds", False)
        + tag("enableHistory", False)
        + tag("enableReports", True)
        + tag("enableSearch", api in ("Route_Job__c", "Route_Plan__c", "Route__c"))
        + tag("enableSharing", True)
        + tag("enableStreamingApi", True)
        + tag("externalSharingModel", external)
        + tag("label", o["label"])
        + name
        + tag("pluralLabel", o["plural"])
        + tag("sharingModel", sharing)
        + tag("visibility", "Public")
        + "</CustomObject>\n"
    )


def layout_xml(api: str, o: dict) -> str:
    fields = o["fields"]
    left, right = [], []
    first = ["Name"]
    for i, f in enumerate(fields):
        (left if i % 2 == 0 else right).append(f)

    def item(field: str, behavior: str) -> str:
        return (
            "            <layoutItems>\n"
            f"                <behavior>{behavior}</behavior>\n"
            f"                <field>{field}</field>\n"
            "            </layoutItems>\n"
        )

    def behavior(f: F) -> str:
        if f.is_md or f.required:
            return "Required"
        return "Edit"

    auto = o["name"][1] == "AutoNumber"
    col1 = item("Name", "Readonly" if auto else "Required") + "".join(item(f.name, behavior(f)) for f in left)
    col2 = "".join(item(f.name, behavior(f)) for f in right)
    sys_section = (
        "    <layoutSections>\n        <customLabel>false</customLabel>\n        <detailHeading>false</detailHeading>\n"
        "        <editHeading>true</editHeading>\n        <label>System Information</label>\n"
        "        <layoutColumns>\n" + item("CreatedById", "Readonly") + "        </layoutColumns>\n"
        "        <layoutColumns>\n" + item("LastModifiedById", "Readonly") + "        </layoutColumns>\n"
        "        <style>TwoColumnsTopToBottom</style>\n    </layoutSections>\n"
    )
    related = "".join(
        "    <relatedLists>\n" + "".join(f"        <fields>{c}</fields>\n" for c in cols)
        + f"        <relatedList>{rl}</relatedList>\n    </relatedLists>\n"
        for rl, cols in RELATED.get(api, [])
    )
    owner = related
    return (
        HEAD + f"<Layout {NS}>\n"
        "    <layoutSections>\n        <customLabel>false</customLabel>\n        <detailHeading>false</detailHeading>\n"
        "        <editHeading>true</editHeading>\n        <label>Information</label>\n"
        f"        <layoutColumns>\n{col1}        </layoutColumns>\n"
        f"        <layoutColumns>\n{col2}        </layoutColumns>\n"
        "        <style>TwoColumnsTopToBottom</style>\n    </layoutSections>\n"
        + sys_section + owner
        + "    <showEmailCheckbox>false</showEmailCheckbox>\n"
        "    <showHighlightsPanel>false</showHighlightsPanel>\n"
        "    <showInteractionLogPanel>false</showInteractionLogPanel>\n"
        "    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>\n"
        "    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>\n"
        "</Layout>\n"
    )


RELATED = {
    "Route_Plan__c": [
        ("Route__c.Route_Plan__c", ["NAME", "Fleet_Asset__c", "Driver__c", "Status__c", "Planned_Start__c",
                                    "Planned_End__c", "Planned_Distance_Km__c"]),
        ("Route_Event__c.Route_Plan__c", ["NAME", "Type__c", "Actor_Type__c", "Occurred_At__c"]),
    ],
    "Route__c": [
        ("Waypoint__c.Route__c", ["NAME", "Sequence__c", "Type__c", "Status__c", "Planned_Arrival__c", "ETA__c",
                                  "Locked__c"]),
        ("Route_Job__c.Planned_Route__c", ["NAME", "Type__c", "Status__c", "Priority__c"]),
        ("Route_Event__c.Route__c", ["NAME", "Type__c", "Actor_Type__c", "Occurred_At__c"]),
    ],
    "Route_Job__c": [
        ("Job_Visit__c.Route_Job__c", ["NAME", "Role__c", "Address__c", "Window_Start__c", "Window_End__c",
                                       "Status__c"]),
    ],
    "Waypoint__c": [
        ("Job_Visit__c.Waypoint__c", ["NAME", "Role__c", "Address__c", "Status__c"]),
    ],
}


def main() -> None:
    for api, o in OBJECTS.items():
        base = ROOT / "objects" / api
        write(base / f"{api}.object-meta.xml", object_xml(api, o))
        for f in o["fields"]:
            write(base / "fields" / f"{f.name}.field-meta.xml", f.xml())
        write(ROOT / "layouts" / f"{api}-{o['label']} Layout.layout-meta.xml", layout_xml(api, o))
        if "tab" in o:
            write(
                ROOT / "tabs" / f"{api}.tab-meta.xml",
                HEAD + f"<CustomTab {NS}>\n" + tag("customObject", True) + tag("motif", o["tab"]) + "</CustomTab>\n",
            )
    for f in ASSET_FIELDS:
        write(ROOT / "objects/Fleet_Asset__c/fields" / f"{f.name}.field-meta.xml", f.xml())

    # Capacity_Dimension__mdt ------------------------------------------------------------------
    mdt = ROOT / "objects/Capacity_Dimension__mdt"
    write(
        mdt / "Capacity_Dimension__mdt.object-meta.xml",
        HEAD + f"<CustomObject {NS}>\n"
        + tag("description", "Capacity slots 1-3 the routing optimizer plans against: which Fleet Asset field "
              "holds the capacity, its unit, and the factor that turns it into the solver's whole numbers.")
        + tag("label", "Capacity Dimension") + tag("pluralLabel", "Capacity Dimensions")
        + tag("visibility", "Public") + "</CustomObject>\n",
    )
    mdt_fields = [
        ("Slot__c", "Slot", "Number", "1, 2 or 3: Job Visit Load_n__c and the solver's capacity index."),
        ("Unit__c", "Unit", "Text", "Display unit, e.g. kg, m³, pallets."),
        ("Asset_Field__c", "Asset Field", "Text", "API name of the Fleet Asset field that holds this capacity."),
        ("Scale__c", "Scale", "Number", "Multiplier that turns values into whole numbers for the solver "
         "(e.g. 1000 turns m³ into litres)."),
        ("Is_Active__c", "Is Active", "Checkbox", "Inactive slots are sent to the solver as zero."),
    ]
    for name, label, ftype, desc in mdt_fields:
        body = [HEAD, f"<CustomField {NS}>\n", tag("fullName", name)]
        if ftype == "Checkbox":
            body.append(tag("defaultValue", True))
        body += [tag("description", desc), tag("externalId", False), tag("fieldManageability", "DeveloperControlled"),
                 tag("label", label)]
        if ftype == "Text":
            body.append(tag("length", 80))
        if ftype == "Number":
            body.append(tag("precision", 10 if name == "Scale__c" else 1))
            body.append(tag("required", False))
            body.append(tag("scale", 0))
        if ftype == "Text":
            body.append(tag("required", False))
        body += [tag("type", ftype)]
        if ftype == "Text":
            body.append(tag("unique", False))
        body.append("</CustomField>\n")
        write(mdt / "fields" / f"{name}.field-meta.xml", "".join(body))

    records = [
        ("Weight", 1, "kg", "Payload_Kg__c", 1),
        ("Volume", 2, "m³", "Cargo_Volume_M3__c", 1000),
        ("Pallets", 3, "pallets", "Pallet_Capacity__c", 1),
    ]
    for label, slot, unit, field, scale in records:
        values = [
            ("Slot__c", "xsd:double", slot),
            ("Unit__c", "xsd:string", unit),
            ("Asset_Field__c", "xsd:string", field),
            ("Scale__c", "xsd:double", scale),
            ("Is_Active__c", "xsd:boolean", "true"),
        ]
        body = (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n'
            + tag("label", label) + tag("protected", False)
            + "".join(
                f"    <values>\n        <field>{f}</field>\n        <value xsi:type=\"{t}\">{escape(str(v))}</value>\n"
                "    </values>\n"
                for f, t, v in values
            )
            + "</CustomMetadata>\n"
        )
        write(ROOT / "customMetadata" / f"Capacity_Dimension.{label}.md-meta.xml", body)

    # Route_Plan_Update__e ---------------------------------------------------------------------
    ev = ROOT / "objects/Route_Plan_Update__e"
    write(
        ev / "Route_Plan_Update__e.object-meta.xml",
        HEAD + f"<CustomObject {NS}>\n" + tag("deploymentStatus", "Deployed")
        + tag("description", "Published when an optimization finishes or a route changes, so open route boards refresh.")
        + tag("eventType", "HighVolume") + tag("label", "Route Plan Update") + tag("pluralLabel", "Route Plan Updates")
        + tag("publishBehavior", "PublishAfterCommit") + "</CustomObject>\n",
    )
    for name, label, ftype, length in [
        ("Route_Plan_Id__c", "Route Plan Id", "Text", 18),
        ("Route_Id__c", "Route Id", "Text", 18),
        ("Status__c", "Status", "Text", 40),
        ("Message__c", "Message", "Text", 255),
        ("Revision__c", "Revision", "Number", None),
    ]:
        body = [HEAD, f"<CustomField {NS}>\n", tag("fullName", name), tag("externalId", False),
                tag("isFilteringDisabled", False), tag("isNameField", False), tag("isSortingDisabled", False),
                tag("label", label)]
        if ftype == "Text":
            body.append(tag("length", length))
        else:
            body.append(tag("precision", 6))
        body.append(tag("required", False))
        if ftype == "Number":
            body.append(tag("scale", 0))
        body.append(tag("type", ftype))
        if ftype == "Text":
            body.append(tag("unique", False))
        body.append("</CustomField>\n")
        write(ev / "fields" / f"{name}.field-meta.xml", "".join(body))

    # Permission set ---------------------------------------------------------------------------
    write(ROOT / "permissionsets/FleetforceRouting.permissionset-meta.xml", permission_set())


ROUTING_CLASSES = [
    "FleetForceRoutingProvider", "MockRoutingProvider", "OrsRoutingProvider", "RoutePlanController",
    "RoutePlanOptimizeJob", "RoutePlanService", "RoutingActions", "RoutingAssistantTools", "RoutingDtos",
    "RoutingPolicy", "RoutingProvider", "RoutingProviders",
]


def permission_set() -> str:
    out = [HEAD, f"<PermissionSet {NS}>\n"]
    classes_dir = ROOT / "classes"
    for c in sorted(c for c in ROUTING_CLASSES if (classes_dir / f"{c}.cls").exists()):
        out.append(f"    <classAccesses>\n        <apexClass>{c}</apexClass>\n        <enabled>true</enabled>\n"
                   "    </classAccesses>\n")
    out.append(tag("description", "FleetForce Routing: plan, optimize and dispatch routes. Assign together with "
                   "Fleetforce Admin or Fleet Admin (which grant the fleet objects). Route Events are create and read "
                   "only: the audit trail is append-only."))
    if (ROOT / "externalCredentials/FleetForce_Routing.externalCredential-meta.xml").exists():
        out.append("    <externalCredentialPrincipalAccesses>\n        <enabled>true</enabled>\n"
                   "        <externalCredentialPrincipal>fleetforce__FleetForce_Routing-Org</externalCredentialPrincipal>\n"
                   "    </externalCredentialPrincipalAccesses>\n")
    fls = []
    for api, o in OBJECTS.items():
        for f in o["fields"]:
            if f.needs_fls:
                fls.append((f"{api}.{f.name}", f.editable and api != "Route_Event__c"))
    for f in ASSET_FIELDS:
        fls.append((f"Fleet_Asset__c.{f.name}", True))
    for field, editable in sorted(fls, key=lambda x: x[0].lower()):
        out.append(f"    <fieldPermissions>\n        <editable>{'true' if editable else 'false'}</editable>\n"
                   f"        <field>{field}</field>\n        <readable>true</readable>\n    </fieldPermissions>\n")
    out.append(tag("hasActivationRequired", False))
    out.append(tag("label", "FleetForce Routing"))
    objs = {api: dict(c=True, r=True, e=True, d=True) for api in OBJECTS}
    objs["Route_Event__c"] = dict(c=True, r=True, e=False, d=False)
    objs["Allocation__c"] = dict(c=True, r=True, e=True, d=False)
    for ro in ["Fleet_Asset__c", "Fleet_Branch__c", "Service_Ticket__c", "Driver_Qualification__c",
               "Schedule_Assignment__c", "Assistant_Session__c"]:
        objs[ro] = dict(c=False, r=True, e=False, d=False)
    for api in sorted(objs, key=str.lower):
        p = objs[api]
        b = lambda x: "true" if x else "false"  # noqa: E731
        out.append(
            "    <objectPermissions>\n"
            f"        <allowCreate>{b(p['c'])}</allowCreate>\n        <allowDelete>{b(p['d'])}</allowDelete>\n"
            f"        <allowEdit>{b(p['e'])}</allowEdit>\n        <allowRead>true</allowRead>\n"
            "        <modifyAllRecords>false</modifyAllRecords>\n"
            f"        <object>{api}</object>\n        <viewAllRecords>false</viewAllRecords>\n"
            "    </objectPermissions>\n"
        )
    for t in sorted(api for api, o in OBJECTS.items() if "tab" in o):
        out.append(f"    <tabSettings>\n        <tab>{t}</tab>\n        <visibility>Visible</visibility>\n"
                   "    </tabSettings>\n")
    out.append("</PermissionSet>\n")
    return "".join(out)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[2] == "--permset-only":
        write(ROOT / "permissionsets/FleetforceRouting.permissionset-meta.xml", permission_set())
    else:
        main()
