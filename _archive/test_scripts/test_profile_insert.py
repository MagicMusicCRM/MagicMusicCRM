import requests
import uuid

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'REDACTED_LEGACY_SUPABASE_ANON_KEY'
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
