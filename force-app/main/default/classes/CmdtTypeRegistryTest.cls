@IsTest
private class CmdtTypeRegistryTest {
  @IsTest
  static void testValidTypePasses() {
    Test.startTest();
    CmdtTypeRegistry.validate('Country_Profile__mdt');
    CmdtTypeRegistry.validate('Vehicle_Model__mdt');
    Test.stopTest();
    System.assert(true, 'Valid CMDT types should not throw');
  }

  @IsTest
  static void testInvalidTypeThrows() {
    Boolean threw = false;
    Test.startTest();
    try {
      CmdtTypeRegistry.validate('Account');
    } catch (CmdtTypeRegistry.UnsupportedCmdtTypeException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assert(
      threw,
      'Unsupported type should throw UnsupportedCmdtTypeException'
    );
  }

  @IsTest
  static void testBlankTypeThrows() {
    Boolean threw = false;
    Test.startTest();
    try {
      CmdtTypeRegistry.validate('');
    } catch (CmdtTypeRegistry.UnsupportedCmdtTypeException ex) {
      threw = true;
    }
    Test.stopTest();
    System.assert(
      threw,
      'Blank type should throw UnsupportedCmdtTypeException'
    );
  }

  @IsTest
  static void testSupportedTypesList() {
    List<CmdtTypeRegistry.TypeOption> options = CmdtTypeRegistry.getSupportedTypes();
    System.assert(options != null && options.size() == 6);
  }
}
