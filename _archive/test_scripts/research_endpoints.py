import urllib.request
import json
import urllib.parse
from datetime import datetime, timedelta

AUTH_KEY = 'L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n'
BASE_URL = "https://sokol.t8s.ru/Api/V2/"

# Test scenarios
SCENARIOS = [
    ("GetSchedule", {"dateFrom": "2024-01-01", "dateTo": "2024-12-31"}),
    ("GetLessons", {"from": "2024-01-01", "to": "2024-12-31"}),
    ("GetTasks", {}),
    ("GetSubscriptions", {}),
    ("GetEdUnitStudents", {}),
    ("GetComments", {}),
    ("GetStudentMaturityLogs", {"studentId": 0}), # Just testing if it returns 404 or something else
    ("GetEdUnits", {}),
    ("GetStudents", {"take": 1}),
]

def test_endpoint(name, params):
    full_params = params.copy()
    full_params['authkey'] = AUTH_KEY
    query_string = urllib.parse.urlencode(full_params)
    url = f"{BASE_URL}{name}?{query_string}"
    
    print(f"Testing {name} with params {params}...")
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read())
            # Print keys instead of full data to see structure
            keys = list(data.keys()) if isinstance(data, dict) else "Not a dict"
            print(f"  [SUCCESS] Keys: {keys}")
            if keys and isinstance(data, dict):
                first_key = keys[0]
                if isinstance(data[first_key], list) and len(data[first_key]) > 0:
                    print(f"  [SAMPLE] {first_key}[0]: {str(data[first_key][0])[:200]}...")
            return True
    except urllib.error.HTTPError as e:
        print(f"  [FAILED] {name}: {e.code} {e.reason}")
        return False
    except Exception as e:
        print(f"  [ERROR] {name}: {e}")
        return False

print("Thorough HolliHop Endpoint Discovery...")
for name, params in SCENARIOS:
    test_endpoint(name, params)
