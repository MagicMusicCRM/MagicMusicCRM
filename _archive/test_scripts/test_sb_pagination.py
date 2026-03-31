import requests
import json

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'

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
