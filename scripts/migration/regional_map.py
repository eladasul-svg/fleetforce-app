#!/usr/bin/env python3
"""
Turns the backup taken by migrate_regional.sh into restore files with the new values.

    python3 regional_map.py <backup-dir>

Reads  <backup-dir>/{branches,schedules,insurance,qualifications}.csv  (SOQL exports, namespaced headers)
Writes <backup-dir>/restore_{...}.csv  and prints every value it could not map (left blank, never guessed).

Mappings (from the work order):
- Branch Country: United States -> US, Canada -> CA, Mexico -> MX, United Kingdom -> GB, Other -> blank.
- Time zones: Eastern -> America/New_York, Central -> America/Chicago, Mountain -> America/Denver (America/Phoenix
  for a branch in Arizona, which has no daylight saving), Pacific -> America/Los_Angeles, Alaska -> America/Anchorage,
  Hawaii -> Pacific/Honolulu. A value that is already an IANA name is kept.
- Insurance Status (was a number): expired by date -> Expired; otherwise 0 -> Cancelled, anything else -> Active.
- Qualification Status (was a number): past Valid Until -> Expired; within 30 days -> Expiring Soon;
  otherwise 0 -> Revoked, anything else -> Valid.
"""
import csv
import datetime
import os
import sys

NS = 'fleetforce__'
COUNTRY = {'United States': 'US', 'Canada': 'CA', 'Mexico': 'MX', 'United Kingdom': 'GB', 'Other': ''}
TZ = {'Eastern': 'America/New_York', 'Central': 'America/Chicago', 'Mountain': 'America/Denver',
      'Pacific': 'America/Los_Angeles', 'Alaska': 'America/Anchorage', 'Hawaii': 'Pacific/Honolulu'}
TODAY = datetime.date.today()
unmapped = []


def rows(d, name):
    path = os.path.join(d, name + '.csv')
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def write(d, name, fields, out):
    with open(os.path.join(d, 'restore_' + name + '.csv'), 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator='\n')  # Bulk API expects LF
        w.writeheader()
        w.writerows(out)
    print(f'  restore_{name}.csv: {len(out)} rows')


def tz(value, state, what):
    if not value:
        return ''
    if '/' in value:
        return value
    if value == 'Mountain' and state == 'AZ':
        return 'America/Phoenix'
    if value in TZ:
        return TZ[value]
    unmapped.append(f'{what}: time zone "{value}"')
    return ''


def country(value, what):
    if not value:
        return ''
    if len(value) == 2 and value.isalpha():
        return value.upper()
    if value in COUNTRY:
        return COUNTRY[value]
    unmapped.append(f'{what}: country "{value}"')
    return ''


def date(v):
    try:
        return datetime.date.fromisoformat(v[:10])
    except (TypeError, ValueError):
        return None


def is_zero(v):
    try:
        return float(v) == 0
    except (TypeError, ValueError):
        return False


def main(d):
    out = []
    for r in rows(d, 'branches'):
        what = f'branch {r["Name"]}'
        out.append({'Id': r['Id'], NS + 'Country__c': country(r.get(NS + 'Country__c'), what),
                    NS + 'Time_Zone__c': tz(r.get(NS + 'Time_Zone__c'), r.get(NS + 'US_State__c'), what)})
    write(d, 'branches', ['Id', NS + 'Country__c', NS + 'Time_Zone__c'], out)

    out = []
    for r in rows(d, 'schedules'):
        out.append({'Id': r['Id'], NS + 'Time_Zone__c': tz(r.get(NS + 'Time_Zone__c'), None, f'schedule {r["Name"]}')})
    write(d, 'schedules', ['Id', NS + 'Time_Zone__c'], out)

    out = []
    for r in rows(d, 'insurance'):
        exp = date(r.get(NS + 'Expiration_Date__c'))
        s = r.get(NS + 'Status__c')
        status = 'Expired' if exp and exp < TODAY else ('Cancelled' if is_zero(s) else 'Active')
        out.append({'Id': r['Id'], NS + 'Status__c': status})
    write(d, 'insurance', ['Id', NS + 'Status__c'], out)

    out = []
    for r in rows(d, 'qualifications'):
        until = date(r.get(NS + 'Valid_Until__c'))
        s = r.get(NS + 'Status__c')
        if until and until < TODAY:
            status = 'Expired'
        elif until and (until - TODAY).days <= 30:
            status = 'Expiring Soon'
        else:
            status = 'Revoked' if is_zero(s) else 'Valid'
        out.append({'Id': r['Id'], NS + 'Status__c': status})
    write(d, 'qualifications', ['Id', NS + 'Status__c'], out)

    if unmapped:
        print('  Not mapped (left blank):')
        for u in unmapped:
            print('   -', u)


if __name__ == '__main__':
    main(sys.argv[1])
