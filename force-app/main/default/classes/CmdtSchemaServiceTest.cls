@IsTest
private class CmdtSchemaServiceTest {
  @IsTest
  static void testGetFieldDescribesForCountryProfile() {
    Test.startTest();
    List<CmdtSchemaService.CmdtFieldInfo> fields = CmdtSchemaService.getFieldDescribes(
      'Country_Profile__mdt'
    );
    Test.stopTest();

    System.assertNotEquals(null, fields);
    System.assert(fields.size() > 0);

    Boolean hasIsoCode = false;
    for (CmdtSchemaService.CmdtFieldInfo f : fields) {
      if (f.apiName.contains('ISO_Code__c')) {
        hasIsoCode = true;
      }
    }
    System.assert(hasIsoCode, 'Expected ISO_Code__c field in describes');
  }

  @IsTest
  static void testGetTypeInfo() {
    Test.startTest();
    CmdtSchemaService.CmdtTypeInfo info = CmdtSchemaService.getTypeInfo(
      'Country_Profile__mdt'
    );
    Test.stopTest();

    System.assertNotEquals(null, info);
    System.assert(info.apiName.contains('Country_Profile__mdt'));
  }

  @IsTest
  static void testInvalidTypeThrows() {
    Boolean threw = false;
    Test.startTest();
    try {
      CmdtSchemaService.getFieldDescribes('Invalid_Type__mdt');
    } catch (Exception ex) {
      threw = true;
    }
    Test.stopTest();
    System.assert(threw, 'Expected exception on invalid type');
  }
}
