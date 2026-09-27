@RestResource(urlMapping='/motorpoolReservation')
global without sharing class MotorpoolPortalController {

    global class ReservationRequest {
        global String firstName;
        global String lastName;
        global String email;
        global String phone;
        global String startTime;
        global String endTime;
        global Integer minSeats;
    }

    @HttpPost
    global static void submitReservation() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            ReservationRequest input = (ReservationRequest) JSON.deserialize(
                req.requestBody.toString(), ReservationRequest.class
            );
            fleetforce__Reservation__c r = new fleetforce__Reservation__c(
                fleetforce__Guest_First_Name__c = input.firstName,
                fleetforce__Guest_Last_Name__c  = input.lastName,
                fleetforce__Guest_Email__c      = input.email,
                fleetforce__Guest_Phone__c      = input.phone,
                fleetforce__Start_Time__c       = (String.isBlank(input.startTime) ? null : (DateTime) JSON.deserialize('"' + input.startTime + '"', DateTime.class)),
                fleetforce__End_Time__c         = (String.isBlank(input.endTime)   ? null : (DateTime) JSON.deserialize('"' + input.endTime   + '"', DateTime.class)),
                fleetforce__Min_Seats__c        = input.minSeats,
                fleetforce__Status__c           = 'Pending'
            );
            insert r;
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'id' => r.Id }));
        } catch (Exception e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'error' => e.getMessage() }));
        }
    }
}
