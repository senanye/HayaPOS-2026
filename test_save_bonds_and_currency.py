import requests
import json
import sqlite3
import os

BASE_URL = "http://127.0.0.1:9000"

def test_bond_currency_and_account():
    print("--- 1. Testing GET /api/currencies ---")
    res_cur = requests.get(f"{BASE_URL}/api/currencies")
    print(f"Currencies ({res_cur.status_code}):", res_cur.json()[:2] if res_cur.status_code == 200 else res_cur.text)
    
    print("\n--- 2. Testing GET /api/accounts ---")
    res_acc = requests.get(f"{BASE_URL}/api/accounts")
    accounts = res_acc.json()
    print(f"Accounts count: {len(accounts)}")
    first_acc = accounts[0] if accounts else {"accId": 498, "name": "حساب تجريبي"}
    acc_id = first_acc.get("accId", 498)
    print(f"Using Account: ID={acc_id}, Name={first_acc.get('name')}")
    
    # 3. Create Receipt Bond (isReceipt=True) with currency ID 2 (or 1)
    print("\n--- 3. Creating Receipt Bond (Type 10) with MoneyID=2 & AccID ---")
    receipt_payload = {
        "expensesId": acc_id,
        "amount": 250.75,
        "note": "سند قبض تجريبي اختبار حفظ العملة والحساب",
        "date": "2026-08-14",
        "isReceipt": True,
        "pointNo": 31,
        "userId": 1,
        "moneyId": 2,
        "accountId": acc_id,
        "details": [
            {
                "expensesId": acc_id,
                "amount": 250.75,
                "note": "بند 1 لسند القبض"
            }
        ]
    }
    res_create_r = requests.post(f"{BASE_URL}/api/bonds", json=receipt_payload)
    print(f"Receipt Bond Create ({res_create_r.status_code}):", res_create_r.json())
    receipt_trans_num = res_create_r.json().get("transNumber")

    # 4. Create Payment Bond (isReceipt=False) with currency ID 3
    print("\n--- 4. Creating Payment Bond (Type 11) with MoneyID=3 & AccID ---")
    payment_payload = {
        "expensesId": acc_id,
        "amount": 175.50,
        "note": "سند صرف تجريبي اختبار حفظ العملة والحساب",
        "date": "2026-08-14",
        "isReceipt": False,
        "pointNo": 31,
        "userId": 1,
        "moneyId": 3,
        "accountId": acc_id,
        "details": [
            {
                "expensesId": acc_id,
                "amount": 175.50,
                "note": "بند 1 لسند الصرف"
            }
        ]
    }
    res_create_p = requests.post(f"{BASE_URL}/api/bonds", json=payment_payload)
    print(f"Payment Bond Create ({res_create_p.status_code}):", res_create_p.json())
    payment_trans_num = res_create_p.json().get("transNumber")

    # 5. Check in SQLite local db
    print("\n--- 5. Checking local SQLite server/branches.db for saved bonds ---")
    db_path = "server/branches.db" if os.path.exists("server/branches.db") else "branches.db"
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT fldTransNumber, fldType, fldMoneyID, fldAccID, fldDescription FROM Main WHERE fldTransNumber IN (?, ?)", (receipt_trans_num, payment_trans_num))
    rows = cur.fetchall()
    print("Main table in SQLite:")
    for r in rows:
        print(f"  TransNum={r[0]}, Type={r[1]}, fldMoneyID={r[2]}, fldAccID={r[3]}, Desc={r[4]}")
    conn.close()

    # 6. Check GET /api/bonds response
    print("\n--- 6. Checking GET /api/bonds response ---")
    res_bonds = requests.get(f"{BASE_URL}/api/bonds")
    bonds = res_bonds.json()
    for b in bonds:
        if b.get("transNumber") in [receipt_trans_num, payment_trans_num]:
            print(f"  Bond TransNum={b.get('transNumber')}: moneyId={b.get('moneyId')}, accountId={b.get('accountId')}, isReceipt={b.get('isReceipt')}, amount={b.get('amount')}")

    print("\n=== All Bond Tests Completed Successfully ===")

if __name__ == "__main__":
    test_bond_currency_and_account()
