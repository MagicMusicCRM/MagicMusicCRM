import requests
import json

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'REDACTED_LEGACY_SUPABASE_ANON_KEY'

def test_supabase_pagination():
    table = "groups"
    limit = 5
    offset = 0
    url = f"{SUPABASE_URL}/rest/v1/{table}?select=id,hollihop_id&limit={limit}&offset={offset}"
    headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
    print(f"Testing {url}...")
    res = requests.get(url, headers=headers)
    print(f"Status: {res.status_code}")
    if res.status_code == 200:
        print(f"Result length: {len(res.json())}")
        print(json.dumps(res.json(), indent=2))
    else:
        print(f"Error: {res.text}")

test_supabase_pagination()
