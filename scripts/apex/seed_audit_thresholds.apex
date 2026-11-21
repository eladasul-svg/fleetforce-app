// Seed Philips UK Audit Threshold Rules
delete [SELECT Id FROM Fleet_Audit_Threshold__c];

List<Fleet_Audit_Threshold__c> thresholds = new List<Fleet_Audit_Threshold__c>{
    new Fleet_Audit_Threshold__c(
        Rule_Name__c = 'Unallocated Spend Warning',
        Metric_Type__c = 'Unallocated_Spend_Pct',
        Operator__c = 'Greater_Than',
        Threshold_Value__c = 5.00,
        Severity__c = 'Critical_Blocker',
        Notification_Target__c = 'Teams_Webhook',
        Is_Active__c = true,
        Description__c = 'Flags invoice for executive audit review if unallocated vehicle or cost center spend exceeds 5.0% of total billed gross.'
    ),
    new Fleet_Audit_Threshold__c(
        Rule_Name__c = 'Single Line High-Value Cap',
        Metric_Type__c = 'Single_Line_Max_Gross',
        Operator__c = 'Greater_Or_Equal',
        Threshold_Value__c = 5000.00,
        Severity__c = 'Warning',
        Notification_Target__c = 'Chatter',
        Is_Active__c = true,
        Description__c = 'Flags non-rental/leasing invoice lines exceeding £5,000 (€6,000 equivalent) requiring senior fleet management sign-off.'
    ),
    new Fleet_Audit_Threshold__c(
        Rule_Name__c = 'Missing EoC Repair Credit Allowance',
        Metric_Type__c = 'Missing_Credit_Count',
        Operator__c = 'Greater_Than',
        Threshold_Value__c = 0.00,
        Severity__c = 'Critical_Blocker',
        Notification_Target__c = 'Platform_Event',
        Is_Active__c = true,
        Description__c = 'Alerts when return repair or refurbishment lines lack the contractual £250/€300 credit allowance.'
    ),
    new Fleet_Audit_Threshold__c(
        Rule_Name__c = 'Operational Recharge Surge',
        Metric_Type__c = 'Recharge_Spend_Pct',
        Operator__c = 'Greater_Than',
        Threshold_Value__c = 3.00,
        Severity__c = 'Warning',
        Notification_Target__c = 'Email_Digest',
        Is_Active__c = true,
        Description__c = 'Notifies fleet payroll team if driver recharges and fines exceed 3% of total invoice gross.'
    )
};

insert thresholds;
System.debug('Successfully seeded ' + thresholds.size() + ' Fleet Audit Thresholds.');
