/**
 * The tools Claude can call from the FleetForce Assistant, and their executors.
 *
 * Every read runs in USER_MODE and every proposed write is executed in USER_MODE only after the
 * user approves it in the UI, so the assistant can never see or change more than the running user
 * could through the standard UI.
 */
public with sharing class AssistantTools {

    public static final Integer MAX_ROWS = 50;
    public static final Integer MAX_FIELDS = 100;
    public static final Integer MAX_PICKLIST_VALUES = 30;
    public static final Integer MAX_RESULT_CHARS = 20000;

    private static final Set<String> STANDARD_SHORTLIST = new Set<String>{
        'Account', 'Contact', 'Lead', 'Opportunity', 'Case', 'User', 'Task', 'Event', 'Product2', 'Asset'
    };

    public class ToolResult {
        public String content;
        public Boolean isError = false;
        public String summary;
        public Map<String, Object> proposal;
    }

    // ---------------------------------------------------------------------------------------------
    // Definitions sent to Claude
    // ---------------------------------------------------------------------------------------------

    public static List<Object> definitions() {
        return new List<Object>{
            tool('list_objects',
                'List the Salesforce objects the current user can query. Without a search term it returns the ' +
                'FleetForce objects plus the common standard objects; pass a search term to find any other object by ' +
                'API name or label.',
                new Map<String, Object>{
                    'search' => prop('string', 'Optional case-insensitive text to match against object API names and labels.')
                }, new List<String>()),
            tool('describe_object',
                'Get the fields of an object the user can access: API names, labels, types, whether they are required, ' +
                'picklist values, lookup targets, and child relationships. Call this before writing SOQL against an ' +
                'object or proposing a record change so you use real field API names.',
                new Map<String, Object>{
                    'objectApiName' => prop('string', 'Object API name, e.g. Fleet_Asset__c or Account.')
                }, new List<String>{ 'objectApiName' }),
            tool('query_records',
                'Run a SOQL SELECT query as the current user (sharing and field-level security are enforced). ' +
                'Returns at most ' + MAX_ROWS + ' rows; use aggregate functions, WHERE filters and ORDER BY to keep ' +
                'results focused. Relationship fields (Owner.Name, Fleet_Asset__r.Name) and subqueries are supported.',
                new Map<String, Object>{
                    'soql' => prop('string', 'A complete SOQL SELECT statement.')
                }, new List<String>{ 'soql' }),
            tool('get_record',
                'Fetch one record by Id with all fields the user can read. Use this for the record the user is ' +
                'currently viewing, or any Id you already have.',
                new Map<String, Object>{
                    'recordId' => prop('string', 'A 15 or 18 character Salesforce record Id.'),
                    'fields' => new Map<String, Object>{
                        'type' => 'array', 'items' => new Map<String, Object>{ 'type' => 'string' },
                        'description' => 'Optional list of field API names to return instead of all readable fields.'
                    }
                }, new List<String>{ 'recordId' }),
            tool('propose_create',
                'Propose creating a new record. Nothing is saved until the user approves the proposal in the UI; ' +
                'the tool result tells you whether they approved. Include every required field. Use ISO dates ' +
                '(YYYY-MM-DD) and datetimes (YYYY-MM-DDTHH:MM:SSZ), and picklist API values.',
                new Map<String, Object>{
                    'objectApiName' => prop('string', 'Object API name of the record to create.'),
                    'fields' => new Map<String, Object>{
                        'type' => 'object',
                        'description' => 'Map of field API name to value.',
                        'additionalProperties' => true
                    },
                    'reason' => prop('string', 'One sentence, shown to the user, explaining why you propose this.')
                }, new List<String>{ 'objectApiName', 'fields' }),
            tool('propose_update',
                'Propose changing fields on an existing record. Nothing is saved until the user approves the ' +
                'proposal in the UI; the tool result tells you whether they approved. Only include the fields that ' +
                'should change.',
                new Map<String, Object>{
                    'recordId' => prop('string', 'Id of the record to update.'),
                    'fields' => new Map<String, Object>{
                        'type' => 'object',
                        'description' => 'Map of field API name to new value.',
                        'additionalProperties' => true
                    },
                    'reason' => prop('string', 'One sentence, shown to the user, explaining why you propose this.')
                }, new List<String>{ 'recordId', 'fields' })
        };
    }

    private static Map<String, Object> tool(String name, String description, Map<String, Object> props, List<String> required) {
        return new Map<String, Object>{
            'name' => name,
            'description' => description,
            'input_schema' => new Map<String, Object>{
                'type' => 'object',
                'properties' => props,
                'required' => required
            }
        };
    }

    private static Map<String, Object> prop(String type, String description) {
        return new Map<String, Object>{ 'type' => type, 'description' => description };
    }

    // ---------------------------------------------------------------------------------------------
    // Execution
    // ---------------------------------------------------------------------------------------------

    public static ToolResult execute(String name, Map<String, Object> input) {
        if (input == null) {
            input = new Map<String, Object>();
        }
        try {
            if (name == 'list_objects') {
                return listObjects((String) input.get('search'));
            }
            if (name == 'describe_object') {
                return describeObject((String) input.get('objectApiName'));
            }
            if (name == 'query_records') {
                return queryRecords((String) input.get('soql'));
            }
            if (name == 'get_record') {
                return getRecord((String) input.get('recordId'), (List<Object>) input.get('fields'));
            }
            if (name == 'propose_create') {
                return proposeCreate((String) input.get('objectApiName'), asMap(input.get('fields')), (String) input.get('reason'));
            }
            if (name == 'propose_update') {
                return proposeUpdate((String) input.get('recordId'), asMap(input.get('fields')), (String) input.get('reason'));
            }
            return error('Unknown tool: ' + name);
        } catch (Exception e) {
            return error(e.getTypeName() + ': ' + e.getMessage());
        }
    }

    public static Boolean isProposal(String toolName) {
        return toolName == 'propose_create' || toolName == 'propose_update';
    }

    // ---- list_objects ---------------------------------------------------------------------------

    private static ToolResult listObjects(String search) {
        String needle = String.isBlank(search) ? null : search.trim().toLowerCase();
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        List<String> names = new List<String>(gd.keySet());
        names.sort();

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (String key : names) {
            Schema.DescribeSObjectResult d = gd.get(key).getDescribe(SObjectDescribeOptions.DEFERRED);
            String api = d.getName();
            Boolean candidate = needle != null
                ? (api.toLowerCase().contains(needle) || d.getLabel().toLowerCase().contains(needle))
                : (api.endsWith('__c') || STANDARD_SHORTLIST.contains(api));
            if (!candidate || !d.isAccessible() || !d.isQueryable() || d.isCustomSetting()) {
                continue;
            }
            out.add(new Map<String, Object>{ 'apiName' => api, 'label' => d.getLabel(), 'custom' => d.isCustom() });
            if (out.size() >= MAX_FIELDS) {
                break;
            }
        }
        ToolResult r = ok(new Map<String, Object>{
            'count' => out.size(),
            'objects' => out,
            'hint' => needle == null ? 'Pass a search term to find objects not listed here.' : null
        });
        r.summary = 'Listed ' + out.size() + ' objects' + (needle == null ? '' : ' matching "' + search.trim() + '"');
        return r;
    }

    // ---- describe_object ------------------------------------------------------------------------

    private static ToolResult describeObject(String objectApiName) {
        Schema.DescribeSObjectResult d = describeAccessible(objectApiName);
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        List<String> fieldNames = new List<String>(d.fields.getMap().keySet());
        fieldNames.sort();
        for (String fn : fieldNames) {
            Schema.DescribeFieldResult f = d.fields.getMap().get(fn).getDescribe();
            if (!f.isAccessible()) {
                continue;
            }
            Map<String, Object> info = new Map<String, Object>{
                'apiName' => f.getName(),
                'label' => f.getLabel(),
                'type' => String.valueOf(f.getType()),
                'required' => f.isCreateable() && !f.isNillable() && !f.isDefaultedOnCreate(),
                'createable' => f.isCreateable(),
                'updateable' => f.isUpdateable()
            };
            if (f.getType() == Schema.DisplayType.PICKLIST || f.getType() == Schema.DisplayType.MULTIPICKLIST) {
                List<String> values = new List<String>();
                for (Schema.PicklistEntry p : f.getPicklistValues()) {
                    if (p.isActive()) {
                        values.add(p.getValue());
                    }
                    if (values.size() >= MAX_PICKLIST_VALUES) {
                        break;
                    }
                }
                info.put('picklistValues', values);
            }
            if (f.getType() == Schema.DisplayType.REFERENCE) {
                List<String> refs = new List<String>();
                for (Schema.SObjectType t : f.getReferenceTo()) {
                    refs.add(t.getDescribe(SObjectDescribeOptions.DEFERRED).getName());
                }
                info.put('referenceTo', refs);
                info.put('relationshipName', f.getRelationshipName());
            }
            fields.add(info);
        }

        List<Map<String, Object>> children = new List<Map<String, Object>>();
        for (Schema.ChildRelationship cr : d.getChildRelationships()) {
            if (cr.getRelationshipName() == null) {
                continue;
            }
            Schema.DescribeSObjectResult cd = cr.getChildSObject().getDescribe(SObjectDescribeOptions.DEFERRED);
            if (!cd.isAccessible() || !cd.isQueryable()) {
                continue;
            }
            children.add(new Map<String, Object>{
                'relationshipName' => cr.getRelationshipName(),
                'childObject' => cd.getName(),
                'field' => cr.getField().getDescribe().getName()
            });
            if (children.size() >= MAX_PICKLIST_VALUES) {
                break;
            }
        }

        ToolResult r = ok(new Map<String, Object>{
            'apiName' => d.getName(),
            'label' => d.getLabel(),
            'createable' => d.isCreateable(),
            'updateable' => d.isUpdateable(),
            'fields' => fields,
            'childRelationships' => children
        });
        r.summary = 'Described ' + d.getLabel() + ' (' + fields.size() + ' fields)';
        return r;
    }

    // ---- query_records --------------------------------------------------------------------------

    private static ToolResult queryRecords(String soql) {
        String q = soql == null ? '' : soql.trim();
        if (!q.toUpperCase().startsWith('SELECT')) {
            return error('Only SELECT statements are allowed.');
        }
        if (q.contains(';')) {
            return error('Semicolons are not allowed in the query.');
        }
        Boolean hasLimit = Pattern.compile('(?i)\\sLIMIT\\s+\\d+').matcher(q).find();
        Boolean hasAggregate = Pattern.compile('(?i)\\b(COUNT|COUNT_DISTINCT|SUM|AVG|MIN|MAX)\\s*\\(').matcher(q).find();
        Boolean hasGroupBy = Pattern.compile('(?i)\\sGROUP\\s+BY\\s').matcher(q).find();
        // An ungrouped aggregate query returns one row and rejects LIMIT.
        if (!hasLimit && !(hasAggregate && !hasGroupBy)) {
            q += ' LIMIT ' + (MAX_ROWS + 1);
        }

        List<SObject> rows = Database.query(q, AccessLevel.USER_MODE);
        Boolean truncated = rows.size() > MAX_ROWS;
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        for (Integer i = 0; i < Math.min(rows.size(), MAX_ROWS); i++) {
            records.add(toMap(rows[i]));
        }

        ToolResult r = ok(new Map<String, Object>{
            'count' => records.size(),
            'truncated' => truncated,
            'records' => records
        });
        String label = rows.isEmpty() ? 'records' : objectLabel(rows[0]);
        r.summary = 'Queried ' + label + ' — ' + records.size() + (truncated ? '+' : '') + ' row' + (records.size() == 1 ? '' : 's');
        return r;
    }

    // ---- get_record -----------------------------------------------------------------------------

    private static ToolResult getRecord(String recordId, List<Object> requested) {
        Id rid = parseId(recordId);
        Schema.DescribeSObjectResult d = rid.getSObjectType().getDescribe();
        if (!d.isAccessible()) {
            return error('You do not have access to ' + d.getName() + ' records.');
        }
        Map<String, Schema.SObjectField> fieldMap = d.fields.getMap();
        List<String> selectFields = new List<String>();
        if (requested != null && !requested.isEmpty()) {
            for (Object o : requested) {
                String fn = String.valueOf(o);
                if (fieldMap.containsKey(fn.toLowerCase()) && fieldMap.get(fn.toLowerCase()).getDescribe().isAccessible()) {
                    selectFields.add(fn);
                }
            }
        } else {
            List<String> names = new List<String>(fieldMap.keySet());
            names.sort();
            for (String fn : names) {
                Schema.DescribeFieldResult f = fieldMap.get(fn).getDescribe();
                if (!f.isAccessible() || f.getType() == Schema.DisplayType.ADDRESS || f.getType() == Schema.DisplayType.LOCATION) {
                    continue;
                }
                selectFields.add(f.getName());
                if (selectFields.size() >= MAX_FIELDS) {
                    break;
                }
            }
        }
        if (selectFields.isEmpty()) {
            return error('No readable fields found.');
        }
        String q = 'SELECT ' + String.join(selectFields, ', ') + ' FROM ' + d.getName() + ' WHERE Id = :rid';
        List<SObject> rows = Database.queryWithBinds(q, new Map<String, Object>{ 'rid' => rid }, AccessLevel.USER_MODE);
        if (rows.isEmpty()) {
            return error('Record ' + recordId + ' was not found or you cannot see it.');
        }
        ToolResult r = ok(new Map<String, Object>{ 'object' => d.getName(), 'record' => toMap(rows[0]) });
        r.summary = 'Read ' + d.getLabel() + ' record';
        return r;
    }

    // ---- propose_create / propose_update --------------------------------------------------------

    private static ToolResult proposeCreate(String objectApiName, Map<String, Object> fields, String reason) {
        Schema.DescribeSObjectResult d = describeAccessible(objectApiName);
        if (!d.isCreateable()) {
            return error('You cannot create ' + d.getLabel() + ' records.');
        }
        if (fields == null || fields.isEmpty()) {
            return error('fields must contain at least one field.');
        }
        List<Map<String, Object>> changes = new List<Map<String, Object>>();
        for (String fn : fields.keySet()) {
            Schema.DescribeFieldResult f = fieldOrError(d, fn);
            if (!f.isCreateable()) {
                return error('Field ' + f.getName() + ' cannot be set on create.');
            }
            changes.add(new Map<String, Object>{
                'apiName' => f.getName(), 'label' => f.getLabel(), 'type' => String.valueOf(f.getType()),
                'proposed' => coerce(f, fields.get(fn))
            });
        }
        return proposalResult(new Map<String, Object>{
            'action' => 'create', 'objectApiName' => d.getName(), 'objectLabel' => d.getLabel(),
            'reason' => reason, 'changes' => changes
        }, 'Proposed new ' + d.getLabel());
    }

    private static ToolResult proposeUpdate(String recordId, Map<String, Object> fields, String reason) {
        Id rid = parseId(recordId);
        Schema.DescribeSObjectResult d = rid.getSObjectType().getDescribe();
        if (!d.isAccessible() || !d.isUpdateable()) {
            return error('You cannot update ' + d.getLabel() + ' records.');
        }
        if (fields == null || fields.isEmpty()) {
            return error('fields must contain at least one field.');
        }
        List<String> selectFields = new List<String>{ 'Id' };
        Map<String, Schema.DescribeFieldResult> describes = new Map<String, Schema.DescribeFieldResult>();
        for (String fn : fields.keySet()) {
            Schema.DescribeFieldResult f = fieldOrError(d, fn);
            if (!f.isUpdateable()) {
                return error('Field ' + f.getName() + ' is not updateable.');
            }
            describes.put(fn, f);
            selectFields.add(f.getName());
        }
        Boolean nameAlreadySelected = false;
        for (String fn : describes.keySet()) {
            if (fn.equalsIgnoreCase('Name')) {
                nameAlreadySelected = true;
            }
        }
        if (d.fields.getMap().containsKey('name') && !nameAlreadySelected) {
            selectFields.add('Name');
        }
        String q = 'SELECT ' + String.join(selectFields, ', ') + ' FROM ' + d.getName() + ' WHERE Id = :rid';
        List<SObject> rows = Database.queryWithBinds(q, new Map<String, Object>{ 'rid' => rid }, AccessLevel.USER_MODE);
        if (rows.isEmpty()) {
            return error('Record ' + recordId + ' was not found or you cannot see it.');
        }
        SObject current = rows[0];
        List<Map<String, Object>> changes = new List<Map<String, Object>>();
        for (String fn : fields.keySet()) {
            Schema.DescribeFieldResult f = describes.get(fn);
            changes.add(new Map<String, Object>{
                'apiName' => f.getName(), 'label' => f.getLabel(), 'type' => String.valueOf(f.getType()),
                'current' => current.get(f.getName()),
                'proposed' => coerce(f, fields.get(fn))
            });
        }
        Object recordName = d.fields.getMap().containsKey('name') ? current.get('Name') : null;
        return proposalResult(new Map<String, Object>{
            'action' => 'update', 'objectApiName' => d.getName(), 'objectLabel' => d.getLabel(),
            'recordId' => String.valueOf(rid), 'recordName' => recordName,
            'reason' => reason, 'changes' => changes
        }, 'Proposed update to ' + d.getLabel() + (recordName == null ? '' : ' "' + recordName + '"'));
    }

    private static ToolResult proposalResult(Map<String, Object> proposal, String summary) {
        ToolResult r = new ToolResult();
        r.proposal = proposal;
        r.summary = summary;
        r.content = 'Proposal shown to the user; waiting for their decision.';
        return r;
    }

    /** Applies an approved proposal in USER_MODE. Returns the outcome to feed back to Claude. */
    public static Map<String, Object> executeProposal(Map<String, Object> proposal) {
        String action = (String) proposal.get('action');
        String objectApiName = (String) proposal.get('objectApiName');
        Schema.DescribeSObjectResult d = describeAccessible(objectApiName);
        SObject rec = d.getSObjectType().newSObject();
        if (action == 'update') {
            rec.Id = (Id) proposal.get('recordId');
        }
        for (Object o : (List<Object>) proposal.get('changes')) {
            Map<String, Object> change = (Map<String, Object>) o;
            Schema.DescribeFieldResult f = fieldOrError(d, (String) change.get('apiName'));
            rec.put(f.getName(), coerce(f, change.get('proposed')));
        }
        try {
            Database.SaveResult sr = action == 'update'
                ? Database.update(rec, true, AccessLevel.USER_MODE)
                : Database.insert(rec, true, AccessLevel.USER_MODE);
            return new Map<String, Object>{
                'approved' => true, 'success' => true, 'action' => action,
                'objectApiName' => d.getName(), 'objectLabel' => d.getLabel(),
                'recordId' => String.valueOf(sr.getId())
            };
        } catch (DmlException e) {
            return new Map<String, Object>{
                'approved' => true, 'success' => false, 'action' => action,
                'objectApiName' => d.getName(), 'error' => e.getDmlMessage(0)
            };
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    private static Schema.DescribeSObjectResult describeAccessible(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new ToolException('objectApiName is required.');
        }
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApiName.toLowerCase());
        if (t == null) {
            throw new ToolException('Object ' + objectApiName + ' does not exist or you cannot access it.');
        }
        Schema.DescribeSObjectResult d = t.getDescribe();
        if (!d.isAccessible()) {
            throw new ToolException('You do not have access to ' + d.getName() + '.');
        }
        return d;
    }

    private static Schema.DescribeFieldResult fieldOrError(Schema.DescribeSObjectResult d, String fieldName) {
        Schema.SObjectField f = String.isBlank(fieldName) ? null : d.fields.getMap().get(fieldName.toLowerCase());
        if (f == null) {
            throw new ToolException('Field ' + fieldName + ' does not exist on ' + d.getName() + '.');
        }
        Schema.DescribeFieldResult fd = f.getDescribe();
        if (!fd.isAccessible()) {
            throw new ToolException('You do not have access to field ' + fd.getName() + '.');
        }
        return fd;
    }

    private static Id parseId(String recordId) {
        try {
            return Id.valueOf(recordId);
        } catch (Exception e) {
            throw new ToolException('"' + recordId + '" is not a valid record Id.');
        }
    }

    @TestVisible
    private static Object coerce(Schema.DescribeFieldResult f, Object value) {
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value).trim();
        if (s == '') {
            return null;
        }
        switch on f.getType() {
            when INTEGER {
                return Decimal.valueOf(s).intValue();
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(s);
            }
            when BOOLEAN {
                return Boolean.valueOf(s);
            }
            when DATE {
                return s.length() > 10 ? Date.valueOf(s.substring(0, 10)) : Date.valueOf(s);
            }
            when DATETIME {
                return (DateTime) JSON.deserialize('"' + s + '"', DateTime.class);
            }
            when else {
                return s;
            }
        }
    }

    @TestVisible
    private static Map<String, Object> toMap(SObject rec) {
        Map<String, Object> out = new Map<String, Object>();
        for (String field : rec.getPopulatedFieldsAsMap().keySet()) {
            Object v = rec.getPopulatedFieldsAsMap().get(field);
            if (v instanceof SObject) {
                out.put(field, toMap((SObject) v));
            } else if (v instanceof List<SObject>) {
                List<Map<String, Object>> children = new List<Map<String, Object>>();
                for (SObject c : (List<SObject>) v) {
                    children.add(toMap(c));
                }
                out.put(field, children);
            } else {
                out.put(field, v);
            }
        }
        return out;
    }

    private static String objectLabel(SObject rec) {
        try {
            return rec.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
        } catch (Exception e) {
            return 'records';
        }
    }

    private static Map<String, Object> asMap(Object o) {
        return o instanceof Map<String, Object> ? (Map<String, Object>) o : null;
    }

    private static ToolResult ok(Map<String, Object> payload) {
        ToolResult r = new ToolResult();
        String json = JSON.serialize(payload);
        if (json.length() > MAX_RESULT_CHARS) {
            json = json.substring(0, MAX_RESULT_CHARS) + '... [result truncated; narrow the query]';
        }
        r.content = json;
        return r;
    }

    private static ToolResult error(String message) {
        ToolResult r = new ToolResult();
        r.isError = true;
        r.content = message;
        r.summary = 'Tool error: ' + message.abbreviate(80);
        return r;
    }

    public class ToolException extends Exception {}
}
