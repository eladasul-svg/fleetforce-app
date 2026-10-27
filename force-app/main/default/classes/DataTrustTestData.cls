/**
 * Test data for the data trust tests: vehicles, the Standard / EV batch profiles and streams.
 */
@IsTest
public class DataTrustTestData {

    public static Fleet_Asset__c asset(String name, String fuel, String make, String model, Integer year, String country) {
        return new Fleet_Asset__c(Name = name, Is_Active__c = true, Fuel_Type__c = fuel, Vehicle_Class__c = 'Commercial',
            Make__c = make, Model__c = model, Model_Year__c = year, Country__c = country);
    }

    public static Data_Source__c source(String name) {
        Data_Source__c s = new Data_Source__c(Name = name, Source_Type__c = 'Telematics', Status__c = 'Active',
            Expected_Frequency_Hours__c = 24, Reference_URL__c = 'https://example.com/' + name.replace(' ', '-'));
        insert s;
        return s;
    }

    /** The Standard profile used by the seed: 8 signals; Location 24 h, Odometer 72 h, Fuel 72 h, Maintenance 720 h required. */
    public static Stream_Profile__c standardProfile() {
        Stream_Profile__c p = new Stream_Profile__c(Name = 'Standard', Expected_Signal_Count__c = 8, Is_Default__c = true,
            Priority__c = 100, Active__c = true);
        insert p;
        insert new List<Stream_Profile_Line__c>{
            line(p, 'Location', true, 24, 2),
            line(p, 'Odometer', true, 72, 1),
            line(p, 'Fuel or charge', true, 72, 1),
            line(p, 'Maintenance plan', true, 720, 1),
            line(p, 'Diagnostics', false, 168, null)
        };
        return p;
    }

    public static Stream_Profile__c evProfile() {
        Stream_Profile__c p = new Stream_Profile__c(Name = 'EV batch', Expected_Signal_Count__c = 14, Fuel_Type__c = 'Electric',
            Priority__c = 10, Active__c = true);
        insert p;
        insert new List<Stream_Profile_Line__c>{
            line(p, 'Location', true, 24, 3),
            line(p, 'Fuel or charge', true, 24, 4)
        };
        return p;
    }

    public static Stream_Profile_Line__c line(Stream_Profile__c p, String type, Boolean required, Integer maxAge, Integer minSignals) {
        return new Stream_Profile_Line__c(Stream_Profile__c = p.Id, Data_Type__c = type, Required__c = required,
            Max_Age_Hours__c = maxAge, Min_Signals__c = minSignals);
    }

    public static Data_Stream__c stream(Id assetId, Data_Source__c src, String type, Datetime lastUpdate, Integer signals) {
        return new Data_Stream__c(Name = type, Fleet_Asset__c = assetId, Data_Source__c = src.Id, Data_Type__c = type,
            Last_Update__c = lastUpdate, Signals_Present__c = signals);
    }

    /** All four required Standard streams fresh, 8 signals. */
    public static List<Data_Stream__c> healthyStreams(Id assetId, Data_Source__c src, Datetime nowTs) {
        return new List<Data_Stream__c>{
            stream(assetId, src, 'Location', nowTs.addHours(-2), 2),
            stream(assetId, src, 'Odometer', nowTs.addHours(-2), 1),
            stream(assetId, src, 'Diagnostics', nowTs.addHours(-2), 1),
            stream(assetId, src, 'Fuel or charge', nowTs.addHours(-12), 2),
            stream(assetId, src, 'Maintenance plan', nowTs.addHours(-72), 2)
        };
    }

    public static External_Notice__c notice(String extId, String type, String make, String model, Integer yFrom, Integer yTo) {
        return new External_Notice__c(Name = extId, External_Id__c = extId, Notice_Type__c = type, Title__c = extId + ' title',
            Summary__c = 'Summary of ' + extId, Severity__c = 'High', Status__c = 'Active', Reviewed__c = true,
            Make__c = make, Model__c = model, Year_From__c = yFrom, Year_To__c = yTo,
            Published_On__c = System.today(), Effective_On__c = System.today().addDays(30));
    }
}
