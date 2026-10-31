#!/usr/bin/env python3
"""
One-time conversion of the SFDMU demo dataset (data/sfdmu-export) from four US branches to the multi-country demo:
Lisbon (PT), London (GB), Tel Aviv (IL) and Chicago (US). Safe to rerun: it does nothing once the US branch IDs are gone.

What it changes:
- Branches: name, Branch ID, address (Region / State is a restricted list of US states, so it stays blank outside
  the US and County / Province holds the region), location, country (ISO), IANA time zone, currency and units. Chicago keeps
  America/Chicago although the US Country Profile default is America/New_York (shows a branch override).
- Schedules: IANA time zones; names that said a US region are renamed (references follow).
- Vehicles: plates in the branch country's format, Registered State only in the US, Regulatory Category from body type,
  one cross-border vehicle (registered PT, operating from London). Registration Country is otherwise left blank
  (it inherits the branch country).
- Distances: vehicles at km branches have every stored odometer, trip distance and speed converted from miles.
- Fuel: vehicles outside the US log litres at a local price; Calculated Economy is recomputed in the vehicle's units.
- Insurance and qualification Status: 1/0 become Active/Expired and Valid/Expired.

Usage: python3 scripts/data/regionalise_demo_data.py [data/sfdmu-export]
"""
import csv
import os
import sys

KM_PER_MILE = 1.609344
L_PER_GAL = 3.785411784

DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'sfdmu-export')
NS = 'fleetforce__'

BRANCHES = {
    'BR-DAL': dict(id='BR-LIS', name='Lisbon Central HQ', city='Lisbon', country='PT', region='',
                   county='Lisboa', street='Avenida da Liberdade 110', zip='1250-146', lat='38.7223', lon='-9.1393',
                   phone='+351 21 555 0100', email='lisbon.hq', slug='lisbon-hq', tz='Europe/Lisbon', cur='EUR',
                   dist='km', vol='L', wt='kg'),
    'BR-ATL': dict(id='BR-LON', name='London Hub', city='London', country='GB', region='',
                   county='Greater London', street='12 Wharf Road', zip='N1 7GS', lat='51.5317', lon='-0.0950',
                   phone='+44 20 7946 0100', email='london.hub', slug='london-hub', tz='Europe/London', cur='GBP',
                   dist='mi', vol='L', wt='kg'),
    'BR-DEN': dict(id='BR-TLV', name='Tel Aviv Satellite', city='Tel Aviv-Yafo', country='IL',
                   region='', county='Tel Aviv District', street='14 Rothschild Boulevard', zip='6688114',
                   lat='32.0636', lon='34.7722', phone='+972 3 555 0100', email='telaviv.satellite',
                   slug='tel-aviv-satellite', tz='Asia/Jerusalem', cur='ILS', dist='km', vol='L', wt='kg'),
    'BR-PHX': dict(id='BR-CHI', name='Chicago Service Center', city='Chicago', country='US', region='IL',
                   county='Cook County', street='2400 S Halsted St', zip='60608', lat='41.8486', lon='-87.6466',
                   phone='(312) 555-0100', email='chicago.service', slug='chicago-service-center',
                   tz='America/Chicago', cur='USD', dist='mi', vol='gal_US', wt='lb'),
}
NEW_BRANCHES = {b['id']: b for b in BRANCHES.values()}
OLD_TO_NEW_ID = {old: b['id'] for old, b in BRANCHES.items()}

# schedule name -> (new name, time zone)
SCHEDULES = {
    'Standard Business Hours (Eastern)': ('Standard Business Hours (London)', 'Europe/London'),
    'Extended Mountain Field Support': ('Extended Field Support (Tel Aviv)', 'Asia/Jerusalem'),
    '24/7 Continuous Operations': ('24/7 Continuous Operations', 'Europe/Lisbon'),
    'Southwest Express Logistics Hours': ('Express Logistics Hours (Chicago)', 'America/Chicago'),
}
SCHEDULE_RENAME = {old: new for old, (new, _) in SCHEDULES.items() if old != new}
SCHEDULE_TZ = {new: tz for new, tz in SCHEDULES.values()}

FUEL = {  # local price per litre and station brand
    'PT': (1.79, 'Galp'), 'GB': (1.46, 'Shell'), 'IL': (7.35, 'Paz'),
}
CROSS_BORDER_ASSET = None  # chosen below: the first London van


def read(name):
    path = os.path.join(DIR, name + '.csv')
    with open(path, encoding='utf-8-sig', newline='') as f:
        r = csv.DictReader(f)
        return r.fieldnames, list(r)


def write(name, fields, rows):
    path = os.path.join(DIR, name + '.csv')
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, quoting=csv.QUOTE_ALL)
        w.writeheader()
        w.writerows(rows)


