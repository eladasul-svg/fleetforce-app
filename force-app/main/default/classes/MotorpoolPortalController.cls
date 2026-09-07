public without sharing class MotorpoolPortalController {
    // In the namespace-owner org, flows aren't self-prefixed.
    // In subscriber orgs the flow is installed as fleetforce__Motorpool_Reservation_Request.
    // Organization.NamespacePrefix = 'fleetforce' means we ARE the namespace owner.
    public String getFlowApiName() {
        String ns = [SELECT NamespacePrefix FROM Organization LIMIT 1].NamespacePrefix;
        return 'fleetforce' == ns
            ? 'Motorpool_Reservation_Request'
            : 'fleetforce__Motorpool_Reservation_Request';
    }
}
