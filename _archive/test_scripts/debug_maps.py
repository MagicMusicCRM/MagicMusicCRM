import requests
import json
import urllib.request
import urllib.parse
import time

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'
API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def get_sb_map(table):
    print(f"Loading map for {table}...", flush=True)
    url = f"{SUPABASE_URL}/rest/v1/{table}?select=hollihop_id,id"
    headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
    start = time.time()
    res = requests.get(url, headers=headers)
    print(f"  Done in {time.time()-start:.2f}s (Status: {res.status_code})", flush=True)
    if res.status_code == 200:
        return {item["hollihop_id"]: item["id"] for item in res.json() if item["hollihop_id"] is not None}
    return {}

def test():
    s_map = get_sb_map("students")
    t_map = get_sb_map("teachers")
    b_map = get_sb_map("branches")
    g_map = get_sb_map("groups")
    print(f"Total Maps: S:{len(s_map)}, T:{len(t_map)}, B:{len(b_map)}, G:{len(g_map)}", flush=True)

test()