def ensure(fields, *cols):
    for c in cols:
        if c not in fields:
            fields.append(c)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def fmt(v, decimals=0):
    if v is None:
        return ''
    return str(int(round(v))) if decimals == 0 else f'{v:.{decimals}f}'


def remap_branch_refs(fields, rows):
    for r in rows:
        for c in fields:
            if c.endswith('__r.' + NS + 'Branch_ID__c') and r[c] in OLD_TO_NEW_ID:
                r[c] = OLD_TO_NEW_ID[r[c]]


def remap_schedule_refs(fields, rows):
    for r in rows:
        for c in fields:
            if (c.endswith('Schedule__r.Name')) and r[c] in SCHEDULE_RENAME:
                r[c] = SCHEDULE_RENAME[r[c]]


def plate(country, i, old):
    letters = 'ABCDEFGHJKLMNPRSTUVWXYZ'
    a, b, c, d = (letters[(i * k + 3) % len(letters)] for k in (1, 3, 5, 7))
    n = (i * 37 + 11) % 100
    if country == 'PT':
        return f'{a}{b}-{n:02d}-{c}{d}'
    if country == 'GB':
        return f'{a}{b}{(i * 7) % 90 + 10:02d} {c}{d}{letters[i % len(letters)]}'
    if country == 'IL':
        return f'{(i * 53 + 101) % 900 + 100}-{n:02d}-{(i * 17 + 7) % 900 + 100}'
    return f'IL-{(i * 71 + 200) % 900 + 100}{c}{d}'


def category(regime_us, body):
    if regime_us:
        return {'Pickup': 'US_Class_2', 'Van': 'US_Class_2', 'Truck': 'US_Class_5'}.get(body, 'US_Class_1')
    return {'Pickup': 'EU_N1', 'Van': 'EU_N1', 'Truck': 'EU_N2'}.get(body, 'EU_M1')


