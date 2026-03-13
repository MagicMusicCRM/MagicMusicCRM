import json
import os
import requests
from pathlib import Path

SUPABASE_URL = 'https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhibHBueXdubGhmZ29mc2tiZHhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNDA5ODcsImV4cCI6MjA4ODcxNjk4N30.qRuC_TQ8rlz68fzi0geqqdbkA7ABRBEyw3GyMkMJJxg'

def upsert_data(table_name, payload, conflict_column="name"):
    url = f"{SUPABASE_URL}/rest/v1/{table_name}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates"
    }
    params = {"on_conflict": conflict_column}
    response = requests.post(url, headers=headers, params=params, json=payload)
    if response.status_code not in (200, 201):
        print(f"Error inserting to {table_name}: {response.text}")
    else:
        print(f"Successfully updated {table_name}")

def insert_branches_and_rooms():
    branches = [
        {
            "name": "Сокол",
            "location": "Москва",
            "address": "Ленинградский проспект 75к1А. ВХОД со двора, в правом углу дома",
            "contacts": "89015700387",
            "description": "Вишневская В., Богатырёва М. В., Мазалова А. Ю."
        },
        {
            "name": "Спортивная",
            "location": "Москва",
            "address": "Комсомольский проспект, дом 41. ВХОД со двора, с проспекта - в арку, после арки сразу налево . КОД от двери: 135 (нужно нажать 3 цифры ОДНОВРЕМЕННО)",
            "contacts": "89684778837",
            "description": "Назарова Н. Н., Спортивная А., Крошкин Д. А., Сусарина А. В."
        }
    ]
    
    upsert_data("branches", branches, conflict_column="name")
    
    # Get branch IDs
    headers = {"apikey": SUPABASE_KEY, "Authorization": f"Bearer {SUPABASE_KEY}"}
    res = requests.get(f"{SUPABASE_URL}/rest/v1/branches?select=id,name", headers=headers)
    branches_map = {b["name"]: b["id"] for b in res.json()}
    
    rooms = []
    # Sokol rooms
    sokol_id = branches_map.get("Сокол")
    if sokol_id:
        for r_name in ["BIG Room 4", "Guitar room 6", "Piano room 7", "Room 1", "Room 2 Козодаев", "Room 3", "Room 5"]:
            rooms.append({"name": r_name, "branch_id": sokol_id})
            
    # Sportivnaya rooms
    sport_id = branches_map.get("Спортивная")
    if sport_id:
        for r_name in ["СПОРТИВНАЯ Room 1", "СПОРТИВНАЯ Room 2", "СПОРТИВНАЯ Room 3", "СПОРТИВНАЯ Room 4", "СПОРТИВНАЯ Room 5"]:
            rooms.append({"name": r_name, "branch_id": sport_id})
            
    if rooms:
        upsert_data("rooms", rooms, conflict_column="name,branch_id")

if __name__ == "__main__":
    insert_branches_and_rooms()
