import json
import requests

API_URL_V1 = "https://sokol.t8s.ru/Api/V1/"
API_URL_V2 = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def test_endpoint(base_url, endpoint):
    params = {'authkey': AUTH_KEY, "dateFrom": "2024-03-01", "dateTo": "2024-03-07"}
    url = f"{base_url}{endpoint}"
    print(f"Testing GET {url}...")
    try:
        res = requests.get(url, params=params, timeout=10)
        print(f"Status: {res.status_code}")
        if res.status_code == 200:
            print(f"Success! Keys: {list(res.json().keys()) if isinstance(res.json(), dict) else 'List result'}")
        else:
            print(f"Error: {res.text[:100]}")
    except Exception as e:
        print(f"Exception: {e}")

test_endpoint(API_URL_V1, "GetSchedule")
test_endpoint(API_URL_V2, "GetSchedule")
