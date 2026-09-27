@IsTest
private class AssistantToolsTest {

    private static final String ASSET_OBJECT = Schema.SObjectType.fleetforce__Fleet_Asset__c.getName();

    @TestSetup
    static void makeData() {
        Account vendor = new Account(Name = 'Tools Vendor');
        insert vendor;
        insert new fleetforce__Fleet_Asset__c(
            Name = 'TOOL-ASSET-001',
            fleetforce__Status__c = 'Available',
            fleetforce__Vendor__c = vendor.Id
        );

        // FleetAdmin grants FLS on Fleet_Asset__c's custom fields (Status__c, Vendor__c); the running
        // user has no profile-level access to custom fields without it. USER_MODE tool queries need
        // the SUT call itself to run inside a fresh System.runAs(self) block - see asSelfUser() below.
        Id userId = UserInfo.getUserId();
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'FleetAdmin' LIMIT 1];
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :ps.Id] == 0) {
            System.runAs(new User(Id = userId)) {
                insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
            }
        }
    }

    private static User asSelfUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static Map<String, Object> parse(AssistantTools.ToolResult r) {
        return (Map<String, Object>) JSON.deserializeUntyped(r.content);
    }

    private static Map<String, Object> input(String key, Object value) {
        return new Map<String, Object>{ key => value };
    }

    @IsTest
    static void definitionsDescribeSixTools() {
        List<Object> defs = AssistantTools.definitions();
        System.assertEquals(6, defs.size());
        Set<String> names = new Set<String>();
        for (Object o : defs) {
            Map<String, Object> d = (Map<String, Object>) o;
            names.add((String) d.get('name'));
            System.assert(d.containsKey('input_schema'), 'every tool needs an input_schema');
            System.assert(String.isNotBlank((String) d.get('description')));
        }
        System.assert(names.containsAll(new Set<String>{
            'list_objects', 'describe_object', 'query_records', 'get_record', 'propose_create', 'propose_update'
        }));
        System.assert(AssistantTools.isProposal('propose_update'));
        System.assert(!AssistantTools.isProposal('query_records'));
    }

    @IsTest
    static void listObjectsDefaultIncludesFleetObjectsAndSearchFindsStandard() {
        AssistantTools.ToolResult all = AssistantTools.execute('list_objects', null);
        System.assert(!all.isError, all.content);
        Set<String> apis = new Set<String>();
        for (Object o : (List<Object>) parse(all).get('objects')) {
            apis.add((String) ((Map<String, Object>) o).get('apiName'));
        }
        System.assert(apis.contains(ASSET_OBJECT), 'default listing should include ' + ASSET_OBJECT);
        System.assert(apis.contains('Account'));

        AssistantTools.ToolResult searched = AssistantTools.execute('list_objects', input('search', 'contact'));
        System.assert(!searched.isError);
        System.assert(searched.summary.contains('contact'));
        Boolean found = false;
        for (Object o : (List<Object>) parse(searched).get('objects')) {
            if (((Map<String, Object>) o).get('apiName') == 'Contact') {
                found = true;
            }
        }
        System.assert(found, 'search should find Contact');
    }

    @IsTest
    static void describeObjectReturnsFieldsAndRejectsUnknown() {
        AssistantTools.ToolResult r;
        System.runAs(asSelfUser()) {
            r = AssistantTools.execute('describe_object', input('objectApiName', ASSET_OBJECT));
        }
        System.assert(!r.isError, r.content);
        Map<String, Object> d = parse(r);
        System.assertEquals(ASSET_OBJECT, d.get('apiName'));
        Boolean hasName = false;
        Boolean hasStatusValues = false;
        for (Object o : (List<Object>) d.get('fields')) {
            Map<String, Object> f = (Map<String, Object>) o;
            if (f.get('apiName') == 'Name') {
                hasName = true;
            }
            if (String.valueOf(f.get('apiName')).endsWith('Status__c') && f.containsKey('picklistValues')) {
                hasStatusValues = true;
            }
        }
        System.assert(hasName);
        System.assert(hasStatusValues, 'picklist fields should list their values');
        System.assert(d.containsKey('childRelationships'));

        AssistantTools.ToolResult bad = AssistantTools.execute('describe_object', input('objectApiName', 'No_Such_Object__c'));
        System.assert(bad.isError);
        System.assert(bad.content.contains('does not exist'));

        AssistantTools.ToolResult blank = AssistantTools.execute('describe_object', new Map<String, Object>());
        System.assert(blank.isError);
    }

    @IsTest
    static void queryRecordsRunsSelectAndRejectsOtherStatements() {
        AssistantTools.ToolResult r;
        System.runAs(asSelfUser()) {
            r = AssistantTools.execute('query_records',
                input('soql', 'SELECT Id, Name, fleetforce__Vendor__r.Name FROM ' + ASSET_OBJECT + ' WHERE Name = \'TOOL-ASSET-001\''));
        }
        System.assert(!r.isError, r.content);
        Map<String, Object> d = parse(r);
        System.assertEquals(1, d.get('count'));
        System.assertEquals(false, d.get('truncated'));
        Map<String, Object> row = (Map<String, Object>) ((List<Object>) d.get('records'))[0];
        System.assertEquals('TOOL-ASSET-001', row.get('Name'));
        Map<String, Object> vendor = (Map<String, Object>) row.get('fleetforce__Vendor__r');
        System.assertEquals('Tools Vendor', vendor.get('Name'));
        System.assert(r.summary.startsWith('Queried'));

        AssistantTools.ToolResult agg = AssistantTools.execute('query_records', input('soql', 'SELECT COUNT(Id) total FROM Account'));
        System.assert(!agg.isError, agg.content);

        AssistantTools.ToolResult withLimit = AssistantTools.execute('query_records', input('soql', 'SELECT Id FROM Account LIMIT 1'));
        System.assert(!withLimit.isError);

        System.assert(AssistantTools.execute('query_records', input('soql', 'DELETE FROM Account')).isError);
        System.assert(AssistantTools.execute('query_records', input('soql', 'SELECT Id FROM Account; SELECT Id FROM Contact')).isError);
        AssistantTools.ToolResult invalid = AssistantTools.execute('query_records', input('soql', 'SELECT Nope__x FROM Account'));
        System.assert(invalid.isError);
        System.assert(invalid.summary.startsWith('Tool error'));
    }

    @IsTest
    static void getRecordReadsFieldsAndValidatesId() {
        fleetforce__Fleet_Asset__c asset = [SELECT Id FROM fleetforce__Fleet_Asset__c LIMIT 1];
        AssistantTools.ToolResult r = AssistantTools.execute('get_record', input('recordId', asset.Id));
        System.assert(!r.isError, r.content);
        Map<String, Object> rec = (Map<String, Object>) parse(r).get('record');
        System.assertEquals('TOOL-ASSET-001', rec.get('Name'));

        AssistantTools.ToolResult subset = AssistantTools.execute('get_record', new Map<String, Object>{
            'recordId' => asset.Id, 'fields' => new List<Object>{ 'Name', 'Not_A_Field__c' }
        });
        System.assert(!subset.isError, subset.content);
        Map<String, Object> sub = (Map<String, Object>) parse(subset).get('record');
        System.assertEquals('TOOL-ASSET-001', sub.get('Name'));

        System.assert(AssistantTools.execute('get_record', input('recordId', 'not-an-id')).isError);
        Id missing = Id.valueOf('001000000000001AAA');
        System.assert(AssistantTools.execute('get_record', input('recordId', missing)).isError);
    }

    @IsTest
    static void proposeCreateThenExecuteInsertsRecord() {
        AssistantTools.ToolResult r = AssistantTools.execute('propose_create', new Map<String, Object>{
            'objectApiName' => 'Account',
            'fields' => new Map<String, Object>{ 'Name' => 'Proposed Vendor', 'NumberOfEmployees' => '12' },
            'reason' => 'The user asked for a new vendor.'
        });
        System.assert(!r.isError, r.content);
        System.assertNotEquals(null, r.proposal);
        System.assertEquals('create', r.proposal.get('action'));
        System.assertEquals('Account', r.proposal.get('objectApiName'));
        System.assert(r.summary.contains('Proposed new'));

        Map<String, Object> outcome = AssistantTools.executeProposal(r.proposal);
        System.assertEquals(true, outcome.get('success'), String.valueOf(outcome));
        Account created = [SELECT Name, NumberOfEmployees FROM Account WHERE Id = :(Id) outcome.get('recordId')];
        System.assertEquals('Proposed Vendor', created.Name);
        System.assertEquals(12, created.NumberOfEmployees);

        System.assert(AssistantTools.execute('propose_create', new Map<String, Object>{
            'objectApiName' => 'Account', 'fields' => new Map<String, Object>()
        }).isError);
        System.assert(AssistantTools.execute('propose_create', new Map<String, Object>{
            'objectApiName' => 'Account', 'fields' => new Map<String, Object>{ 'Nope__c' => 1 }
        }).isError);
    }

    @IsTest
    static void proposeUpdateShowsCurrentValuesAndExecuteUpdates() {
        Account a = [SELECT Id FROM Account WHERE Name = 'Tools Vendor'];
        AssistantTools.ToolResult r = AssistantTools.execute('propose_update', new Map<String, Object>{
            'recordId' => a.Id,
            'fields' => new Map<String, Object>{ 'Name' => 'Renamed Vendor' }
        });
        System.assert(!r.isError, r.content);
        System.assertEquals('update', r.proposal.get('action'));
        System.assertEquals('Tools Vendor', r.proposal.get('recordName'));
        Map<String, Object> change = (Map<String, Object>) ((List<Object>) r.proposal.get('changes'))[0];
        System.assertEquals('Tools Vendor', change.get('current'));
        System.assertEquals('Renamed Vendor', change.get('proposed'));

        // Round-trip through JSON as the service does before executing.
        Map<String, Object> stored = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(r.proposal));
        Map<String, Object> outcome = AssistantTools.executeProposal(stored);
        System.assertEquals(true, outcome.get('success'), String.valueOf(outcome));
        System.assertEquals('Renamed Vendor', [SELECT Name FROM Account WHERE Id = :a.Id].Name);

        System.assert(AssistantTools.execute('propose_update', new Map<String, Object>{
            'recordId' => 'bad', 'fields' => new Map<String, Object>{ 'Name' => 'x' }
        }).isError);
        System.assert(AssistantTools.execute('propose_update', new Map<String, Object>{
            'recordId' => a.Id, 'fields' => new Map<String, Object>{ 'CreatedDate' => '2020-01-01' }
        }).isError);
    }

    @IsTest
    static void executeProposalReportsDmlFailure() {
        AssistantTools.ToolResult r = AssistantTools.execute('propose_create', new Map<String, Object>{
            'objectApiName' => 'Contact',
            'fields' => new Map<String, Object>{ 'FirstName' => 'No' }
        });
        System.assert(!r.isError, r.content);
        Map<String, Object> outcome = AssistantTools.executeProposal(r.proposal);
        System.assertEquals(false, outcome.get('success'));
        System.assert(String.isNotBlank((String) outcome.get('error')));
    }

    @IsTest
    static void coerceConvertsByFieldType() {
        System.assertEquals(7, AssistantTools.coerce(Schema.SObjectType.Account.fields.NumberOfEmployees,'7.0'));
        System.assertEquals(12.5, AssistantTools.coerce(Schema.SObjectType.Account.fields.AnnualRevenue,12.5));
        System.assertEquals(true, AssistantTools.coerce(Schema.SObjectType.Contact.fields.DoNotCall,'true'));
        System.assertEquals(Date.newInstance(2026, 9, 18), AssistantTools.coerce(Schema.SObjectType.Opportunity.fields.CloseDate,'2026-09-18T10:00:00Z'));
        DateTime dt = (DateTime) AssistantTools.coerce(Schema.SObjectType.Task.fields.ReminderDateTime,'2026-09-18T10:30:00Z');
        System.assertEquals(2026, dt.yearGmt());
        System.assertEquals(null, AssistantTools.coerce(Schema.SObjectType.Account.fields.Name,'  '));
        System.assertEquals('x', AssistantTools.coerce(Schema.SObjectType.Account.fields.Name,'x'));
    }

    @IsTest
    static void unknownToolIsAnError() {
        AssistantTools.ToolResult r = AssistantTools.execute('teleport', null);
        System.assert(r.isError);
        System.assert(r.content.contains('Unknown tool'));
    }
}
