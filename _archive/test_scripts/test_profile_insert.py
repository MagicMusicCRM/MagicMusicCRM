import requests
import uuid

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'
HEADERS = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}", "Content-Type": "application/json"}

url = f"{SUPABASE_URL}/rest/v1/profiles"
prof_id = str(uuid.uuid4())
batch = [{
    "id": prof_id,
    "role": "client",
    "first_name": "Test",
    "last_name": "Test",
    "phone": "12345"
}]

upsert_headers = {**HEADERS, "Prefer": "return=representation,resolution=merge-duplicates"}
params = {"on_conflict": "id"}

response = requests.post(url, headers=upsert_headers, params=params, json=batch)
print(response.status_code)
print(response.text)
