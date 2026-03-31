import urllib.request
import json
import urllib.parse

AUTH_KEY = 'L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n'
BASE_URL = "https://sokol.t8s.ru/Api/V2/GetOffices"

print("Minimal Test Start...", flush=True)
try:
    url = f"{BASE_URL}?authkey={AUTH_KEY}"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
        print(f"SUCCESS: Found {len(data.get('Offices', []))} offices", flush=True)
except Exception as e:
    print(f"ERROR: {e}", flush=True)
