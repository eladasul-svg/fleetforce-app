@IsTest
private class CmdtRecordServiceTest {
  @IsTest
  static void testGetRecordsForCountryProfile() {
    Test.startTest();
    List<SObject> records = CmdtRecordService.getRecords(
      'Country_Profile__mdt'
    );
    Test.stopTest();

    System.assertNotEquals(null, records);
    System.assert(
      records.size() >= 10,
      'Expected at least 10 shipped country profiles'
    );
  }

  @IsTest
  static void testInvalidTypeThrows() {
    Boolean threw = false;
    Test.startTest();
    try {
      CmdtRecordService.getRecords('Account');
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assert(threw, 'Expected exception on invalid type');
  }
}
