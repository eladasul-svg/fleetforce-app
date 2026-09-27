@IsTest
private class MotorpoolPortalControllerTest {

    private static RestRequest buildRequest(String body) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/fleetforce/motorpoolReservation';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        return req;
    }

    @IsTest
    static void submitReservationInsertsRecordAndReturnsId() {
        RestContext.request = buildRequest(JSON.serialize(new Map<String, Object>{
            'firstName' => 'Jane',
            'lastName'  => 'Smith',
            'email'     => 'jane.smith@example.com',
            'phone'     => '555-1234',
            'startTime' => '2026-10-05T09:00:00.000Z',
            'endTime'   => '2026-10-06T17:00:00.000Z',
            'minSeats'  => 2
        }));
        RestContext.response = new RestResponse();

        Test.startTest();
        MotorpoolPortalController.submitReservation();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assert(String.isNotBlank((String) body.get('id')));

        fleetforce__Reservation__c r = [
            SELECT fleetforce__Guest_First_Name__c, fleetforce__Guest_Email__c,
                   fleetforce__Min_Seats__c, fleetforce__Status__c
            FROM fleetforce__Reservation__c
            WHERE Id = :(Id) body.get('id')
        ];
        System.assertEquals('Jane', r.fleetforce__Guest_First_Name__c);
        System.assertEquals('jane.smith@example.com', r.fleetforce__Guest_Email__c);
        System.assertEquals(2, r.fleetforce__Min_Seats__c);
        System.assertEquals('Pending', r.fleetforce__Status__c);
    }

    @IsTest
    static void submitReservationWithBlankDatesLeavesThemNull() {
        RestContext.request = buildRequest(JSON.serialize(new Map<String, Object>{
            'firstName' => 'No',
            'lastName'  => 'Dates',
            'email'     => 'no.dates@example.com',
            'minSeats'  => 1
        }));
        RestContext.response = new RestResponse();

        MotorpoolPortalController.submitReservation();

        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void malformedBodyReturns400WithError() {
        RestContext.request = buildRequest('not valid json');
        RestContext.response = new RestResponse();

        MotorpoolPortalController.submitReservation();

        System.assertEquals(400, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assert(String.isNotBlank((String) body.get('error')));
    }
}
