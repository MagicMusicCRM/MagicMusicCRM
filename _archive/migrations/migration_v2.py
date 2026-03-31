import json
import requests
import urllib.request
import urllib.parse
from datetime import datetime, timedelta
import time
import socket

# --- CONFIGURATION ---
API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"
SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'

# Set global timeout for urllib
socket.setdefaulttimeout(30)

# --- HELPERS ---
def fetch_hh(endpoint, params=None):
    if params is None: params = {}
    params['authkey'] = AUTH_KEY
    query_string = urllib.parse.urlencode(params)
    url = f"{API_URL}{endpoint}?{query_string}"
    print(f"  [HH] Fetching {endpoint}...", flush=True)
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            print(f"  [HH] Fetched {endpoint} success", flush=True)
            return data
    except Exception as e:
        print(f"  [HH] Error fetching {endpoint}: {e}", flush=True)
        return None

def upsert_sb(table, data, conflict="hollihop_id"):
    if not data: return
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates"
    }
    params = {"on_conflict": conflict}
    batch_size = 500
    for i in range(0, len(data), batch_size):
        batch = data[i:i+batch_size]
        print(f"  [SB] Upserting {len(batch)} to {table}...", flush=True)
        res = requests.post(url, headers=headers, params=params, json=batch, timeout=30)
        if res.status_code not in (200, 201):
            print(f"  [SB] Error in {table}: {res.status_code} - {res.text}", flush=True)
        else:
            print(f"  [SB] Upserted {len(batch)} to {table}", flush=True)

def get_sb_map(table, key_col="hollihop_id", val_col="id"):
    print(f"  [SB] Loading map for {table}...", flush=True)
    all_data = {}
    limit = 1000
    offset = 0
    headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
    
    while True:
        url = f"{SUPABASE_URL}/rest/v1/{table}?select={key_col},{val_col}&limit={limit}&offset={offset}"
        try:
            res = requests.get(url, headers=headers, timeout=30)
            if res.status_code == 200:
                chunk = res.json()
                if not chunk: break
                for item in chunk:
                    if item[key_col] is not None:
                        all_data[item[key_col]] = item[val_col]
                print(f"    Loaded {len(all_data)} items...", flush=True)
                if len(chunk) < limit: break
                offset += limit
            else:
                print(f"    Error: {res.status_code} - {res.text}", flush=True)
                break
        except Exception as e:
            print(f"    Exception: {e}", flush=True)
            break
            
    print(f"  [SB] Total {len(all_data)} items for {table}", flush=True)
    return all_data

def main():
    print("--- Starting Migration V2 (Lessons & Memberships) ---", flush=True)
    
    # 1. Maps for resolution
    students_map = get_sb_map("students")
    teachers_map = get_sb_map("teachers")
    branches_map = get_sb_map("branches")
    groups_map = get_sb_map("groups")
    
    # We also need ClientId to UUID map for students because memberships use ClientId
    print("Fetching ClientIds from HH...", flush=True)
    all_students = []
    skip = 0
    while True:
        res = fetch_hh("GetStudents", {"skip": skip, "take": 500})
        if not res or "Students" not in res: break
        chunk = res["Students"]
        all_students.extend(chunk)
        print(f"    Fetched {len(chunk)} students (Total: {len(all_students)})", flush=True)
        if len(chunk) < 500: break
        skip += 500
    client_id_to_uuid = {s["ClientId"]: students_map.get(s["Id"]) for s in all_students if "ClientId" in s}
    print(f"Mapped {len(client_id_to_uuid)} clients to students.", flush=True)

    # 2. Group Memberships
    print("Fetching Group Memberships...", flush=True)
    memberships_res = fetch_hh("GetEdUnitStudents", {"take": 10000})
    memberships = (memberships_res or {}).get("EdUnitStudents", [])
    print(f"Found {len(memberships)} memberships in HH.", flush=True)
    memberships_payload = []
    for m in memberships:
        gid = groups_map.get(m.get("EdUnitId"))
        sid = client_id_to_uuid.get(m.get("ClientId"))
        if gid and sid:
            memberships_payload.append({"group_id": gid, "student_id": sid})
    
    if memberships_payload:
        print(f"Upserting {len(memberships_payload)} memberships...", flush=True)
        url = f"{SUPABASE_URL}/rest/v1/group_students"
        headers = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates"
        }
        try:
            res = requests.post(url, headers=headers, json=memberships_payload, timeout=30)
            print(f"  Upserted memberships: {res.status_code}", flush=True)
        except Exception as e:
            print(f"  Error upserting memberships: {e}", flush=True)

    # 3. Lessons (Schedule) - Month-by-month chunking
    print("Fetching Lessons (Schedule) in chunks...", flush=True)
    start_date = datetime(2023, 1, 1)
    end_date = datetime(2025, 12, 31)
    
    current_start = start_date
    total_lessons = 0
    
    while current_start < end_date:
        next_month = (current_start.replace(day=28) + timedelta(days=4)).replace(day=1)
        chunk_end = next_month - timedelta(days=1)
        if chunk_end > end_date: chunk_end = end_date
        
        ds = current_start.strftime("%Y-%m-%d")
        de = chunk_end.strftime("%Y-%m-%d")
        
        print(f"  Processing chunk {ds} to {de}...", flush=True)
        schedule_res = fetch_hh("GetSchedule", {"dateFrom": ds, "dateTo": de, "take": 5000})
        schedule = (schedule_res or {}).get("Schedule", [])
        print(f"    Found {len(schedule)} items", flush=True)
        
        lessons_payload = []
        for s in schedule:
            group_uuid = groups_map.get(s.get("EdUnitId"))
            teacher_uuid = teachers_map.get(s.get("TeacherId"))
            branch_uuid = branches_map.get(s.get("OfficeOrCompanyId"))
            
            hh_status = s.get("Status")
            status = "planned"
            if hh_status == "Пройдено": status = "completed"
            elif hh_status == "Отменено": status = "cancelled"
            
            lessons_payload.append({
                "hollihop_id": s["Id"],
                "group_id": group_uuid,
                "teacher_id": teacher_uuid,
                "branch_id": branch_uuid,
                "scheduled_at": s.get("ScheduledAt"),
                "status": status,
                "duration_minutes": 60 
            })
        
        if lessons_payload:
            upsert_sb("lessons", lessons_payload)
            total_lessons += len(lessons_payload)
            
        current_start = next_month
        time.sleep(0.1)

    print(f"--- Migration V2 Finished. Total Lessons: {total_lessons} ---", flush=True)

if __name__ == "__main__":
    main()
