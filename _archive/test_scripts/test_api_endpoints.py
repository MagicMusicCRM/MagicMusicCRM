import json
import urllib.request
import urllib.parse

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

endpoints = [
    "GetPayments",
    "GetTasks",
    "GetComments",
    "GetStudentLogs",
    "GetSystemLogs",
    "GetHistory",
    "GetCommunications",
    "GetInvoices",
    "GetEdUnitLessons"
]

def test_endpoint(endpoint):
    params = {'authkey': AUTH_KEY}
    query_string = urllib.parse.urlencode(params)
    url = f"{API_URL}{endpoint}?{query_string}"
    
    print(f"Testing {endpoint}...", end=" ")
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req) as response:
            status = response.getcode()
            content = response.read().decode('utf-8')
            data = json.loads(content)
            print(f"SUCCESS ({status}). Keys: {list(data.keys())}")
            # Try to see total count if available
            for k in data.keys():
                if isinstance(data[k], list):
                    print(f"  - {k} count: {len(data[k])}")
    except Exception as e:
        print(f"FAILED: {e}")

if __name__ == "__main__":
    for ep in endpoints:
        test_endpoint(ep)
