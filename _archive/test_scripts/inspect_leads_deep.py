import json
import urllib.request
import urllib.parse

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def fetch(endpoint, params=None):
    if params is None:
        params = {}
    params['authkey'] = AUTH_KEY
    params['take'] = 10
    
    query_string = urllib.parse.urlencode(params)
    url = f"{API_URL}{endpoint}?{query_string}"
    
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode('utf-8'))
            return data
    except Exception as e:
        return None

def main():
    leads = fetch("GetLeads")
    if leads and "Leads" in leads:
        for l in leads["Leads"]:
            # Check for fields that might contain comments or history
            keys = l.keys()
            if any(k in keys for k in ["Comments", "Notes", "History", "Logs", "Maturity"]):
                print(f"Lead ID {l['Id']} has interesting keys: {[k for k in keys if k in ['Comments', 'Notes', 'History', 'Logs', 'Maturity']]}")
                # print(json.dumps(l, indent=2, ensure_ascii=False))
            else:
                 # Print full keys for the first one just in case
                 if l == leads["Leads"][0]:
                     print(f"Lead keys: {list(keys)}")

if __name__ == "__main__":
    main()
