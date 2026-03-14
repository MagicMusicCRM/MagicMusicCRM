import os
import json
import urllib.request
import urllib.parse
from datetime import datetime
import time

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

# Create backup directory
backup_dir = "hollihop_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
os.makedirs(backup_dir, exist_ok=True)

def fetch_data(endpoint, params=None):
    if params is None:
        params = {}
    params['authkey'] = AUTH_KEY
    
    query_string = urllib.parse.urlencode(params)
    url = f"{API_URL}{endpoint}?{query_string}"
    
    print(f"Fetching from {endpoint}...")
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            return data
    except Exception as e:
        print(f"Error fetching {endpoint}: {e}")
        return None

def save_json(filename, data):
    path = os.path.join(backup_dir, filename)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Saved {filename}")

def main():
    print(f"Starting HolliHop CRM Export to {backup_dir}...")
    
    # 1. Export Locations
    locations = fetch_data("GetLocations")
    if locations:
        save_json("locations.json", locations)
        
    # 2. Export Offices
    offices = fetch_data("GetOffices")
    if offices:
        save_json("offices.json", offices)
        
    # 3. Export Lead Statuses
    statuses = fetch_data("GetLeadStatuses")
    if statuses:
        save_json("lead_statuses.json", statuses)
        
    # 4. Export Teachers
    # Teachers don't seem to be paginated by default if there are few, but let's just fetch all.
    teachers = fetch_data("GetTeachers")
    if teachers:
        save_json("teachers.json", teachers)
        
    # 5. Export EdUnits (Classes/Groups)
    edunits = fetch_data("GetEdUnits")
    if edunits:
        save_json("ed_units.json", edunits)
        
    # 6. Export Leads (with pagination)
    all_leads = []
    skip = 0
    take = 200
    
    print("Fetching leads (this might take a while)...")
    while True:
        leads_response = fetch_data("GetLeads", {"skip": skip, "take": take})
        if not leads_response or "Leads" not in leads_response:
            break
            
        leads_chunk = leads_response["Leads"]
        all_leads.extend(leads_chunk)
        
        print(f"  Fetched {len(leads_chunk)} leads (Total: {len(all_leads)})...")
        
        if len(leads_chunk) < take:
            break
            
        skip += take
        time.sleep(0.1) # Be nice to the API
        
    if all_leads:
        save_json("leads.json", {"Leads": all_leads})
        print(f"Successfully exported {len(all_leads)} leads.")
        
    # 7. Export Students
    all_students = []
    skip = 0
    print("Fetching students...")
    while True:
        students_response = fetch_data("GetStudents", {"skip": skip, "take": take})
        if not students_response or "Students" not in students_response:
            break
            
        chunk = students_response["Students"]
        all_students.extend(chunk)
        print(f"  Fetched {len(chunk)} students (Total: {len(all_students)})...")
        
        if len(chunk) < take:
            break
        skip += take
        time.sleep(0.1)
        
    if all_students:
        save_json("students.json", {"Students": all_students})
        print(f"Successfully exported {len(all_students)} students.")

    # 8. Export EdUnitStudents
    all_edunit_students = []
    skip = 0
    print("Fetching EdUnitStudents...")
    while True:
        eus_response = fetch_data("GetEdUnitStudents", {"skip": skip, "take": take})
        if not eus_response or "EdUnitStudents" not in eus_response:
            break
            
        chunk = eus_response["EdUnitStudents"]
        all_edunit_students.extend(chunk)
        print(f"  Fetched {len(chunk)} EdUnitStudents (Total: {len(all_edunit_students)})...")
        
        if len(chunk) < take:
            break
        skip += take
        time.sleep(0.1)
        
    if all_edunit_students:
        save_json("ed_unit_students.json", {"EdUnitStudents": all_edunit_students})
        print(f"Successfully exported {len(all_edunit_students)} EdUnitStudents.")

    # 9. Export Tasks
    all_tasks = []
    skip = 0
    print("Fetching tasks...")
    while True:
        tasks_response = fetch_data("GetTasks", {"skip": skip, "take": take})
        if not tasks_response or "Tasks" not in tasks_response:
            break
        chunk = tasks_response["Tasks"]
        all_tasks.extend(chunk)
        print(f"  Fetched {len(chunk)} tasks...")
        if len(chunk) < take:
            break
        skip += take
        time.sleep(0.1)
    if all_tasks:
        save_json("tasks.json", {"Tasks": all_tasks})

    # 10. Export Student Logs (History/Comments)
    # This often includes communications and comments
    print("Fetching student logs...")
    logs_response = fetch_data("GetStudentLogs", {"take": 2000}) 
    if logs_response:
        save_json("student_logs.json", logs_response)
        print("Successfully exported student logs.")

    print("Export complete!")

if __name__ == "__main__":
    main()
