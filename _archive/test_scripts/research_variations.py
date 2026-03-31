import urllib.request
import json
import urllib.parse

AUTH_KEY = 'L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n'
BASE_URL = "https://sokol.t8s.ru/Api/V2/"

ENDPOINTS = [
    "GetLogs",
    "GetStudentLogs",
    "GetLeadLogs",
    "GetManagerTasks",
    "GetUserTasks",
    "GetContracts",
    "GetStudentSubscriptions",
    "GetSubscriptions",
    "GetStudentContract",
    "GetJournal",
    "GetHistory",
    "GetEventLogs"
]

def test_endpoint(name):
    url = f"{BASE_URL}{name}?authkey={AUTH_KEY}&take=1"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read())
            print(f"[SUCCESS] {name}")
            return True
    except:
        return False

print("Testing Variations...")
for ep in ENDPOINTS:
    if test_endpoint(ep):
        pass
    else:
        print(f"[FAILED] {ep}")
