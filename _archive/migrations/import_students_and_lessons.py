import json
import os
import requests
import uuid
from pathlib import Path
from datetime import datetime, timedelta

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'
HEADERS = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}", "Content-Type": "application/json"}

project_dir = Path("c:/Users/User/Kvazar Projects/MagicMusicCRM")
backup_dirs = sorted(project_dir.glob("hollihop_backup_*"), reverse=True)
if not backup_dirs:
    print("No backup directory found!")
    exit(1)

data_dir = backup_dirs[0]
print(f"Using data from: {data_dir}")

def fetch_map(endpoint, key_col, val_col=None):
    res = requests.get(f"{SUPABASE_URL}/rest/v1/{endpoint}", headers=HEADERS)
    if res.status_code != 200:
        print(f"Error fetching {endpoint}: {res.text}")
        return {}
    data = res.json()
    if val_col is None:
        return {item[key_col]: item for item in data}
    return {item[key_col]: item[val_col] for item in data if key_col in item}

import time

def upsert_data(table_name, payload, conflict_column="id"):
    url = f"{SUPABASE_URL}/rest/v1/{table_name}"
    params = {"on_conflict": conflict_column}
    upsert_headers = {**HEADERS, "Prefer": "resolution=merge-duplicates"}
    batch_size = 100
    for i in range(0, len(payload), batch_size):
        batch = payload[i:i+batch_size]
        success = False
        for attempt in range(3):
            try:
                response = requests.post(url, headers=upsert_headers, params=params, json=batch)
                if response.status_code not in (200, 201):
                    print(f"Error inserting to {table_name}: {response.text}")
                else:
                    print(f"Inserted {len(batch)} records to {table_name}")
                success = True
                break
            except requests.exceptions.ConnectionError as e:
                print(f"Attempt {attempt+1} failed with ConnectionError. Retrying...")
                time.sleep(2)
        if not success:
            print(f"Failed to insert batch to {table_name} after 3 attempts.")

print("Fetching existing mappings...")
branches_map = fetch_map("branches?select=id,hollihop_id", "hollihop_id", "id")
teachers_map = fetch_map("teachers?select=id,hollihop_id", "hollihop_id", "id")
groups_map = fetch_map("groups?select=id,hollihop_id", "hollihop_id", "id")
existing_students = fetch_map("students?select=id,profile_id,hollihop_id", "hollihop_id")

# 1. Import Students
print("Importing Students...")
with open(data_dir / 'students.json', encoding='utf-8') as f:
    students_data = json.load(f).get('Students', [])

profiles_payload = []
students_payload = []

for s in students_data:
    hh_id = s["Id"]
    if hh_id in existing_students:
        prof_id = existing_students[hh_id]["profile_id"]
        stud_id = existing_students[hh_id]["id"]
    else:
        prof_id = str(uuid.uuid4())
        stud_id = str(uuid.uuid4())
        existing_students[hh_id] = {"id": stud_id, "profile_id": prof_id}
        
    profiles_payload.append({
        "id": prof_id,
        "role": "client",
        "first_name": s.get("FirstName", ""),
        "last_name": s.get("LastName", ""),
        "phone": s.get("Mobile", s.get("Phone", ""))
    })
    
    students_payload.append({
        "id": stud_id,
        "profile_id": prof_id,
        "hollihop_id": hh_id,
        "custom_data": {}
    })

if profiles_payload:
    upsert_data("profiles", profiles_payload)
if students_payload:
    upsert_data("students", students_payload, conflict_column="hollihop_id")

# 2. Extract and import Rooms from EdUnits ScheduleItems
print("Importing Rooms and Lessons...")
with open(data_dir / 'ed_units.json', encoding='utf-8') as f:
    edunits_data = json.load(f).get('EdUnits', [])

existing_rooms = fetch_map("rooms?select=name,id,branch_id", "name", "id")
rooms_payload = []
lessons_payload = []

for e in edunits_data:
    group_id = groups_map.get(e["Id"])
    if not group_id:
        continue
    branch_id = branches_map.get(e.get("OfficeOrCompanyId"))
    teacher_id = None
    assignee = e.get("Assignee")
    if assignee:
        teacher_id = teachers_map.get(assignee["Id"])
        
    schedule_items = e.get("ScheduleItems", [])
    for item in schedule_items:
        classroom_name = item.get("ClassroomName")
        room_id = None
        if classroom_name:
            if classroom_name not in existing_rooms:
                room_id = str(uuid.uuid4())
                existing_rooms[classroom_name] = room_id
                rooms_payload.append({
                    "id": room_id,
                    "name": classroom_name,
                    "branch_id": branch_id,
                    "capacity": 20
                })
            else:
                room_id = existing_rooms[classroom_name]

        try:
            b_date_str = item.get("BeginDate")
            e_date_str = item.get("EndDate")
            b_time = item.get("BeginTime")
            e_time = item.get("EndTime")
            weekdays_mask = item.get("Weekdays", 0)
            
            if not b_date_str or not e_date_str or not b_time or not e_time:
                continue
                
            b_date = datetime.strptime(b_date_str, "%Y-%m-%d").date()
            e_date = datetime.strptime(e_date_str, "%Y-%m-%d").date()
            
            # Helper to check if a python weekday (0=Mon, 6=Sun) matches HolliHop bitmask
            def matches_weekday(dt_date, mask):
                if mask == 0: return True # If no mask, assume it occurs on the dates given or maybe just once?
                hh_day = 1 << dt_date.weekday()
                return (mask & hh_day) != 0

            current_date = b_date
            while current_date <= e_date:
                if matches_weekday(current_date, weekdays_mask) or (weekdays_mask == 0 and current_date == b_date):
                    b_dt = datetime.strptime(f"{current_date} {b_time}", "%Y-%m-%d %H:%M")
                    e_dt_full = datetime.strptime(f"{current_date} {e_time}", "%Y-%m-%d %H:%M")
                    duration = int((e_dt_full - b_dt).total_seconds() / 60)
                    
                    scheduled_at = b_dt.isoformat() + "Z"
                    lesson_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"lesson_{item['Id']}_{current_date}"))
                    
                    lessons_payload.append({
                        "id": lesson_id,
                        "group_id": group_id,
                        "teacher_id": teacher_id,
                        "branch_id": branch_id,
                        "room_id": room_id,
                        "status": "scheduled",
                        "duration_minutes": duration,
                        "scheduled_at": scheduled_at,
                        "custom_data": {"schedule_item_id": item["Id"], "weekdays": weekdays_mask}
                    })
                current_date += timedelta(days=1)
                
        except Exception as ex:
            print("Skipped schedule item error:", ex)

if rooms_payload:
    upsert_data("rooms", rooms_payload)
if lessons_payload:
    upsert_data("lessons", lessons_payload)

print("Import of students and lessons completed successfully!")
