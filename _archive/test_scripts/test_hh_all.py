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
            data = res.json()
            keys = list(data.keys())
            print(f"Success! Keys: {keys}")
            # print(json.dumps(data, indent=2, ensure_ascii=False))
        else:
            print(f"Error: {res.text[:200]}")
    except Exception as e:
        print(f"Exception: {e}")

test_endpoint("GetEdUnits")
test_endpoint("GetEdUnitStudents")
test_endpoint("GetStudents")
test_endpoint("GetTeachers")
test_endpoint("GetStudentServices")
