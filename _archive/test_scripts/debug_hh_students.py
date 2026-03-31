import requests
import json
import time

API_URL = "https://sokol.t8s.ru/Api/V2/"
AUTH_KEY = "L/GNdp2hnzeCkipgzZn64mjlazEnwByibYJoUGle7oLx2oNQtq0l6DVoi39m6G2n"

def debug_students():
    params = {'authkey': AUTH_KEY}
    print("Fetching GetStudents...")
    res = requests.get(f"{API_URL}GetStudents", params=params)
    if res.status_code == 200:
        data = res.json()
        students = data.get("Students", [])
        print(f"Found {len(students)} students")
        if students:
            print("First student JSON:")
            print(json.dumps(students[0], indent=2, ensure_ascii=False))
    else:
        print(f"Error: {res.status_code} - {res.text}")

if __name__ == "__main__":
    debug_students()
