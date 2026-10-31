@IsTest
private class FleetAssetIdentityTest {
  static Fleet_Branch__c branch(String country) {
    Fleet_Branch__c b = new Fleet_Branch__c(
      Name = 'Branch ' + country,
      Country__c = country
    );
    insert b;
    return b;
  }

  @IsTest
  static void plateKeyUsesRegistrationCountryThenBranch() {
    Fleet_Branch__c london = branch('GB');
    Fleet_Asset__c registeredPt = new Fleet_Asset__c(
      Name = 'PT car',
      Branch__c = london.Id,
      Country__c = 'PT',
      License_Plate__c = 'aa-00 aa'
    );
    Fleet_Asset__c local = new Fleet_Asset__c(
      Name = 'GB car',
      Branch__c = london.Id,
      License_Plate__c = 'AB12 CDE'
    );
    insert new List<Fleet_Asset__c>{ registeredPt, local };

    Map<Id, Fleet_Asset__c> saved = new Map<Id, Fleet_Asset__c>(
      [
        SELECT Plate_Key__c
        FROM Fleet_Asset__c
        WHERE Id IN :new List<Id>{ registeredPt.Id, local.Id }
      ]
    );
    System.assertEquals('PT|AA00AA', saved.get(registeredPt.Id).Plate_Key__c);
    System.assertEquals('GB|AB12CDE', saved.get(local.Id).Plate_Key__c);
  }

  @IsTest
  static void vinReplacesPlateKey() {
    Fleet_Asset__c a = new Fleet_Asset__c(
      Name = 'Car',
      Country__c = 'PT',
      License_Plate__c = 'AA-00-AA'
    );
    insert a;
    a.VIN__c = '1hgcm82633a004352';
    update a;

    a = [SELECT VIN__c, Plate_Key__c FROM Fleet_Asset__c WHERE Id = :a.Id];
    System.assertEquals('1HGCM82633A004352', a.VIN__c);
    System.assertEquals(null, a.Plate_Key__c);
  }

  @IsTest
  static void samePlateInSameCountryIsRejected() {
    insert new Fleet_Asset__c(
      Name = 'First',
      Country__c = 'PT',
      License_Plate__c = 'AA-00-AA'
    );
    Boolean rejected = false;
    try {
      insert new Fleet_Asset__c(
        Name = 'Second',
        Country__c = 'PT',
        License_Plate__c = 'aa 00 aa'
      );
    } catch (DmlException e) {
      rejected = e.getDmlType(0) == StatusCode.DUPLICATE_VALUE;
    }
    System.assert(
      rejected,
      'The same plate in the same country must be rejected'
    );
    insert new Fleet_Asset__c(
      Name = 'Elsewhere',
      Country__c = 'ES',
      License_Plate__c = 'AA-00-AA'
    );
  }

  @IsTest
  static void vinMustBeSeventeenValidCharacters() {
    for (String bad : new List<String>{ 'VIN123', '1HGCM82633A00435O' }) {
      Boolean rejected = false;
      try {
        insert new Fleet_Asset__c(Name = 'Bad VIN', VIN__c = bad);
      } catch (DmlException e) {
        rejected =
          e.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION;
      }
      System.assert(rejected, bad + ' must be rejected');
    }
  }

  @IsTest
  static void normalisePlateHandlesBlanks() {
    System.assertEquals(null, FleetAssetIdentity.normalisePlate(null));
    System.assertEquals(null, FleetAssetIdentity.normalisePlate(' - '));
  }
}
