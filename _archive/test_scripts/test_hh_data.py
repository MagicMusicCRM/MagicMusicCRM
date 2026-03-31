import json
import urllib.request
import urllib.parse

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def fetch_hh(endpoint, params):
    params['authkey'] = AUTH_KEY
    url = f"{API_URL}{endpoint}?{urllib.parse.urlencode(params)}"
    print(f"Fetching {url}...")
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req) as res:
        return json.loads(res.read().decode('utf-8'))

# Test GetSchedule
print("--- GetSchedule Test ---")
sched = fetch_hh("GetSchedule", {"dateFrom": "2024-03-01", "dateTo": "2024-03-07", "take": 10})
print(json.dumps(sched, indent=2, ensure_ascii=False))

# Test GetEdUnitStudents
print("\n--- GetEdUnitStudents Test ---")
mems = fetch_hh("GetEdUnitStudents", {"take": 10})
print(json.dumps(mems, indent=2, ensure_ascii=False))
