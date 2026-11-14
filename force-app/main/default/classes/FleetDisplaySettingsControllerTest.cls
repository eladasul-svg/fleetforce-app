@IsTest
private class FleetDisplaySettingsControllerTest {
  @TestSetup
  static void grantAccess() {
    // FleetforceAdmin grants edit access to the setting (same pattern as AssistantToolsTest).
    Id userId = UserInfo.getUserId();
    PermissionSet ps = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'FleetforceAdmin'
      LIMIT 1
    ];
    if (
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :userId AND PermissionSetId = :ps.Id
      ] == 0
    ) {
      System.runAs(new User(Id = userId)) {
        insert new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetId = ps.Id
        );
      }
    }
  }

  @IsTest
  static void defaultsToSilhouetteWhenUnset() {
    System.assertEquals(
      'silhouette',
      FleetDisplaySettingsController.getIconStyle()
    );
  }

  @IsTest
  static void savedStyleIsReturned() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      System.assertEquals(
        'classic',
        FleetDisplaySettingsController.saveIconStyle('Classic')
      );
      System.assertEquals(
        'classic',
        FleetDisplaySettingsController.getIconStyle()
      );
      FleetDisplaySettingsController.saveIconStyle('futuristic');
      System.assertEquals(
        'futuristic',
        FleetDisplaySettingsController.getIconStyle()
      );
    }
  }

  @IsTest
  static void unknownStyleIsRejected() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      try {
        FleetDisplaySettingsController.saveIconStyle('steampunk');
        System.assert(false, 'expected an exception');
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
    System.assertEquals(
      'silhouette',
      FleetDisplaySettingsController.getIconStyle()
    );
  }

  @IsTest
  static void regionalSettingsListOptionsAndProfiles() {
    FleetDisplaySettingsController.RegionalSettings r = FleetDisplaySettingsController.getRegionalSettings();
    System.assertEquals(
      UserInfo.isMultiCurrencyOrganization(),
      r.multiCurrency
    );
    System.assertNotEquals(null, r.orgCurrency);
    System.assert(r.countries.size() > 200, 'every ISO country is offered');
    System.assertEquals(2, r.distanceUnits.size());
    System.assert(
      r.profiles.size() >= 10,
      'the shipped Country Profiles are listed'
    );
  }

  @IsTest
  static void regionalSettingsAreSavedAndValidated() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      FleetDisplaySettingsController.RegionalSettings r = FleetDisplaySettingsController.saveRegionalSettings(
        'mi',
        'gal_US',
        'lb',
        'US',
        'America/Chicago',
        'USD'
      );
      System.assert(r.canEdit);
      System.assertEquals('mi', r.distanceUnit);
      System.assertEquals(
        'America/Chicago',
        fleetforce__Fleet_Display_Setting__c.getOrgDefaults()
          .fleetforce__Default_Time_Zone__c
      );

      r = FleetDisplaySettingsController.saveRegionalSettings(
        'km',
        'L',
        'kg',
        '',
        null,
        ''
      );
      System.assertEquals(null, r.country);
      try {
        FleetDisplaySettingsController.saveRegionalSettings(
          'furlongs',
          'L',
          'kg',
          null,
          null,
          null
        );
        System.assert(false, 'expected an exception');
      } catch (AuraHandledException e) {
        System.assert(true);
      }
    }
    System.assertEquals(
      'km',
      fleetforce__Fleet_Display_Setting__c.getOrgDefaults()
        .fleetforce__Default_Distance_Unit__c
    );
  }

  @IsTest
  static void generalSettingsAreRetrievedAndSaved() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      FleetDisplaySettingsController.GeneralSettings g = FleetDisplaySettingsController.getGeneralSettings();
      System.assertNotEquals(null, g);
      System.assert(g.canEdit);

      FleetDisplaySettingsController.GeneralSettings saved = FleetDisplaySettingsController.saveGeneralSettings(
        true,
        'Claude 3.5 Sonnet',
        true,
        'AIzaSyDummyGoogleKey12345',
        'sk-ant-dummy-anthropic-key-12345',
        'sk-dummy-openai-key-12345'
      );
      System.assertEquals(true, saved.enableAiInsights);
      System.assertEquals('Claude 3.5 Sonnet', saved.aiProvider);
      System.assertEquals(true, saved.enableExtendedPrivacy);
      System.assertEquals(true, saved.hasGoogleKey);
      System.assertEquals(true, saved.hasAnthropicKey);
      System.assertEquals(true, saved.hasOpenAiKey);
      System.assert(saved.maskedGoogleKey.contains('••••'));
      System.assert(saved.aiProviders.size() >= 4);

      fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
      System.assertEquals(true, org.fleetforce__Enable_AI_Insights__c);
      System.assertEquals('Claude 3.5 Sonnet', org.fleetforce__AI_Provider__c);
      System.assertEquals(true, org.fleetforce__Enable_Extended_Privacy__c);
      System.assertEquals(
        'AIzaSyDummyGoogleKey12345',
        org.fleetforce__Google_Api_Key__c
      );
    }
  }

  @IsTest
  static void brandSettingsAreRetrievedAndSaved() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      FleetDisplaySettingsController.BrandSettings b = FleetDisplaySettingsController.getBrandSettings();
      System.assertNotEquals(null, b);
      System.assert(b.canEdit);

      FleetDisplaySettingsController.BrandSettings saved = FleetDisplaySettingsController.saveBrandSettings(
        'modern',
        true,
        'Acme Global Fleet',
        '#0176D3',
        'https://example.com/logo.png'
      );
      System.assertEquals('modern', saved.iconStyle);
      System.assertEquals(true, saved.useCustomTheme);
      System.assertEquals('Acme Global Fleet', saved.customThemeName);
      System.assertEquals('#0176D3', saved.customBrandColor);
    }
  }
}
