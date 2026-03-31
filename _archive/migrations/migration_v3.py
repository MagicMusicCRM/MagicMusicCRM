import json
import requests
import time
from datetime import datetime

# --- CONFIGURATION ---
API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"
SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'

# --- HELPERS ---
def fetch_hh(endpoint, params=None):
    if params is None: params = {}
    params['authkey'] = AUTH_KEY
    try:
        url = f"{API_URL}{endpoint}"
        print(f"[HH] Calling {url}...", flush=True)
        res = requests.get(url, params=params, timeout=30)
        if res.status_code == 200:
            return res.json()
        print(f"[HH] Error {endpoint}: {res.status_code} - {res.text}", flush=True)
        return None
    except Exception as e:
        print(f"[HH] Exception {endpoint}: {e}", flush=True)
        return None

def fetch_paginated(endpoint, key_name, take=500):
    all_data = []
    skip = 0
    while True:
        print(f"[HH] Fetching {endpoint} (skip={skip}, take={take})...", flush=True)
        res = fetch_hh(endpoint, {"skip": skip, "take": take})
        if not res or key_name not in res: 
            print(f"[HH] {endpoint} returned no data for key {key_name}", flush=True)
            break
        chunk = res[key_name]
        all_data.extend(chunk)
        print(f"[HH] {endpoint}: {len(all_data)} fetched total...", flush=True)
        if len(chunk) < take: break
        skip += take
        time.sleep(0.1)
    return all_data

def upsert_sb(table, data, conflict="hollihop_id"):
    if not data: 
        print(f"[SB] No data to upsert for {table}", flush=True)
        return
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates"
    }
    batch_size = 100 # Even smaller batch
    for i in range(0, len(data), batch_size):
        batch = data[i:i+batch_size]
        print(f"[SB] Upserting batch {i//batch_size + 1} to {table}...", flush=True)
        try:
            res = requests.post(url, headers=headers, params={"on_conflict": conflict}, json=batch, timeout=60)
            if res.status_code not in (200, 201):
                print(f"[SB] Error {table}: {res.text}", flush=True)
            else:
                print(f"[SB] {table}: {len(batch)} items upserted successfully", flush=True)
        except Exception as e:
            print(f"[SB] Exception during {table} upsert: {e}", flush=True)
        time.sleep(0.1)

def get_sb_map(table, key_col="hollihop_id", val_col="id"):
    print(f"[SB] Fetching map for {table} ({key_col} -> {val_col})...", flush=True)
    all_items = []
    offset = 0
    limit = 500
    while True:
        url = f"{SUPABASE_URL}/rest/v1/{table}?select={key_col},{val_col}&offset={offset}&limit={limit}"
        headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
        print(f"[SB]   Fetching {table} chunk (offset={offset})...", flush=True)
        try:
            res = requests.get(url, headers=headers, timeout=30)
            if res.status_code != 200:
                print(f"[SB]   Error {table}: {res.status_code} - {res.text}", flush=True)
                break
            chunk = res.json()
            all_items.extend(chunk)
            print(f"[SB]   {table}: {len(all_items)} items fetched so far", flush=True)
            if len(chunk) < limit: break
            offset += limit
            time.sleep(0.05)
        except Exception as e:
            print(f"[SB]   Exception during map fetch: {e}", flush=True)
            break
    
    mapping = {item[key_col]: item[val_col] for item in all_items if item.get(key_col) is not None}
    print(f"[SB] Found {len(mapping)} items for {table} map", flush=True)
    return mapping

# --- MAIN ---
def main():
    print("--- Starting Final Migration Phase (v4) ---", flush=True)
    
    # 1. Maps
    groups_map = get_sb_map("groups")
    students_map = get_sb_map("students")
    teachers_map = get_sb_map("teachers")
    
    print("[HH] Mapping ClientId to StudentId...", flush=True)
    hh_students = fetch_paginated("GetStudents", "Students")
    client_id_map = {s["ClientId"]: students_map.get(s["Id"]) for s in hh_students if "ClientId" in s}
    print(f"[HH] Mapped {len(client_id_map)} client IDs", flush=True)

    # 2. Group Students (Memberships)
    print("\n[HH] Fetching Group Memberships...", flush=True)
    mems = fetch_paginated("GetEdUnitStudents", "EdUnitStudents")
    mems_payload = []
    print(f"[HH] Processing {len(mems)} memberships...", flush=True)
    for m in mems:
        group_id = m.get("EdUnitId")
        client_id = m.get("StudentClientId")
        group_uuid = groups_map.get(group_id)
        student_uuid = client_id_map.get(client_id)
        
        if group_uuid and student_uuid:
            mems_payload.append({
                "group_id": group_uuid,
                "student_id": student_uuid,
                "created_at": m.get("BeginDate") or datetime.now().isoformat()
            })
    
    if mems_payload:
        print(f"[SB] Sending {len(mems_payload)} group memberships to DB...", flush=True)
        # Use upsert_sb with unique constraint if any (group_id, student_id)
        # But group_students might not have hollihop_id. It has composite PK.
        # Direct REST API POST with no resolution=merge-duplicates might fail if already exists.
        # So we use standard POST and hope for the best, or use upsert with composite pk if supported.
        url = f"{SUPABASE_URL}/rest/v1/group_students"
        headers = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates"
        }
        batch_size = 100
        for i in range(0, len(mems_payload), batch_size):
            batch = mems_payload[i:i+batch_size]
            print(f"[SB] Batch {i//batch_size + 1} group_students...", flush=True)
            try:
                res = requests.post(url, headers=headers, json=batch, timeout=60)
                if res.status_code not in (200, 201):
                    print(f"[SB] Error group_students: {res.text}", flush=True)
                else:
                    print(f"[SB] group_students: {len(batch)} upserted", flush=True)
            except Exception as e:
                print(f"[SB] Exception: {e}", flush=True)
            time.sleep(0.1)
    else:
        print("[SB] No memberships found to migrate", flush=True)

    # 3. Lessons (Recurring from EdUnits)
    print("\n[HH] Fetching EdUnits for Schedule...", flush=True)
    units_data = fetch_hh("GetEdUnits")
    units = units_data.get("EdUnits", []) if units_data else []
    lessons_payload = []
    print(f"[HH] Processing {len(units)} EdUnits for schedule items...", flush=True)
    for u in units:
        group_uuid = groups_map.get(u["Id"])
        if not group_uuid: continue
        
        for s in u.get("ScheduleItems", []):
            teacher_uuid = None
            if s.get("TeacherId"):
                teacher_uuid = teachers_map.get(s["TeacherId"])
            
            lessons_payload.append({
                "group_id": group_uuid,
                "teacher_id": teacher_uuid,
                "scheduled_at": u.get("BeginDate") or s.get("BeginDate"), 
                "status": "planned",
                "hollihop_id": f"rec_{s['Id']}", 
                "custom_data": {"classroom": s.get("ClassroomName"), "weekdays": s.get("Weekdays"), "time": f"{s.get('BeginTime')}-{s.get('EndTime')}"}
            })
    
    if lessons_payload:
        print(f"[SB] Upserting {len(lessons_payload)} lessons...", flush=True)
        upsert_sb("lessons", lessons_payload, conflict="hollihop_id")

    print("\n--- Final Migration Phase Finished ---", flush=True)

if __name__ == "__main__":
    main()
