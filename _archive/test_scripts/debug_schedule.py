import json
import urllib.request
import urllib.parse
import time

AUTH_KEY = 'L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n'
BASE_URL = "https://sokol.t8s.ru/Api/V2/"

def test_schedule():
    print("Testing GetSchedule volume...", flush=True)
    start_date = "2023-01-01"
    end_date = "2025-12-31"
    url = f"{BASE_URL}GetSchedule?authkey={AUTH_KEY}&dateFrom={start_date}&dateTo={end_date}&take=10000"
    start = time.time()
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            count = len(data.get("Schedule", []))
            print(f"  Found {count} items in {time.time()-start:.2f}s", flush=True)
    except Exception as e:
        print(f"  Error: {e}", flush=True)

test_schedule()
