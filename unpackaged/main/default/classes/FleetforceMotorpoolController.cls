global without sharing class FleetforceMotorpoolController {
    @RemoteAction
    global static String submitReservation(
        String firstName, String lastName, String email, String phone,
        String startTime, String endTime, Integer minSeats
    ) {
        fleetforce__Reservation__c r = new fleetforce__Reservation__c(
            fleetforce__Guest_First_Name__c = firstName,
            fleetforce__Guest_Last_Name__c  = lastName,
            fleetforce__Guest_Email__c      = email,
            fleetforce__Guest_Phone__c      = phone,
            fleetforce__Start_Time__c       = String.isBlank(startTime) ? null :
                (DateTime) JSON.deserialize('"' + startTime + '"', DateTime.class),
            fleetforce__End_Time__c         = String.isBlank(endTime) ? null :
                (DateTime) JSON.deserialize('"' + endTime + '"', DateTime.class),
            fleetforce__Min_Seats__c        = minSeats,
            fleetforce__Status__c           = 'Pending'
        );
        insert r;
        return r.Id;
    }
}
