import urllib.request
import json
import urllib.parse

AUTH_KEY = 'L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n'
BASE_URL = "https://sokol.t8s.ru/Api/V2/"

def inspect_record(endpoint, key):
    url = f"{BASE_URL}{endpoint}?authkey={AUTH_KEY}&take=1"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            if key in data and data[key]:
                print(f"--- {endpoint} FULL RECORD ---")
                print(json.dumps(data[key][0], indent=2, ensure_ascii=False))
    except Exception as e:
        print(f"Error {endpoint}: {e}")

inspect_record("GetStudents", "Students")
inspect_record("GetLeads", "Leads")
inspect_record("GetEdUnits", "EdUnits")
