import json
import os
import requests
import urllib.request
import urllib.parse
from datetime import datetime
import time
from pathlib import Path

# --- CONFIGURATION ---
API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"
SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'

# --- HOLLIHOP FETCHING ---
def fetch_hh(endpoint, params=None):
    if params is None:
        params = {}
    params['authkey'] = AUTH_KEY
    query_string = urllib.parse.urlencode(params)
    url = f"{API_URL}{endpoint}?{query_string}"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        print(f"Error fetching {endpoint}: {e}")
        return None

def fetch_paginated(endpoint, key_name, take=200):
    all_data = []
    skip = 0
    print(f"Fetching {endpoint}...")
    while True:
        res = fetch_hh(endpoint, {"skip": skip, "take": take})
        if not res or key_name not in res: break
        chunk = res[key_name]
        all_data.extend(chunk)
        print(f"  Fetched {len(chunk)} (Total: {len(all_data)})")
        if len(chunk) < take: break
        skip += take
        time.sleep(0.1)
    return all_data

# --- SUPABASE REST HELPER ---
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
        res = requests.post(url, headers=headers, params=params, json=batch)
        if res.status_code not in (200, 201):
            print(f"Error in {table}: {res.text}")
        else:
            print(f"Upserted {len(batch)} to {table}")

def get_sb_map(table, key_col="hollihop_id", val_col="id"):
    url = f"{SUPABASE_URL}/rest/v1/{table}?select={key_col},{val_col}"
    headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
    res = requests.get(url, headers=headers)
    if res.status_code == 200:
        return {item[key_col]: item[val_col] for item in res.json() if item[key_col] is not None}
    return {}

# --- MAIN MIGRATION ---
def main():
    print("--- Starting Full Migration ---")
    
    # 1. Offices (Branches)
    offices = fetch_hh("GetOffices").get("Offices", [])
    branches_payload = [{"hollihop_id": o["Id"], "name": o["Name"], "address": o.get("Address", "")} for o in offices]
    upsert_sb("branches", branches_payload)
    branches_map = get_sb_map("branches")

    # 2. Teachers
    teachers = fetch_hh("GetTeachers").get("Teachers", [])
    teachers_payload = [{
        "hollihop_id": t["Id"], "first_name": t.get("FirstName", ""), "last_name": t.get("LastName", ""),
        "phone": t.get("Mobile", ""), "email": t.get("EMail", ""), "fired": t.get("Fired", False)
    } for t in teachers]
    upsert_sb("teachers", teachers_payload)
    teachers_map = get_sb_map("teachers")

    # 3. Students
    students = fetch_paginated("GetStudents", "Students")
    students_payload = []
    for s in students:
        students_payload.append({
            "hollihop_id": s["Id"], "first_name": s.get("FirstName", ""), "last_name": s.get("LastName", ""),
            "middle_name": s.get("MiddleName", ""), "phone": s.get("Mobile", s.get("Phone", "")),
            "email": s.get("EMail", ""), "gender": "male" if s.get("Gender") else "female" if s.get("Gender") is not None else None,
            "created_at": s.get("Created"),
            "custom_data": {
                "level": s.get("Level"),
                "maturity": s.get("Maturity"),
                "birthday": s.get("Birthday"),
                "address": s.get("Address")
            }
        })
    upsert_sb("students", students_payload)
    students_map = get_sb_map("students")

    # 4. Leads
    leads = fetch_paginated("GetLeads", "Leads")
    status_map = {s["Id"]: s["Name"] for s in fetch_hh("GetLeadStatuses").get("Statuses", [])}
    leads_payload = []
    for l in leads:
        branch_id = None
        offices_l = l.get("OfficesAndCompanies", [])
        if offices_l: branch_id = branches_map.get(offices_l[0]["Id"])
        
        leads_payload.append({
            "hollihop_id": l["Id"], 
            "name": l.get("FirstName", ""), 
            "last_name": l.get("LastName", ""),
            "middle_name": l.get("MiddleName", ""),
            "phone": l.get("Mobile", ""), 
            "email": l.get("EMail", ""),
            "status": status_map.get(l.get("StatusId"), "new"),
            "branch_id": branch_id,
            "created_at": l.get("Created"),
            "custom_data": {
                "level": l.get("Level"),
                "discipline": l.get("Discipline"),
                "source": l.get("Source"),
                "category": l.get("Category")
            }
        })
    upsert_sb("leads", leads_payload)

    # 5. EdUnits (Groups)
    edunits = fetch_hh("GetEdUnits").get("EdUnits", [])
    groups_payload = []
    for e in edunits:
        branch_id = branches_map.get(e.get("OfficeOrCompanyId"))
        teacher_id = None
        assignee = e.get("Assignee")
        if assignee: teacher_id = teachers_map.get(assignee["Id"])
        
        groups_payload.append({
            "hollihop_id": e["Id"], "name": e.get("Name", "Unnamed"),
            "branch_id": branch_id, "teacher_id": teacher_id,
            "custom_data": {"discipline": e.get("Discipline"), "level": e.get("Level"), "type": e.get("Type")}
        })
    upsert_sb("groups", groups_payload)

    # 6. Payments
    all_payments = []
    skip = 0
    print("Fetching Payments...")
    while True:
        res = fetch_hh("GetPayments", {"skip": skip, "take": 500})
        if not res or "Payments" not in res: break
        chunk = res["Payments"]
        all_payments.extend(chunk)
        print(f"  Fetched {len(chunk)} (Total: {len(all_payments)})")
        if len(chunk) < 500: break
        skip += 500
        time.sleep(0.1)

    # Fetch ClientId -> StudentId map from HolliHop student list to resolve ClientId
    # Actually, GetStudents returned 'ClientId' in the inspect script.
    client_to_student_map = {s["ClientId"]: students_map.get(s["Id"]) for s in students if "ClientId" in s}
    
    payments_payload = []
    for p in all_payments:
        student_uuid = client_to_student_map.get(p.get("ClientId"))
        branch_uuid = branches_map.get(p.get("OfficeOrCompanyId"))
        
        payments_payload.append({
            "hollihop_id": p["Id"],
            "student_id": student_uuid, # Linked to our students table
            "amount": p.get("ValueQuantity", 0),
            "description": f"{p.get('Type')} - {p.get('State')}",
            "payment_date": p.get("PaidDate") or p.get("Date"),
            "branch_id": branch_uuid,
            "type": "subscription" if p.get("Type") == "Учеба" else "other"
        })
    upsert_sb("payments", payments_payload)

    print("--- Migration Finished Successfully ---")

if __name__ == "__main__":
    main()
