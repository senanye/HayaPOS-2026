import json
import sqlite3
import pyodbc

import sqlite3
import pyodbc

try:
    server = r"SENANSERVER\SQLEXPRESS"
    db = "sp0"
    usr = "sa"
    pwd = "as"
    
    conn_str = f"DRIVER={{SQL Server}};SERVER={server};DATABASE={db};UID={usr};PWD={pwd}"
    conn = pyodbc.connect(conn_str)
    cur = conn.cursor()
    
    cur.execute("SELECT TOP 20 fldID, fldExpensesName, fldAccID FROM tblExpensesList")
    exp_list = cur.fetchall()
    print("=== SQL Server tblExpensesList ===")
    for r in exp_list:
        print(f"fldID: {r[0]}, fldExpensesName: {r[1]}, fldAccID: {r[2]}")
        
    cur.execute("SELECT TOP 10 fldTransNumber, fldType, fldAccID, fldDescription, fldDate FROM Main ORDER BY fldTransNumber DESC")
    main_rows = cur.fetchall()
    print("\n=== SQL Server Main Recent Records ===")
    for r in main_rows:
        print(f"TransNum: {r[0]}, Type: {r[1]}, fldAccID: {r[2]}, Desc: {r[3]}, Date: {r[4]}")
        
    cur.close()
    conn.close()
except Exception as e:
    print(f"SQL Server error: {e}")
except Exception as e:
    print(f"SQL Server error: {e}")

try:
    sq = sqlite3.connect('server/branches.db')
    sq_cur = sq.cursor()
    sq_cur.execute("SELECT fldID, fldExpensesName, fldAccID FROM tblExpensesList LIMIT 20")
    print("\n=== SQLite tblExpensesList ===")
    for r in sq_cur.fetchall():
        print(f"fldID: {r[0]}, fldExpensesName: {r[1]}, fldAccID: {r[2]}")
    sq.close()
except Exception as e:
    print(f"SQLite error: {e}")
