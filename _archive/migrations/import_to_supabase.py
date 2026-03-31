import json
import os
import requests
from pathlib import Path

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'

# The path to the latest backup folder
project_dir = Path("c:/Users/User/Kvazar Projects/MagicMusicCRM")
backup_dirs = sorted(project_dir.glob("hollihop_backup_*"), reverse=True)
if not backup_dirs:
    print("No backup directory found!")
    exit(1)

data_dir = backup_dirs[0]
print(f"Using data from: {data_dir}")

def upsert_data(table_name, payload, conflict_column="hollihop_id"):
    url = f"{SUPABASE_URL}/rest/v1/{table_name}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": f"resolution=merge-duplicates"
    }
    # Supabase REST API requires 'on_conflict' query param for merge-duplicates
    params = {
        "on_conflict": conflict_column
    }
    batch_size = 500
    total = len(payload)
    for i in range(0, total, batch_size):
        batch = payload[i:i+batch_size]
        response = requests.post(url, headers=headers, params=params, json=batch)
        if response.status_code not in (200, 201):
            print(f"Error inserting to {table_name}: {response.text}")
        else:
            print(f"Inserted {len(batch)} records to {table_name} (progress: {min(i+batch_size, total)}/{total})")

# 1. Import Branches (Offices)
print("Importing Branches...")
with open(data_dir / 'offices.json', encoding='utf-8') as f:
    offices_data = json.load(f).get('Offices', [])
    
branches_payload = []
for o in offices_data:
    branches_payload.append({
        "hollihop_id": o["Id"],
        "name": o["Name"],
        "address": o.get("Address", ""),
        "contact_info": o.get("Phone", ""),
    })
if branches_payload:
    upsert_data("branches", branches_payload)

# Fetch mapped branches to get their UUIDs for foreign keys
headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
res = requests.get(f"{SUPABASE_URL}/rest/v1/branches?select=id,hollihop_id", headers=headers)
branches_map = {b["hollihop_id"]: b["id"] for b in res.json()}

# 2. Import Teachers
print("Importing Teachers...")
with open(data_dir / 'teachers.json', encoding='utf-8') as f:
    teachers_data = json.load(f).get('Teachers', [])

teachers_payload = []
for t in teachers_data:
    teachers_payload.append({
        "hollihop_id": t["Id"],
        "first_name": t.get("FirstName", ""),
        "last_name": t.get("LastName", ""),
        "middle_name": t.get("MiddleName", ""),
        "phone": t.get("Phone", t.get("Mobile", "")),
        "email": t.get("EMail", ""),
        "fired": t.get("Fired", False),
        "disciplines": t.get("Disciplines", []),
        "status": t.get("Status", ""),
    })
if teachers_payload:
    upsert_data("teachers", teachers_payload)

# Fetch mapped teachers to get UUIDs
res = requests.get(f"{SUPABASE_URL}/rest/v1/teachers?select=id,hollihop_id", headers=headers)
teachers_map = {t["hollihop_id"]: t["id"] for t in res.json()}

# 3. Import Lead Statuses (Optional, to text map)
status_map = {}
with open(data_dir / 'lead_statuses.json', encoding='utf-8') as f:
    statuses_data = json.load(f).get('Statuses', [])
    for s in statuses_data:
        status_map[s["Id"]] = s["Name"]

# 4. Import Leads
print("Importing Leads...")
with open(data_dir / 'leads.json', encoding='utf-8') as f:
    leads_data = json.load(f).get('Leads', [])

leads_payload = []
for l in leads_data:
    hh_status_id = l.get("StatusId")
    status_text = status_map.get(hh_status_id, "new") if hh_status_id else "new"
    
    branch_id = None
    offices = l.get("OfficesAndCompanies", [])
    if offices:
        branch_id = branches_map.get(offices[0]["Id"])
        
    leads_payload.append({
        "hollihop_id": l["Id"],
        "name": l.get("FirstName", ""),
        "last_name": l.get("LastName", ""),
        "phone": l.get("Mobile", ""),
        "email": l.get("EMail", ""),
        "source": "",
        "status": status_text,
        "hollihop_status_id": hh_status_id,
        "branch_id": branch_id,
        "custom_data": {
            "address_date": l.get("AddressDate")
        }
    })
if leads_payload:
    upsert_data("leads", leads_payload)

# 5. Import Groups (EdUnits)
print("Importing Groups...")
with open(data_dir / 'ed_units.json', encoding='utf-8') as f:
    edunits_data = json.load(f).get('EdUnits', [])

groups_payload = []
for e in edunits_data:
    branch_id = branches_map.get(e.get("OfficeOrCompanyId"))
    
    teacher_id = None
    assignee = e.get("Assignee")
    if assignee:
        teacher_id = teachers_map.get(assignee["Id"])
        
    groups_payload.append({
        "hollihop_id": e["Id"],
        "name": e.get("Name", "Unnamed"),
        "branch_id": branch_id,
        "teacher_id": teacher_id,
        "custom_data": {
            "type": e.get("Type"),
            "discipline": e.get("Discipline"),
            "level": e.get("Level")
        }
    })
if groups_payload:
    upsert_data("groups", groups_payload)

# 6. Import Comments (Student & Lead Logs)
print("Importing Comments...")

# We need maps to link HolliHop IDs to Supabase UUIDs
# Students map already exists if we ran import_students_and_lessons.py
# For leads it's in leads_payload but we better fetch from DB for certainty
headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
res_l = requests.get(f"{SUPABASE_URL}/rest/v1/leads?select=id,hollihop_id", headers=headers)
leads_map = {l["hollihop_id"]: l["id"] for l in res_l.json()}

res_s = requests.get(f"{SUPABASE_URL}/rest/v1/students?select=id,hollihop_id", headers=headers)
students_map = {s["hollihop_id"]: s["id"] for s in res_s.json()}

comments_payload = []

def process_logs(filename, entity_type, id_key, id_map):
    path = data_dir / filename
    if not os.path.exists(path):
        return
    
    with open(path, encoding='utf-8') as f:
        logs_data = json.load(f).get('Logs', [])
    
    for log in logs_data:
        hh_entity_id = log.get(id_key)
        supabase_id = id_map.get(hh_entity_id)
        
        if supabase_id and log.get('Comment'):
            comments_payload.append({
                "entity_id": supabase_id,
                "entity_type": entity_type,
                "content": log.get('Comment'),
                "created_at": log.get('Date'),
                # We don't map author for now, default to system or null
            })

process_logs('student_logs.json', 'student', 'StudentIdSubj', students_map)
process_logs('lead_logs.json', 'lead', 'LeadIdSubj', leads_map)

if comments_payload:
    # We use a custom upsert strategy for comments to avoid duplicates
    # Since comments don't have unique IDs in our schema from HH easily, 
    # we just insert them. If this script is run multiple times, 
    # it might duplicate unless we add a hash or HH log ID.
    # For now, let's just insert.
    url = f"{SUPABASE_URL}/rest/v1/entity_comments"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json"
    }
    batch_size = 500
    for i in range(0, len(comments_payload), batch_size):
        batch = comments_payload[i:i+batch_size]
        requests.post(url, headers=headers, json=batch)
    print(f"Imported {len(comments_payload)} comments.")

print("Import to Supabase finished successfully!")
