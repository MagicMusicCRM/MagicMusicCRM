import requests
import json
import uuid
import os

# Configuration
SUPABASE_URL = os.environ.get("LEGACY_SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("LEGACY_SUPABASE_ANON_KEY", "")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError("LEGACY_SUPABASE_URL and LEGACY_SUPABASE_ANON_KEY are required.")

def upsert_data(table, data, unique_column='id'):
    """Upserts data into Supabase using REST API."""
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates"
    }

    response = requests.post(url, headers=headers, json=data)
    if response.status_code in [200, 201]:
        print(f"Successfully upserted data into {table}")
    else:
        print(f"Error inserting to {table}: {response.text}")

def update_branch(branch_id, name):
    url = f"{SUPABASE_URL}/rest/v1/branches?id=eq.{branch_id}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal"
    }
    data = {"name": name}
    response = requests.patch(url, headers=headers, json=data)
    if response.status_code in [200, 201, 204]:
        print(f"Successfully updated branch {name}")
    else:
        print(f"Error updating branch {name}: {response.text}")

def insert_branches_and_rooms():
    # Real branch IDs from the database
    sokol_id = "4f2fdb12-b11b-40f9-b207-e48538aaa130"
    sportivnaya_id = "e5406482-e33d-48c3-8139-f0acffcab32f"

    print("Updating branch names...")
    update_branch(sokol_id, "Сокол")
    update_branch(sportivnaya_id, "Спортивная")

    # Rooms definition
    rooms = [
        {"branch_id": sokol_id, "name": "Аудитория 1"},
        {"branch_id": sokol_id, "name": "Аудитория 2"},
        {"branch_id": sokol_id, "name": "Зал"},
        {"branch_id": sportivnaya_id, "name": "Малая аудитория"},
        {"branch_id": sportivnaya_id, "name": "Большая аудитория"},
    ]

    print("Inserting rooms...")
    for room in rooms:
        # Check if room already exists
        url_check = f"{SUPABASE_URL}/rest/v1/rooms?branch_id=eq.{room['branch_id']}&name=eq.{room['name']}"
        headers = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
        }
        check_resp = requests.get(url_check, headers=headers)
        if check_resp.status_code == 200 and len(check_resp.json()) > 0:
            print(f"Room {room['name']} already exists.")
            continue

        # Insert room
        url = f"{SUPABASE_URL}/rest/v1/rooms"
        headers_post = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json",
        }
        room["id"] = str(uuid.uuid4())
        resp = requests.post(url, headers=headers_post, json=room)
        if resp.status_code in [200, 201]:
            print(f"Inserted room: {room['name']}")
        else:
            print(f"Error inserting room {room['name']}: {resp.text}")

if __name__ == "__main__":
    insert_branches_and_rooms()
