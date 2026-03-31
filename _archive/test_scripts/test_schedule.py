import json
import urllib.request
import urllib.parse

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def fetch(endpoint, params=None):
    if params is None:
        params = {}
    params['authkey'] = AUTH_KEY
    params['take'] = 1
    
    query_string = urllib.parse.urlencode(params)
    url = f"{API_URL}{endpoint}?{query_string}"
    
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            return data
    except Exception as e:
        return str(e)

def main():
    # Try GetSchedule
    schedule = fetch("GetSchedule", {"dateFrom": "2024-03-01", "dateTo": "2024-03-31"})
    print("\n--- GET SCHEDULE ---")
    print(json.dumps(schedule, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
