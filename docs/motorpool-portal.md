# Motorpool booking portal (Experience Cloud, LWR)

A public "Book a vehicle" site: pick dates, seats and vehicle type, see which vehicles are free (with a 7-day
availability strip per vehicle), select one and send a booking request. The request becomes a **Pending**
`Reservation__c` assigned to the chosen vehicle; a motorpool manager approves it in Fleet Ops.

## Where the pieces live

| Piece | Location | Ships in the package? |
|---|---|---|
| `motorpoolBooking` LWC, `MotorpoolBookingController` (+ test) | `force-app` | yes |
| Site (`digitalExperiences`, `networks`, `digitalExperienceConfigs`) | `unpackaged/` | **no** - LWR site workspaces are reported not to be packageable in a 2GP managed package, so the site is deployed separately, like the older Sites-based portal |
| Guest user profile access to the booking Apex | `unpackaged/main/default/profiles/FleetForce Motorpool Profile.profile-meta.xml` | no (profiles are not packageable) |
| Digital Experiences org setting | `unpackaged/main/default/settings/Communities.settings-meta.xml` | no |

## Standing the site up in a new org

1. Deploy the package source (`force-app`) and assign `FleetforceAdmin`.
2. Enable Digital Experiences (once per org):
   `sf project deploy start --source-dir unpackaged/main/default/settings/Communities.settings-meta.xml`
3. Create the site shell so the guest user and domain exist (the name and prefix must match the config):
   `sf community create --name "FleetForce Motorpool" --template-name "Build Your Own (LWR)" --url-path-prefix motorpool`
   and wait for the background job to finish.
4. Deploy the site and the guest profile:
   `sf project deploy start --source-dir unpackaged/main/default/digitalExperiences --source-dir unpackaged/main/default/networks --source-dir unpackaged/main/default/digitalExperienceConfigs --source-dir "unpackaged/main/default/profiles/FleetForce Motorpool Profile.profile-meta.xml"`
5. Publish: `sf community publish --name "FleetForce Motorpool"` (republish after any change to the component or the site).
6. Seed the demo data: `sf apex run --file scripts/apex/seed_motorpool_bookings.apex` (also re-run it to refresh the dates).

The public URL is `https://<org domain>.my.site.com/motorpool/`.

## Things to know

- The site is public (guest access); bookings made there are owned by an active administrator because guest users
  cannot own records.
- Availability: a vehicle is bookable when it is active with status **Available**. For a window it is unavailable if
  it overlaps a Pending / Approved / Active reservation, an availability blackout, or an in-shop service ticket.
- `book()` takes simple parameters on purpose: a custom-class parameter failed with a generic server error for the
  guest user on the LWR runtime.
- The component is referenced in the site as `fleetforce:motorpoolBooking` (namespaced).
