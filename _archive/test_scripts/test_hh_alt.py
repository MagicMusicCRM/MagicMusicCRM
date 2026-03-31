import json
import requests

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def test_endpoint(endpoint):
    params = {'authkey': AUTH_KEY}
    url = f"{API_URL}{endpoint}"
    print(f"Testing GET {url}...")
    try:
        res = requests.get(url, params=params, timeout=10)
        print(f"Status: {res.status_code}")
        if res.status_code == 200:
            print(f"Success! Keys: {list(res.json().keys())}")
        else:
            print(f"Error: {res.text[:100]}")
    except Exception as e:
        print(f"Exception: {e}")

test_endpoint("GetLessons")
test_endpoint("GetMemberships")
test_endpoint("GetStudentLogs")
test_endpoint("GetLeadLogs")
test_endpoint("GetTasks")
test_endpoint("GetUsers")
