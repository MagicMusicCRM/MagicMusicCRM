import json
import requests

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def test_endpoint(endpoint, method="GET", params=None):
    if params is None: params = {}
    params['authkey'] = AUTH_KEY
    url = f"{API_URL}{endpoint}"
    print(f"Testing {method} {url} with params {params}...")
    try:
        if method == "GET":
            res = requests.get(url, params=params, timeout=10)
        else:
            res = requests.post(url, params={"authkey": AUTH_KEY}, json=params, timeout=10)
        
        print(f"Status: {res.status_code}")
        if res.status_code == 200:
            data = res.json()
            # print(json.dumps(data, indent=2, ensure_ascii=False)[:500])
            print("Success!")
        else:
            print(f"Error: {res.text}")
    except Exception as e:
        print(f"Exception: {e}")

# Test GET vs POST for GetSchedule
test_endpoint("GetSchedule", "GET", {"dateFrom": "2024-03-01", "dateTo": "2024-03-07"})
test_endpoint("GetSchedule", "POST", {"dateFrom": "2024-03-01", "dateTo": "2024-03-07"})