def main():
    _, branch_rows = read(NS + 'Fleet_Branch__c')
    if not any(r[NS + 'Branch_ID__c'] in BRANCHES for r in branch_rows):
        print('Already converted: no US branch IDs left, nothing changed.')
        return

    # ---- schedules
    f, rows = read(NS + 'Fleet_Schedule__c')
    for r in rows:
        r['Name'] = SCHEDULE_RENAME.get(r['Name'], r['Name'])
        r[NS + 'Time_Zone__c'] = SCHEDULE_TZ.get(r['Name'], r[NS + 'Time_Zone__c'])
    write(NS + 'Fleet_Schedule__c', f, rows)
    for name in (NS + 'Schedule_Window__c', NS + 'Schedule_Exception__c', NS + 'Schedule_Assignment__c'):
        f, rows = read(name)
        remap_schedule_refs(f, rows)
        remap_branch_refs(f, rows)
        write(name, f, rows)

    # ---- branches
    f, rows = read(NS + 'Fleet_Branch__c')
    ensure(f, NS + 'Currency_Code__c', NS + 'Distance_Unit__c', NS + 'Volume_Unit__c', NS + 'Weight_Unit__c')
    branch_by_sfid = {}
    for r in rows:
        b = BRANCHES.get(r[NS + 'Branch_ID__c']) or NEW_BRANCHES.get(r[NS + 'Branch_ID__c'])
        if not b:
            continue
        r.update({
            'Name': b['name'], NS + 'Branch_ID__c': b['id'], NS + 'City__c': b['city'],
            NS + 'Country__c': b['country'], NS + 'US_State__c': b['region'], NS + 'County_Province__c': b['county'],
            NS + 'Street__c': b['street'], NS + 'Zip_Code__c': b['zip'], NS + 'Location__Latitude__s': b['lat'],
            NS + 'Location__Longitude__s': b['lon'], NS + 'Phone__c': b['phone'],
            NS + 'Email__c': b['email'] + '@fleetforce-demo.com',
            NS + 'Website__c': 'https://www.fleetforce-demo.com/locations/' + b['slug'],
            NS + 'Time_Zone__c': b['tz'], NS + 'Currency_Code__c': b['cur'], NS + 'Distance_Unit__c': b['dist'],
            NS + 'Volume_Unit__c': b['vol'], NS + 'Weight_Unit__c': b['wt'],
        })
        remap_schedule_refs(f, [r])
        branch_by_sfid[r['Id']] = b
    write(NS + 'Fleet_Branch__c', f, rows)

    # ---- vehicles
    f, rows = read(NS + 'Fleet_Asset__c')
    ensure(f, NS + 'Country__c', NS + 'Regulatory_Category__c')
    remap_branch_refs(f, rows)
    km_assets, asset_country, asset_branch = set(), {}, {}
    cross_border = None
    for i, r in enumerate(sorted(rows, key=lambda x: x[NS + 'Asset_ID__c'])):
        b = branch_by_sfid.get(r[NS + 'Branch__c'])
        if not b:
            continue
        aid = r[NS + 'Asset_ID__c']
        asset_branch[aid] = b
        reg = b['country']
        if cross_border is None and b['country'] == 'GB' and r[NS + 'Body_Type__c'] == 'Van':
            cross_border = aid
            reg = 'PT'
            r[NS + 'Country__c'] = 'PT'
        elif r.get(NS + 'Country__c') not in ('PT',):
            r[NS + 'Country__c'] = ''
        asset_country[aid] = reg
        r[NS + 'License_Plate__c'] = plate(reg, i + 1, r[NS + 'License_Plate__c'])
        r[NS + 'Registered_State__c'] = 'IL' if reg == 'US' else ''
        r[NS + 'Regulatory_Category__c'] = category(reg == 'US', r[NS + 'Body_Type__c'])
        if b['dist'] == 'km':
            km_assets.add(aid)
            r[NS + 'Odometer__c'] = fmt(num(r[NS + 'Odometer__c']) and num(r[NS + 'Odometer__c']) * KM_PER_MILE)
            if num(r.get(NS + 'Max_Range__c')):
                r[NS + 'Max_Range__c'] = fmt(num(r[NS + 'Max_Range__c']) * KM_PER_MILE)
    write(NS + 'Fleet_Asset__c', f, rows)
    sfid_to_aid = {r['Id']: r[NS + 'Asset_ID__c'] for r in rows}

    def aid_of(r):
        return r.get(NS + 'Fleet_Asset__r.' + NS + 'Asset_ID__c') or sfid_to_aid.get(r.get(NS + 'Fleet_Asset__c')) \
            or r.get(NS + 'Asset_ID__c')

    # ---- distances on related records
    for name, cols in ((NS + 'Service_Ticket__c', ['Odometer__c']),
                       (NS + 'Telemetry_Raw__c', ['Odometer__c', 'Speed__c']),
                       (NS + 'Allocation__c', ['Odometer_Start__c', 'Odometer_End__c', 'Distance_Driven__c'])):
        f, rows = read(name)
        remap_branch_refs(f, rows)
        for r in rows:
            if aid_of(r) in km_assets:
                for c in cols:
                    v = num(r.get(NS + c))
                    if v is not None:
                        r[NS + c] = fmt(v * KM_PER_MILE, 1 if c == 'Speed__c' else 0)
        write(name, f, rows)

    # ---- fuel
    f, rows = read(NS + 'Fuel_Log__c')
    for n, r in enumerate(rows):
        aid = aid_of(r)
        b = asset_branch.get(aid)
        if not b:
            continue
        if aid in km_assets:
            for c in ('Odometer__c', 'Trip_Distance__c'):
                v = num(r.get(NS + c))
                if v is not None:
                    r[NS + c] = fmt(v * KM_PER_MILE)
        if b['country'] in FUEL and r[NS + 'UOM__c'] == 'Gallons (US)':
            price, brand = FUEL[b['country']]
            r[NS + 'UOM__c'] = 'Liters'
            r[NS + 'Volume__c'] = fmt(num(r[NS + 'Volume__c']) * L_PER_GAL, 1)
            r[NS + 'Unit_Cost__c'] = fmt(price, 2)
            r[NS + 'Vendor_Name__c'] = f'{brand} {b["city"]} #{100 + n}'
        dist, vol = num(r.get(NS + 'Trip_Distance__c')), num(r.get(NS + 'Volume__c'))
        if dist and vol:
            r[NS + 'Fuel_Economy__c'] = fmt(dist / vol, 1)
    write(NS + 'Fuel_Log__c', f, rows)

    # ---- status picklists
    for name, mapping in ((NS + 'Insurance_Policy__c', {'1': 'Active', '0': 'Expired'}),
                          (NS + 'Driver_Qualification__c', {'1': 'Valid', '0': 'Expired'})):
        f, rows = read(name)
        for r in rows:
            r[NS + 'Status__c'] = mapping.get(r[NS + 'Status__c'], r[NS + 'Status__c'])
        write(name, f, rows)

    # ---- everything else that points at a branch
    for name in ('Contact', NS + 'Branch_Assignment__c', NS + 'Reservation__c'):
        f, rows = read(name)
        remap_branch_refs(f, rows)
        write(name, f, rows)

    print(f'Branches: {", ".join(b["name"] for b in BRANCHES.values())}')
    print(f'Vehicles converted to km: {len(km_assets)}; cross-border vehicle: {cross_border} (registered PT, at London)')


if __name__ == '__main__':
    main()
