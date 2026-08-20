import requests
import json
import pyodbc
import sqlite3

BASE_URL = "http://127.0.0.1:9000"

print("1. Testing GET /api/accounts and /api/items...")
res_acc = requests.get(f"{BASE_URL}/api/accounts")
print(f"Status: {res_acc.status_code}")
accounts = res_acc.json()
print(f"Accounts count: {len(accounts)}")
test_acc = accounts[0] if accounts else {"accId": 204, "name": "حساب اختباري"}
print(f"Testing with account: {test_acc}")

res_items = requests.get(f"{BASE_URL}/api/items")
items = res_items.json()
valid_barcode = items[0]["barcode"] if items else "1"
valid_name = items[0]["itemName"] if items else "صنف"
print(f"Testing with valid item: barcode={valid_barcode}, name={valid_name}")

test_cases = [
    {"type": 35, "desc": "فاتورة مبيعات تجريبية برقم حساب", "accId": test_acc["accId"]},
    {"type": 36, "desc": "فاتورة مردودات تجريبية برقم حساب", "accId": test_acc["accId"]},
    {"type": 20, "desc": "فاتورة مشتريات تجريبية برقم حساب", "accId": test_acc["accId"]},
    {"type": 22, "desc": "أمر توريد مخزني تجريبي برقم حساب", "accId": test_acc["accId"]},
    {"type": 23, "desc": "أمر صرف مخزني تجريبي برقم حساب", "accId": test_acc["accId"]},
]

saved_trans_numbers = []

for tc in test_cases:
    payload = {
        "date": "2026-08-14",
        "description": tc["desc"],
        "userId": 1,
        "pointNo": 31,
        "payCash": 1,
        "transType": tc["type"],
        "moneyId": 1,
        "accountId": tc["accId"],
        "details": [
            {
                "barcode": valid_barcode,
                "itemName": valid_name,
                "quantity": 1,
                "salesPrice": 100.0,
                "discount": 0,
                "taxTotal": 0,
                "totalItem": 100
            }
        ]
    }
    
    r = requests.post(f"{BASE_URL}/api/transactions", json=payload)
    print(f"\nSaving {tc['desc']} -> Status {r.status_code}: {r.json()}")
    if r.status_code == 200:
        tn = r.json().get("transNumber")
        saved_trans_numbers.append(tn)

print("\n2. Verifying saved records in SQL Server Main table...")
try:
    conn = pyodbc.connect("DRIVER={SQL Server};SERVER=SENANSERVER\\SQLEXPRESS;DATABASE=sp;UID=sa;PWD=as")
    cur = conn.cursor()
    for tn in saved_trans_numbers:
        cur.execute("SELECT fldTransNumber, fldType, fldAccID, fldDescription FROM Main WHERE fldTransNumber = ?", (tn,))
        row = cur.fetchone()
        if row:
            print(f"[SQL Server] Trans #{row[0]}, Type: {row[1]}, fldAccID: {row[2]}")
        else:
            print(f"[SQL Server] Trans #{tn} NOT FOUND!")
    cur.close()
    conn.close()
except Exception as e:
    print(f"SQL Server verification error: {e}")

print("\n3. Verifying saved records in SQLite branches.db Main table...")
try:
    sq = sqlite3.connect("server/branches.db")
    sq_cur = sq.cursor()
    for tn in saved_trans_numbers:
        sq_cur.execute("SELECT fldTransNumber, fldType, fldAccID, fldDescription FROM Main WHERE fldTransNumber = ?", (tn,))
        row = sq_cur.fetchone()
        if row:
            print(f"[SQLite] Trans #{row[0]}, Type: {row[1]}, fldAccID: {row[2]}")
        else:
            print(f"[SQLite] Trans #{tn} NOT FOUND!")
    sq.close()
except Exception as e:
    print(f"SQLite verification error: {e}")

print("\n4. Testing GET /api/transactions/{trans_number}...")
for tn in saved_trans_numbers:
    r_get = requests.get(f"{BASE_URL}/api/transactions/{tn}")
    if r_get.status_code == 200:
        data = r_get.json()
        print(f"[API Response] Trans #{tn} -> accountId: {data.get('accountId')}, accountName: {data.get('accountName')}")
    else:
        print(f"[API Response] Failed to GET trans #{tn}: {r_get.text}")
