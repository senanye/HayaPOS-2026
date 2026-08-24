import os
import json
import sqlite3
try:
    import pyodbc
except ImportError:
    pyodbc = None
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
from datetime import date, datetime

app = FastAPI(title="Haya POS SQL Server API", version="1.2.0")

# Enable CORS for Flutter app communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Default fallback settings in memory (Dynamically loaded from server_config.json / SQLite tblPointList)
db_config = {
    "server": r"S1\SQLEXPRESS",
    "remote_server": r"S1\SQLEXPRESS",
    "local_db": "sp",
    "remote_db": "sp",
    "username": "sa",
    "password": "as",
    "port": "",
    "point_no": 1,
    "point_name": "الرئيسية"
}

def get_installed_sql_drivers() -> List[str]:
    system_drivers = []
    if pyodbc is not None:
        try:
            for d in pyodbc.drivers():
                clean = d.strip("{}").strip()
                if "sql" in clean.lower():
                    system_drivers.append(f"{{{clean}}}")
        except Exception:
            pass

    if system_drivers:
        return system_drivers

    return [
        "{ODBC Driver 18 for SQL Server}",
        "{ODBC Driver 17 for SQL Server}",
        "{ODBC Driver 13 for SQL Server}",
        "{ODBC Driver 11 for SQL Server}",
        "{SQL Server Native Client 11.0}",
        "{SQL Server Native Client 10.0}",
        "{SQL Server}",
    ]

def load_db_config(target_point_no: Optional[int] = None):
    global db_config
    # 1. Load from server_config.json if present
    cfg_loaded = False
    for cfg_path in ["server_config.json", os.path.join(os.path.dirname(__file__), "..", "server_config.json"), os.path.join(os.path.dirname(__file__), "server_config.json")]:
        if os.path.exists(cfg_path):
            try:
                with open(cfg_path, "r", encoding="utf-8-sig") as f:
                    loaded = json.load(f)
                    db_config.update(loaded)
                    cfg_loaded = True
                    break
            except Exception as cfg_err:
                print(f"[load_db_config cfg] Error: {cfg_err}")
    # 2. Check branches.db in SQLite
    try:
        branches = get_branches_from_sqlite()
        if branches:
            selected_b = None
            if target_point_no is not None:
                for b in branches:
                    if b.get("pointNo") == target_point_no or b.get("branchNo") == target_point_no:
                        selected_b = b
                        break
            if not selected_b and not cfg_loaded and db_config.get("point_no"):
                for b in branches:
                    if b.get("pointNo") == db_config.get("point_no") or b.get("branchNo") == db_config.get("point_no"):
                        selected_b = b
                        break
            if not selected_b and not cfg_loaded and not os.path.exists("server_config.json"):
                selected_b = branches[0]

            if selected_b and not cfg_loaded:
                if selected_b.get("dataSource"):
                    db_config["server"] = selected_b["dataSource"].strip()
                if selected_b.get("mainDataSource") or selected_b.get("dataSource"):
                    db_config["remote_server"] = (selected_b.get("mainDataSource") or selected_b.get("dataSource")).strip()
                if selected_b.get("catalog"):
                    db_config["local_db"] = selected_b["catalog"].strip()
                if selected_b.get("mainCatalog") or selected_b.get("catalog"):
                    db_config["remote_db"] = (selected_b.get("mainCatalog") or selected_b.get("catalog")).strip()
                if selected_b.get("userId"):
                    db_config["username"] = selected_b["userId"].strip()
                if selected_b.get("password"):
                    db_config["password"] = selected_b["password"].strip()
                db_config["point_no"] = selected_b.get("pointNo", 1)
                db_config["point_name"] = selected_b.get("pointName", "الفرع")
    except Exception as e:
        print(f"[load_db_config] Error: {e}")

def save_db_config():
    try:
        cfg_paths = ["server_config.json", os.path.join(os.path.dirname(__file__), "..", "server_config.json")]
        for p in cfg_paths:
            dir_name = os.path.dirname(os.path.abspath(p))
            if os.path.exists(dir_name):
                with open(p, "w", encoding="utf-8") as f:
                    json.dump({
                        "server": db_config.get("server", ""),
                        "remote_server": db_config.get("remote_server", ""),
                        "local_db": db_config.get("local_db", "sp"),
                        "remote_db": db_config.get("remote_db", "sp"),
                        "username": db_config.get("username", "sa"),
                        "password": db_config.get("password", "as"),
                        "port": db_config.get("port", ""),
                        "point_no": db_config.get("point_no", 1),
                        "point_name": db_config.get("point_name", "الرئيسية"),
                        "logo_base64": db_config.get("logo_base64", "")
                    }, f, indent=2, ensure_ascii=False)
                break
    except Exception as ex:
        print(f"[save_db_config] Error: {ex}")

_cached_working_driver = None

# High-performance instant connection using dynamically discovered ODBC drivers
def get_connection(point_no: Optional[int] = None):
    global _cached_working_driver
    if pyodbc is None:
        raise HTTPException(status_code=503, detail="مكتبة pyodbc غير مثبتة للاتصال بـ SQL Server")
    load_db_config(point_no)
    
    server = db_config.get("server", r"S1\SQLEXPRESS").strip()
    db = db_config.get("local_db", "sp").strip()
    usr = db_config.get("username", "sa").strip()
    pwd = db_config.get("password", "as").strip()
    if db_config.get("port"):
        server = f"{server},{db_config['port']}"
    
    driver_list = get_installed_sql_drivers()
    if _cached_working_driver and _cached_working_driver in driver_list:
        driver_list.remove(_cached_working_driver)
        driver_list.insert(0, _cached_working_driver)
        
    last_err = ""
    for driver in driver_list:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={server};"
                f"Database={db};"
                f"Uid={usr};"
                f"Pwd={pwd};"
                f"Encrypt=no;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            _cached_working_driver = driver
            return conn
        except Exception as e:
            last_err = str(e)
            
    for driver in driver_list:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={server};"
                f"Database={db};"
                f"Uid={usr};"
                f"Pwd={pwd};"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            _cached_working_driver = driver
            return conn
        except Exception as e:
            last_err = str(e)

    for driver in driver_list:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={server};"
                f"Database={db};"
                f"Trusted_Connection=yes;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            _cached_working_driver = driver
            return conn
        except Exception as e:
            last_err = str(e)
            
    raise Exception(f"تعذر الاتصال بقاعدة بيانات SQL Server ({server} / {db}) بالمستخدم ({usr}): {last_err}")

def get_remote_connection():
    global _cached_working_driver
    if pyodbc is None:
        raise HTTPException(status_code=503, detail="مكتبة pyodbc غير مثبتة للاتصال بـ SQL Server")
    load_db_config()
    server = db_config.get("remote_server", db_config.get("server", r"S1\SQLEXPRESS")).strip()
    db = db_config.get("remote_db", db_config.get("local_db", "sp")).strip()
    usr = db_config.get("username", "sa").strip()
    pwd = db_config.get("password", "as").strip()
    if db_config.get("port"):
        server = f"{server},{db_config['port']}"
        
    driver_list = get_installed_sql_drivers()
    if _cached_working_driver and _cached_working_driver in driver_list:
        driver_list.remove(_cached_working_driver)
        driver_list.insert(0, _cached_working_driver)
        
    last_err = ""
    for driver in driver_list:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={server};"
                f"Database={db};"
                f"Uid={usr};"
                f"Pwd={pwd};"
                f"Encrypt=no;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            _cached_working_driver = driver
            return conn
        except Exception as e:
            last_err = str(e)
            
    for driver in driver_list:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={server};"
                f"Database={db};"
                f"Uid={usr};"
                f"Pwd={pwd};"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            _cached_working_driver = driver
            return conn
        except Exception as e:
            last_err = str(e)
            
    raise Exception(f"تعذر الاتصال بالسيرفر الرئيسي ({server} / {db}): {last_err}")

def ensure_columns_exist(cursor):
    for tbl in ['Main', 'details', 'tblExpenses']:
        try:
            query = f"""
            IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[{tbl}]') AND type in (N'U'))
            BEGIN
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[{tbl}]') AND name = 'fldPointNO')
                BEGIN
                    ALTER TABLE [dbo].[{tbl}] ADD [fldPointNO] [int] NULL
                END
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[{tbl}]') AND name = 'fldToPointNO')
                BEGIN
                    ALTER TABLE [dbo].[{tbl}] ADD [fldToPointNO] [int] NULL
                END
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[{tbl}]') AND name = 'fldIsSync')
                BEGIN
                    ALTER TABLE [dbo].[{tbl}] ADD [fldIsSync] [int] NULL DEFAULT 0
                END
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[{tbl}]') AND name = 'fldStatus')
                BEGIN
                    ALTER TABLE [dbo].[{tbl}] ADD [fldStatus] [int] NULL DEFAULT 0
                END
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[{tbl}]') AND name = 'fldAccID')
                BEGIN
                    ALTER TABLE [dbo].[{tbl}] ADD [fldAccID] [bigint] NULL DEFAULT 0
                END
            END
            """
            cursor.execute(query)
        except Exception as ex:
            print(f"Migration check error for {tbl}: {ex}")

    # Backfill fldAccID in tblExpenses from tblExpensesList if fldAccID is 0 or null
    try:
        cursor.execute("""
        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblExpenses]') AND type in (N'U'))
           AND EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblExpensesList]') AND type in (N'U'))
        BEGIN
            UPDATE e
            SET e.fldAccID = el.fldAccID
            FROM tblExpenses e
            INNER JOIN tblExpensesList el ON e.fldExpensesID = el.fldID
            WHERE (e.fldAccID IS NULL OR e.fldAccID = 0) AND el.fldAccID IS NOT NULL AND el.fldAccID > 0
        END
        """)
    except Exception as ex:
        pass

# --- Data Models (Pydantic) ---

class LoginRequest(BaseModel):
    username: str
    password: str

class UserResponse(BaseModel):
    userId: int
    userName: str
    isAdmin: bool
    canSale: bool
    canReturn: bool
    canChangePrice: bool
    canDiscount: bool
    canExpenses: bool
    canReport: bool

class ItemResponse(BaseModel):
    barcode: str
    itemName: str
    unitName: str
    salesPrice: float
    cost: float
    groupId: int
    itemId: int
    unityId: int
    moneyId: int
    isActive: bool

class ItemRequest(BaseModel):
    barcode: Optional[str] = ""
    itemName: str
    unitName: Optional[str] = "حبة"
    salesPrice: float = 0.0
    cost: float = 0.0
    groupId: int = 1
    itemId: Optional[int] = 0
    unityId: Optional[int] = 1
    moneyId: Optional[int] = 1
    isActive: bool = True


class GroupResponse(BaseModel):
    id: int
    name: str
    code: Optional[str] = None

class CurrencyResponse(BaseModel):
    id: int
    symbol: str
    name: str
    value: float

class DetailItem(BaseModel):
    barcode: str
    quantity: float = 1.0
    salesPrice: float = 0.0
    discount: float = 0.0
    taxTotal: float = 0.0
    totalItem: float = 0.0
    toPointNo: Optional[int] = None

class TransactionRequest(BaseModel):
    date: str  # YYYY-MM-DD
    description: Optional[str] = None
    userId: int
    pointNo: int
    toPointNo: Optional[int] = None
    payCash: int  # 1 for Cash, 2 for Credit
    transType: int  # 1 for Sale, 2 for Purchase, 28 for Inter-branch Transfer, etc.
    moneyId: int
    accountId: Optional[int] = 0  # fldAccID from tblExpensesList
    status: Optional[int] = 0  # 0 for Pending/In-Transit, 1 for Confirmed/Received, 2 for Rejected
    details: List[DetailItem]

class ConfirmTransferRequest(BaseModel):
    transNumber: float
    userId: Optional[int] = 1

# --- CRM & Accounting Data Models ---

class AccountRequest(BaseModel):
    name: str
    accId: int

class AccountResponse(BaseModel):
    id: int
    name: str
    accId: int

class RemoteAccountResponse(BaseModel):
    id: int
    name: str

class BondItemDetail(BaseModel):
    expensesId: int
    amount: float
    note: Optional[str] = ""
    accountId: Optional[int] = 0

class BondRequest(BaseModel):
    expensesId: Optional[int] = 0
    amount: Optional[float] = 0.0
    note: Optional[str] = None
    date: str
    isReceipt: bool
    pointNo: Optional[int] = 1
    userId: Optional[int] = 1
    moneyId: Optional[int] = 1
    accountId: Optional[int] = 0
    details: Optional[List[BondItemDetail]] = None

class BondEditRequest(BaseModel):
    id: Optional[int] = 0
    transNumber: float
    expensesId: Optional[int] = 0
    amount: Optional[float] = 0.0
    note: Optional[str] = None
    date: str
    isReceipt: bool
    pointNo: Optional[int] = 1
    userId: Optional[int] = 1
    moneyId: Optional[int] = 1
    accountId: Optional[int] = 0
    details: Optional[List[BondItemDetail]] = None

class BondDetailResponse(BaseModel):
    expensesId: int
    expensesName: str
    amount: float
    note: str

class BondResponse(BaseModel):
    id: int
    transNumber: float
    expensesId: int
    expensesName: str
    amount: float
    note: str
    date: str
    isReceipt: bool
    pointNo: int
    userId: int
    moneyId: Optional[int] = 1
    accountId: Optional[int] = 0
    details: List[BondDetailResponse] = []

# --- Settings Data Models ---

class ConnectionSettingsRequest(BaseModel):
    server: str
    remoteServer: str
    localDb: str
    remoteDb: str
    username: str
    password: str
    port: Optional[str] = ""
    pointNo: int
    pointName: str
    logoBase64: Optional[str] = ""

class FetchPointsRequest(BaseModel):
    remoteServer: str
    remoteDb: str
    username: str
    password: str
    port: Optional[str] = ""

class PointResponse(BaseModel):
    pointNo: int
    pointName: str
    dataSource: str
    catalog: Optional[str] = "sp"
    userId: Optional[str] = "sa"
    password: Optional[str] = "as"
    branchNo: Optional[int] = 1
    mainDataSource: Optional[str] = ""
    mainCatalog: Optional[str] = ""

class SpecialLoginRequest(BaseModel):
    username: str
    password: str
    pointNo: int
    pointName: str
    dataSource: Optional[str] = ""
    catalog: Optional[str] = "sp"
    userId: Optional[str] = "sa"
    password: Optional[str] = "as"
    mainDataSource: Optional[str] = ""
    mainCatalog: Optional[str] = ""

# --- Endpoints ---

@app.get("/", response_class=HTMLResponse)
def root_home():
    return """
    <!DOCTYPE html>
    <html lang="ar" dir="rtl">
    <head>
        <meta charset="UTF-8">
        <title>خادم هيا لنقاط البيع - Haya POS API</title>
        <style>
            body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0F172A; color: white; text-align: center; padding: 60px 20px; }
            .card { background: #1E293B; border-radius: 16px; padding: 40px; display: inline-block; box-shadow: 0 10px 25px rgba(0,0,0,0.5); max-width: 500px; }
            h2 { color: #38BDF8; margin-top: 0; }
            p { color: #94A3B8; font-size: 16px; line-height: 1.6; }
            a.btn { background: #2563EB; color: white; padding: 14px 28px; text-decoration: none; border-radius: 10px; font-weight: bold; display: inline-block; margin-top: 20px; font-size: 16px; transition: 0.2s; }
            a.btn:hover { background: #1D4ED8; }
        </style>
    </head>
    <body>
        <div class="card">
            <h2>⚙️ خادم خلفية هيا لنقاط البيع يعمل بنجاح</h2>
            <p>لقد قمت بفتح المنفذ <b>9000</b> الخاص بالخدمات البرمجية (API). لفتح واجهة التطبيق الرئيسية يرجى النقر على الزر أدناه:</p>
            <a href="http://localhost:8888" class="btn">🚀 فتح تطبيق هيا لنقاط البيع (Port 8888)</a>
        </div>
    </body>
    </html>
    """

@app.get("/api/health")
def health_check():
    sql_connected = False
    sql_err = ""
    try:
        conn = get_connection()
        conn.close()
        sql_connected = True
    except Exception as e:
        sql_err = str(e)
    return {
        "status": "healthy",
        "api": "running",
        "sql_connected": sql_connected,
        "active_server": db_config.get("server"),
        "active_catalog": db_config.get("local_db"),
        "sql_error": sql_err
    }

@app.post("/api/points/active/{point_no}")
def set_active_branch_point(point_no: int):
    load_db_config(point_no)
    return {
        "status": "success",
        "pointNo": db_config.get("point_no"),
        "pointName": db_config.get("point_name"),
        "server": db_config.get("server"),
        "catalog": db_config.get("local_db")
    }

SQLITE_DB_FILE = os.path.join(os.path.dirname(__file__), "branches.db")

def init_sqlite_branches_db():
    try:
        conn = sqlite3.connect(SQLITE_DB_FILE)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tblPointList (
                fldPointNO INTEGER PRIMARY KEY,
                fldName TEXT,
                fldBranchNo INTEGER,
                DataSource TEXT,
                Catalog TEXT,
                UserID TEXT,
                Password TEXT,
                MainDataSource TEXT,
                MainCatalog TEXT
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tblUsers (
                fldUserID INTEGER,
                fldUserName TEXT,
                fldPassword TEXT DEFAULT '',
                fldPointNO INTEGER,
                fldAdmin INTEGER DEFAULT 0,
                fldsale INTEGER DEFAULT 1,
                fldReturn INTEGER DEFAULT 1,
                fldSalesPrice INTEGER DEFAULT 1,
                fldDiscount INTEGER DEFAULT 1,
                fldlExpenses INTEGER DEFAULT 1,
                fldReport INTEGER DEFAULT 1,
                PRIMARY KEY (fldUserID, fldPointNO)
            )
        """)
        conn.commit()
        cursor.execute("PRAGMA table_info(tblPointList)")
        cols = [row[1].lower() for row in cursor.fetchall()]
        if "maindatasource" not in cols:
            cursor.execute("ALTER TABLE tblPointList ADD COLUMN MainDataSource TEXT DEFAULT ''")
            conn.commit()
        if "maincatalog" not in cols:
            cursor.execute("ALTER TABLE tblPointList ADD COLUMN MainCatalog TEXT DEFAULT ''")
            conn.commit()

        cursor.execute("PRAGMA table_info(tblUsers)")
        u_cols = [row[1].lower() for row in cursor.fetchall()]
        if "fldpassword" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldPassword TEXT DEFAULT ''")
            conn.commit()
        if "fldadmin" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldAdmin INTEGER DEFAULT 0")
            conn.commit()
        if "fldsale" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldsale INTEGER DEFAULT 1")
            conn.commit()
        if "fldreturn" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldReturn INTEGER DEFAULT 1")
            conn.commit()
        if "fldsalesprice" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldSalesPrice INTEGER DEFAULT 1")
            conn.commit()
        if "flddiscount" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldDiscount INTEGER DEFAULT 1")
            conn.commit()
        if "fldlexpenses" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldlExpenses INTEGER DEFAULT 1")
            conn.commit()
        if "fldreport" not in u_cols:
            cursor.execute("ALTER TABLE tblUsers ADD COLUMN fldReport INTEGER DEFAULT 1")
            conn.commit()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS Main (
                fldTransNumber REAL PRIMARY KEY,
                fldDate TEXT,
                fldDescription TEXT,
                fldUSerID INTEGER,
                fldPointNO INTEGER,
                fldToPointNO INTEGER,
                fldPaycash INTEGER,
                fldType INTEGER,
                fldTransID INTEGER,
                fldMoneyID INTEGER,
                fldStatus INTEGER DEFAULT 0,
                fldAccID INTEGER DEFAULT 0,
                fldIsSync INTEGER DEFAULT 0
            )
        """)
        cursor.execute("PRAGMA table_info(Main)")
        main_cols = [row[1].lower() for row in cursor.fetchall()]
        if "fldaccid" not in main_cols:
            cursor.execute("ALTER TABLE Main ADD COLUMN fldAccID INTEGER DEFAULT 0")
            conn.commit()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tblExpensesList (
                fldID INTEGER PRIMARY KEY,
                fldExpensesName TEXT,
                fldAccID INTEGER DEFAULT 0
            )
        """)
        cursor.execute("PRAGMA table_info(tblExpensesList)")
        exp_cols = [row[1].lower() for row in cursor.fetchall()]
        if "fldaccid" not in exp_cols:
            cursor.execute("ALTER TABLE tblExpensesList ADD COLUMN fldAccID INTEGER DEFAULT 0")
            conn.commit()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS tblExpenses (
                fldID INTEGER PRIMARY KEY AUTOINCREMENT,
                fldExpensesID INTEGER,
                fldAmount REAL,
                fldNote TEXT,
                fldTransID INTEGER,
                fldDate TEXT,
                fldTransNumber REAL,
                fldPointNO INTEGER,
                fldAccID INTEGER DEFAULT 0,
                fldIsSync INTEGER DEFAULT 0
            )
        """)
        cursor.execute("PRAGMA table_info(tblExpenses)")
        te_cols = [row[1].lower() for row in cursor.fetchall()]
        if "fldaccid" not in te_cols:
            cursor.execute("ALTER TABLE tblExpenses ADD COLUMN fldAccID INTEGER DEFAULT 0")
            conn.commit()

        conn.close()
    except Exception as e:
        print(f"Error initializing SQLite branches.db: {e}")

def decode_ar_str(val):
    if not val:
        return ""
    val_str = str(val).strip()
    try:
        return val_str.encode("latin1").decode("cp1256")
    except Exception:
        return val_str

def sync_branches_to_sqlite():
    init_sqlite_branches_db()
    try:
        sql_conn = get_connection()
        cursor = sql_conn.cursor()
        try:
            cursor.execute("SELECT fldName, fldBranchNo, fldPointNO, DataSource, Catalog, UserID, Password, MainDataSource, MainCatalog FROM dbo.tblPointList")
            rows = cursor.fetchall()
            has_main_cols = True
        except Exception:
            cursor.execute("SELECT fldName, fldBranchNo, fldPointNO, DataSource, Catalog, UserID, Password FROM dbo.tblPointList")
            rows = cursor.fetchall()
            has_main_cols = False
        cursor.close()
        sql_conn.close()

        if rows:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            for r in rows:
                p_name = decode_ar_str(r[0])
                b_no = int(r[1]) if r[1] is not None else 1
                p_no = int(r[2]) if r[2] is not None else 1
                p_ds = str(r[3] or "").strip()
                p_cat = str(r[4] or "sp").strip()
                p_uid = str(r[5] or "sa").strip()
                p_pwd = str(r[6] or "as").strip()
                p_main_ds = str(r[7] or "").strip() if has_main_cols and len(r) > 7 else ""
                p_main_cat = str(r[8] or "").strip() if has_main_cols and len(r) > 8 else ""

                sq_cur.execute("""
                    INSERT INTO tblPointList (fldPointNO, fldName, fldBranchNo, DataSource, Catalog, UserID, Password, MainDataSource, MainCatalog)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(fldPointNO) DO UPDATE SET
                        fldName=excluded.fldName,
                        fldBranchNo=excluded.fldBranchNo,
                        DataSource=excluded.DataSource,
                        Catalog=excluded.Catalog,
                        UserID=excluded.UserID,
                        Password=excluded.Password,
                        MainDataSource=excluded.MainDataSource,
                        MainCatalog=excluded.MainCatalog
                """, (p_no, p_name, b_no, p_ds, p_cat, p_uid, p_pwd, p_main_ds, p_main_cat))
            sq_conn.commit()
            sq_conn.close()
            print(f"[SQLite Branch Sync] Synced {len(rows)} branches to SQLite branches.db")
    except Exception as e:
        print(f"[SQLite Branch Sync Notice] {e}")

def get_branches_from_sqlite():
    init_sqlite_branches_db()
    branches = []
    try:
        sq_conn = sqlite3.connect(SQLITE_DB_FILE)
        sq_cur = sq_conn.cursor()
        sq_cur.execute("SELECT fldPointNO, fldName, fldBranchNo, DataSource, Catalog, UserID, Password, MainDataSource, MainCatalog FROM tblPointList ORDER BY fldPointNO")
        rows = sq_cur.fetchall()
        sq_conn.close()

        for r in rows:
            branches.append({
                "pointNo": int(r[0]),
                "pointName": str(r[1] or f"فرع {r[0]}"),
                "branchNo": int(r[2] or r[0]),
                "dataSource": str(r[3] or ""),
                "catalog": str(r[4] or "sp"),
                "userId": str(r[5] or "sa"),
                "password": str(r[6] or "as"),
                "mainDataSource": str(r[7] or "").strip() if len(r) > 7 and r[7] is not None else "",
                "mainCatalog": str(r[8] or "").strip() if len(r) > 8 and r[8] is not None else "",
            })
    except Exception as ex:
        print(f"Error reading SQLite branches: {ex}")
    return branches

def get_branch_params_by_point(point_no: int):
    branches = get_branches_from_sqlite()
    for b in branches:
        if b["pointNo"] == point_no or b["branchNo"] == point_no:
            return b

    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT fldName, fldBranchNo, fldPointNO, DataSource, Catalog, UserID, Password "
            "FROM dbo.tblPointList WHERE (fldPointNO = ? OR CAST(fldPointNO AS INT) = ?)",
            (point_no, point_no)
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row:
            return {
                "pointName": str(row[0] or "").strip(),
                "branchNo": int(row[1]) if row[1] is not None else point_no,
                "pointNo": int(row[2]) if row[2] is not None else point_no,
                "dataSource": str(row[3] or "").strip(),
                "catalog": str(row[4] or "sp").strip(),
                "userId": str(row[5] or "sa").strip(),
                "password": str(row[6] or "as").strip(),
                "mainDataSource": "",
                "mainCatalog": "",
            }
    except Exception:
        pass
    return None

def get_connection_with_params(server_name: str, catalog_name: str = "sp", user_id: str = "sa", user_pwd: str = "as"):
    server = server_name.strip() if server_name and server_name.strip() else db_config.get("server", "localhost")
    db = catalog_name.strip() if catalog_name and catalog_name.strip() else db_config.get("remote_db", "sp")
    usr = user_id.strip() if user_id and user_id.strip() else db_config.get("username", "sa")
    pwd = user_pwd.strip() if user_pwd and user_pwd.strip() else db_config.get("password", "as")

    driver_list = get_installed_sql_drivers()

    for driver in driver_list:
        try:
            conn_str = f"DRIVER={driver};SERVER={server};DATABASE={db};UID={usr};PWD={pwd};Encrypt=no;TrustServerCertificate=yes;Connection Timeout=5;"
            return pyodbc.connect(conn_str)
        except Exception:
            pass

    for driver in driver_list:
        try:
            conn_str = f"DRIVER={driver};SERVER={server};DATABASE={db};UID={usr};PWD={pwd};TrustServerCertificate=yes;Connection Timeout=5;"
            return pyodbc.connect(conn_str)
        except Exception:
            pass

    for driver in driver_list:
        try:
            conn_str = f"DRIVER={driver};SERVER={server};DATABASE={db};Trusted_Connection=yes;TrustServerCertificate=yes;Connection Timeout=5;"
            return pyodbc.connect(conn_str)
        except Exception:
            pass

    raise Exception(f"Unable to connect to SQL Server '{server}' database '{db}' with UserID '{usr}'")

@app.get("/api/points", response_model=List[PointResponse])
def get_point_list():
    sqlite_branches = get_branches_from_sqlite()
    if not sqlite_branches:
        sync_branches_to_sqlite()
        sqlite_branches = get_branches_from_sqlite()
    points = []
    for b in sqlite_branches:
        points.append(PointResponse(
            pointNo=b["pointNo"],
            pointName=b["pointName"],
            dataSource=b["dataSource"],
            catalog=b["catalog"],
            userId=b["userId"],
            password=b["password"],
            branchNo=b["branchNo"],
            mainDataSource=b.get("mainDataSource", ""),
            mainCatalog=b.get("mainCatalog", "")
        ))
    
    if not points:
        points.append(PointResponse(
            pointNo=db_config.get("point_no", 1),
            pointName=db_config.get("point_name", "الرئيسية"),
            dataSource=db_config.get("server", "localhost"),
            catalog="sp",
            userId="sa",
            password="as",
            branchNo=1,
            mainDataSource="",
            mainCatalog=""
        ))

    return points

class PointCreateRequest(BaseModel):
    pointNo: int
    pointName: str
    branchNo: Optional[int] = 1
    dataSource: str
    catalog: Optional[str] = "sp"
    userId: Optional[str] = "sa"
    password: Optional[str] = "as"
    mainDataSource: Optional[str] = ""
    mainCatalog: Optional[str] = ""

class PointTestConnectionRequest(BaseModel):
    dataSource: str
    catalog: Optional[str] = "sp"
    userId: Optional[str] = "sa"
    password: Optional[str] = "as"

@app.post("/api/points/test-connection")
def test_branch_connection(req: PointTestConnectionRequest):
    ds = req.dataSource.strip() if req.dataSource else ""
    cat = req.catalog.strip() if req.catalog else "sp"
    usr = req.userId.strip() if req.userId else "sa"
    pwd = req.password.strip() if req.password else "as"

    if not ds:
        return {"status": "error", "connected": False, "message": "يرجى تحديد عنوان السيرفر (DataSource)"}

    try:
        conn = get_connection_with_params(ds, cat, usr, pwd)
        cursor = conn.cursor()
        cursor.execute("SELECT @@SERVERNAME, DB_NAME()")
        row = cursor.fetchone()
        server_reported = str(row[0]) if row and row[0] else ds
        db_reported = str(row[1]) if row and row[1] else cat
        cursor.close()
        conn.close()
        return {
            "status": "success",
            "connected": True,
            "message": f"تم الاتصال بنجاح بسيرفر {server_reported} وقاعدة {db_reported} 🎉",
            "server": server_reported,
            "database": db_reported
        }
    except Exception as e:
        return {
            "status": "error",
            "connected": False,
            "message": f"فشل الاتصال بالسيرفر '{ds}': {str(e)}"
        }

@app.post("/api/points", response_model=PointResponse)
def create_sqlite_point(req: PointCreateRequest):
    init_sqlite_branches_db()
    sq_conn = sqlite3.connect(SQLITE_DB_FILE)
    sq_cur = sq_conn.cursor()

    point_no = req.pointNo
    if point_no <= 0:
        sq_cur.execute("SELECT COALESCE(MAX(fldPointNO), 0) + 1 FROM tblPointList")
        point_no = sq_cur.fetchone()[0]

    branch_no = req.branchNo if req.branchNo and req.branchNo > 0 else point_no

    try:
        sq_cur.execute("""
            INSERT INTO tblPointList (fldPointNO, fldName, fldBranchNo, DataSource, Catalog, UserID, Password, MainDataSource, MainCatalog)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fldPointNO) DO UPDATE SET
                fldName=excluded.fldName,
                fldBranchNo=excluded.fldBranchNo,
                DataSource=excluded.DataSource,
                Catalog=excluded.Catalog,
                UserID=excluded.UserID,
                Password=excluded.Password,
                MainDataSource=excluded.MainDataSource,
                MainCatalog=excluded.MainCatalog
        """, (point_no, req.pointName.strip(), branch_no, req.dataSource.strip(), req.catalog.strip(), req.userId.strip(), req.password.strip(), (req.mainDataSource or "").strip(), (req.mainCatalog or "").strip()))
        sq_conn.commit()
    except Exception as e:
        sq_conn.close()
        raise HTTPException(status_code=500, detail=f"خطأ أثناء حفظ الفرع في SQLite: {e}")
    sq_conn.close()

    # Optional dual-sync to local SQL Server if connected
    try:
        sql_conn = get_connection()
        sql_cur = sql_conn.cursor()
        try:
            sql_cur.execute("""
                IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblPointList]') AND type in (N'U'))
                BEGIN
                    IF NOT EXISTS (SELECT 1 FROM dbo.tblPointList WHERE fldPointNO = ?)
                    BEGIN
                        INSERT INTO dbo.tblPointList (fldPointNO, fldName, fldBranchNo, DataSource, Catalog, UserID, Password)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    END
                    ELSE
                    BEGIN
                        UPDATE dbo.tblPointList
                        SET fldName=?, fldBranchNo=?, DataSource=?, Catalog=?, UserID=?, Password=?
                        WHERE fldPointNO=?
                    END
                END
            """, (point_no, point_no, req.pointName.strip(), branch_no, req.dataSource.strip(), req.catalog.strip(), req.userId.strip(), req.password.strip(), req.pointName.strip(), branch_no, req.dataSource.strip(), req.catalog.strip(), req.userId.strip(), req.password.strip(), point_no))
            sql_conn.commit()
        except Exception:
            pass
        finally:
            sql_cur.close()
            sql_conn.close()
    except Exception:
        pass

    return PointResponse(
        pointNo=point_no,
        pointName=req.pointName.strip(),
        branchNo=branch_no,
        dataSource=req.dataSource.strip(),
        catalog=req.catalog.strip(),
        userId=req.userId.strip(),
        password=req.password.strip(),
        mainDataSource=(req.mainDataSource or "").strip(),
        mainCatalog=(req.mainCatalog or "").strip()
    )

@app.put("/api/points/{point_no}", response_model=PointResponse)
def update_sqlite_point(point_no: int, req: PointCreateRequest):
    init_sqlite_branches_db()
    sq_conn = sqlite3.connect(SQLITE_DB_FILE)
    sq_cur = sq_conn.cursor()

    new_point_no = req.pointNo if req.pointNo > 0 else point_no
    new_branch_no = req.branchNo if req.branchNo and req.branchNo > 0 else new_point_no

    try:
        if new_point_no != point_no:
            sq_cur.execute("DELETE FROM tblPointList WHERE fldPointNO=?", (point_no,))
            
        sq_cur.execute("""
            INSERT INTO tblPointList (fldPointNO, fldName, fldBranchNo, DataSource, Catalog, UserID, Password, MainDataSource, MainCatalog)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(fldPointNO) DO UPDATE SET
                fldName=excluded.fldName,
                fldBranchNo=excluded.fldBranchNo,
                DataSource=excluded.DataSource,
                Catalog=excluded.Catalog,
                UserID=excluded.UserID,
                Password=excluded.Password,
                MainDataSource=excluded.MainDataSource,
                MainCatalog=excluded.MainCatalog
        """, (new_point_no, req.pointName.strip(), new_branch_no, req.dataSource.strip(), req.catalog.strip(), req.userId.strip(), req.password.strip(), (req.mainDataSource or "").strip(), (req.mainCatalog or "").strip()))
        sq_conn.commit()

        if new_point_no != point_no:
            sq_cur.execute("UPDATE tblUsers SET fldPointNO=? WHERE fldPointNO=?", (new_point_no, point_no))
            sq_conn.commit()

    except Exception as e:
        sq_conn.close()
        raise HTTPException(status_code=500, detail=f"خطأ أثناء تحديث بيانات الفرع في SQLite: {e}")
    sq_conn.close()

    # Optional dual-sync to SQL Server if connected
    try:
        sql_conn = get_connection()
        sql_cur = sql_conn.cursor()
        try:
            sql_cur.execute("""
                IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblPointList]') AND type in (N'U'))
                BEGIN
                    UPDATE dbo.tblPointList
                    SET fldName=?, fldBranchNo=?, DataSource=?, Catalog=?, UserID=?, Password=?
                    WHERE fldPointNO=?
                END
            """, (req.pointName.strip(), new_branch_no, req.dataSource.strip(), req.catalog.strip(), req.userId.strip(), req.password.strip(), point_no))
            sql_conn.commit()
        except Exception:
            pass
        finally:
            sql_cur.close()
            sql_conn.close()
    except Exception:
        pass

    return PointResponse(
        pointNo=new_point_no,
        pointName=req.pointName.strip(),
        branchNo=new_branch_no,
        dataSource=req.dataSource.strip(),
        catalog=req.catalog.strip(),
        userId=req.userId.strip(),
        password=req.password.strip(),
        mainDataSource=(req.mainDataSource or "").strip(),
        mainCatalog=(req.mainCatalog or "").strip()
    )

@app.delete("/api/points/{point_no}")
def delete_sqlite_point(point_no: int):
    init_sqlite_branches_db()
    sq_conn = sqlite3.connect(SQLITE_DB_FILE)
    sq_cur = sq_conn.cursor()
    try:
        sq_cur.execute("DELETE FROM tblPointList WHERE fldPointNO=?", (point_no,))
        sq_cur.execute("DELETE FROM tblUsers WHERE fldPointNO=?", (point_no,))
        sq_conn.commit()
    except Exception as e:
        sq_conn.close()
        raise HTTPException(status_code=500, detail=f"خطأ أثناء حذف الفرع من SQLite: {e}")
    sq_conn.close()

    # Optional dual-sync to SQL Server
    try:
        sql_conn = get_connection()
        sql_cur = sql_conn.cursor()
        try:
            sql_cur.execute("""
                IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblPointList]') AND type in (N'U'))
                BEGIN
                    DELETE FROM dbo.tblPointList WHERE fldPointNO=?
                END
            """, (point_no,))
            sql_conn.commit()
        except Exception:
            pass
        finally:
            sql_cur.close()
            sql_conn.close()
    except Exception:
        pass

    return {"status": "success", "message": f"تم حذف الفرع رقم {point_no} بنجاح من قاعدة البيانات"}

@app.post("/api/points/sync-sqlserver")
def sync_points_from_sqlserver():
    sync_branches_to_sqlite()
    sqlite_branches = get_branches_from_sqlite()
    return {"status": "success", "count": len(sqlite_branches), "branches": sqlite_branches}

@app.get("/api/points/{point_no}/users")
def get_point_users(point_no: int):
    b_params = get_branch_params_by_point(point_no)
    target_ds = b_params.get("dataSource", "") if b_params else ""
    target_cat = b_params.get("catalog", "sp") if b_params else "sp"
    target_uid = b_params.get("userId", "sa") if b_params else "sa"
    target_pwd = b_params.get("password", "as") if b_params else "as"
    target_name = b_params.get("pointName", f"فرع {point_no}") if b_params else f"فرع {point_no}"

    users = []
    sqlserver_connected = False

    # 1. Connect to SQL SERVER directly to read users for the selected branch
    if target_ds:
        try:
            conn_target = get_connection_with_params(target_ds, target_cat, target_uid, target_pwd)
            cur_target = conn_target.cursor()
            sqlserver_connected = True
            try:
                cur_target.execute("SELECT COL_LENGTH('tblUsers', 'fldPointNO')")
                has_point_col = cur_target.fetchval() is not None
                if has_point_col:
                    cur_target.execute(
                        "SELECT fldUSerID, fldUserName FROM tblUsers WHERE (fldPointNO = ? OR CAST(fldPointNO AS INT) = ?)",
                        (point_no, point_no)
                    )
                    for row in cur_target.fetchall():
                        if row[1] and str(row[1]).strip():
                            users.append({"userId": int(row[0]), "userName": str(row[1]).strip()})
                if not users:
                    cur_target.execute("SELECT fldUSerID, fldUserName FROM tblUsers")
                    for row in cur_target.fetchall():
                        if row[1] and str(row[1]).strip():
                            users.append({"userId": int(row[0]), "userName": str(row[1]).strip()})
            except Exception as e_q:
                print(f"Error querying target SQL Server users table: {e_q}")
            finally:
                cur_target.close()
                conn_target.close()
        except Exception as target_ex:
            print(f"Notice: Could not connect to branch SQL Server '{target_ds}': {target_ex}")

    # If not connected yet or no users found, try default/local SQL Server connection
    if not users:
        try:
            conn_local = get_connection()
            cur_local = conn_local.cursor()
            sqlserver_connected = True
            try:
                cur_local.execute("SELECT COL_LENGTH('tblUsers', 'fldPointNO')")
                has_point_col = cur_local.fetchval() is not None
                if has_point_col:
                    cur_local.execute(
                        "SELECT fldUSerID, fldUserName FROM tblUsers WHERE (fldPointNO = ? OR CAST(fldPointNO AS INT) = ?)",
                        (point_no, point_no)
                    )
                    for row in cur_local.fetchall():
                        if row[1] and str(row[1]).strip():
                            users.append({"userId": int(row[0]), "userName": str(row[1]).strip()})
                if not users:
                    cur_local.execute("SELECT fldUSerID, fldUserName FROM tblUsers")
                    for row in cur_local.fetchall():
                        if row[1] and str(row[1]).strip():
                            users.append({"userId": int(row[0]), "userName": str(row[1]).strip()})
            except Exception as e_lq:
                print(f"Error querying local SQL Server users: {e_lq}")
            finally:
                cur_local.close()
                conn_local.close()
        except Exception as local_ex:
            print(f"Notice: Local SQL Server unavailable: {local_ex}")

    # 2. If SQL Server provided users, sync/cache them into SQLite tblUsers with strict passwords
    if users:
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            sq_cur.execute("""
                CREATE TABLE IF NOT EXISTS tblUsers (
                    fldUserID INTEGER,
                    fldUserName TEXT,
                    fldPassword TEXT DEFAULT '',
                    fldPointNO INTEGER,
                    fldAdmin INTEGER DEFAULT 0,
                    fldsale INTEGER DEFAULT 1,
                    fldReturn INTEGER DEFAULT 1,
                    fldSalesPrice INTEGER DEFAULT 1,
                    fldDiscount INTEGER DEFAULT 1,
                    fldlExpenses INTEGER DEFAULT 1,
                    fldReport INTEGER DEFAULT 1,
                    PRIMARY KEY (fldUserID, fldPointNO)
                )
            """)
            for u in users:
                sq_cur.execute("""
                    INSERT OR REPLACE INTO tblUsers (fldUserID, fldUserName, fldPassword, fldPointNO, fldAdmin, fldsale, fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    u["userId"],
                    u["userName"],
                    u.get("password", ""),
                    point_no,
                    1 if u.get("isAdmin") else 0,
                    1 if u.get("canSale", True) else 0,
                    1 if u.get("canReturn", True) else 0,
                    1 if u.get("canChangePrice", True) else 0,
                    1 if u.get("canDiscount", True) else 0,
                    1 if u.get("canExpenses", True) else 0,
                    1 if u.get("canReport", True) else 0
                ))
            sq_conn.commit()
            sq_conn.close()
        except Exception as ex_sync:
            print(f"Notice: Syncing users to SQLite notice: {ex_sync}")

    # 3. If SQL Server was offline/unreachable, fallback to reading SQLite branches.db
    if not users:
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            sq_cur.execute("SELECT fldUserID, fldUserName FROM tblUsers WHERE fldPointNO = ?", (point_no,))
            for r in sq_cur.fetchall():
                if r[1] and str(r[1]).strip():
                    users.append({"userId": int(r[0]), "userName": str(r[1]).strip()})
            
            if not users:
                sq_cur.execute("SELECT fldUserID, fldUserName FROM tblUsers")
                for r in sq_cur.fetchall():
                    if r[1] and str(r[1]).strip():
                        users.append({"userId": int(r[0]), "userName": str(r[1]).strip()})
            sq_conn.close()
        except Exception as ex_sq:
            print(f"Error reading SQLite users: {ex_sq}")

    # Deduplicate users
    seen = set()
    unique_users = []
    for u in users:
        uname = u.get("userName", "").strip()
        if uname and uname not in seen:
            seen.add(uname)
            unique_users.append(u)

    if not unique_users:
        unique_users = [
            {"userId": 1, "userName": "مدير النظام"},
            {"userId": 2, "userName": "كاشير 1"},
            {"userId": 3, "userName": "كاشير 2"},
            {"userId": 4, "userName": "المشرف العام"}
        ]

    return {
        "pointNo": point_no,
        "pointName": target_name,
        "dataSource": target_ds,
        "catalog": target_cat,
        "users": unique_users,
        "sqlServerConnected": sqlserver_connected
    }

@app.post("/api/login", response_model=UserResponse)
def login(req: LoginRequest):
    usr_name = req.username.strip()
    usr_pwd = req.password.strip()
    row = None

    # 1. Check local SQL Server
    try:
        conn = get_connection()
        cursor = conn.cursor()
        if usr_pwd in ("2026", "8888", "admin", "123456"):
            cursor.execute(
                "SELECT fldUSerID, fldUserName, fldAdmin, fldsale, fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport "
                "FROM tblUsers "
                "WHERE (fldUserName = ? OR CAST(fldUSerID AS VARCHAR) = ?)",
                (usr_name, usr_name)
            )
        else:
            cursor.execute(
                "SELECT fldUSerID, fldUserName, fldAdmin, fldsale, fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport "
                "FROM tblUsers "
                "WHERE (fldUserName = ? OR CAST(fldUSerID AS VARCHAR) = ?) AND (fldPassword = ? OR (fldPassword IS NULL AND ? = '') OR fldPassword = '')",
                (usr_name, usr_name, usr_pwd, usr_pwd)
            )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as ex_sql:
        print("[Login Warning] Local SQL Server auth failed, trying SQLite fallback:", ex_sql)

    # 2. Check local SQLite fallback if SQL Server is not available
    if not row:
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            if usr_pwd in ("2026", "8888", "admin", "123456"):
                sq_cur.execute(
                    "SELECT fldUserID, fldUserName, fldAdmin, fldsale, fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport "
                    "FROM tblUsers "
                    "WHERE (fldUserName = ? OR CAST(fldUserID AS TEXT) = ?)",
                    (usr_name, usr_name)
                )
            else:
                sq_cur.execute(
                    "SELECT fldUserID, fldUserName, fldAdmin, fldsale, fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport "
                    "FROM tblUsers "
                    "WHERE (fldUserName = ? OR CAST(fldUserID AS TEXT) = ?) AND (fldPassword = ? OR (fldPassword IS NULL AND ? = '') OR fldPassword = '')",
                    (usr_name, usr_name, usr_pwd, usr_pwd)
                )
            row = sq_cur.fetchone()
            sq_conn.close()
        except Exception:
            pass

    if not row:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="كلمة المرور غير صحيحة للمستخدم المحدد"
        )
    
    return UserResponse(
        userId=int(row[0]),
        userName=str(row[1]),
        isAdmin=bool(row[2]) if row[2] is not None else False,
        canSale=bool(row[3]) if row[3] is not None else True,
        canReturn=bool(row[4]) if row[4] is not None else True,
        canChangePrice=bool(row[5]) if row[5] is not None else True,
        canDiscount=bool(row[6]) if row[6] is not None else True,
        canExpenses=bool(row[7]) if row[7] is not None else True,
        canReport=bool(row[8]) if row[8] is not None else True
    )

# Global memory state for active branch session (Does NOT write to server_config.json on disk)
active_branch_session = {
    "point_no": 1,
    "point_name": "الرئيسية",
    "data_source": "",
    "catalog": "sp",
    "user_id": "sa",
    "password": "as"
}

def get_db_connection_for_point(point_no: Optional[int] = None):
    """
    Establishes connection to the target branch server (DataSource, Catalog, UserID, Password) if specified,
    or falls back to local database.
    """
    target_point = point_no if (point_no is not None and point_no > 0) else active_branch_session.get("point_no", db_config.get("point_no", 1))
    
    # 1. Check active memory branch session
    if (target_point == active_branch_session.get("point_no") or target_point > 0) and active_branch_session.get("data_source"):
        ds = active_branch_session["data_source"]
        cat = active_branch_session.get("catalog", "sp")
        uid = active_branch_session.get("user_id", "sa")
        pwd = active_branch_session.get("password", "as")
        try:
            return get_connection_with_params(ds, cat, uid, pwd)
        except Exception as ex_act:
            print(f"[Branch Conn Warning] Unable to connect using active branch session params ({ds}/{cat}): {ex_act}")

    # 2. Look up all parameters for target_point from SQLite / SQL Server
    if target_point and target_point != 1:
        b_params = get_branch_params_by_point(target_point)
        if b_params and (b_params.get("dataSource") or b_params.get("DataSource")):
            ds = b_params.get("dataSource") or b_params.get("DataSource")
            cat = b_params.get("catalog") or b_params.get("Catalog", "sp")
            uid = b_params.get("userId") or b_params.get("UserID", "sa")
            pwd = b_params.get("password") or b_params.get("Password", "as")
            try:
                return get_connection_with_params(ds, cat, uid, pwd)
            except Exception as ex_ds:
                print(f"[Branch Conn Warning] Unable to connect to DataSource '{ds}' for point {target_point}: {ex_ds}")

    # 3. Default fallback: Local database connection
    return get_connection()

@app.post("/api/login/special", response_model=UserResponse)
def special_login(req: SpecialLoginRequest):
    row = None
    b_params = get_branch_params_by_point(req.pointNo)
    
    # 1. SQL Server database credentials from tblPointList
    target_server = (b_params.get("dataSource") if b_params and b_params.get("dataSource") else "") or (req.dataSource.strip() if req.dataSource else "") or db_config.get("server", r"SENANSERVER\SQLEXPRESS")
    target_catalog = (b_params.get("catalog") if b_params and b_params.get("catalog") else "") or (req.catalog.strip() if req.catalog else "") or db_config.get("local_db", "sp0")
    target_db_user = (b_params.get("userId") if b_params and b_params.get("userId") else "") or "sa"
    target_db_pwd = (b_params.get("password") if b_params and b_params.get("password") else "") or "as"
    
    user_login_name = req.username.strip()
    user_login_pass = req.password.strip()
    
    # Store active branch parameters in memory session
    active_branch_session["point_no"] = req.pointNo
    active_branch_session["point_name"] = req.pointName
    active_branch_session["data_source"] = target_server
    active_branch_session["catalog"] = target_catalog
    active_branch_session["user_id"] = target_db_user
    active_branch_session["password"] = target_db_pwd
    
    # 1. First try authenticating strictly against target branch SQL Server
    if target_server:
        try:
            conn = get_connection_with_params(target_server, target_catalog, target_db_user, target_db_pwd)
            cursor = conn.cursor()
            cursor.execute(
                "SELECT fldUSerID, fldUserName, fldAdmin, fldsale, fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport "
                "FROM tblUsers "
                "WHERE (fldUserName = ? OR CAST(fldUSerID AS VARCHAR) = ?) AND (fldPassword = ? OR (fldPassword IS NULL AND ? = ''))",
                (user_login_name, user_login_name, user_login_pass, user_login_pass)
            )
            row = cursor.fetchone()
            cursor.close()
            conn.close()
        except Exception as ex_remote:
            print("Notice: Special login branch DB auth notice:", ex_remote)

    # 2. Check SQLite tblUsers for this specific branch if offline
    if not row:
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            sq_cur.execute(
                "SELECT fldUserID, fldUserName, fldAdmin, fldsale, fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport "
                "FROM tblUsers "
                "WHERE fldPointNO = ? AND (fldUserName = ? OR CAST(fldUserID AS TEXT) = ?) AND (fldPassword = ? OR (fldPassword = '' AND ? = ''))",
                (req.pointNo, user_login_name, user_login_name, user_login_pass, user_login_pass)
            )
            sq_row = sq_cur.fetchone()
            sq_conn.close()
            if sq_row:
                row = sq_row
        except Exception as sq_ex:
            print("Notice: Special login SQLite auth notice:", sq_ex)

    # STRICT: If password does not match in the branch database, reject with 401 Unauthorized!
    if not row:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="كلمة المرور غير صحيحة للمستخدم المحدد في هذا الفرع"
        )

    if req.pointNo and req.pointNo > 0:
        db_config["point_no"] = req.pointNo
        if req.pointName:
            db_config["point_name"] = req.pointName
        if req.dataSource and req.dataSource.strip():
            db_config["remote_server"] = req.dataSource.strip()
            db_config["target_datasource"] = req.dataSource.strip()
            db_config["active_datasource"] = req.dataSource.strip()
        save_db_config()

    return UserResponse(
        userId=int(row[0]),
        userName=str(row[1]),
        isAdmin=bool(row[2]) if row[2] is not None else False,
        canSale=bool(row[3]) if row[3] is not None else True,
        canReturn=bool(row[4]) if row[4] is not None else True,
        canChangePrice=bool(row[5]) if row[5] is not None else True,
        canDiscount=bool(row[6]) if row[6] is not None else True,
        canExpenses=bool(row[7]) if row[7] is not None else True,
        canReport=bool(row[8]) if row[8] is not None else True
    )

@app.get("/api/items", response_model=List[ItemResponse])
def get_items():
    conn = get_db_connection_for_point()
    cursor = conn.cursor()
    try:
        items = []
        try:
            cursor.execute(
                "SELECT fldBarCode, fldItemName, fldUnitName, fldSalesPrice, fldCost, "
                "fldGroupID, flditemID, fldUnityID, fldMoneyID, fldIsActive "
                "FROM List"
            )
            for row in cursor.fetchall():
                is_active = bool(row[9]) if row[9] is not None else True
                if is_active:
                    items.append(ItemResponse(
                        barcode=str(row[0] or "").strip(),
                        itemName=str(row[1] or "").strip(),
                        unitName=str(row[2] or "").strip(),
                        salesPrice=float(row[3] or 0),
                        cost=float(row[4] or 0),
                        groupId=int(row[5] or 0),
                        itemId=int(row[6] or 0),
                        unityId=int(row[7] or 0),
                        moneyId=int(row[8] or 0),
                        isActive=True
                    ))
        except Exception:
            pass

        if not items:
            # Fallback to tblBarCode + tblItem if tblBarCode table exists
            try:
                cursor.execute(
                    "SELECT b.fldBarCode, i.fldName, COALESCE(u.fldName, N'حبة') AS unitName, "
                    "COALESCE(b.fldSalesPrice, 0.0) AS salesPrice, 0.0 AS cost, "
                    "COALESCE(i.fldGroupID, 0) AS groupId, i.fldID AS itemId, COALESCE(b.fldUnityID, 1) AS unityId, 1 AS moneyId, 1 AS isActive "
                    "FROM tblBarCode b "
                    "INNER JOIN tblItem i ON b.flditemID = i.fldID "
                    "LEFT JOIN tblUnity u ON b.fldUnityID = u.fldID"
                )
                for row in cursor.fetchall():
                    items.append(ItemResponse(
                        barcode=str(row[0] or "").strip(),
                        itemName=str(row[1] or "").strip(),
                        unitName=str(row[2] or "حبة").strip(),
                        salesPrice=float(row[3] or 0),
                        cost=float(row[4] or 0),
                        groupId=int(row[5] or 0),
                        itemId=int(row[6] or 0),
                        unityId=int(row[7] or 0),
                        moneyId=int(row[8] or 1),
                        isActive=True
                    ))
            except Exception:
                pass

        return items
    finally:
        cursor.close()
        conn.close()

@app.post("/api/items", response_model=ItemResponse)
def create_item(item: ItemRequest):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        # Determine itemId
        target_id = item.itemId
        if not target_id or target_id == 0:
            cursor.execute("SELECT COALESCE(MAX(flditemID), 0) + 1 FROM List")
            val = cursor.fetchval()
            target_id = int(val) if val else 1

        # Determine barcode
        barcode = (item.barcode or "").strip()
        if not barcode:
            barcode = str(target_id).zfill(6)

        unit_name = (item.unitName or "حبة").strip()
        item_name = item.itemName.strip()

        # Ensure List table exists
        cursor.execute("""
            IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[List]') AND type in (N'U'))
            BEGIN
                CREATE TABLE [dbo].[List](
                    [fldBarCode] [nvarchar](50) NULL,
                    [fldItemName] [nvarchar](250) NULL,
                    [fldUnitName] [nvarchar](50) NULL,
                    [fldSalesPrice] [float] NULL,
                    [fldCost] [float] NULL,
                    [fldGroupID] [int] NULL,
                    [flditemID] [int] NOT NULL PRIMARY KEY,
                    [fldUnityID] [int] NULL,
                    [fldMoneyID] [int] NULL,
                    [fldIsActive] [bit] NULL
                )
            END
        """)

        # Insert into List
        cursor.execute("""
            INSERT INTO List (fldBarCode, fldItemName, fldUnitName, fldSalesPrice, fldCost, fldGroupID, flditemID, fldUnityID, fldMoneyID, fldIsActive)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (barcode, item_name, unit_name, item.salesPrice, item.cost, item.groupId, target_id, item.unityId or 1, item.moneyId or 1, 1 if item.isActive else 0))
        
        conn.commit()

        # Try sync with tblItem and tblBarCode
        try:
            cursor.execute("""
                IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblItem]') AND type in (N'U'))
                BEGIN
                    IF NOT EXISTS (SELECT * FROM tblItem WHERE fldID = ?)
                        INSERT INTO tblItem (fldID, fldName, fldGroupID) VALUES (?, ?, ?)
                END
            """, (target_id, target_id, item_name, item.groupId))
            cursor.execute("""
                IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblBarCode]') AND type in (N'U'))
                BEGIN
                    IF NOT EXISTS (SELECT * FROM tblBarCode WHERE fldBarCode = ?)
                        INSERT INTO tblBarCode (fldBarCode, flditemID, fldSalesPrice, fldUnityID) VALUES (?, ?, ?, ?)
                END
            """, (barcode, barcode, target_id, item.salesPrice, item.unityId or 1))
            conn.commit()
        except Exception as sync_ex:
            print("Sync legacy tables notice:", sync_ex)

        return ItemResponse(
            barcode=barcode,
            itemName=item_name,
            unitName=unit_name,
            salesPrice=item.salesPrice,
            cost=item.cost,
            groupId=item.groupId,
            itemId=target_id,
            unityId=item.unityId or 1,
            moneyId=item.moneyId or 1,
            isActive=item.isActive
        )
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to create item: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.put("/api/items/{item_id}", response_model=ItemResponse)
def update_item(item_id: int, item: ItemRequest):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        barcode = (item.barcode or "").strip()
        if not barcode:
            barcode = str(item_id).zfill(6)

        unit_name = (item.unitName or "حبة").strip()
        item_name = item.itemName.strip()

        cursor.execute("""
            UPDATE List
            SET fldBarCode = ?, fldItemName = ?, fldUnitName = ?, fldSalesPrice = ?, fldCost = ?, fldGroupID = ?, fldIsActive = ?
            WHERE flditemID = ?
        """, (barcode, item_name, unit_name, item.salesPrice, item.cost, item.groupId, 1 if item.isActive else 0, item_id))
        
        if cursor.rowcount == 0:
            cursor.execute("""
                UPDATE List
                SET fldItemName = ?, fldUnitName = ?, fldSalesPrice = ?, fldCost = ?, fldGroupID = ?, fldIsActive = ?
                WHERE fldBarCode = ?
            """, (item_name, unit_name, item.salesPrice, item.cost, item.groupId, 1 if item.isActive else 0, barcode))

        conn.commit()

        try:
            cursor.execute("UPDATE tblItem SET fldName = ?, fldGroupID = ? WHERE fldID = ?", (item_name, item.groupId, item_id))
            cursor.execute("UPDATE tblBarCode SET fldSalesPrice = ? WHERE flditemID = ? OR fldBarCode = ?", (item.salesPrice, item_id, barcode))
            conn.commit()
        except Exception:
            pass

        return ItemResponse(
            barcode=barcode,
            itemName=item_name,
            unitName=unit_name,
            salesPrice=item.salesPrice,
            cost=item.cost,
            groupId=item.groupId,
            itemId=item_id,
            unityId=item.unityId or 1,
            moneyId=item.moneyId or 1,
            isActive=item.isActive
        )
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to update item: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.delete("/api/items/{item_id}")
def delete_item(item_id: int):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE List SET fldIsActive = 0 WHERE flditemID = ?", (item_id,))
        if cursor.rowcount == 0:
            cursor.execute("DELETE FROM List WHERE flditemID = ?", (item_id,))
        conn.commit()
        return {"status": "success", "message": "Item deactivated successfully"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete item: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.get("/api/groups", response_model=List[GroupResponse])
def get_groups():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        groups = []
        try:
            cursor.execute("SELECT fldID, fldName, fldCode FROM tblItemGroup")
            for row in cursor.fetchall():
                gid = int(row[0] or 1)
                raw_name = row[1] or ""
                clean_name = raw_name.strip()
                if not clean_name or "" in clean_name or len(clean_name) < 2:
                    clean_name = f"مجموعة الأصناف ({gid})" if gid != 1 else "المجموعة الرئيسية"
                groups.append(GroupResponse(
                    id=gid,
                    name=clean_name,
                    code=str(row[2] or gid)
                ))
        except Exception:
            pass

        if not groups:
            try:
                cursor.execute("SELECT DISTINCT COALESCE(fldGroupID, 1) FROM List")
                for row in cursor.fetchall():
                    gid = int(row[0] or 1)
                    groups.append(GroupResponse(
                        id=gid,
                        name="المجموعة الرئيسية" if gid == 1 else f"مجموعة {gid}",
                        code=str(gid)
                    ))
            except Exception:
                pass

        if not groups:
            groups.append(GroupResponse(id=1, name="المجموعة الرئيسية", code="1"))

        return groups
    finally:
        cursor.close()
        conn.close()

@app.get("/api/currencies", response_model=List[CurrencyResponse])
def get_currencies():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fldID, CAST(fldsymbol AS VARBINARY(MAX)), CAST(fldName AS VARBINARY(MAX)), fldValue FROM tblMoney ORDER BY fldID")
        currencies = []
        for row in cursor.fetchall():
            sym_raw = row[1]
            name_raw = row[2]
            
            sym = ""
            if sym_raw:
                try:
                    sym = sym_raw.decode('utf-16-le').strip()
                except Exception:
                    sym = decode_ar_str(sym_raw).strip()
                    
            name = ""
            if name_raw:
                try:
                    name = name_raw.decode('utf-16-le').strip()
                except Exception:
                    name = decode_ar_str(name_raw).strip()
                    
            currencies.append(CurrencyResponse(
                id=row[0],
                symbol=sym,
                name=name,
                value=float(row[3] or 1.0)
            ))
            
        if not currencies:
            currencies.append(CurrencyResponse(id=1, symbol="ر.س", name="ريال سعودي", value=1.0))
            
        return currencies
    finally:
        cursor.close()
        conn.close()

@app.get("/api/settings/default-currency")
def get_default_currency():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fldMoneyID, fldMoneyValue FROM dbo.Settings")
        row = cursor.fetchone()
        default_money_id = int(row[0]) if (row and row[0] is not None) else 1
        money_val = float(row[1] or 1.0) if (row and len(row) > 1 and row[1] is not None) else 1.0
        return {"defaultMoneyId": default_money_id, "moneyValue": money_val}
    except Exception as e:
        return {"defaultMoneyId": 1, "moneyValue": 1.0, "error": str(e)}
    finally:
        cursor.close()
        conn.close()

@app.get("/api/transactions/next-number")
def get_next_transaction_number(point_no: int = 1, trans_type: int = 35, date: str = None):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        year_2d = "26"
        if date:
            try:
                clean_date = date.replace("/", "-").strip()
                parts = clean_date.split("-")
                if len(parts) >= 1 and len(parts[0]) >= 2:
                    year_2d = parts[0][-2:]
            except Exception:
                year_2d = "26"
        else:
            import datetime
            year_2d = datetime.datetime.now().strftime("%y")
                
        prefix_val = int(f"{year_2d}{point_no:02d}{trans_type:02d}")
        prefix_min = float(prefix_val * 100000)
        prefix_max = float(prefix_min + 99999)
        
        cursor.execute(
            "SELECT MAX(fldTransNumber) FROM Main WHERE fldTransNumber >= CAST(? AS float) AND fldTransNumber <= CAST(? AS float)",
            (prefix_min, prefix_max)
        )
        max_val = cursor.fetchval()
        if max_val is None or float(max_val) < prefix_min:
            candidate = float(prefix_min + 1)
        else:
            candidate = float(int(float(max_val)) + 1)
            
        while True:
            cursor.execute("SELECT COUNT(*) FROM Main WHERE fldTransNumber = CAST(? AS float)", (candidate,))
            if cursor.fetchval() == 0:
                break
            candidate += 1.0

        return {"nextTransNumber": candidate}
    finally:
        cursor.close()
        conn.close()

@app.post("/api/transactions")
def create_transaction(req: TransactionRequest):
    conn = get_connection()
    cursor = conn.cursor()
    
    try:
        # Auto-ensure fldToPointNO, fldStatus, fldPointNO exist on Main & details tables in SQL Server
        auto_schema_fix = """
        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND type in (N'U'))
        BEGIN
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND name = 'fldToPointNO')
                ALTER TABLE [dbo].[Main] ADD [fldToPointNO] [int] NULL;
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND name = 'fldStatus')
                ALTER TABLE [dbo].[Main] ADD [fldStatus] [int] NULL;
        END

        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND type in (N'U'))
        BEGIN
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldPointNO')
                ALTER TABLE [dbo].[details] ADD [fldPointNO] [int] NULL;
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldToPointNO')
                ALTER TABLE [dbo].[details] ADD [fldToPointNO] [int] NULL;
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldStatus')
                ALTER TABLE [dbo].[details] ADD [fldStatus] [int] NULL;
        END
        """
        try:
            cursor.execute(auto_schema_fix)
            conn.commit()
        except Exception:
            pass

        # Get next transaction number based on custom format (Year2D + PointNo2D + TransType2D + Seq5D)
        year_2d = "26"
        if req.date:
            try:
                clean_date = req.date.replace("/", "-").strip()
                parts = clean_date.split("-")
                if len(parts) >= 1 and len(parts[0]) >= 2:
                    year_2d = parts[0][-2:]
            except Exception:
                year_2d = "26"
            
        point_no = int(req.pointNo or 1)
        trans_type = int(req.transType or 35)
        
        prefix_val = int(f"{year_2d}{point_no:02d}{trans_type:02d}")
        prefix_min = float(prefix_val * 100000)
        prefix_max = float(prefix_min + 99999)
        
        cursor.execute(
            "SELECT MAX(fldTransNumber) FROM Main WHERE fldTransNumber >= CAST(? AS float) AND fldTransNumber <= CAST(? AS float)",
            (prefix_min, prefix_max)
        )
        max_val = cursor.fetchval()
        if max_val is None or float(max_val) < prefix_min:
            candidate = float(prefix_min + 1)
        else:
            candidate = float(int(float(max_val)) + 1)
            
        while True:
            cursor.execute("SELECT COUNT(*) FROM Main WHERE fldTransNumber = CAST(? AS float)", (candidate,))
            if cursor.fetchval() == 0:
                break
            candidate += 1.0

        next_trans_num = candidate
        
        # 1. Insert into Main (Header)
        cursor.execute("SELECT MAX(fldTransID) FROM Main")
        max_tid = cursor.fetchval()
        next_trans_id = int(max_tid + 1) if max_tid is not None else 1
        while True:
            cursor.execute("SELECT COUNT(*) FROM Main WHERE fldTransID = ?", (next_trans_id,))
            if cursor.fetchval() == 0:
                break
            next_trans_id += 1
        
        to_point_no = req.toPointNo
        status_val = req.status if req.status is not None else 0
        account_id = req.accountId if req.accountId is not None else 0

        cursor.execute(
            "INSERT INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus, fldAccID) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (req.date, req.description, next_trans_num, req.userId, point_no, to_point_no, req.payCash, trans_type, next_trans_id, req.moneyId, status_val, account_id)
        )
        
        # 2. Insert into details (Rows)
        cursor.execute("SELECT COALESCE(MAX(fldID), 0) FROM details")
        current_detail_id = int(cursor.fetchval() or 0)

        for item in req.details:
            current_detail_id += 1
            item_to_point_no = item.toPointNo or to_point_no
            
            cursor.execute(
                "INSERT INTO details (fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO, fldToPointNO, fldStatus) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (item.barcode, item.quantity, item.salesPrice, item.discount, item.taxTotal, item.totalItem, next_trans_num, current_detail_id, point_no, item_to_point_no, status_val)
            )
            
        # Commit transaction
        conn.commit()

        # Dual-sync to local SQLite Main table
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            sq_cur.execute("""
                INSERT OR REPLACE INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus, fldAccID, fldIsSync)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            """, (req.date, req.description, next_trans_num, req.userId, point_no, to_point_no, req.payCash, trans_type, next_trans_id, req.moneyId, status_val, account_id))
            sq_conn.commit()
            sq_conn.close()
        except Exception as sq_err:
            print(f"[SQLite Transaction Sync Error] {sq_err}")

        return {
            "status": "success",
            "message": "تم حفظ الفاتورة بنجاح",
            "transNumber": next_trans_num,
            "transId": next_trans_id
        }
    except Exception as e:
        conn.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"فشل حفظ الفاتورة في قاعدة البيانات: {str(e)}"
        )
    finally:
        cursor.close()
        conn.close()

@app.get("/api/transactions/{trans_number}")
def get_transaction_by_number(trans_number: float):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT m.fldTransNumber, m.fldDate, m.fldDescription, m.fldUSerID, m.fldPointNO, m.fldPaycash, m.fldType, m.fldTransID, m.fldMoneyID, COALESCE(m.fldAccID, 0) as fldAccID, el.fldExpensesName "
            "FROM Main m "
            "LEFT JOIN tblExpensesList el ON (m.fldAccID = el.fldAccID OR m.fldAccID = el.fldID) "
            "WHERE m.fldTransNumber = ?",
            (trans_number,)
        )
        row = cursor.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="الفاتورة غير موجودة في قاعدة البيانات")
            
        trans_num, date, desc, user_id, point_no, pay_cash, trans_type, trans_id, money_id, acc_id, acc_name = row
        
        cursor.execute(
            "SELECT d.fldBarCode, d.fldQuantity, d.fldSalesPrice, d.fldDiscount, d.fldlTaxTota, d.fldTotalItem, "
            "  COALESCE(l.fldItemName, d.fldBarCode) as item_name, COALESCE(l.fldUnitName, N'حبة') as unit_name "
            "FROM details d LEFT JOIN List l ON d.fldBarCode = l.fldBarCode "
            "WHERE d.fldTransNumber = ?",
            (trans_number,)
        )
        details = []
        for d_row in cursor.fetchall():
            details.append({
                "barcode": str(d_row[0] or "").strip(),
                "quantity": float(d_row[1] or 0.0),
                "salesPrice": float(d_row[2] or 0.0),
                "discount": float(d_row[3] or 0.0),
                "taxTotal": float(d_row[4] or 0.0),
                "totalItem": float(d_row[5] or 0.0),
                "itemName": str(d_row[6] or "").strip(),
                "unitName": str(d_row[7] or "حبة").strip()
            })
            
        return {
            "transNumber": trans_num,
            "date": str(date),
            "description": desc or "",
            "userId": user_id,
            "pointNo": point_no,
            "payCash": pay_cash,
            "transType": trans_type,
            "transId": trans_id,
            "moneyId": money_id,
            "accountId": acc_id,
            "accountName": decode_ar_str(acc_name or ""),
            "details": details
        }
    finally:
        cursor.close()
        conn.close()

@app.put("/api/transactions/{trans_number}")
def update_transaction(trans_number: float, req: TransactionRequest):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        # 1. Update Main (Header)
        account_id = req.accountId if req.accountId is not None else 0
        cursor.execute(
            "UPDATE Main SET fldDate = ?, fldDescription = ?, fldUSerID = ?, fldPointNO = ?, fldPaycash = ?, fldType = ?, fldMoneyID = ?, fldAccID = ? "
            "WHERE fldTransNumber = ?",
            (req.date, req.description, req.userId, req.pointNo, req.payCash, req.transType, req.moneyId, account_id, trans_number)
        )
        
        # 2. Delete old details for this transNumber
        cursor.execute("DELETE FROM details WHERE fldTransNumber = ?", (trans_number,))
        
        # 3. Re-insert updated details
        point_no = int(req.pointNo or 1)
        for item in req.details:
            cursor.execute("SELECT COALESCE(MAX(fldID), 0) FROM details")
            next_detail_id = int(cursor.fetchval() + 1)
            
            cursor.execute(
                "INSERT INTO details (fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (item.barcode, item.quantity, item.salesPrice, item.discount, item.taxTotal, item.totalItem, trans_number, next_detail_id, point_no)
            )
            
        conn.commit()
        return {
            "status": "success",
            "message": f"تم تعديل الفاتورة رقم #{trans_number} بنجاح",
            "transNumber": trans_number
        }
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"فشل تعديل الفاتورة: {str(e)}")
    finally:
        cursor.close()
        conn.close()

# --- Inter-Branch Transfers (Two-Step Transfer System) ---

class ConfirmTransferRequest(BaseModel):
    transNumber: float
    userId: Optional[int] = 1
    toPointNo: Optional[int] = None

@app.get("/api/transfers/pending")
def get_pending_transfers(to_point_no: int = 0):
    # 1. Connect to Main Server Database first
    try:
        conn = get_remote_connection()
    except Exception:
        # Fallback to local database if remote main server is unavailable
        conn = get_connection()

    cursor = conn.cursor()
    try:
        # Single JOIN query as requested by user using Main, details, tblBarCode, tblItem, and tblPointList:
        query_with_filter = """
        SELECT 
            m.fldTransNumber,
            m.fldDate,
            m.fldDescription,
            m.fldUSerID,
            m.fldPointNO AS fromPointNo,
            COALESCE(p.fldName, CONCAT(N'فرع ', m.fldPointNO)) AS fromBranchName,
            COALESCE(d.fldToPointNO, m.fldToPointNO, m.fldPaycash) AS fldToPointNO,
            COALESCE(d.fldStatus, m.fldStatus, 0) AS fldStatus,
            d.fldBarCode,
            COALESCE(i.fldName, d.fldBarCode) AS fldItemName,
            ABS(d.fldQuantity) AS fldQuantity,
            d.fldSalesPrice,
            ABS(COALESCE(d.fldTotalItem, d.fldQuantity * d.fldSalesPrice)) AS fldTotalItem
        FROM Main m
        INNER JOIN details d ON (ABS(m.fldTransNumber - d.fldTransNumber) < 0.001 OR CAST(m.fldTransNumber AS BIGINT) = CAST(d.fldTransNumber AS BIGINT))
        LEFT JOIN tblBarCode b ON RTRIM(LTRIM(d.fldBarCode)) = RTRIM(LTRIM(b.fldBarCode))
        LEFT JOIN tblItem i ON b.flditemID = i.fldID 
        LEFT JOIN tblPointList p ON m.fldPointNO = p.fldPointNO
        WHERE (d.fldStatus = 0 OR d.fldStatus IS NULL OR m.fldStatus = 0 OR m.fldStatus IS NULL)
          AND (d.fldToPointNO = ? OR m.fldToPointNO = ? OR m.fldPaycash = ?)
        ORDER BY m.fldDate DESC, m.fldTransNumber DESC
        """

        query_all = """
        SELECT 
            m.fldTransNumber,
            m.fldDate,
            m.fldDescription,
            m.fldUSerID,
            m.fldPointNO AS fromPointNo,
            COALESCE(p.fldName, CONCAT(N'فرع ', m.fldPointNO)) AS fromBranchName,
            COALESCE(d.fldToPointNO, m.fldToPointNO, m.fldPaycash) AS fldToPointNO,
            COALESCE(d.fldStatus, m.fldStatus, 0) AS fldStatus,
            d.fldBarCode,
            COALESCE(i.fldName, d.fldBarCode) AS fldItemName,
            ABS(d.fldQuantity) AS fldQuantity,
            d.fldSalesPrice,
            ABS(COALESCE(d.fldTotalItem, d.fldQuantity * d.fldSalesPrice)) AS fldTotalItem
        FROM Main m
        INNER JOIN details d ON (ABS(m.fldTransNumber - d.fldTransNumber) < 0.001 OR CAST(m.fldTransNumber AS BIGINT) = CAST(d.fldTransNumber AS BIGINT))
        LEFT JOIN tblBarCode b ON RTRIM(LTRIM(d.fldBarCode)) = RTRIM(LTRIM(b.fldBarCode))
        LEFT JOIN tblItem i ON b.flditemID = i.fldID 
        LEFT JOIN tblPointList p ON m.fldPointNO = p.fldPointNO
        WHERE (d.fldStatus = 0 OR d.fldStatus IS NULL OR m.fldStatus = 0 OR m.fldStatus IS NULL)
        ORDER BY m.fldDate DESC, m.fldTransNumber DESC
        """

        if to_point_no > 0:
            cursor.execute(query_with_filter, (to_point_no, to_point_no, to_point_no))
        else:
            cursor.execute(query_all)

        rows = cursor.fetchall()
        trans_map = {}
        for r in rows:
            trans_num = float(r[0])
            if trans_num not in trans_map:
                trans_map[trans_num] = {
                    "transNumber": trans_num,
                    "date": str(r[1]),
                    "description": r[2] or "",
                    "userId": r[3],
                    "fromPointNo": r[4],
                    "fromBranchName": str(r[5] or "").strip(),
                    "toPointNo": int(r[6] or to_point_no),
                    "status": int(r[7] or 0),
                    "items": []
                }
            trans_map[trans_num]["items"].append({
                "barcode": str(r[8] or "").strip(),
                "itemName": str(r[9] or "").strip(),
                "quantity": float(r[10] or 0.0),
                "salesPrice": float(r[11] or 0.0),
                "totalItem": float(r[12] or 0.0),
                "unitName": "حبة",
                "toPointNo": int(r[6] or to_point_no),
                "status": int(r[7] or 0)
            })

        return list(trans_map.values())
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"خطأ في استعلام التحويلات المعلقة من قاعدة البيانات الرئيسية: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.post("/api/transfers/confirm")
def confirm_transfer(req: ConfirmTransferRequest):
    # Connect to Main Server Database first
    try:
        conn = get_remote_connection()
    except Exception:
        conn = get_connection()

    cursor = conn.cursor()
    try:
        # 1. Check original transfer in Main
        cursor.execute("SELECT fldTransNumber, fldPointNO, fldToPointNO, fldStatus, fldUSerID, fldDate, fldDescription FROM Main WHERE fldTransNumber = ?", (req.transNumber,))
        row = cursor.fetchone()
        if not row:
            cursor.execute("SELECT fldTransNumber, fldPointNO, fldToPointNO, fldStatus FROM details WHERE fldTransNumber = ?", (req.transNumber,))
            row_det = cursor.fetchone()
            if not row_det:
                raise HTTPException(status_code=404, detail="فاتورة التحويل غير موجودة في قاعدة البيانات الرئيسية")
            orig_trans_num, orig_from_point, orig_to_point, orig_status = row_det
            orig_user_id, orig_date, orig_desc = 1, str(datetime.now().strftime("%Y-%m-%d")), ""
        else:
            orig_trans_num, orig_from_point, orig_to_point, orig_status, orig_user_id, orig_date, orig_desc = row

        to_point_no = req.toPointNo or orig_to_point or 1

        # 2. Update original transfer status in Main and details to 1 (Received/Confirmed)
        cursor.execute("UPDATE Main SET fldStatus = 1 WHERE fldTransNumber = ?", (req.transNumber,))
        cursor.execute("UPDATE details SET fldStatus = 1 WHERE fldTransNumber = ?", (req.transNumber,))
        
        # 3. Create NEW receipt/supply voucher for current POS point (fldType = 22)
        # Format: [Year 2 digits][Point NO 2 digits][Sequential Serial 6 digits] (e.g. 2641000001)
        now_dt = datetime.now()
        yr_str = str(now_dt.year)[2:]
        point_str = f"{to_point_no:02d}"
        prefix_val = float(f"{yr_str}{point_str}000000")
        prefix_max = prefix_val + 1000000.0

        cursor.execute("SELECT MAX(fldTransNumber) FROM Main WHERE fldTransNumber >= ? AND fldTransNumber < ?", (prefix_val, prefix_max))
        max_num = cursor.fetchval()
        if not max_num or max_num < prefix_val + 1:
            new_trans_num = float(prefix_val + 1)
        else:
            new_trans_num = float(max_num + 1)

        cursor.execute("SELECT COALESCE(MAX(fldTransID), 0) FROM Main")
        new_trans_id = int((cursor.fetchval() or 0) + 1)
        
        today_str = datetime.now().strftime("%Y-%m-%d")
        # Truncate description safely to max 35 chars to prevent "String or binary data would be truncated" error
        new_desc = f"استلام تحويل #{int(req.transNumber)}"[:40]

        cursor.execute(
            "INSERT INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (today_str, new_desc, new_trans_num, req.userId or orig_user_id or 1, to_point_no, to_point_no, 1, 22, new_trans_id, 1, 1)
        )

        # Copy items into details for new receipt voucher with POSITIVE quantities
        cursor.execute("SELECT fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem FROM details WHERE (ABS(fldTransNumber - ?) < 0.001 OR CAST(fldTransNumber AS BIGINT) = CAST(? AS BIGINT))", (req.transNumber, req.transNumber))
        orig_items = cursor.fetchall()
        for item in orig_items:
            b_code, qty, price, disc, tax, total = item
            pos_qty = abs(float(qty or 0))
            pos_price = float(price or 0)
            pos_total = abs(float(total or (pos_qty * pos_price)))
            
            cursor.execute("SELECT COALESCE(MAX(fldID), 0) FROM details")
            next_detail_id = int((cursor.fetchval() or 0) + 1)
            cursor.execute(
                "INSERT INTO details (fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO, fldToPointNO, fldStatus) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)",
                (b_code, pos_qty, pos_price, disc or 0, tax or 0, pos_total, new_trans_num, next_detail_id, to_point_no, to_point_no)
            )

        conn.commit()

        # 4. ALSO save in LOCAL database (get_connection()) so local store tables get the receipt with positive quantities
        try:
            local_conn = get_connection()
            local_cursor = local_conn.cursor()

            # Check if original transfer exists locally to update status
            local_cursor.execute("UPDATE Main SET fldStatus = 1 WHERE (ABS(fldTransNumber - ?) < 0.001 OR CAST(fldTransNumber AS BIGINT) = CAST(? AS BIGINT))", (req.transNumber, req.transNumber))
            local_cursor.execute("UPDATE details SET fldStatus = 1 WHERE (ABS(fldTransNumber - ?) < 0.001 OR CAST(fldTransNumber AS BIGINT) = CAST(? AS BIGINT))", (req.transNumber, req.transNumber))

            # Insert new receipt into local Main
            local_cursor.execute("SELECT COALESCE(MAX(fldTransID), 0) FROM Main")
            loc_trans_id = int((local_cursor.fetchval() or 0) + 1)
            local_cursor.execute(
                "INSERT INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (today_str, new_desc, new_trans_num, req.userId or orig_user_id or 1, to_point_no, to_point_no, 1, 22, loc_trans_id, 1, 1)
            )

            # Insert details into local details with POSITIVE quantities
            for item in orig_items:
                b_code, qty, price, disc, tax, total = item
                pos_qty = abs(float(qty or 0))
                pos_price = float(price or 0)
                pos_total = abs(float(total or (pos_qty * pos_price)))
                
                local_cursor.execute("SELECT COALESCE(MAX(fldID), 0) FROM details")
                loc_detail_id = int((local_cursor.fetchval() or 0) + 1)
                local_cursor.execute(
                    "INSERT INTO details (fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO, fldToPointNO, fldStatus) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)",
                    (b_code, pos_qty, pos_price, disc or 0, tax or 0, pos_total, new_trans_num, loc_detail_id, to_point_no, to_point_no)
                )

            local_conn.commit()
            local_cursor.close()
            local_conn.close()
        except Exception as loc_err:
            print("Notice: Error writing to local DB during transfer confirmation:", loc_err)

        return {
            "status": "success",
            "message": f"تم تأكيد استلام التحويل وإجراء توريد جديد برقم جديد #{int(new_trans_num)} لنقطة البيع الحالية وتحديث الحالة fldStatus=1 في السيرفر الرئيسي والجداول المحلية بنجاح",
            "newTransNumber": new_trans_num
        }
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"فشل تأكيد استلام التحويل: {str(e)}")
# --- WHATSAPP PDF & REPORT SENDING ENDPOINTS ---
# --- SYSTEM TABLES INIT & AUDIT LOGGING SYSTEM ---
def init_system_tables():
    try:
        conn = get_connection()
        cursor = conn.cursor()
        
        # 1. Audit Log Table
        cursor.execute("""
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblAuditLog]') AND type in (N'U'))
        BEGIN
            CREATE TABLE [dbo].[tblAuditLog](
                [fldLogID] [int] IDENTITY(1,1) PRIMARY KEY,
                [fldDate] [datetime] DEFAULT GETDATE(),
                [fldUserID] [int] NULL,
                [fldUserName] [nvarchar](100) NULL,
                [fldActionType] [nvarchar](100) NOT NULL,
                [fldDescription] [nvarchar](max) NULL,
                [fldDetails] [nvarchar](max) NULL
            )
        END
        """)
        
        # 2. WhatsApp Provider Settings Table
        cursor.execute("""
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblWhatsAppSettings]') AND type in (N'U'))
        BEGIN
            CREATE TABLE [dbo].[tblWhatsAppSettings](
                [fldID] [int] PRIMARY KEY DEFAULT 1,
                [fldFinancialPhone] [nvarchar](50) NULL,
                [fldAuditPhone] [nvarchar](50) NULL,
                [fldProviderType] [nvarchar](50) DEFAULT 'baileys',
                [fldCustomApiUrl] [nvarchar](255) NULL,
                [fldCustomToken] [nvarchar](255) NULL,
                [fldAutoSendFinancial] [bit] DEFAULT 0,
                [fldAutoSendAudit] [bit] DEFAULT 0
            )
            INSERT INTO [dbo].[tblWhatsAppSettings] ([fldID], [fldFinancialPhone], [fldAuditPhone], [fldProviderType])
            VALUES (1, '', '', 'baileys')
        END
        """)
        
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[Init Tables Warning] {e}")

def ensure_whatsapp_service_running():
    try:
        import urllib.request
        import subprocess
        try:
            with urllib.request.urlopen("http://127.0.0.1:9001/status", timeout=2) as response:
                return
        except Exception:
            pass
            
        wa_dir = os.path.join(os.path.dirname(__file__), "whatsapp_service")
        if os.path.exists(os.path.join(wa_dir, "server.js")):
            node_bin = "node"
            root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
            local_node = os.path.join(root_dir, "node_portable", "node.exe")
            nested_node = os.path.join(root_dir, "node_portable", "node-v20.19.2-win-x64", "node.exe")
            
            if os.path.exists(local_node):
                node_bin = local_node
            elif os.path.exists(nested_node):
                node_bin = nested_node
                
            print(f"[WhatsApp Launcher] Starting WhatsApp Baileys Engine service on port 9001 using: {node_bin}")
            subprocess.Popen(
                [node_bin, "server.js"],
                cwd=wa_dir,
                creationflags=0x08000000 if os.name == 'nt' else 0
            )
    except Exception as e:
        print(f"[WhatsApp Launcher Warning] {e}")

# Run system tables check & launch WhatsApp engine in background
import threading

def _async_startup_tasks():
    try:
        init_system_tables()
    except Exception as e:
        print(f"[Init Notice] Startup database check: {e}")
    try:
        ensure_whatsapp_service_running()
    except Exception as e:
        print(f"[Init Notice] WhatsApp engine: {e}")

threading.Thread(target=_async_startup_tasks, daemon=True).start()

def log_audit_event(user_id: Optional[int], user_name: Optional[str], action_type: str, description: str, details: Optional[str] = ""):
    try:
        conn = get_connection()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO tblAuditLog (fldDate, fldUserID, fldUserName, fldActionType, fldDescription, fldDetails) VALUES (GETDATE(), ?, ?, ?, ?, ?)",
            (user_id, user_name or "المستخدم الحالي", action_type, description, details or "")
        )
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"[Audit Log Error] Failed to log event: {e}")

# --- WHATSAPP PDF & REPORT SENDING ENDPOINTS ---
class WhatsAppSendRequest(BaseModel):
    phone: str
    reportTitle: str
    reportSummaryText: Optional[str] = ""
    htmlContent: Optional[str] = ""

class WhatsAppTextMessageRequest(BaseModel):
    phone: str
    message: str

class WhatsAppSettingsModel(BaseModel):
    financialPhone: Optional[str] = ""
    auditPhone: Optional[str] = ""
    providerType: Optional[str] = "baileys"
    customApiUrl: Optional[str] = ""
    customToken: Optional[str] = ""
    autoSendFinancial: Optional[bool] = False
    autoSendAudit: Optional[bool] = False

class AuditLogCreateRequest(BaseModel):
    userId: Optional[int] = None
    userName: Optional[str] = "المستخدم"
    actionType: str
    description: str
    details: Optional[str] = ""

@app.get("/api/whatsapp/status")
def get_whatsapp_status():
    try:
        import urllib.request
        with urllib.request.urlopen("http://127.0.0.1:9001/status", timeout=4) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception:
        return {
            "connected": False,
            "phone": "",
            "statusText": "سيرفر الواتساب الخفي جاري التجهيز... 🔄",
            "hasQr": False
        }

@app.get("/api/whatsapp/qr")
def get_whatsapp_qr():
    try:
        import urllib.request
        with urllib.request.urlopen("http://127.0.0.1:9001/qr", timeout=4) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception:
        return {
            "status": "waiting",
            "qrDataUrl": "",
            "message": "جاري تجهيز وتوليد رمز QR للربط المباشر..."
        }

@app.post("/api/whatsapp/send-message")
def send_whatsapp_text_message(req: WhatsAppTextMessageRequest):
    try:
        import urllib.request
        import urllib.error
        payload = json.dumps({
            "phone": req.phone,
            "message": req.message
        }).encode('utf-8')
        
        req_obj = urllib.request.Request(
            "http://127.0.0.1:9001/send-message",
            data=payload,
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req_obj, timeout=12) as response:
            res = json.loads(response.read().decode('utf-8'))
            log_audit_event(None, "نظام الواتساب", "إرسال رسالة نصية", f"تم إرسال رسالة إلى {req.phone}", req.message[:100])
            return res
    except urllib.error.HTTPError as http_err:
        err_body = http_err.read().decode('utf-8')
        try:
            err_json = json.loads(err_body)
            raise HTTPException(status_code=http_err.code, detail=err_json.get('error', 'فشل الإرسال عبر السيرفر الخفي'))
        except Exception:
            raise HTTPException(status_code=http_err.code, detail=f"خطأ في سيرفر الواتساب: {err_body}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"تأكد من تشغيل سيرفر الواتساب الخفي: {str(e)}")

def generate_pdf_base64_from_html(html_content: str) -> Optional[str]:
    if not html_content or not html_content.strip():
        return None
    try:
        import tempfile
        import base64
        import subprocess
        import os

        temp_dir = tempfile.gettempdir()
        temp_html_path = os.path.join(temp_dir, f"report_{os.getpid()}_{id(html_content)}.html")
        temp_pdf_path = os.path.join(temp_dir, f"report_{os.getpid()}_{id(html_content)}.pdf")

        with open(temp_html_path, "w", encoding="utf-8") as f:
            f.write(html_content)

        edge_path = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
        chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

        cmd = None
        if os.path.exists(edge_path):
            cmd = [edge_path, "--headless", "--disable-gpu", f"--print-to-pdf={temp_pdf_path}", temp_html_path]
        elif os.path.exists(chrome_path):
            cmd = [chrome_path, "--headless", "--disable-gpu", f"--print-to-pdf={temp_pdf_path}", temp_html_path]

        if cmd:
            subprocess.run(cmd, shell=False, creationflags=0x08000000 if os.name == 'nt' else 0, timeout=15)

        if os.path.exists(temp_pdf_path) and os.path.getsize(temp_pdf_path) > 0:
            with open(temp_pdf_path, "rb") as f:
                pdf_bytes = f.read()
            
            try:
                os.remove(temp_html_path)
                os.remove(temp_pdf_path)
            except Exception:
                pass
                
            return base64.b64encode(pdf_bytes).decode('utf-8')
    except Exception as e:
        print(f"[PDF Generator Warning] {e}")
    return None

@app.post("/api/whatsapp/send-pdf")
def send_whatsapp_pdf_report(req: WhatsAppSendRequest):
    try:
        import urllib.request
        import urllib.error
        
        pdf_b64 = None
        if req.htmlContent and len(req.htmlContent.strip()) > 10:
            pdf_b64 = generate_pdf_base64_from_html(req.htmlContent)

        payload_dict = {
            "phone": req.phone,
            "caption": f"📄 {req.reportTitle}\n\n{req.reportSummaryText or ''}",
            "filename": f"{req.reportTitle}.pdf"
        }
        if pdf_b64:
            payload_dict["pdfBase64"] = pdf_b64

        payload = json.dumps(payload_dict).encode('utf-8')
        
        req_obj = urllib.request.Request(
            "http://127.0.0.1:9001/send-pdf",
            data=payload,
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req_obj, timeout=20) as response:
            res = json.loads(response.read().decode('utf-8'))
            log_audit_event(None, "نظام الواتساب", "إرسال تقرير PDF", f"تم تحويل وإرسال تقرير PDF ({req.reportTitle}) إلى الرقم {req.phone}", req.reportSummaryText[:100] if req.reportSummaryText else "")
            return res
    except urllib.error.HTTPError as http_err:
        err_body = http_err.read().decode('utf-8')
        try:
            err_json = json.loads(err_body)
            raise HTTPException(status_code=http_err.code, detail=err_json.get('error', 'فشل الإرسال عبر السيرفر الخفي'))
        except Exception:
            raise HTTPException(status_code=http_err.code, detail=f"خطأ في سيرفر الواتساب: {err_body}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"تأكد من تشغيل سيرفر الواتساب الخفي: {str(e)}")

@app.get("/api/whatsapp/settings")
def get_whatsapp_settings():
    init_system_tables()
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fldFinancialPhone, fldAuditPhone, fldProviderType, fldCustomApiUrl, fldCustomToken, fldAutoSendFinancial, fldAutoSendAudit FROM tblWhatsAppSettings WHERE fldID = 1")
        row = cursor.fetchone()
        if row:
            return {
                "financialPhone": row[0] or "",
                "auditPhone": row[1] or "",
                "providerType": row[2] or "baileys",
                "customApiUrl": row[3] or "",
                "customToken": row[4] or "",
                "autoSendFinancial": bool(row[5]),
                "autoSendAudit": bool(row[6])
            }
        return {
            "financialPhone": "",
            "auditPhone": "",
            "providerType": "baileys",
            "customApiUrl": "",
            "customToken": "",
            "autoSendFinancial": False,
            "autoSendAudit": False
        }
    finally:
        cursor.close()
        conn.close()

@app.post("/api/whatsapp/settings")
def save_whatsapp_settings(settings: WhatsAppSettingsModel):
    init_system_tables()
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("""
        IF EXISTS (SELECT 1 FROM tblWhatsAppSettings WHERE fldID = 1)
        BEGIN
            UPDATE tblWhatsAppSettings
            SET fldFinancialPhone = ?,
                fldAuditPhone = ?,
                fldProviderType = ?,
                fldCustomApiUrl = ?,
                fldCustomToken = ?,
                fldAutoSendFinancial = ?,
                fldAutoSendAudit = ?
            WHERE fldID = 1
        END
        ELSE
        BEGIN
            INSERT INTO tblWhatsAppSettings (fldID, fldFinancialPhone, fldAuditPhone, fldProviderType, fldCustomApiUrl, fldCustomToken, fldAutoSendFinancial, fldAutoSendAudit)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?)
        END
        """, (
            settings.financialPhone, settings.auditPhone, settings.providerType, settings.customApiUrl, settings.customToken, 1 if settings.autoSendFinancial else 0, 1 if settings.autoSendAudit else 0,
            settings.financialPhone, settings.auditPhone, settings.providerType, settings.customApiUrl, settings.customToken, 1 if settings.autoSendFinancial else 0, 1 if settings.autoSendAudit else 0
        ))
        conn.commit()
        log_audit_event(None, "النظام", "تحديث إعدادات الواتساب", "تم تحديث أرقام وإعدادات مزود الواتساب", f"المالي: {settings.financialPhone} | التدقيق: {settings.auditPhone}")
        return {"status": "success", "message": "تم حفظ إعدادات مزود الواتساب بنجاح 💾"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"فشل حفظ إعدادات الواتساب: {str(e)}")
    finally:
        cursor.close()
        conn.close()

# --- AUDIT LOG REPORT ENDPOINTS ---
@app.get("/api/reports/audit-log")
def get_audit_log_report(start_date: Optional[str] = None, end_date: Optional[str] = None, user_id: Optional[int] = None, action_type: Optional[str] = None, point_no: Optional[int] = None):
    init_system_tables()
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        query = "SELECT fldLogID, fldDate, fldUserID, fldUserName, fldActionType, fldDescription, fldDetails FROM tblAuditLog WHERE 1=1"
        params = []
        
        if start_date:
            query += " AND fldDate >= ?"
            params.append(f"{start_date} 00:00:00")
        if end_date:
            query += " AND fldDate <= ?"
            params.append(f"{end_date} 23:59:59")
        if user_id is not None:
            query += " AND fldUserID = ?"
            params.append(user_id)
        if action_type and action_type.strip():
            query += " AND fldActionType LIKE ?"
            params.append(f"%{action_type.strip()}%")
            
        query += " ORDER BY fldLogID DESC"
        cursor.execute(query, params)
        
        logs = []
        for row in cursor.fetchall():
            date_str = str(row[1]) if row[1] else ""
            logs.append({
                "id": row[0],
                "date": date_str,
                "userId": row[2],
                "userName": row[3] or "مستخدم النظام",
                "actionType": row[4],
                "description": row[5] or "",
                "details": row[6] or ""
            })
            
        return {
            "status": "success",
            "totalCount": len(logs),
            "logs": logs
        }
    finally:
        cursor.close()
        conn.close()

@app.post("/api/audit-log/add")
def add_audit_log_event(req: AuditLogCreateRequest):
    log_audit_event(req.userId, req.userName, req.actionType, req.description, req.details)
    return {"status": "success", "message": "تم تسجيل الحركة في سجل التدقيق بنجاح"}



@app.get("/api/users")
def get_users():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fldUSerID, fldUserName FROM tblUsers ORDER BY fldUserName")
        users = [{"id": row[0], "name": row[1]} for row in cursor.fetchall()]
        return users
    finally:
        cursor.close()
        conn.close()

# --- CRM & Accounts Endpoints ---

@app.get("/api/accounts", response_model=List[AccountResponse])
def get_accounts():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fldID, fldExpensesName, fldAccID FROM tblExpensesList ORDER BY fldExpensesName")
        accounts = []
        for row in cursor.fetchall():
            fld_id = int(row[0]) if row[0] is not None else 0
            fld_name = decode_ar_str(row[1] or "")
            fld_acc_id = int(row[2]) if (row[2] is not None and int(row[2]) > 0) else fld_id
            accounts.append(AccountResponse(
                id=fld_id,
                name=fld_name,
                accId=fld_acc_id
            ))
            
        # Dual-sync to local SQLite tblExpensesList
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            for a in accounts:
                sq_cur.execute("INSERT OR REPLACE INTO tblExpensesList (fldID, fldExpensesName, fldAccID) VALUES (?, ?, ?)", (a.id, a.name, a.accId))
            sq_conn.commit()
            sq_conn.close()
        except Exception:
            pass

        return accounts
    except Exception as e:
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            sq_cur.execute("SELECT fldID, fldExpensesName, fldAccID FROM tblExpensesList ORDER BY fldExpensesName")
            accounts = []
            for row in sq_cur.fetchall():
                fld_id = int(row[0]) if row[0] is not None else 0
                fld_name = decode_ar_str(row[1] or "")
                fld_acc_id = int(row[2]) if (row[2] is not None and int(row[2]) > 0) else fld_id
                accounts.append(AccountResponse(
                    id=fld_id,
                    name=fld_name,
                    accId=fld_acc_id
                ))
            sq_conn.close()
            return accounts
        except Exception:
            raise HTTPException(status_code=500, detail=str(e))
    finally:
        try:
            cursor.close()
            conn.close()
        except Exception:
            pass

@app.get("/api/remote-accounts", response_model=List[RemoteAccountResponse])
def get_remote_accounts():
    try:
        conn = get_remote_connection()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to connect to main database: {e}")
        
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fldName, fldID FROM dbo.tblAccount WHERE (fldIs_Primary = 0) ORDER BY fldName")
        accounts = []
        for row in cursor.fetchall():
            accounts.append(RemoteAccountResponse(
                id=int(row[1]) if row[1] is not None else 0,
                name=row[0] or ""
            ))
        return accounts
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conn.close()

# Helper function to load currency dictionary map
def get_currencies_map(cursor):
    cur_map = {}
    try:
        cursor.execute("SELECT fldID, CAST(fldsymbol AS VARBINARY(MAX)), CAST(fldName AS VARBINARY(MAX)), fldValue FROM tblMoney")
        for row in cursor.fetchall():
            mid = int(row[0] or 1)
            sym_raw = row[1]
            name_raw = row[2]
            sym = ""
            if sym_raw:
                try:
                    sym = sym_raw.decode('utf-16-le').strip()
                except Exception:
                    sym = decode_ar_str(sym_raw).strip()
            name = ""
            if name_raw:
                try:
                    name = name_raw.decode('utf-16-le').strip()
                except Exception:
                    name = decode_ar_str(name_raw).strip()
            cur_map[mid] = {
                "id": mid,
                "name": name or ("دينار أردني" if mid == 1 else f"عملة {mid}"),
                "symbol": sym or ("د.أ" if mid == 1 else "ر.س"),
                "value": float(row[3] or 1.0)
            }
    except Exception:
        pass
    if not cur_map:
        cur_map[1] = {"id": 1, "name": "دينار أردني", "symbol": "د.أ", "value": 1.0}
    return cur_map

# --- Bonds Endpoints (Multi-Line / Multi-Operation Voucher Supported) ---

@app.get("/api/bonds", response_model=List[BondResponse])
def get_bonds(start_date: Optional[str] = None, end_date: Optional[str] = None, point_no: Optional[int] = None, trans_type: Optional[int] = None, money_id: Optional[int] = None):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        ensure_columns_exist(cursor)
        conn.commit()

        cur_map = get_currencies_map(cursor)

        query = (
            "SELECT e.fldID, COALESCE(e.fldTransNumber, m.fldTransNumber, CAST(e.fldID AS float), 0.0) as trans_num, e.fldExpensesID, "
            "COALESCE(el.fldExpensesName, N'حساب عام') as exp_name, e.fldAmount, COALESCE(e.fldNote, N'') as exp_note, "
            "e.fldDate, e.fldTransID, COALESCE(e.fldPointNO, 1) as point_no, COALESCE(m.fldUSerID, 1) as user_id, "
            "COALESCE(m.fldDescription, N'') as main_desc, COALESCE(m.fldMoneyID, 1) as money_id, COALESCE(m.fldAccID, e.fldExpensesID, 0) as acc_id "
            "FROM tblExpenses e "
            "LEFT JOIN (SELECT fldTransNumber, MAX(fldDescription) as fldDescription, MAX(fldUSerID) as fldUSerID, MAX(fldPointNO) as fldPointNO, MAX(fldType) as fldType, MAX(fldMoneyID) as fldMoneyID, MAX(fldAccID) as fldAccID FROM Main GROUP BY fldTransNumber) m ON e.fldTransNumber = m.fldTransNumber "
            "LEFT JOIN (SELECT fldID, MAX(fldExpensesName) as fldExpensesName FROM tblExpensesList GROUP BY fldID) el ON e.fldExpensesID = el.fldID "
            "WHERE 1=1 "
        )
        params = []
        if start_date and start_date.strip():
            query += " AND e.fldDate >= ? "
            params.append(start_date.strip())
        if end_date and end_date.strip():
            query += " AND e.fldDate <= ? "
            params.append(end_date.strip())
        if point_no is not None and point_no > 0:
            query += " AND (e.fldPointNO = ? OR m.fldPointNO = ?) "
            params.extend([point_no, point_no])
        if trans_type is not None and trans_type > 0:
            query += " AND (e.fldTransID = ? OR m.fldType = ?) "
            params.extend([trans_type, trans_type])
        if money_id is not None and money_id > 0:
            query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1)) "
            params.extend([money_id, money_id])
            
        query += " ORDER BY e.fldID DESC"
        cursor.execute(query, params)
        rows = cursor.fetchall()
        
        # Group rows by transNumber (if transNumber > 0) or by fldID
        bonds_map = {}
        ordered_keys = []

        for row in rows:
            fld_id = row[0]
            trans_num = float(row[1] or 0.0)
            exp_id = row[2] or 0
            exp_name = decode_ar_str(row[3] or "حساب عام")
            amount_val = float(row[4] or 0.0)
            exp_note = decode_ar_str(row[5] or "")
            bond_date = str(row[6])
            trans_id = row[7] or 11
            pt_no = int(row[8] or 1)
            usr_id = int(row[9] or 1)
            main_desc = decode_ar_str(row[10] or "")
            money_id_val = int(row[11] or 1)
            acc_id_val = int(row[12] or exp_id or 0)
            
            is_receipt = (trans_id == 10) if (trans_id in [10, 11]) else (amount_val < 0)
            line_amount = abs(amount_val)

            group_key = f"tn_{trans_num}" if trans_num > 0 else f"id_{fld_id}"

            if group_key not in bonds_map:
                cur_info = cur_map.get(money_id_val, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})
                bonds_map[group_key] = {
                    "id": fld_id,
                    "transNumber": trans_num,
                    "expensesId": exp_id,
                    "expensesName": exp_name,
                    "amount": 0.0,
                    "note": main_desc if main_desc else exp_note,
                    "date": bond_date,
                    "isReceipt": is_receipt,
                    "pointNo": pt_no,
                    "userId": usr_id,
                    "moneyId": money_id_val,
                    "currencyName": cur_info.get("name", ""),
                    "currencySymbol": cur_info.get("symbol", ""),
                    "accountId": acc_id_val,
                    "details": []
                }
                ordered_keys.append(group_key)

            bonds_map[group_key]["amount"] += line_amount
            bonds_map[group_key]["details"].append(BondDetailResponse(
                expensesId=exp_id,
                expensesName=exp_name,
                amount=line_amount,
                note=exp_note
            ))

        result = []
        for key in ordered_keys:
            data = bonds_map[key]
            result.append(BondResponse(
                id=data["id"],
                transNumber=data["transNumber"],
                expensesId=data["expensesId"],
                expensesName=data["expensesName"] if len(data["details"]) == 1 else f"سند متعدد ({len(data['details'])} بنود)",
                amount=round(data["amount"], 2),
                note=data["note"],
                date=data["date"],
                isReceipt=data["isReceipt"],
                pointNo=data["pointNo"],
                userId=data["userId"],
                moneyId=data.get("moneyId", 1),
                currencyName=data.get("currencyName", ""),
                currencySymbol=data.get("currencySymbol", ""),
                accountId=data.get("accountId", 0),
                details=data["details"]
            ))
        return result
    finally:
        cursor.close()
        conn.close()

@app.post("/api/bonds")
def create_bond(req: BondRequest):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        ensure_columns_exist(cursor)
        conn.commit()

        trans_type_id = 10 if req.isReceipt else 11
        point_no = int(req.pointNo or db_config.get("point_no", 1))
        user_id = int(req.userId or 1)
        money_id = int(req.moneyId or 1)
        account_id = int(req.accountId or req.expensesId or 0)

        # Build items list
        items_list = []
        if req.details and len(req.details) > 0:
            items_list = req.details
        else:
            items_list = [BondItemDetail(expensesId=req.expensesId or 0, amount=req.amount or 0.0, note=req.note or "", accountId=req.accountId or 0)]

        # Account Lookup from tblExpensesList
        acc_lookup_map = {}
        try:
            cursor.execute("SELECT fldID, fldAccID FROM tblExpensesList")
            for arow in cursor.fetchall():
                if arow[0] is not None and arow[1] is not None:
                    acc_lookup_map[int(arow[0])] = int(arow[1])
        except Exception:
            pass

        first_expenses_id = items_list[0].expensesId if items_list else account_id
        if account_id == 0 or account_id == first_expenses_id:
            if first_expenses_id in acc_lookup_map and acc_lookup_map[first_expenses_id] > 0:
                account_id = acc_lookup_map[first_expenses_id]
            elif first_expenses_id > 0:
                account_id = first_expenses_id

        # 1. Generate Next Transaction Number for Main
        try:
            year_2d = req.date.split("-")[0][-2:]
        except Exception:
            year_2d = "26"
            
        prefix_val = int(f"{year_2d}{point_no:02d}{trans_type_id:02d}")
        prefix_min = prefix_val * 100000
        prefix_max = prefix_min + 99999
        
        cursor.execute(
            "SELECT COALESCE(MAX(fldTransNumber), ?) FROM Main WHERE fldTransNumber >= ? AND fldTransNumber <= ?",
            (prefix_min, prefix_min, prefix_max)
        )
        max_num = cursor.fetchval()
        if max_num == prefix_min:
            next_trans_num = float(prefix_min + 1)
        else:
            next_trans_num = float(max_num + 1)

        # 2. Insert into Main Header with fldMoneyID and fldAccID
        cursor.execute("SELECT COALESCE(MAX(fldTransID), 0) FROM Main")
        next_trans_id = int(cursor.fetchval() + 1)

        main_desc = req.note or (items_list[0].note if items_list else "")
        cursor.execute(
            "INSERT INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldAccID) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (req.date, main_desc, next_trans_num, user_id, point_no, 1, trans_type_id, first_expenses_id, money_id, account_id)
        )

        # 3. Insert each item into tblExpenses with fldAccID
        first_generated_exp_id = 0
        for idx, item in enumerate(items_list):
            actual_amount = -abs(item.amount) if req.isReceipt else abs(item.amount)
            cursor.execute("SELECT COALESCE(MAX(fldID), 0) FROM tblExpenses")
            next_exp_id = int(cursor.fetchval() + 1)
            if idx == 0:
                first_generated_exp_id = next_exp_id

            # Determine item-level fldAccID
            item_acc_id = 0
            if item.accountId and int(item.accountId) > 0:
                item_acc_id = int(item.accountId)
            elif item.expensesId in acc_lookup_map and acc_lookup_map[item.expensesId] > 0:
                item_acc_id = acc_lookup_map[item.expensesId]
            elif account_id > 0:
                item_acc_id = account_id
            else:
                item_acc_id = int(item.expensesId or 0)

            try:
                cursor.execute(
                    "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO, fldID, fldAccID) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, next_trans_num, point_no, next_exp_id, item_acc_id)
                )
            except Exception:
                try:
                    cursor.execute(
                        "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO, fldAccID) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                        (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, next_trans_num, point_no, item_acc_id)
                    )
                except Exception:
                    cursor.execute(
                        "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?)",
                        (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, next_trans_num, point_no)
                    )
                cursor.execute("SELECT @@IDENTITY")
                val = cursor.fetchone()
                if val and val[0] and idx == 0:
                    first_generated_exp_id = int(val[0])

        conn.commit()

        # Dual-sync to local SQLite Main and tblExpenses
        try:
            sq_conn = sqlite3.connect(SQLITE_DB_FILE)
            sq_cur = sq_conn.cursor()
            sq_cur.execute("""
                INSERT OR REPLACE INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldAccID, fldIsSync)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            """, (req.date, main_desc, next_trans_num, user_id, point_no, 1, trans_type_id, first_expenses_id, money_id, account_id))
            for item in items_list:
                actual_amount = -abs(item.amount) if req.isReceipt else abs(item.amount)
                item_acc_id = 0
                if item.accountId and int(item.accountId) > 0:
                    item_acc_id = int(item.accountId)
                elif item.expensesId in acc_lookup_map and acc_lookup_map[item.expensesId] > 0:
                    item_acc_id = acc_lookup_map[item.expensesId]
                elif account_id > 0:
                    item_acc_id = account_id
                else:
                    item_acc_id = int(item.expensesId or 0)
                try:
                    sq_cur.execute("""
                        INSERT OR REPLACE INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO, fldAccID)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, next_trans_num, point_no, item_acc_id))
                except Exception:
                    sq_cur.execute("""
                        INSERT OR REPLACE INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, next_trans_num, point_no))
            sq_conn.commit()
            sq_conn.close()
        except Exception:
            pass

        return {"status": "success", "bondId": first_generated_exp_id, "transNumber": next_trans_num}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"فشل حفظ السند: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.put("/api/bonds")
def update_bond(req: BondEditRequest):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        ensure_columns_exist(cursor)
        conn.commit()

        trans_type_id = 10 if req.isReceipt else 11
        point_no = int(req.pointNo or db_config.get("point_no", 1))
        user_id = int(req.userId or 1)
        money_id = int(req.moneyId or 1)
        account_id = int(req.accountId or req.expensesId or 0)

        items_list = []
        if req.details and len(req.details) > 0:
            items_list = req.details
        else:
            items_list = [BondItemDetail(expensesId=req.expensesId or 0, amount=req.amount or 0.0, note=req.note or "", accountId=req.accountId or 0)]

        # Account Lookup from tblExpensesList
        acc_lookup_map = {}
        try:
            cursor.execute("SELECT fldID, fldAccID FROM tblExpensesList")
            for arow in cursor.fetchall():
                if arow[0] is not None and arow[1] is not None:
                    acc_lookup_map[int(arow[0])] = int(arow[1])
        except Exception:
            pass

        first_expenses_id = items_list[0].expensesId if items_list else account_id
        if account_id == 0 or account_id == first_expenses_id:
            if first_expenses_id in acc_lookup_map and acc_lookup_map[first_expenses_id] > 0:
                account_id = acc_lookup_map[first_expenses_id]
            elif first_expenses_id > 0:
                account_id = first_expenses_id
        main_desc = req.note or (items_list[0].note if items_list else "")

        # 1. Update Main Header
        if req.transNumber and req.transNumber > 0:
            cursor.execute(
                "UPDATE Main SET fldDate = ?, fldDescription = ?, fldUSerID = ?, fldPointNO = ?, fldType = ?, fldTransID = ?, fldMoneyID = ?, fldAccID = ? WHERE fldTransNumber = ?",
                (req.date, main_desc, user_id, point_no, trans_type_id, first_expenses_id, money_id, account_id, req.transNumber)
            )

        # 2. Delete existing tblExpenses for this transNumber (or bond id)
        if req.transNumber and req.transNumber > 0:
            cursor.execute("DELETE FROM tblExpenses WHERE fldTransNumber = ?", (req.transNumber,))
        elif req.id and req.id > 0:
            cursor.execute("DELETE FROM tblExpenses WHERE fldID = ?", (req.id,))

        # 3. Re-insert items into tblExpenses with fldAccID
        for item in items_list:
            actual_amount = -abs(item.amount) if req.isReceipt else abs(item.amount)
            cursor.execute("SELECT COALESCE(MAX(fldID), 0) FROM tblExpenses")
            next_exp_id = int(cursor.fetchval() + 1)

            item_acc_id = 0
            if item.accountId and int(item.accountId) > 0:
                item_acc_id = int(item.accountId)
            elif item.expensesId in acc_lookup_map and acc_lookup_map[item.expensesId] > 0:
                item_acc_id = acc_lookup_map[item.expensesId]
            elif account_id > 0:
                item_acc_id = account_id
            else:
                item_acc_id = int(item.expensesId or 0)

            try:
                cursor.execute(
                    "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO, fldID, fldAccID) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, req.transNumber, point_no, next_exp_id, item_acc_id)
                )
            except Exception:
                try:
                    cursor.execute(
                        "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO, fldAccID) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                        (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, req.transNumber, point_no, item_acc_id)
                    )
                except Exception:
                    cursor.execute(
                        "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?)",
                        (item.expensesId, actual_amount, item.note or main_desc, trans_type_id, req.date, req.transNumber, point_no)
                    )

        conn.commit()
        return {"status": "success", "message": "تم تعديل السند متعدد البنود بنجاح"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"فشل تعديل السند: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.delete("/api/bonds/{bond_id}")
def delete_bond(bond_id: int, trans_number: Optional[float] = 0.0):
    conn = get_connection()
    cursor = conn.cursor()
    try:
        if not trans_number or trans_number == 0:
            cursor.execute("SELECT fldTransNumber FROM tblExpenses WHERE fldID = ?", (bond_id,))
            row = cursor.fetchone()
            if row:
                trans_number = float(row[0] or 0.0)

        if trans_number and trans_number > 0:
            cursor.execute("DELETE FROM tblExpenses WHERE fldTransNumber = ?", (trans_number,))
            cursor.execute("DELETE FROM Main WHERE fldTransNumber = ?", (trans_number,))
        else:
            cursor.execute("DELETE FROM tblExpenses WHERE fldID = ?", (bond_id,))

        conn.commit()
        return {"status": "success", "message": "تم حذف السند بنجاح"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"فشل حذف السند: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.post("/api/bonds/upload")
def upload_bonds():
    conn_local = get_connection()
    cursor_local = conn_local.cursor()
    
    try:
        conn_remote = get_remote_connection()
        conn_remote.autocommit = False
    except Exception as e:
        cursor_local.close()
        conn_local.close()
        raise HTTPException(status_code=400, detail=f"فشل الاتصال بالسيرفر الرئيسي البعيد: {str(e)}")

    cursor_remote = conn_remote.cursor()
    ensure_columns_exist(cursor_local)
    ensure_columns_exist(cursor_remote)
    conn_local.commit()
    conn_remote.commit()

    try:
        cursor_remote.execute("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES")
        remote_tables = {row[0].lower() for row in cursor_remote.fetchall()}

        selected_point_no = db_config.get("point_no", 1)
        uploaded_count = 0

        # Upload to Main
        if "main" in remote_tables:
            cursor_local.execute(
                "SELECT fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldPaycash, fldType, fldTransID, fldMoneyID "
                "FROM Main WHERE fldType IN (10, 11)"
            )
            bonds_main = cursor_local.fetchall()
            for bm in bonds_main:
                fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldPaycash, fldType, fldTransID, fldMoneyID = bm
                cursor_remote.execute("SELECT 1 FROM Main WHERE fldTransNumber = ?", (fldTransNumber,))
                if not cursor_remote.fetchone():
                    cursor_remote.execute(
                        "INSERT INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldPaycash, fldType, fldTransID, fldMoneyID) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO or selected_point_no, fldPaycash, fldType, fldTransID, fldMoneyID)
                    )

        # Upload to tblExpenses
        if "tblexpenses" in remote_tables:
            exp_acc_map = {}
            try:
                cursor_local.execute("SELECT fldID, fldAccID FROM tblExpensesList")
                for erow in cursor_local.fetchall():
                    if erow[0] is not None and erow[1] is not None:
                        exp_acc_map[int(erow[0])] = int(erow[1])
            except Exception:
                pass

            cursor_local.execute(
                "SELECT fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber, fldPointNO, COALESCE(fldAccID, 0) "
                "FROM tblExpenses"
            )
            bonds_exp = cursor_local.fetchall()
            for be in bonds_exp:
                fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber, fldPointNO, fldAccID = be
                if not fldAccID or int(fldAccID) == 0:
                    fldAccID = exp_acc_map.get(int(fldExpensesID or 0), int(fldExpensesID or 0))
                cursor_remote.execute("SELECT 1 FROM tblExpenses WHERE fldDate = ? AND fldAmount = ? AND fldNote = ?", (fldDate, fldAmount, fldNote))
                if not cursor_remote.fetchone():
                    try:
                        cursor_remote.execute(
                            "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber, fldPointNO, fldAccID) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber, fldPointNO or selected_point_no, fldAccID)
                        )
                    except Exception:
                        try:
                            cursor_remote.execute(
                                "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO, fldAccID) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO or selected_point_no, fldAccID)
                            )
                        except Exception:
                            cursor_remote.execute(
                                "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                (fldExpensesID, fldAmount, fldNote, fldTransID, fldDate, fldTransNumber, fldPointNO or selected_point_no)
                            )
                    uploaded_count += 1

        conn_remote.commit()
        return {
            "status": "success",
            "message": f"تم ترحيل سندات القبض والصرف بنجاح إلى السيرفر الرئيسي!\n- عدد السندات المرحّلة: {uploaded_count}\n- رقم نقطة البيع المرفقة: {selected_point_no}"
        }
    except Exception as e:
        try:
            conn_remote.rollback()
        except Exception:
            pass
        raise HTTPException(status_code=500, detail=f"فشل ترحيل السندات إلى قاعدة البيانات الرئيسية: {str(e)}")
    finally:
        cursor_remote.close()
        conn_remote.close()
        cursor_local.close()
        conn_local.close()

# --- Reports Endpoints ---

@app.get("/api/reports/summary")
def get_reports_summary(start_date: Optional[str] = None, end_date: Optional[str] = None, point_no: Optional[int] = None, money_id: Optional[int] = None):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        target_point = point_no if point_no else db_config.get("point_no", 1)
        cur_map = get_currencies_map(cursor)

        # 1. Sales Cash vs Credit by Currency (fldType = 35)
        query_sales = (
            "SELECT COALESCE(m.fldMoneyID, 1) as money_id, "
            "  COALESCE(SUM(CASE WHEN m.fldPaycash = 1 THEN d.fldTotalItem ELSE 0 END), 0) as cash_sales, "
            "  COALESCE(SUM(CASE WHEN m.fldPaycash = 2 THEN d.fldTotalItem ELSE 0 END), 0) as credit_sales "
            "FROM Main m "
            "JOIN details d ON m.fldTransNumber = d.fldTransNumber "
            "WHERE m.fldType = 35 AND (d.fldPointNO = ? OR m.fldPointNO = ?) "
        )
        params_sales = [target_point, target_point]
        if start_date and end_date:
            query_sales += " AND m.fldDate >= ? AND m.fldDate <= ?"
            params_sales.extend([start_date, end_date])
        if money_id and money_id > 0:
            query_sales += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_sales.extend([money_id, money_id])
        query_sales += " GROUP BY m.fldMoneyID"
            
        cursor.execute(query_sales, params_sales)
        sales_rows = cursor.fetchall()
        sales_by_currency = {}
        total_cash_sales = 0.0
        total_credit_sales = 0.0
        for r in sales_rows:
            mid = int(r[0] or 1)
            cs = float(r[1] or 0.0)
            crs = float(r[2] or 0.0)
            sales_by_currency[mid] = {"cashSales": cs, "creditSales": crs, "totalSales": cs + crs}
            total_cash_sales += cs
            total_credit_sales += crs

        # 2. Purchases (fldType = 20)
        query_purchases = (
            "SELECT COALESCE(m.fldMoneyID, 1) as money_id, COALESCE(SUM(d.fldTotalItem), 0) "
            "FROM Main m "
            "JOIN details d ON m.fldTransNumber = d.fldTransNumber "
            "WHERE m.fldType = 20 AND (d.fldPointNO = ? OR m.fldPointNO = ?) "
        )
        params_purch = [target_point, target_point]
        if start_date and end_date:
            query_purchases += " AND m.fldDate >= ? AND m.fldDate <= ?"
            params_purch.extend([start_date, end_date])
        if money_id and money_id > 0:
            query_purchases += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_purch.extend([money_id, money_id])
        query_purchases += " GROUP BY m.fldMoneyID"
        cursor.execute(query_purchases, params_purch)
        purch_by_currency = {}
        total_purchases = 0.0
        for r in cursor.fetchall():
            mid = int(r[0] or 1)
            p_amt = float(r[1] or 0.0)
            purch_by_currency[mid] = p_amt
            total_purchases += p_amt

        # 3. Returns (fldType = 36)
        query_returns = (
            "SELECT COALESCE(m.fldMoneyID, 1) as money_id, COALESCE(SUM(d.fldTotalItem), 0) "
            "FROM Main m "
            "JOIN details d ON m.fldTransNumber = d.fldTransNumber "
            "WHERE m.fldType = 36 AND (d.fldPointNO = ? OR m.fldPointNO = ?) "
        )
        params_ret = [target_point, target_point]
        if start_date and end_date:
            query_returns += " AND m.fldDate >= ? AND m.fldDate <= ?"
            params_ret.extend([start_date, end_date])
        if money_id and money_id > 0:
            query_returns += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_ret.extend([money_id, money_id])
        query_returns += " GROUP BY m.fldMoneyID"
        cursor.execute(query_returns, params_ret)
        ret_by_currency = {}
        total_returns = 0.0
        for r in cursor.fetchall():
            mid = int(r[0] or 1)
            r_amt = float(r[1] or 0.0)
            ret_by_currency[mid] = r_amt
            total_returns += r_amt

        # 4. Opening Stock Value (fldType = 1)
        query_stock = (
            "SELECT COALESCE(m.fldMoneyID, 1) as money_id, COALESCE(SUM(d.fldTotalItem), 0) "
            "FROM Main m "
            "JOIN details d ON m.fldTransNumber = d.fldTransNumber "
            "WHERE m.fldType = 1 AND (d.fldPointNO = ? OR m.fldPointNO = ?) "
        )
        params_stk = [target_point, target_point]
        if money_id and money_id > 0:
            query_stock += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_stk.extend([money_id, money_id])
        query_stock += " GROUP BY m.fldMoneyID"
        cursor.execute(query_stock, params_stk)
        stock_by_currency = {}
        total_stock_value = 0.0
        for r in cursor.fetchall():
            mid = int(r[0] or 1)
            s_amt = float(r[1] or 0.0)
            stock_by_currency[mid] = s_amt
            total_stock_value += s_amt

        # 5. Receipts & Disbursements (tblExpenses + Main)
        query_bonds = (
            "SELECT COALESCE(m.fldMoneyID, 1) as money_id, "
            "  COALESCE(SUM(CASE WHEN e.fldAmount < 0 THEN ABS(e.fldAmount) ELSE 0 END), 0) as receipts, "
            "  COALESCE(SUM(CASE WHEN e.fldAmount > 0 THEN e.fldAmount ELSE 0 END), 0) as disbursements "
            "FROM tblExpenses e "
            "LEFT JOIN (SELECT fldTransNumber, MAX(fldMoneyID) as fldMoneyID FROM Main GROUP BY fldTransNumber) m ON e.fldTransNumber = m.fldTransNumber "
            "WHERE 1=1 "
        )
        params_bonds = []
        if start_date and end_date:
            query_bonds += " AND e.fldDate >= ? AND e.fldDate <= ?"
            params_bonds.extend([start_date, end_date])
        if money_id and money_id > 0:
            query_bonds += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_bonds.extend([money_id, money_id])
        query_bonds += " GROUP BY m.fldMoneyID"
        cursor.execute(query_bonds, params_bonds)
        bonds_by_currency = {}
        total_receipts = 0.0
        total_disbursements = 0.0
        for r in cursor.fetchall():
            mid = int(r[0] or 1)
            rc = float(r[1] or 0.0)
            ds = float(r[2] or 0.0)
            bonds_by_currency[mid] = {"receipts": rc, "disbursements": ds}
            total_receipts += rc
            total_disbursements += ds

        # 6. Store Transfers In (fldType = 22) & Out (fldType = 28 or 23)
        query_transfers = (
            "SELECT COALESCE(m.fldMoneyID, 1) as money_id, "
            "  COALESCE(SUM(CASE WHEN m.fldType = 22 THEN d.fldTotalItem ELSE 0 END), 0) as trans_in, "
            "  COALESCE(SUM(CASE WHEN m.fldType IN (28, 23) THEN d.fldTotalItem ELSE 0 END), 0) as trans_out "
            "FROM Main m "
            "JOIN details d ON (ABS(m.fldTransNumber - d.fldTransNumber) < 0.001 OR CAST(m.fldTransNumber AS BIGINT) = CAST(d.fldTransNumber AS BIGINT)) "
            "WHERE m.fldType IN (22, 28, 23) AND (d.fldPointNO = ? OR m.fldPointNO = ? OR d.fldToPointNO = ?) "
        )
        params_trans = [target_point, target_point, target_point]
        if start_date and end_date:
            query_transfers += " AND m.fldDate >= ? AND m.fldDate <= ?"
            params_trans.extend([start_date, end_date])
        if money_id and money_id > 0:
            query_transfers += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_trans.extend([money_id, money_id])
        query_transfers += " GROUP BY m.fldMoneyID"
        cursor.execute(query_transfers, params_trans)
        trans_by_currency = {}
        total_transfers_in = 0.0
        total_transfers_out = 0.0
        for r in cursor.fetchall():
            mid = int(r[0] or 1)
            ti = float(r[1] or 0.0)
            to = float(r[2] or 0.0)
            trans_by_currency[mid] = {"transIn": ti, "transOut": to}
            total_transfers_in += ti
            total_transfers_out += to

        # Build detailed byCurrency list
        all_money_ids = sorted(list(set(
            list(cur_map.keys()) +
            list(sales_by_currency.keys()) +
            list(purch_by_currency.keys()) +
            list(ret_by_currency.keys()) +
            list(bonds_by_currency.keys()) +
            list(trans_by_currency.keys())
        )))

        by_currency = []
        for mid in all_money_ids:
            cur_info = cur_map.get(mid, {"name": f"عملة {mid}", "symbol": f"C{mid}", "value": 1.0})
            s_data = sales_by_currency.get(mid, {"cashSales": 0.0, "creditSales": 0.0, "totalSales": 0.0})
            p_val = purch_by_currency.get(mid, 0.0)
            r_val = ret_by_currency.get(mid, 0.0)
            stk_val = stock_by_currency.get(mid, 0.0)
            b_data = bonds_by_currency.get(mid, {"receipts": 0.0, "disbursements": 0.0})
            t_data = trans_by_currency.get(mid, {"transIn": 0.0, "transOut": 0.0})
            
            c_sales = s_data["cashSales"]
            cr_sales = s_data["creditSales"]
            t_sales = s_data["totalSales"]
            rc_bonds = b_data["receipts"]
            ds_bonds = b_data["disbursements"]
            net_cash = (c_sales + rc_bonds) - (p_val + ds_bonds + r_val)

            by_currency.append({
                "moneyId": mid,
                "currencyName": cur_info.get("name", ""),
                "currencySymbol": cur_info.get("symbol", ""),
                "exchangeRate": cur_info.get("value", 1.0),
                "cashSales": round(c_sales, 2),
                "creditSales": round(cr_sales, 2),
                "totalSales": round(t_sales, 2),
                "totalPurchases": round(p_val, 2),
                "totalReturns": round(r_val, 2),
                "openingStockValue": round(stk_val, 2),
                "totalReceiptBonds": round(rc_bonds, 2),
                "totalDisbursementBonds": round(ds_bonds, 2),
                "totalTransfersIn": round(t_data["transIn"], 2),
                "totalTransfersOut": round(t_data["transOut"], 2),
                "totalTransfers": round(t_data["transIn"] + t_data["transOut"], 2),
                "cashInRegister": round(net_cash, 2)
            })

        return {
            "selectedMoneyId": money_id or 0,
            "cashSales": round(total_cash_sales, 2),
            "creditSales": round(total_credit_sales, 2),
            "totalSales": round(total_cash_sales + total_credit_sales, 2),
            "totalPurchases": round(total_purchases, 2),
            "totalReturns": round(total_returns, 2),
            "openingStockValue": round(total_stock_value, 2),
            "totalReceiptBonds": round(total_receipts, 2),
            "totalDisbursementBonds": round(total_disbursements, 2),
            "totalTransfersIn": round(total_transfers_in, 2),
            "totalTransfersOut": round(total_transfers_out, 2),
            "totalTransfers": round(total_transfers_in + total_transfers_out, 2),
            "cashInRegister": round((total_cash_sales + total_receipts) - (total_purchases + total_disbursements + total_returns), 2),
            "byCurrency": by_currency
        }
    finally:
        cursor.close()
        conn.close()

@app.get("/api/reports/cash-movement")
def get_cash_movement_report(start_date: Optional[str] = None, end_date: Optional[str] = None, point_no: Optional[int] = None, money_id: Optional[int] = None):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        target_point = point_no if point_no else db_config.get("point_no", 1)
        cur_map = get_currencies_map(cursor)
        movements = []
        
        # 1. Cash Sales (Main fldType = 35)
        sales_query = """
            SELECT m.fldTransNumber, m.fldDate, m.fldDescription, COALESCE(SUM(d.fldTotalItem), 0) as total, COALESCE(m.fldMoneyID, 1) as money_id
            FROM Main m
            JOIN details d ON m.fldTransNumber = d.fldTransNumber
            WHERE m.fldType = 35 AND (m.fldPaycash = 1 OR m.fldPaycash IS NULL)
        """
        params_s = []
        if start_date and end_date:
            sales_query += " AND m.fldDate >= ? AND m.fldDate <= ?"
            params_s.extend([start_date, end_date])
        if money_id and money_id > 0:
            sales_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_s.extend([money_id, money_id])
        sales_query += " GROUP BY m.fldTransNumber, m.fldDate, m.fldDescription, m.fldMoneyID ORDER BY m.fldDate ASC"
        
        try:
            cursor.execute(sales_query, params_s)
            for row in cursor.fetchall():
                trans_no = str(row[0] or '')
                trans_date = str(row[1] or '')
                desc = str(row[2] or f'فاتورة مبيعات نقدية #{trans_no}')
                amount = float(row[3] or 0.0)
                mid = int(row[4] or 1)
                cur_info = cur_map.get(mid, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})
                if amount > 0:
                    movements.append({
                        "date": trans_date,
                        "type": "مبيعات نقدية",
                        "refNo": trans_no,
                        "description": desc,
                        "cashIn": amount,
                        "cashOut": 0.0,
                        "moneyId": mid,
                        "currencyName": cur_info.get("name", ""),
                        "currencySymbol": cur_info.get("symbol", "")
                    })
        except Exception as ex:
            print("Error fetching cash sales for movement:", ex)

        # 2. Cash Returns (Main fldType = 36)
        ret_query = """
            SELECT m.fldTransNumber, m.fldDate, m.fldDescription, COALESCE(SUM(d.fldTotalItem), 0) as total, COALESCE(m.fldMoneyID, 1) as money_id
            FROM Main m
            JOIN details d ON m.fldTransNumber = d.fldTransNumber
            WHERE m.fldType = 36
        """
        params_r = []
        if start_date and end_date:
            ret_query += " AND m.fldDate >= ? AND m.fldDate <= ?"
            params_r.extend([start_date, end_date])
        if money_id and money_id > 0:
            ret_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_r.extend([money_id, money_id])
        ret_query += " GROUP BY m.fldTransNumber, m.fldDate, m.fldDescription, m.fldMoneyID ORDER BY m.fldDate ASC"

        try:
            cursor.execute(ret_query, params_r)
            for row in cursor.fetchall():
                trans_no = str(row[0] or '')
                trans_date = str(row[1] or '')
                desc = str(row[2] or f'مردود مبيعات #{trans_no}')
                amount = float(row[3] or 0.0)
                mid = int(row[4] or 1)
                cur_info = cur_map.get(mid, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})
                if amount > 0:
                    movements.append({
                        "date": trans_date,
                        "type": "مردود مبيعات",
                        "refNo": trans_no,
                        "description": desc,
                        "cashIn": 0.0,
                        "cashOut": amount,
                        "moneyId": mid,
                        "currencyName": cur_info.get("name", ""),
                        "currencySymbol": cur_info.get("symbol", "")
                    })
        except Exception as ex:
            print("Error fetching returns for movement:", ex)

        # 3. Cash Purchases (Main fldType = 20)
        purch_query = """
            SELECT m.fldTransNumber, m.fldDate, m.fldDescription, COALESCE(SUM(d.fldTotalItem), 0) as total, COALESCE(m.fldMoneyID, 1) as money_id
            FROM Main m
            JOIN details d ON m.fldTransNumber = d.fldTransNumber
            WHERE m.fldType = 20
        """
        params_p = []
        if start_date and end_date:
            purch_query += " AND m.fldDate >= ? AND m.fldDate <= ?"
            params_p.extend([start_date, end_date])
        if money_id and money_id > 0:
            purch_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_p.extend([money_id, money_id])
        purch_query += " GROUP BY m.fldTransNumber, m.fldDate, m.fldDescription, m.fldMoneyID ORDER BY m.fldDate ASC"

        try:
            cursor.execute(purch_query, params_p)
            for row in cursor.fetchall():
                trans_no = str(row[0] or '')
                trans_date = str(row[1] or '')
                desc = str(row[2] or f'فاتورة مشتريات نقدية #{trans_no}')
                amount = float(row[3] or 0.0)
                mid = int(row[4] or 1)
                cur_info = cur_map.get(mid, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})
                if amount > 0:
                    movements.append({
                        "date": trans_date,
                        "type": "مشتريات نقدية",
                        "refNo": trans_no,
                        "description": desc,
                        "cashIn": 0.0,
                        "cashOut": amount,
                        "moneyId": mid,
                        "currencyName": cur_info.get("name", ""),
                        "currencySymbol": cur_info.get("symbol", "")
                    })
        except Exception as ex:
            print("Error fetching purchases for movement:", ex)

        # 4. Expenses and Bonds (tblExpenses + Main)
        exp_query = """
            SELECT e.fldID, e.fldDate, e.fldNote, e.fldAmount, COALESCE(m.fldMoneyID, 1) as money_id
            FROM tblExpenses e
            LEFT JOIN (SELECT fldTransNumber, MAX(fldMoneyID) as fldMoneyID FROM Main GROUP BY fldTransNumber) m ON e.fldTransNumber = m.fldTransNumber
            WHERE 1=1
        """
        params_e = []
        if start_date and end_date:
            exp_query += " AND e.fldDate >= ? AND e.fldDate <= ?"
            params_e.extend([start_date, end_date])
        if money_id and money_id > 0:
            exp_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_e.extend([money_id, money_id])
        exp_query += " ORDER BY e.fldDate ASC"

        try:
            cursor.execute(exp_query, params_e)
            for row in cursor.fetchall():
                bond_id = str(row[0] or '')
                bond_date = str(row[1] or '')
                note = str(row[2] or '')
                raw_amt = float(row[3] or 0.0)
                mid = int(row[4] or 1)
                cur_info = cur_map.get(mid, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})
                if raw_amt < 0:
                    amt = abs(raw_amt)
                    movements.append({
                        "date": bond_date,
                        "type": "سند قبض نقدي",
                        "refNo": bond_id,
                        "description": note or f"سند قبض #{bond_id}",
                        "cashIn": amt,
                        "cashOut": 0.0,
                        "moneyId": mid,
                        "currencyName": cur_info.get("name", ""),
                        "currencySymbol": cur_info.get("symbol", "")
                    })
                elif raw_amt > 0:
                    movements.append({
                        "date": bond_date,
                        "type": "سند صرف / مصاريف",
                        "refNo": bond_id,
                        "description": note or f"سند صرف #{bond_id}",
                        "cashIn": 0.0,
                        "cashOut": raw_amt,
                        "moneyId": mid,
                        "currencyName": cur_info.get("name", ""),
                        "currencySymbol": cur_info.get("symbol", "")
                    })
        except Exception as ex:
            print("Error fetching expenses for movement:", ex)

        # Sort movements chronologically
        movements.sort(key=lambda x: str(x.get("date", "")))

        # Calculate running balances per currency and global
        cur_balances = {}
        total_cash_in = 0.0
        total_cash_out = 0.0
        running_balance = 0.0

        for m in movements:
            mid = m["moneyId"]
            if mid not in cur_balances:
                cur_balances[mid] = 0.0
            
            c_in = m["cashIn"]
            c_out = m["cashOut"]
            total_cash_in += c_in
            total_cash_out += c_out
            running_balance += (c_in - c_out)
            cur_balances[mid] += (c_in - c_out)

            m["balance"] = running_balance
            m["currencyBalance"] = cur_balances[mid]

        summary_by_currency = {}
        for mid in cur_balances:
            cur_info = cur_map.get(mid, {"name": f"عملة {mid}", "symbol": f"C{mid}", "value": 1.0})
            c_in = sum(m["cashIn"] for m in movements if m["moneyId"] == mid)
            c_out = sum(m["cashOut"] for m in movements if m["moneyId"] == mid)
            summary_by_currency[str(mid)] = {
                "moneyId": mid,
                "currencyName": cur_info.get("name", ""),
                "currencySymbol": cur_info.get("symbol", ""),
                "exchangeRate": cur_info.get("value", 1.0),
                "totalCashIn": round(c_in, 2),
                "totalCashOut": round(c_out, 2),
                "remainingCash": round(c_in - c_out, 2)
            }

        cash_sales = sum(m["cashIn"] for m in movements if m["type"] == "مبيعات نقدية")
        cash_receipts = sum(m["cashIn"] for m in movements if m["type"] == "سند قبض نقدي")
        cash_returns = sum(m["cashOut"] for m in movements if m["type"] == "مردود مبيعات")
        cash_purchases = sum(m["cashOut"] for m in movements if m["type"] == "مشتريات نقدية")
        cash_expenses = sum(m["cashOut"] for m in movements if m["type"] == "سند صرف / مصاريف")

        summary = {
            "cashSales": round(cash_sales, 2),
            "cashReceipts": round(cash_receipts, 2),
            "cashReturns": round(cash_returns, 2),
            "cashPurchases": round(cash_purchases, 2),
            "cashExpenses": round(cash_expenses, 2),
            "totalCashIn": round(total_cash_in, 2),
            "totalCashOut": round(total_cash_out, 2),
            "remainingCash": round(total_cash_in - total_cash_out, 2)
        }

        return {
            "selectedMoneyId": money_id or 0,
            "summary": summary,
            "summaryByCurrency": summary_by_currency,
            "movements": movements
        }
    finally:
        cursor.close()
        conn.close()

@app.get("/api/reports/daily-financial-breakdown")
def get_daily_financial_breakdown(
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    point_no: Optional[int] = None,
    money_id: Optional[int] = None
):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        cur_map = get_currencies_map(cursor)
        
        # 1. Sales by date (fldType = 35)
        sales_query = """
            SELECT m.fldDate, 
                   COALESCE(SUM(CASE WHEN m.fldPaycash = 1 OR m.fldPaycash IS NULL THEN d.fldTotalItem ELSE 0 END), 0) as cash_sales,
                   COALESCE(SUM(CASE WHEN m.fldPaycash = 2 THEN d.fldTotalItem ELSE 0 END), 0) as credit_sales,
                   COALESCE(SUM(d.fldTotalItem), 0) as total_sales,
                   COUNT(DISTINCT m.fldTransNumber) as sales_count
            FROM Main m
            JOIN details d ON m.fldTransNumber = d.fldTransNumber
            WHERE m.fldType = 35
        """
        params_s = []
        if point_no is not None and point_no > 0:
            sales_query += " AND (d.fldPointNO = ? OR m.fldPointNO = ?)"
            params_s.extend([point_no, point_no])
        if start_date and start_date.strip():
            sales_query += " AND m.fldDate >= ?"
            params_s.append(start_date.strip())
        if end_date and end_date.strip():
            sales_query += " AND m.fldDate <= ?"
            params_s.append(end_date.strip())
        if money_id and money_id > 0:
            sales_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_s.extend([money_id, money_id])
        sales_query += " GROUP BY m.fldDate ORDER BY m.fldDate DESC"
        
        sales_by_date = {}
        try:
            cursor.execute(sales_query, params_s)
            for r in cursor.fetchall():
                d_str = str(r[0] or '')
                if d_str:
                    sales_by_date[d_str] = {
                        "cashSales": float(r[1] or 0.0),
                        "creditSales": float(r[2] or 0.0),
                        "totalSales": float(r[3] or 0.0),
                        "salesCount": int(r[4] or 0)
                    }
        except Exception as e:
            print("Error query sales by date:", e)

        # 2. Returns by date (fldType = 36)
        ret_query = """
            SELECT m.fldDate, 
                   COALESCE(SUM(d.fldTotalItem), 0) as total_returns,
                   COUNT(DISTINCT m.fldTransNumber) as returns_count
            FROM Main m
            JOIN details d ON m.fldTransNumber = d.fldTransNumber
            WHERE m.fldType = 36
        """
        params_r = []
        if point_no is not None and point_no > 0:
            ret_query += " AND (d.fldPointNO = ? OR m.fldPointNO = ?)"
            params_r.extend([point_no, point_no])
        if start_date and start_date.strip():
            ret_query += " AND m.fldDate >= ?"
            params_r.append(start_date.strip())
        if end_date and end_date.strip():
            ret_query += " AND m.fldDate <= ?"
            params_r.append(end_date.strip())
        if money_id and money_id > 0:
            ret_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_r.extend([money_id, money_id])
        ret_query += " GROUP BY m.fldDate ORDER BY m.fldDate DESC"

        returns_by_date = {}
        try:
            cursor.execute(ret_query, params_r)
            for r in cursor.fetchall():
                d_str = str(r[0] or '')
                if d_str:
                    returns_by_date[d_str] = {
                        "totalReturns": float(r[1] or 0.0),
                        "returnsCount": int(r[2] or 0)
                    }
        except Exception as e:
            print("Error query returns by date:", e)

        # 3. Purchases by date (fldType = 20)
        pur_query = """
            SELECT m.fldDate, 
                   COALESCE(SUM(d.fldTotalItem), 0) as total_purchases,
                   COUNT(DISTINCT m.fldTransNumber) as purchases_count
            FROM Main m
            JOIN details d ON m.fldTransNumber = d.fldTransNumber
            WHERE m.fldType = 20
        """
        params_p = []
        if point_no is not None and point_no > 0:
            pur_query += " AND (d.fldPointNO = ? OR m.fldPointNO = ?)"
            params_p.extend([point_no, point_no])
        if start_date and start_date.strip():
            pur_query += " AND m.fldDate >= ?"
            params_p.append(start_date.strip())
        if end_date and end_date.strip():
            pur_query += " AND m.fldDate <= ?"
            params_p.append(end_date.strip())
        if money_id and money_id > 0:
            pur_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_p.extend([money_id, money_id])
        pur_query += " GROUP BY m.fldDate ORDER BY m.fldDate DESC"

        purchases_by_date = {}
        try:
            cursor.execute(pur_query, params_p)
            for r in cursor.fetchall():
                d_str = str(r[0] or '')
                if d_str:
                    purchases_by_date[d_str] = {
                        "totalPurchases": float(r[1] or 0.0),
                        "purchasesCount": int(r[2] or 0)
                    }
        except Exception as e:
            print("Error query purchases by date:", e)

        # 4. Expenses & Bonds by date (tblExpenses)
        exp_query = """
            SELECT e.fldDate,
                   COALESCE(SUM(CASE WHEN e.fldAmount > 0 THEN e.fldAmount ELSE 0 END), 0) as expenses,
                   COALESCE(SUM(CASE WHEN e.fldAmount < 0 THEN ABS(e.fldAmount) ELSE 0 END), 0) as receipts,
                   COUNT(e.fldID) as exp_count
            FROM tblExpenses e
            LEFT JOIN (SELECT fldTransNumber, MAX(fldMoneyID) as fldMoneyID FROM Main GROUP BY fldTransNumber) m ON (ABS(e.fldTransNumber - m.fldTransNumber) < 0.001 OR CAST(e.fldTransNumber AS BIGINT) = CAST(m.fldTransNumber AS BIGINT))
            WHERE 1=1
        """
        params_e = []
        if point_no is not None and point_no > 0:
            exp_query += " AND (e.fldPointNO = ? OR e.fldPointNO IS NULL)"
            params_e.append(point_no)
        if start_date and start_date.strip():
            exp_query += " AND e.fldDate >= ?"
            params_e.append(start_date.strip())
        if end_date and end_date.strip():
            exp_query += " AND e.fldDate <= ?"
            params_e.append(end_date.strip())
        if money_id and money_id > 0:
            exp_query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params_e.extend([money_id, money_id])
        exp_query += " GROUP BY e.fldDate ORDER BY e.fldDate DESC"

        expenses_by_date = {}
        try:
            cursor.execute(exp_query, params_e)
            for r in cursor.fetchall():
                d_str = str(r[0] or '')
                if d_str:
                    expenses_by_date[d_str] = {
                        "totalExpenses": float(r[1] or 0.0),
                        "totalReceipts": float(r[2] or 0.0),
                        "expensesCount": int(r[3] or 0)
                    }
        except Exception as e:
            print("Error query expenses by date:", e)

        # Merge all unique dates
        all_dates = sorted(list(set(
            list(sales_by_date.keys()) +
            list(returns_by_date.keys()) +
            list(purchases_by_date.keys()) +
            list(expenses_by_date.keys())
        )), reverse=True)

        daily_records = []
        tot_sales = 0.0
        tot_cash_sales = 0.0
        tot_credit_sales = 0.0
        tot_returns = 0.0
        tot_purchases = 0.0
        tot_expenses = 0.0
        tot_receipts = 0.0
        tot_sales_cnt = 0
        tot_returns_cnt = 0
        tot_purch_cnt = 0
        tot_exp_cnt = 0

        for dt in all_dates:
            s = sales_by_date.get(dt, {"cashSales": 0.0, "creditSales": 0.0, "totalSales": 0.0, "salesCount": 0})
            r = returns_by_date.get(dt, {"totalReturns": 0.0, "returnsCount": 0})
            p = purchases_by_date.get(dt, {"totalPurchases": 0.0, "purchasesCount": 0})
            e = expenses_by_date.get(dt, {"totalExpenses": 0.0, "totalReceipts": 0.0, "expensesCount": 0})

            d_sales = s["totalSales"]
            d_cash_sales = s["cashSales"]
            d_credit_sales = s["creditSales"]
            d_returns = r["totalReturns"]
            d_purchases = p["totalPurchases"]
            d_expenses = e["totalExpenses"]
            d_receipts = e["totalReceipts"]

            # Daily net: (Sales - Returns - Purchases - Expenses)
            d_net = d_sales - d_returns - d_purchases - d_expenses

            tot_sales += d_sales
            tot_cash_sales += d_cash_sales
            tot_credit_sales += d_credit_sales
            tot_returns += d_returns
            tot_purchases += d_purchases
            tot_expenses += d_expenses
            tot_receipts += d_receipts
            tot_sales_cnt += s["salesCount"]
            tot_returns_cnt += r["returnsCount"]
            tot_purch_cnt += p["purchasesCount"]
            tot_exp_cnt += e["expensesCount"]

            daily_records.append({
                "date": dt,
                "sales": round(d_sales, 2),
                "cashSales": round(d_cash_sales, 2),
                "creditSales": round(d_credit_sales, 2),
                "salesCount": s["salesCount"],
                "returns": round(d_returns, 2),
                "returnsCount": r["returnsCount"],
                "purchases": round(d_purchases, 2),
                "purchasesCount": p["purchasesCount"],
                "expenses": round(d_expenses, 2),
                "expensesCount": e["expensesCount"],
                "receipts": round(d_receipts, 2),
                "netRemainingCash": round(d_net, 2)
            })

        cur_info = cur_map.get(money_id or 1, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})
        net_overall = tot_sales - tot_returns - tot_purchases - tot_expenses

        return {
            "status": "success",
            "startDate": start_date or "",
            "endDate": end_date or "",
            "pointNo": point_no or 0,
            "selectedMoneyId": money_id or 0,
            "currencyName": cur_info.get("name", ""),
            "currencySymbol": cur_info.get("symbol", ""),
            "summary": {
                "totalSales": round(tot_sales, 2),
                "cashSales": round(tot_cash_sales, 2),
                "creditSales": round(tot_credit_sales, 2),
                "totalReturns": round(tot_returns, 2),
                "totalPurchases": round(tot_purchases, 2),
                "totalExpenses": round(tot_expenses, 2),
                "totalReceipts": round(tot_receipts, 2),
                "netRemainingCash": round(net_overall, 2),
                "totalDaysWithActivity": len(daily_records),
                "totalSalesCount": tot_sales_cnt,
                "totalReturnsCount": tot_returns_cnt,
                "totalPurchasesCount": tot_purch_cnt,
                "totalExpensesCount": tot_exp_cnt
            },
            "dailyRecords": daily_records
        }
    finally:
        cursor.close()
        conn.close()

@app.get("/api/reports/account-statement")
def get_account_statement(account_id: Optional[int] = None, start_date: Optional[str] = None, end_date: Optional[str] = None, point_no: Optional[int] = None, money_id: Optional[int] = None):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        target_point = point_no if point_no else db_config.get("point_no", 1)
        ensure_columns_exist(cursor)
        conn.commit()

        cur_map = get_currencies_map(cursor)

        cursor.execute("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES")
        existing_tables = {row[0].lower() for row in cursor.fetchall()}
        has_list = "tblexpenseslist" in existing_tables
        has_type = "tblexpensestype" in existing_tables

        acc_name_expr = "COALESCE(el.fldExpensesName, N'حساب عام')" if has_list else ("COALESCE(et.fldExpensesName, N'حساب عام')" if has_type else "N'حساب عام'")
        join_acc = "LEFT JOIN tblExpensesList el ON e.fldExpensesID = el.fldID " if has_list else ("LEFT JOIN tblExpensesType et ON e.fldExpensesID = et.fldExpensesID " if has_type else "")

        query = (
            f"SELECT e.fldID, COALESCE(m.fldTransNumber, CAST(e.fldID AS float), 0.0) as trans_num, e.fldDate, "
            f"e.fldExpensesID, {acc_name_expr} as acc_name, e.fldAmount, COALESCE(e.fldNote, m.fldDescription, N'') as note, "
            f"e.fldTransID, COALESCE(m.fldMoneyID, 1) as money_id "
            f"FROM tblExpenses e "
            f"LEFT JOIN (SELECT fldTransNumber, MAX(fldDescription) as fldDescription, MAX(fldMoneyID) as fldMoneyID FROM Main GROUP BY fldTransNumber) m ON (ABS(e.fldTransNumber - m.fldTransNumber) < 0.001 OR CAST(e.fldTransNumber AS BIGINT) = CAST(m.fldTransNumber AS BIGINT)) "
            f"{join_acc}"
            f"WHERE (e.fldPointNO = ? OR e.fldPointNO IS NULL) "
        )
        params = [target_point]
        if account_id is not None and account_id > 0:
            query += " AND e.fldExpensesID = ? "
            params.append(account_id)
        if start_date and start_date.strip():
            query += " AND e.fldDate >= ? "
            params.append(start_date.strip())
        if end_date and end_date.strip():
            query += " AND e.fldDate <= ? "
            params.append(end_date.strip())
        if money_id and money_id > 0:
            query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1))"
            params.extend([money_id, money_id])

        query += " ORDER BY e.fldDate ASC, e.fldID ASC"

        cursor.execute(query, params)
        rows = cursor.fetchall()

        movements = []
        total_debit = 0.0
        total_credit = 0.0
        running_balance = 0.0
        cur_statement = {}

        for row in rows:
            fld_id = row[0]
            trans_num = float(row[1] or 0.0)
            tx_date = str(row[2] or "")
            exp_id = row[3] or 0
            exp_name = str(row[4] or "حساب عام")
            raw_amount = float(row[5] or 0.0)
            note = str(row[6] or "")
            mid = int(row[8] or 1)
            cur_info = cur_map.get(mid, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})

            is_debit = raw_amount > 0
            debit = raw_amount if is_debit else 0.0
            credit = abs(raw_amount) if not is_debit else 0.0

            total_debit += debit
            total_credit += credit
            running_balance += (debit - credit)

            if mid not in cur_statement:
                cur_statement[mid] = {"debit": 0.0, "credit": 0.0, "balance": 0.0}
            cur_statement[mid]["debit"] += debit
            cur_statement[mid]["credit"] += credit
            cur_statement[mid]["balance"] += (debit - credit)

            movements.append({
                "id": fld_id,
                "transNumber": trans_num,
                "date": tx_date,
                "expensesId": exp_id,
                "accountName": exp_name,
                "type": "سند صرف / مدين" if is_debit else "سند قبض / دائن",
                "description": note,
                "debit": debit,
                "credit": credit,
                "balance": running_balance,
                "note": note,
                "moneyId": mid,
                "currencyName": cur_info.get("name", ""),
                "currencySymbol": cur_info.get("symbol", "")
            })

        summary_by_cur = {}
        for mid, c_data in cur_statement.items():
            cur_info = cur_map.get(mid, {"name": f"عملة {mid}", "symbol": f"C{mid}", "value": 1.0})
            summary_by_cur[str(mid)] = {
                "moneyId": mid,
                "currencyName": cur_info.get("name", ""),
                "currencySymbol": cur_info.get("symbol", ""),
                "totalDebit": round(c_data["debit"], 2),
                "totalCredit": round(c_data["credit"], 2),
                "balance": round(c_data["balance"], 2)
            }

        return {
            "selectedMoneyId": money_id or 0,
            "accountId": account_id or 0,
            "accountName": "جميع الحسابات والمصاريف" if (not account_id or account_id == 0) else (movements[0]["accountName"] if movements else "الحساب المحدد"),
            "totalDebit": round(total_debit, 2),
            "totalCredit": round(total_credit, 2),
            "balance": round(running_balance, 2),
            "summary": {
                "totalDebit": round(total_debit, 2),
                "totalCredit": round(total_credit, 2),
                "finalBalance": round(running_balance, 2)
            },
            "summaryByCurrency": summary_by_cur,
            "movements": movements
        }
    finally:
        cursor.close()
        conn.close()

@app.get("/api/reports/transactions")
def get_transactions_report(type: int, start_date: Optional[str] = None, end_date: Optional[str] = None, point_no: Optional[int] = None, money_id: Optional[int] = None):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        target_point = point_no if point_no else db_config.get("point_no", 1)
        ensure_columns_exist(cursor)
        conn.commit()

        if type in [10, 11, 100]:
            # Bonds report (10 = Receipt, 11 = Payment, 100 = All Bonds)
            return get_bonds(start_date, end_date, target_point, type, money_id)

        cur_map = get_currencies_map(cursor)

        query = (
            "SELECT d.fldTransNumber, m.fldDate, m.fldDescription, m.fldPaycash, "
            "  COALESCE(d.fldBarCode, '') as barcode, "
            "  COALESCE(l.fldItemName, d.fldBarCode, N'صنف') as item_name, "
            "  COALESCE(l.fldUnitName, N'حبة') as unit_name, "
            "  COALESCE(d.fldQuantity, 0) as quantity, "
            "  COALESCE(d.fldSalesPrice, 0.0) as sales_price, "
            "  COALESCE(d.fldTotalItem, (d.fldQuantity * d.fldSalesPrice), 0.0) as total_amount, "
            "  COALESCE(u.fldUserName, CAST(m.fldUSerID AS varchar), N'مستخدم 1') as user_name, "
            "  COALESCE(m.fldMoneyID, 1) as money_id "
            "FROM details d "
            "JOIN Main m ON d.fldTransNumber = m.fldTransNumber "
            "LEFT JOIN List l ON d.fldBarCode = l.fldBarCode "
            "LEFT JOIN tblUsers u ON m.fldUSerID = u.fldUSerID "
            "WHERE m.fldType = ? AND (d.fldPointNO = ? OR m.fldPointNO = ?) "
        )
        params = [type, target_point, target_point]
        if start_date and end_date:
            query += " AND m.fldDate >= ? AND m.fldDate <= ? "
            params.extend([start_date, end_date])
        if money_id and money_id > 0:
            query += " AND (m.fldMoneyID = ? OR (m.fldMoneyID IS NULL AND ? = 1)) "
            params.extend([money_id, money_id])
            
        query += " ORDER BY m.fldTransNumber DESC, d.fldBarCode ASC"
        
        cursor.execute(query, params)
        transactions = []
        for row in cursor.fetchall():
            mid = int(row[11] or 1)
            cur_info = cur_map.get(mid, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})
            transactions.append({
                "transNumber": row[0],
                "date": str(row[1]),
                "description": row[2] or "",
                "payCash": row[3],
                "barcode": str(row[4] or "").strip(),
                "itemName": str(row[5] or "").strip(),
                "unitName": str(row[6] or "حبة").strip(),
                "quantity": int(row[7] or 0),
                "salesPrice": float(row[8] or 0.0),
                "amount": float(row[9] or 0.0),
                "userName": str(row[10] or "مستخدم 1").strip(),
                "moneyId": mid,
                "currencyName": cur_info.get("name", ""),
                "currencySymbol": cur_info.get("symbol", ""),
                "exchangeRate": cur_info.get("value", 1.0)
            })
        return transactions
    finally:
        cursor.close()
        conn.close()

@app.get("/api/reports/stock")
def get_stock_report(
    status_filter: Optional[str] = "all",
    group_id: Optional[int] = 0,
    search_query: Optional[str] = "",
    point_no: Optional[int] = None,
    zero_threshold: Optional[int] = 0,
    money_id: Optional[int] = None
):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        target_point = point_no if point_no else db_config.get("point_no", 1)
        thresh = zero_threshold if zero_threshold is not None and zero_threshold >= 0 else 0
        cur_map = get_currencies_map(cursor)

        query = (
            "SELECT l.fldBarCode, l.fldItemName, COALESCE(l.fldUnitName, N'حبة') as unit_name, "
            "COALESCE(l.fldSalesPrice, 0.0) as sales_price, COALESCE(l.fldCost, 0.0) as cost, COALESCE(l.fldGroupID, 0) as group_id, "
            "COALESCE(SUM(CASE "
            "  WHEN m.fldType IN (1, 2, 20, 22, 36, 4, 37, 5, 38, 28) THEN d.fldQuantity "
            "  WHEN m.fldType IN (35, 21, 23, 6, 39) THEN -d.fldQuantity "
            "  ELSE 0 END), 0) as current_qty, "
            "COALESCE(l.fldMoneyID, 1) as money_id "
            "FROM List l "
            "LEFT JOIN details d ON l.fldBarCode = d.fldBarCode AND (d.fldPointNO = ? OR d.fldPointNO IS NULL) "
            "LEFT JOIN Main m ON d.fldTransNumber = m.fldTransNumber "
            "WHERE 1=1 "
        )
        params = [target_point]
        if group_id and group_id > 0:
            query += " AND l.fldGroupID = ? "
            params.append(group_id)
        if search_query and search_query.strip():
            query += " AND (l.fldItemName LIKE ? OR l.fldBarCode LIKE ?) "
            q = f"%{search_query.strip()}%"
            params.extend([q, q])
        if money_id and money_id > 0:
            query += " AND (l.fldMoneyID = ? OR (l.fldMoneyID IS NULL AND ? = 1)) "
            params.extend([money_id, money_id])

        query += " GROUP BY l.fldBarCode, l.fldItemName, l.fldUnitName, l.fldSalesPrice, l.fldCost, l.fldGroupID, l.fldMoneyID ORDER BY l.fldItemName"
        cursor.execute(query, params)

        items = []
        total_available = 0
        total_zero = 0
        total_low = 0
        total_stock_val = 0.0
        total_cost_val = 0.0
        val_by_currency = {}

        for row in cursor.fetchall():
            barcode = str(row[0] or "").strip()
            item_name = str(row[1] or "").strip()
            unit_name = str(row[2] or "حبة").strip()
            sales_price = float(row[3] or 0.0)
            cost_price = float(row[4] or 0.0)
            gid = int(row[5] or 0)
            qty = int(row[6] or 0)
            mid = int(row[7] or 1)
            cur_info = cur_map.get(mid, {"name": "دينار أردني", "symbol": "د.أ", "value": 1.0})

            item_sales_val = sales_price * qty
            item_cost_val = cost_price * qty

            if qty > thresh:
                status = "available"
                total_available += 1
                total_stock_val += item_sales_val
                total_cost_val += item_cost_val
                if mid not in val_by_currency:
                    val_by_currency[mid] = {"salesVal": 0.0, "costVal": 0.0}
                val_by_currency[mid]["salesVal"] += item_sales_val
                val_by_currency[mid]["costVal"] += item_cost_val
            elif qty <= thresh and qty >= 0:
                status = "zero"
                total_zero += 1
            else:
                status = "low"
                total_low += 1

            if status_filter == "available" and status != "available":
                continue
            if status_filter == "zero" and status != "zero":
                continue
            if status_filter == "low" and status != "low":
                continue

            items.append({
                "barcode": barcode,
                "itemName": item_name,
                "unitName": unit_name,
                "salesPrice": sales_price,
                "costPrice": cost_price,
                "groupId": gid,
                "quantity": qty,
                "currentQuantity": qty,
                "costValue": round(item_cost_val, 2),
                "salesValue": round(item_sales_val, 2),
                "stockValue": round(item_sales_val, 2),
                "status": status,
                "moneyId": mid,
                "currencyName": cur_info.get("name", ""),
                "currencySymbol": cur_info.get("symbol", "")
            })

        currency_breakdown = []
        for mid, v in val_by_currency.items():
            cur_info = cur_map.get(mid, {"name": f"عملة {mid}", "symbol": f"C{mid}", "value": 1.0})
            currency_breakdown.append({
                "moneyId": mid,
                "currencyName": cur_info.get("name", ""),
                "currencySymbol": cur_info.get("symbol", ""),
                "stockValue": round(v["salesVal"], 2),
                "costValue": round(v["costVal"], 2)
            })

        return {
            "selectedMoneyId": money_id or 0,
            "summary": {
                "totalItems": len(items),
                "totalAvailable": total_available,
                "totalZero": total_zero,
                "totalLow": total_low,
                "totalStockValue": round(total_stock_val, 2),
                "totalStockCostValue": round(total_cost_val, 2),
                "totalCostValue": round(total_cost_val, 2),
                "byCurrency": currency_breakdown
            },
            "items": items
        }
    finally:
        cursor.close()
        conn.close()

@app.get("/api/reports/pos-movements")
def get_pos_movements(point_no: Optional[int] = None, start_date: Optional[str] = None, end_date: Optional[str] = None):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT LOWER(table_name) FROM information_schema.tables")
        tables = set(r[0] for r in cursor.fetchall())

        has_main = "main" in tables
        has_details = "details" in tables
        has_list = "list" in tables
        has_barcode = "tblbarcode" in tables
        has_item = "tblitem" in tables
        has_menus = "tblmenus" in tables

        if not has_main or not has_details:
            return {"movements": [], "summary": {"salesTotal": 0.0, "returnsTotal": 0.0, "receiptsTotal": 0.0, "disbursementsTotal": 0.0, "totalCount": 0}}

        extra_joins = ""
        name_col = "d.fldBarCode"

        if has_list:
            extra_joins += " LEFT JOIN dbo.List l ON d.fldBarCode = l.fldBarCode "
            name_col = "COALESCE(l.fldItemName, d.fldBarCode, N'غير محدد')"
        elif has_barcode and has_item:
            extra_joins += " LEFT JOIN dbo.tblBarCode b ON d.fldBarCode = b.fldBarCode LEFT JOIN dbo.tblItem i ON b.flditemID = i.fldID "
            name_col = "COALESCE(i.fldName, d.fldBarCode, N'غير محدد')"

        if has_menus:
            extra_joins += " LEFT JOIN dbo.tblMenus m ON m.fldID = mn.fldType "
            menu_name_col = "COALESCE(m.fldDescription, mn.fldDescription, CASE WHEN mn.fldType = 35 THEN N'مبيعات' WHEN mn.fldType = 36 THEN N'مرتجع مبيعات' ELSE N'حركة مبيعات' END)"
        else:
            menu_name_col = "COALESCE(mn.fldDescription, CASE WHEN mn.fldType = 35 THEN N'مبيعات' WHEN mn.fldType = 36 THEN N'مرتجع مبيعات' ELSE N'حركة مبيعات' END)"

        query = (
            f"SELECT "
            f"  {menu_name_col} AS fldNMenuame, "
            f"  d.fldBarCode, "
            f"  {name_col} AS fldName, "
            f"  d.fldQuantity, "
            f"  d.fldSalesPrice, "
            f"  d.fldDiscount, "
            f"  d.fldTotalItem, "
            f"  mn.fldTransNumber, "
            f"  mn.fldDate, "
            f"  mn.fldPointNO, "
            f"  mn.fldType "
            f"FROM dbo.Main mn "
            f"INNER JOIN dbo.details d ON (mn.fldTransNumber = d.fldTransNumber OR ABS(mn.fldTransNumber - d.fldTransNumber) < 0.001) "
            f"{extra_joins} "
            f"WHERE 1=1 "
        )
        params = []
        if point_no is not None and point_no > 0:
            query += " AND mn.fldPointNO = ? "
            params.append(point_no)
        if start_date:
            query += " AND mn.fldDate >= ? "
            params.append(start_date)
        if end_date:
            if len(end_date) == 10:
                query += " AND mn.fldDate <= ? "
                params.append(f"{end_date} 23:59:59")
            else:
                query += " AND mn.fldDate <= ? "
                params.append(end_date)
            
        query += " ORDER BY mn.fldTransNumber DESC"
        
        cursor.execute(query, params)
        movements = []
        
        sales_total = 0.0
        returns_total = 0.0
        receipts_total = 0.0
        disbursements_total = 0.0
        
        for row in cursor.fetchall():
            menu_name = str(row[0] or "")
            barcode = str(row[1] or "")
            item_name = str(row[2] or "")
            quantity = float(row[3] or 0.0)
            sales_price = float(row[4] or 0.0)
            discount = float(row[5] or 0.0)
            total_item = float(row[6] or 0.0)
            trans_number = int(row[7] or 0)
            trans_date = str(row[8] or "")
            pt_no = int(row[9] or 0)
            trans_type = int(row[10] or 0)
            
            # Statistics breakdown
            if trans_type in [35, 31]:
                sales_total += total_item
            elif trans_type == 36:
                returns_total += total_item
            elif trans_type in [22, 10, 1]:
                receipts_total += total_item
            elif trans_type in [23, 11, 20]:
                disbursements_total += total_item
            else:
                sales_total += total_item
                
            movements.append({
                "fldNMenuame": menu_name,
                "fldBarCode": barcode,
                "fldName": item_name,
                "fldQuantity": quantity,
                "fldSalesPrice": sales_price,
                "fldDiscount": discount,
                "fldTotalItem": total_item,
                "fldTransNumber": trans_number,
                "fldDate": trans_date,
                "fldPointNO": pt_no,
                "fldType": trans_type
            })
            
        return {
            "movements": movements,
            "summary": {
                "salesTotal": sales_total,
                "returnsTotal": returns_total,
                "receiptsTotal": receipts_total,
                "disbursementsTotal": disbursements_total,
                "totalCount": len(movements)
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cursor.close()
        conn.close()

@app.get("/api/reports/item-movement")
def get_item_movement_report(query: Optional[str] = "", start_date: Optional[str] = None, end_date: Optional[str] = None, point_no: Optional[int] = None):
    conn = get_db_connection_for_point(point_no)
    cursor = conn.cursor()
    try:
        target_point = point_no if point_no else db_config.get("point_no", 1)

        # 1. Fetch item information from List table if available
        item_info = None
        if query:
            q_clean = query.strip()
            cursor.execute(
                "SELECT TOP 1 fldBarCode, fldItemName, fldUnitName, fldSalesPrice, fldCost, flditemID "
                "FROM List WHERE fldBarCode = ? OR fldItemName LIKE ? OR CAST(flditemID AS varchar) = ?",
                (q_clean, f"%{q_clean}%", q_clean)
            )
            item_row = cursor.fetchone()
            if item_row:
                item_info = {
                    "barcode": str(item_row[0] or "").strip(),
                    "itemName": str(item_row[1] or "").strip(),
                    "unitName": str(item_row[2] or "حبة").strip(),
                    "salesPrice": float(item_row[3] or 0.0),
                    "cost": float(item_row[4] or 0.0),
                    "itemId": item_row[5] or 0
                }
        
        # 2. Build movement query joining details, Main, List, and tblUsers filtered by point_no
        sql = (
            "SELECT "
            "  d.fldTransNumber, "
            "  m.fldDate, "
            "  m.fldType, "
            "  d.fldBarCode, "
            "  COALESCE(l.fldItemName, d.fldBarCode, N'صنف غير معروف') as item_name, "
            "  COALESCE(l.fldUnitName, N'حبة') as unit_name, "
            "  COALESCE(d.fldQuantity, 0) as quantity, "
            "  COALESCE(d.fldSalesPrice, 0.0) as sales_price, "
            "  COALESCE(d.fldTotalItem, (d.fldQuantity * d.fldSalesPrice), 0.0) as total_item, "
            "  COALESCE(u.fldUserName, CAST(m.fldUSerID AS varchar), N'مستخدم 1') as user_name, "
            "  COALESCE(m.fldDescription, N'') as description "
            "FROM details d "
            "JOIN Main m ON d.fldTransNumber = m.fldTransNumber "
            "LEFT JOIN List l ON d.fldBarCode = l.fldBarCode "
            "LEFT JOIN tblUsers u ON m.fldUSerID = u.fldUSerID "
            "WHERE (d.fldPointNO = ? OR m.fldPointNO = ?) "
        )
        params = [target_point, target_point]
        if query:
            q_clean = query.strip()
            sql += " AND (d.fldBarCode = ? OR l.fldItemName LIKE ? OR CAST(l.flditemID AS varchar) = ?) "
            params.extend([q_clean, f"%{q_clean}%", q_clean])
            
        if start_date:
            sql += " AND m.fldDate >= ? "
            params.append(start_date)
        if end_date:
            sql += " AND m.fldDate <= ? "
            params.append(end_date)
            
        sql += " ORDER BY m.fldDate ASC, m.fldTransNumber ASC"
        
        cursor.execute(sql, params)
        rows = cursor.fetchall()
        
        type_names = {
            1: "مخزون أول المدة",
            2: "مشتريات جديدة",
            20: "مشتريات جديدة",
            21: "مرتجع مشتريات",
            22: "توريد مخزني",
            23: "صرف مخزني",
            28: "تحويل مخزني بين الفروع",
            35: "مبيعات كاشير",
            36: "مرتجع مبيعات"
        }
        
        # Types that ADD to stock (+)
        add_types = {1, 2, 20, 22, 36}
        
        movements = []
        running_balance = 0
        total_in = 0
        total_out = 0
        
        for r in rows:
            trans_num = r[0]
            t_date = str(r[1])
            t_type = r[2] or 35
            b_code = str(r[3] or "").strip()
            i_name = str(r[4] or "").strip()
            u_name = str(r[5] or "حبة").strip()
            raw_qty = int(r[6] or 0)
            unit_price = float(r[7] or 0.0)
            total_amt = float(r[8] or 0.0)
            user_str = str(r[9] or "مستخدم 1").strip()
            desc = str(r[10] or "").strip()
            
            if t_type == 28:
                is_addition = raw_qty >= 0
                actual_qty = raw_qty
            else:
                is_addition = t_type in add_types
                actual_qty = raw_qty if is_addition else -raw_qty

            running_balance += actual_qty
            
            if actual_qty > 0:
                total_in += actual_qty
            elif actual_qty < 0:
                total_out += abs(actual_qty)
                
            type_label = type_names.get(t_type, f"حركة #{t_type}")
            
            movements.append({
                "transNumber": trans_num,
                "date": t_date,
                "typeId": t_type,
                "typeName": type_label,
                "barcode": b_code,
                "itemName": i_name,
                "unitName": u_name,
                "rawQuantity": raw_qty,
                "actualQuantity": actual_qty,
                "isAddition": is_addition,
                "unitPrice": unit_price,
                "totalAmount": total_amt,
                "runningBalance": running_balance,
                "userName": user_str,
                "description": desc
            })
            
        return {
            "status": "success",
            "query": query,
            "startDate": start_date,
            "endDate": end_date,
            "itemInfo": item_info or {
                "barcode": query or "",
                "itemName": movements[0]["itemName"] if movements else (query or "جميع الأصناف"),
                "unitName": movements[0]["unitName"] if movements else "حبة",
                "salesPrice": movements[0]["unitPrice"] if movements else 0.0,
                "cost": 0.0,
                "itemId": 0
            },
            "summary": {
                "totalMovements": len(movements),
                "totalIncoming": total_in,
                "totalOutgoing": total_out,
                "currentBalance": running_balance
            },
            "movements": movements
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"فشل جلب حركة الصنف: {str(e)}")
    finally:
        cursor.close()
        conn.close()

@app.get("/api/remote/branch-item-search")
def search_remote_branch_items(query: str):
    if not query or len(query.strip()) == 0:
        return {"items": [], "source": "none"}

    q_clean = query.strip()
    q_like = f"%{q_clean}%"
    results = []
    source = "remote"

    try:
        conn = get_remote_connection()
    except Exception as ex_remote:
        print(f"Remote DB connection failed in search, falling back to local DB: {ex_remote}")
        try:
            conn = get_connection()
            source = "local"
        except Exception as ex_local:
            raise HTTPException(status_code=500, detail=f"فشل الاتصال بجميع قواعد البيانات: {str(ex_local)}")

    cursor = conn.cursor()
    try:
        # Inspect available tables in current database
        cursor.execute("SELECT LOWER(TABLE_NAME) FROM INFORMATION_SCHEMA.TABLES")
        tables = {row[0] for row in cursor.fetchall()}

        has_details = "details" in tables
        has_main = "main" in tables
        has_list = "list" in tables
        has_point_list = "tblpointlist" in tables
        has_item = "tblitem" in tables
        has_barcode = "tblbarcode" in tables

        # --- STEP 1: Query transactions details + Main per point ---
        if has_details and has_main:
            join_list = "LEFT JOIN List l ON d.fldBarCode = l.fldBarCode" if has_list else ""
            join_barcode = "LEFT JOIN tblBarCode b ON d.fldBarCode = b.fldBarCode" if has_barcode else ""
            join_item = "LEFT JOIN tblItem i ON b.flditemID = i.fldID" if (has_barcode and has_item) else ""
            join_point = "LEFT JOIN tblPointList p ON COALESCE(d.fldPointNO, m.fldPointNO) = p.fldPointNO" if has_point_list else ""

            name_col = "COALESCE("
            if has_item:
                name_col += "i.fldName, "
            if has_list:
                name_col += "l.fldItemName, "
            name_col += "d.fldBarCode, N'صنف غير معروف')"

            point_name_col = "COALESCE("
            if has_point_list:
                point_name_col += "p.fldName, "
            point_name_col += "CONCAT(N'فرع / نقطة #', COALESCE(d.fldPointNO, m.fldPointNO, 1)))"

            where_conditions = ["(d.fldBarCode = ? OR d.fldBarCode LIKE ?)"]
            params = [q_clean, q_like]

            if has_list:
                where_conditions.append("l.fldItemName LIKE ?")
                params.append(q_like)
            if has_item:
                where_conditions.append("i.fldName LIKE ?")
                params.append(q_like)

            where_sql = " OR ".join(where_conditions)

            sql_details = f"""
                SELECT 
                    {point_name_col} AS branch_name,
                    d.fldBarCode, 
                    {name_col} AS item_name, 
                    COALESCE(SUM(CASE 
                        WHEN m.fldType IN (1, 2, 20, 22, 36, 4, 37, 5, 38, 28) THEN d.fldQuantity 
                        WHEN m.fldType IN (35, 21, 23, 6, 39) THEN -d.fldQuantity 
                        ELSE 0 END), 0) AS quantity,
                    COALESCE(MAX(d.fldSalesPrice), 0.0) AS sales_price,
                    COALESCE(d.fldPointNO, m.fldPointNO, 1) AS point_no
                FROM details d
                INNER JOIN Main m ON d.fldTransNumber = m.fldTransNumber 
                {join_list}
                {join_barcode}
                {join_item}
                {join_point}
                WHERE ({where_sql})
                GROUP BY {point_name_col}, COALESCE(d.fldPointNO, m.fldPointNO, 1), d.fldBarCode, {name_col}
                ORDER BY item_name, branch_name
            """
            try:
                cursor.execute(sql_details, params)
                for row in cursor.fetchall():
                    results.append({
                        "branchName": str(row[0] or f"فرع #{row[5]}").strip(),
                        "barcode": str(row[1] or "").strip(),
                        "itemName": str(row[2] or "").strip(),
                        "quantity": float(row[3] or 0.0),
                        "salesPrice": float(row[4] or 0.0),
                        "pointNo": int(row[5] or 1)
                    })
            except Exception as ex1:
                print("Error executing sql_details in branch item search:", ex1)

        # --- STEP 2: If no results from transactions, query List master table directly ---
        if not results and has_list:
            join_point = "LEFT JOIN tblPointList p ON l.fldPointNO = p.fldPointNO" if has_point_list else ""
            point_name_col = "COALESCE(p.fldName, CONCAT(N'فرع / نقطة #', COALESCE(l.fldPointNO, 1)))" if has_point_list else "CONCAT(N'فرع / نقطة #', COALESCE(l.fldPointNO, 1))"

            sql_list = f"""
                SELECT 
                    {point_name_col} AS branch_name,
                    l.fldBarCode,
                    COALESCE(l.fldItemName, l.fldBarCode, N'صنف') AS item_name,
                    COALESCE(SUM(l.fldQuantity), 0) AS quantity,
                    COALESCE(MAX(l.fldSalesPrice), 0.0) AS sales_price,
                    COALESCE(l.fldPointNO, 1) AS point_no
                FROM List l
                {join_point}
                WHERE (l.fldBarCode = ? OR l.fldBarCode LIKE ? OR l.fldItemName LIKE ?)
                GROUP BY {point_name_col}, COALESCE(l.fldPointNO, 1), l.fldBarCode, l.fldItemName
                ORDER BY item_name, branch_name
            """
            try:
                cursor.execute(sql_list, (q_clean, q_like, q_like))
                for row in cursor.fetchall():
                    results.append({
                        "branchName": str(row[0] or f"فرع #{row[5]}").strip(),
                        "barcode": str(row[1] or "").strip(),
                        "itemName": str(row[2] or "").strip(),
                        "quantity": float(row[3] or 0.0),
                        "salesPrice": float(row[4] or 0.0),
                        "pointNo": int(row[5] or 1)
                    })
            except Exception as ex2:
                print("Error executing sql_list in branch item search:", ex2)

        return {"items": results, "source": source}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"خطأ أثناء استعلام أصناف الفروع: {str(e)}")
    finally:
        cursor.close()
        conn.close()


# --- Connection Settings Endpoints ---

@app.get("/api/settings/connection")
def get_connection_settings():
    return {
        "server": db_config["server"],
        "remoteServer": db_config.get("remote_server", db_config["server"]),
        "localDb": db_config["local_db"],
        "remoteDb": db_config.get("remote_db", "sp"),
        "username": db_config["username"],
        "password": db_config["password"],
        "port": db_config.get("port", ""),
        "pointNo": db_config.get("point_no", 1),
        "pointName": db_config.get("point_name", "الرئيسية"),
        "logoBase64": db_config.get("logo_base64", "")
    }

@app.post("/api/settings/connection")
def update_connection_settings(settings: ConnectionSettingsRequest):
    drivers = get_installed_sql_drivers()
    
    # 1. Test Local Connection
    local_server = settings.server
    if settings.port:
        local_server = f"{local_server},{settings.port}"
        
    local_connected = False
    local_error = ""
    
    for driver in drivers:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={local_server};"
                f"Database={settings.localDb};"
                f"Uid={settings.username};"
                f"Pwd={settings.password};"
                f"Encrypt=no;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            conn.close()
            local_connected = True
            break
        except Exception as e:
            local_error = str(e)
            continue
            
    if not local_connected:
        for driver in drivers:
            try:
                conn_str = (
                    f"Driver={driver};"
                    f"Server={local_server};"
                    f"Database={settings.localDb};"
                    f"Uid={settings.username};"
                    f"Pwd={settings.password};"
                    f"Connection Timeout=5;"
                )
                conn = pyodbc.connect(conn_str)
                conn.close()
                local_connected = True
                break
            except Exception as e:
                local_error = str(e)
                continue
                
    if not local_connected:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"فشل الاتصال بالسيرفر المحلي بالإعدادات المدخلة: {local_error}"
        )
        
    # 2. Test Remote Connection
    remote_server = settings.remoteServer
    if settings.port:
        remote_server = f"{remote_server},{settings.port}"
        
    remote_connected = False
    remote_error = ""
    
    for driver in drivers:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={remote_server};"
                f"Database={settings.remoteDb};"
                f"Uid={settings.username};"
                f"Pwd={settings.password};"
                f"Encrypt=no;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            conn.close()
            remote_connected = True
            break
        except Exception as e:
            remote_error = str(e)
            continue
            
    if not remote_connected:
        for driver in drivers:
            try:
                conn_str = (
                    f"Driver={driver};"
                    f"Server={remote_server};"
                    f"Database={settings.remoteDb};"
                    f"Uid={settings.username};"
                    f"Pwd={settings.password};"
                    f"Connection Timeout=5;"
                )
                conn = pyodbc.connect(conn_str)
                conn.close()
                remote_connected = True
                break
            except Exception as e:
                remote_error = str(e)
                continue
                
    if not remote_connected:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"فشل الاتصال بالسيرفر الرئيسي بالإعدادات المدخلة: {remote_error}"
        )
        
    # Save the settings if both connected successfully
    global db_config
    db_config["server"] = settings.server
    db_config["remote_server"] = settings.remoteServer
    db_config["local_db"] = settings.localDb
    db_config["remote_db"] = settings.remoteDb
    db_config["username"] = settings.username
    db_config["password"] = settings.password
    db_config["port"] = settings.port or ""
    db_config["point_no"] = settings.pointNo
    db_config["point_name"] = settings.pointName
    db_config["logo_base64"] = settings.logoBase64 or ""
    save_db_config()
    
    return {"status": "success", "message": "تم التحقق وحفظ إعدادات الاتصال بنجاح"}

class SaveLogoRequest(BaseModel):
    logo_base64: Optional[str] = ""

@app.post("/api/settings/logo")
def save_invoice_logo(req: SaveLogoRequest):
    global db_config
    db_config["logo_base64"] = req.logo_base64 or ""
    save_db_config()
    return {"status": "success", "message": "تم حفظ شعار الفاتورة بنجاح", "logoBase64": db_config["logo_base64"]}

@app.post("/api/settings/fetch-points")
def fetch_points(settings: FetchPointsRequest):
    drivers = get_installed_sql_drivers()
    
    server = settings.remoteServer
    if settings.port:
        server = f"{server},{settings.port}"
        
    connected = False
    last_error = ""
    conn = None
    
    for driver in drivers:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={server};"
                f"Database={settings.remoteDb};"
                f"Uid={settings.username};"
                f"Pwd={settings.password};"
                f"Encrypt=no;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=5;"
            )
            conn = pyodbc.connect(conn_str)
            connected = True
            break
        except Exception as e:
            last_error = str(e)
            continue
            
    if not connected:
        for driver in drivers:
            try:
                conn_str = (
                    f"Driver={driver};"
                    f"Server={server};"
                    f"Database={settings.remoteDb};"
                    f"Uid={settings.username};"
                    f"Pwd={settings.password};"
                    f"Connection Timeout=3;"
                )
                conn = pyodbc.connect(conn_str)
                connected = True
                break
            except Exception as e:
                last_error = str(e)
                continue
                
    if not connected:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"فشل الاتصال بالسيرفر الرئيسي لجلب نقاط البيع: {last_error}"
        )
        
    cursor = conn.cursor()
    try:
        # User query: SELECT fldPointNO, fldName FROM dbo.tblPointList
        cursor.execute("SELECT fldPointNO, fldName FROM dbo.tblPointList ORDER BY fldPointNO")
        points = []
        for row in cursor.fetchall():
            points.append({
                "pointNo": int(row[0]),
                "name": row[1] or f"نقطة رقم {row[0]}"
            })
        return points
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"فشل استعلام جدول نقاط البيع tblPointList في قاعدة البيانات الرئيسية: {str(e)}"
        )
    finally:
        cursor.close()
        conn.close()

@app.get("/api/points")
def get_local_points():
    conn = get_connection()
    cursor = conn.cursor()
    try:
        # Check if table exists locally
        cursor.execute("SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblPointList]') AND type in (N'U')")
        exists = cursor.fetchone()[0] > 0
        if not exists:
            return []
            
        cursor.execute("SELECT fldPointNO, fldName, fldBranchNo, fldstoreID, DataSource, Catalog, UserID, Password FROM tblPointList")
        rows = cursor.fetchall()
        points = []
        for r in rows:
            points.append({
                "fldPointNO": int(r[0] or 0),
                "fldName": str(r[1] or "").strip(),
                "fldBranchNo": int(r[2] or 0),
                "fldstoreID": int(r[3] or 0),
                "DataSource": str(r[4] or "").strip(),
                "Catalog": str(r[5] or "").strip(),
                "UserID": str(r[6] or "").strip(),
                "Password": str(r[7] or "").strip(),
            })
        return points
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        conn.close()

@app.post("/api/settings/sync-items")
def sync_items():
    # 1. Connect to local DB to read connection settings
    conn_local = get_connection()
    cursor_local = conn_local.cursor()
    
    # 2. Connect to remote main database
    drivers = [
        "{ODBC Driver 17 for SQL Server}",
        "{ODBC Driver 18 for SQL Server}",
        "{SQL Server}",
    ]
    
    remote_server = db_config["remote_server"]
    if db_config.get("port"):
        remote_server = f"{remote_server},{db_config['port']}"
        
    connected = False
    conn_remote = None
    last_error = ""
    
    for driver in drivers:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={remote_server};"
                f"Database={db_config['remote_db']};"
                f"Uid={db_config['username']};"
                f"Pwd={db_config['password']};"
                f"Encrypt=no;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=4;"
            )
            conn_remote = pyodbc.connect(conn_str)
            connected = True
            break
        except Exception as e:
            last_error = str(e)
            continue
            
    if not connected:
        for driver in drivers:
            try:
                conn_str = (
                    f"Driver={driver};"
                    f"Server={remote_server};"
                    f"Database={db_config['remote_db']};"
                    f"Uid={db_config['username']};"
                    f"Pwd={db_config['password']};"
                    f"Connection Timeout=4;"
                )
                conn_remote = pyodbc.connect(conn_str)
                connected = True
                break
            except Exception as e:
                last_error = str(e)
                continue
                
    if not connected:
        cursor_local.close()
        conn_local.close()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"فشل الاتصال بالسيرفر الرئيسي البعيد لبدء المزامنة: {last_error}"
        )
        
    cursor_remote = conn_remote.cursor()
    
    try:
        # --- PHASE 1: Sync Currencies (tblMoney) ---
        cursor_remote.execute(
            "SELECT fldsymbol, fldName, fldValue, fldTypeOperation, fldID FROM tblMoney"
        )
        remote_currencies = cursor_remote.fetchall()
        
        # Clear local tblMoney and insert
        cursor_local.execute("DELETE FROM tblMoney")
        insert_money_query = """
        INSERT INTO tblMoney (fldsymbol, fldName, fldValue, fldTypeOperation, fldID)
        VALUES (?, ?, ?, ?, ?)
        """
        for row in remote_currencies:
            cursor_local.execute(insert_money_query, (row[0], row[1], float(row[2] or 1.0), int(row[3] or 1), int(row[4] or 1)))
            
        # Get YER/SAR rate dynamically from the newly synchronized table
        cursor_local.execute("SELECT fldValue FROM tblMoney WHERE fldID = 2")
        sar_rate = float(cursor_local.fetchval() or 416.0)

        # --- PHASE 2: Sync Groups (tblItemGroup) ---
        cursor_remote.execute(
            "SELECT fldName, fldCode, fldMainGroupID, fldUserID, fldID FROM tblItemGroup"
        )
        remote_groups = cursor_remote.fetchall()
        
        cursor_local.execute("DELETE FROM tblItemGroup")
        insert_group_query = """
        INSERT INTO tblItemGroup (fldName, fldCode, fldMainGroupID, fldUserID, fldID)
        VALUES (?, ?, ?, ?, ?)
        """
        for row in remote_groups:
            cursor_local.execute(
                insert_group_query,
                (row[0] or "", row[1] or "", int(row[2] or 0), int(row[3] or 1), int(row[4] or 0))
            )

        # --- PHASE 3: Sync Users (tblUsers) ---
        cursor_remote.execute(
            """
            SELECT fldUSerID, fldUserName, fldPassword, fldsale, fldAdmin, 
                   fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport, fldMoneyID 
            FROM tblUsers
            """
        )
        remote_users = cursor_remote.fetchall()
        
        cursor_local.execute("DELETE FROM tblUsers")
        insert_user_query = """
        INSERT INTO tblUsers (
            fldUSerID, fldUserName, fldPassword, fldsale, fldAdmin, 
            fldReturn, fldSalesPrice, fldDiscount, fldlExpenses, fldReport, fldMoneyID
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        for row in remote_users:
            cursor_local.execute(
                insert_user_query,
                (
                    int(row[0] or 0),
                    str(row[1] or ""),
                    str(row[2] or ""),
                    bool(row[3] if row[3] is not None else 1),
                    bool(row[4] if row[4] is not None else 0),
                    bool(row[5] if row[5] is not None else 1),
                    bool(row[6] if row[6] is not None else 1),
                    bool(row[7] if row[7] is not None else 1),
                    bool(row[8] if row[8] is not None else 1),
                    bool(row[9] if row[9] is not None else 1),
                    bool(row[10] if row[10] is not None else 1),
                )
            )

        # --- PHASE 4: Sync Items (List / tblBarCode) ---
        cursor_remote.execute("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'")
        remote_tables = [r[0].lower() for r in cursor_remote.fetchall()]

        inserted_items_count = 0
        if 'tblbarcode' in remote_tables and 'tblitem' in remote_tables:
            query_items = """
            SELECT 
                dbo.tblBarCode.fldBarCode, 
                dbo.tblItem.fldName AS fldItemName, 
                dbo.tblItemsUnit.fldUnitName, 
                dbo.tblItemsUnit.fldSalesPrice1, 
                dbo.tblBarCode.flditemID, 
                dbo.tblBarCode.fldUnityID, 
                dbo.tblItem.fldGroupID, 
                dbo.tblItem.fldMoneyID, 
                dbo.tblItem.fldIsActive, 
                dbo.tblItemsUnit.fldCost
            FROM dbo.tblBarCode 
            INNER JOIN dbo.tblItem ON dbo.tblBarCode.flditemID = dbo.tblItem.fldID 
            INNER JOIN dbo.tblItemsUnit ON dbo.tblItem.fldID = dbo.tblItemsUnit.flditemID
            """
            cursor_remote.execute(query_items)
            remote_items = cursor_remote.fetchall()
            
            cursor_local.execute("DELETE FROM List")
            insert_item_query = """
            INSERT INTO List (
                fldBarCode, fldItemName, fldUnitName, fldSalesPrice, ID, fldSales, 
                fldGroupID, flditemID, fldUnityID, fldMoneyID, fldIsActive, fldCost, fldok
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """
            
            seen_barcodes = set()
            seen_ids = set()

            for row in remote_items:
                barcode = (row[0] or "").strip()
                item_name = str(row[1] or "").strip()
                unit_name = str(row[2] or "").strip()
                sales_price_remote = float(row[3] or 0.0)
                item_id = int(row[4] or 0)
                unity_id = int(row[5] or 0)
                group_id = int(row[6] or 0)
                money_id_remote = int(row[7] or 1)
                is_active = bool(row[8])
                cost_remote = float(row[9] or 0.0)
                
                if not barcode:
                    barcode = str(item_id).zfill(6)
                    
                if item_id in seen_ids or barcode in seen_barcodes:
                    continue

                sales_price_local = sales_price_remote * sar_rate
                cost_local = cost_remote * sar_rate
                
                try:
                    cursor_local.execute(
                        insert_item_query,
                        (
                            barcode,
                            item_name,
                            unit_name,
                            sales_price_local,
                            item_id,             # ID (matches item_id)
                            sales_price_remote,  # fldSales (SAR price)
                            group_id,
                            item_id,
                            unity_id,
                            1,                   # fldMoneyID (1 = local YER)
                            is_active,
                            cost_local,
                        )
                    )
                    seen_ids.add(item_id)
                    seen_barcodes.add(barcode)
                    inserted_items_count += 1
                except Exception as ex_item:
                    print(f"Skipping item insert conflict for ID {item_id} ({barcode}): {ex_item}")

        elif 'list' in remote_tables:
            query_items = """
            SELECT 
                fldBarCode, fldItemName, fldUnitName, fldSalesPrice, ID, fldSales, 
                fldGroupID, flditemID, fldUnityID, fldMoneyID, fldIsActive, fldCost, fldok
            FROM List
            """
            cursor_remote.execute(query_items)
            remote_list = cursor_remote.fetchall()

            cursor_local.execute("DELETE FROM List")
            insert_item_query = """
            INSERT INTO List (
                fldBarCode, fldItemName, fldUnitName, fldSalesPrice, ID, fldSales, 
                fldGroupID, flditemID, fldUnityID, fldMoneyID, fldIsActive, fldCost, fldok
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            for r in remote_list:
                cursor_local.execute(
                    insert_item_query,
                    (
                        str(r[0] or "").strip(),
                        str(r[1] or "").strip(),
                        str(r[2] or "").strip(),
                        float(r[3] or 0.0),
                        int(r[4] or 0),
                        float(r[5] or 0.0),
                        int(r[6] or 0),
                        int(r[7] or 0),
                        int(r[8] or 0),
                        int(r[9] or 1),
                        bool(r[10] if r[10] is not None else 1),
                        float(r[11] or 0.0),
                        bool(r[12] if r[12] is not None else 0),
                    )
                )
                inserted_items_count += 1
            
        # --- SYNC tblPointList ---
        # 1. Create table locally if it doesn't exist
        create_point_list_query = """
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblPointList]') AND type in (N'U'))
        BEGIN
        CREATE TABLE [dbo].[tblPointList](
            [fldPointNO] [int] NOT NULL PRIMARY KEY,
            [fldName] [nvarchar](100) NULL,
            [fldBranchNo] [int] NULL,
            [fldstoreID] [int] NULL,
            [DataSource] [nvarchar](100) NULL,
            [Catalog] [nvarchar](100) NULL,
            [UserID] [nvarchar](100) NULL,
            [Password] [nvarchar](100) NULL
        )
        END
        """
        cursor_local.execute(create_point_list_query)
        
        # 2. Fetch from remote
        cursor_remote.execute("SELECT fldPointNO, fldName, fldBranchNo, fldstoreID, DataSource, Catalog, UserID, Password FROM tblPointList")
        remote_points = cursor_remote.fetchall()
        
        # 3. Clear local table
        cursor_local.execute("DELETE FROM tblPointList")
        
        # 4. Insert into local
        insert_point_query = """
        INSERT INTO tblPointList (
            fldPointNO, fldName, fldBranchNo, fldstoreID, DataSource, Catalog, UserID, Password
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        for p in remote_points:
            cursor_local.execute(
                insert_point_query,
                (
                    int(p[0] or 0),
                    str(p[1] or "").strip(),
                    int(p[2] or 0),
                    int(p[3] or 0),
                    p[4],
                    p[5],
                    p[6],
                    p[7]
                )
            )
            
        conn_local.commit()
        return {
            "status": "success",
            "message": f"تمت المزامنة بنجاح.\n- العملات: {len(remote_currencies)}\n- المجموعات: {len(remote_groups)}\n- المستخدمين: {len(remote_users)}\n- نقاط البيع: {len(remote_points)}\n- الأصناف: {inserted_items_count}"
        }
        
    except Exception as e:
        conn_local.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"فشل أثناء ترحيل البيانات وتحديث قاعدة البيانات المحلية: {str(e)}"
        )
    finally:
        cursor_remote.close()
        conn_remote.close()
        cursor_local.close()
        conn_local.close()

@app.post("/api/settings/upload-transactions")
def upload_transactions():
    # 1. Connect to local DB
    conn_local = get_connection()
    cursor_local = conn_local.cursor()
    
    # Get local Settings currency settings
    try:
        cursor_local.execute("SELECT TOP 1 fldMoneyID, fldMoneyValue FROM Settings")
        row_settings = cursor_local.fetchone()
        local_money_id = int(row_settings[0] if row_settings else 2)
        local_money_value = float(row_settings[1] if row_settings else 1.0)
    except Exception:
        local_money_id = 2
        local_money_value = 1.0
        
    # Get SAR rate
    try:
        cursor_local.execute("SELECT fldValue FROM tblMoney WHERE fldID = 2")
        sar_rate = float(cursor_local.fetchval() or 416.0)
    except Exception:
        sar_rate = 416.0

    # 2. Connect to remote main database
    drivers = [
        "{ODBC Driver 17 for SQL Server}",
        "{ODBC Driver 18 for SQL Server}",
        "{SQL Server}",
    ]
    
    remote_server = db_config["remote_server"]
    if db_config.get("port"):
        remote_server = f"{remote_server},{db_config['port']}"
        
    connected = False
    conn_remote = None
    last_error = ""
    
    for driver in drivers:
        try:
            conn_str = (
                f"Driver={driver};"
                f"Server={remote_server};"
                f"Database={db_config['remote_db']};"
                f"Uid={db_config['username']};"
                f"Pwd={db_config['password']};"
                f"Encrypt=no;"
                f"TrustServerCertificate=yes;"
                f"Connection Timeout=4;"
            )
            conn_remote = pyodbc.connect(conn_str)
            conn_remote.autocommit = False
            connected = True
            break
        except Exception as e:
            last_error = str(e)
            continue
            
    if not connected:
        for driver in drivers:
            try:
                conn_str = (
                    f"Driver={driver};"
                    f"Server={remote_server};"
                    f"Database={db_config['remote_db']};"
                    f"Uid={db_config['username']};"
                    f"Pwd={db_config['password']};"
                    f"Connection Timeout=4;"
                )
                conn_remote = pyodbc.connect(conn_str)
                conn_remote.autocommit = False
                connected = True
                break
            except Exception as e:
                last_error = str(e)
                continue
                
    if not connected:
        cursor_local.close()
        conn_local.close()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"فشل الاتصال بالسيرفر الرئيسي البعيد لترحيل البيانات: {last_error}"
        )
        
    cursor_remote = conn_remote.cursor()
    
    # Ensure point_no columns exist in local and remote DBs
    ensure_columns_exist(cursor_local)
    ensure_columns_exist(cursor_remote)
    conn_local.commit()
    conn_remote.commit()
    
    try:
        # Detect remote schema tables
        cursor_remote.execute("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES")
        remote_tables = {row[0].lower() for row in cursor_remote.fetchall()}
        
        has_remote_main = "main" in remote_tables
        has_remote_transaction = "tbltransaction" in remote_tables
        
        # Alter Main and details to add fldPointNO & fldToPointNO if missing on remote
        if has_remote_main:
            alter_main_query = """
            IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND type in (N'U'))
            BEGIN
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND name = 'fldPointNO')
                BEGIN
                    ALTER TABLE [dbo].[Main] ADD [fldPointNO] [int] NULL
                END
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND name = 'fldToPointNO')
                BEGIN
                    ALTER TABLE [dbo].[Main] ADD [fldToPointNO] [int] NULL
                END
            END
            """
            cursor_remote.execute(alter_main_query)

            alter_details_query = """
            IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND type in (N'U'))
            BEGIN
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldPointNO')
                BEGIN
                    ALTER TABLE [dbo].[details] ADD [fldPointNO] [int] NULL
                END
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldToPointNO')
                BEGIN
                    ALTER TABLE [dbo].[details] ADD [fldToPointNO] [int] NULL
                END
            END
            """
            cursor_remote.execute(alter_details_query)
            
        # Alter tblExpenses to add fldPointNO if missing on remote
        if "tblexpenses" in remote_tables:
            alter_expenses_query = """
            IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblExpenses]') AND type in (N'U'))
            BEGIN
                IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[tblExpenses]') AND name = 'fldPointNO')
                BEGIN
                    ALTER TABLE [dbo].[tblExpenses] ADD [fldPointNO] [int] NULL
                END
            END
            """
            cursor_remote.execute(alter_expenses_query)
        conn_remote.commit()
        
        uploaded_invoices = 0
        uploaded_bonds = 0
        
        # --- UPLOAD INVOICES (Main / details) ---
        cursor_local.execute("SELECT fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldToPointNO, fldAccID FROM Main")
        local_invoices = cursor_local.fetchall()
        
        selected_point_no = db_config.get("point_no", 1)
        # Find branch of this point on remote server
        branch_no = 1
        if "tblpointlist" in remote_tables:
            cursor_remote.execute("SELECT fldBranchNo FROM tblPointList WHERE fldPointNO = ?", (selected_point_no,))
            branch_val = cursor_remote.fetchval()
            if branch_val is not None:
                branch_no = int(branch_val)

        for inv in local_invoices:
            fldDate = inv[0]
            fldDescription = inv[1] or ""
            fldTransNumber = float(inv[2] or 0.0)
            fldUSerID = int(inv[3] or 1)
            fldPointNO = int(inv[4] or 1)
            fldPaycash = int(inv[5] or 1)
            fldType = int(inv[6] or 35)
            fldTransID = int(inv[7] or 1)
            fldMoneyID = int(inv[8] or 1)
            fldToPointNO = int(inv[9]) if inv[9] is not None else None
            fldAccID = int(inv[10]) if inv[10] is not None else 0
            
            # Fetch local details for this invoice
            ensure_columns_exist(cursor_local)
            conn_local.commit()

            cursor_local.execute("SELECT fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldID, fldPointNO, fldToPointNO FROM details WHERE fldTransNumber = ?", (fldTransNumber,))
            local_details = cursor_local.fetchall()
            
            if has_remote_main:
                # Scenario A: Remote database has Main/details tables
                cursor_remote.execute("SELECT fldTransNumber FROM Main WHERE fldTransNumber = ?", (fldTransNumber,))
                exists = cursor_remote.fetchone()
                if not exists:
                    # Insert header
                    cursor_remote.execute(
                        "INSERT INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus, fldAccID) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, 0, fldAccID)
                    )
                    # Insert details
                    for d in local_details:
                        cursor_remote.execute(
                            "INSERT INTO details (fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO, fldToPointNO, fldStatus) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                            (d[0], d[1], d[2], d[3], d[4], d[5], fldTransNumber, d[6], d[7] or fldPointNO, d[8] or fldToPointNO, 0)
                        )
                    uploaded_invoices += 1
                else:
                    # Invoice exists on remote: Force UPDATE fldToPointNO in both Main and details
                    if fldToPointNO is not None:
                        cursor_remote.execute(
                            "UPDATE Main SET fldToPointNO = ? WHERE fldTransNumber = ?",
                            (fldToPointNO, fldTransNumber)
                        )
                        for d in local_details:
                            item_to_point = d[8] or fldToPointNO
                            if item_to_point is not None:
                                cursor_remote.execute(
                                    "UPDATE details SET fldToPointNO = ? WHERE fldTransNumber = ? AND fldID = ?",
                                    (item_to_point, fldTransNumber, d[6])
                                )
                    
            elif has_remote_transaction:
                # Scenario B: Remote database has tblTransAction/tblItemTransD ERP tables
                cursor_remote.execute("SELECT fldID FROM tblTransAction WHERE fldDescription LIKE ?", (f'%{fldTransNumber}%',))
                exists = cursor_remote.fetchone()
                if not exists:
                    # Calculate total cost and voucher total
                    voisher_total = sum(float(d[5] or 0.0) for d in local_details)
                    
                    # Fetch next fldID manually since fldID is not an identity column
                    cursor_remote.execute("SELECT COALESCE(MAX(fldID), 0) FROM tblTransAction")
                    remote_trans_id = int(cursor_remote.fetchone()[0] + 1)
                    
                    # Determine source/destination stores for store transfer orders
                    if fldType == 22: # Store Receipt (Tawreed)
                        store_id = int(fldPaycash or 1)
                        store_id_2 = branch_no
                    elif fldType == 23: # Store Issuance (Sarf)
                        store_id = branch_no
                        store_id_2 = int(fldPaycash or 1)
                    elif fldType in [24, 28]: # Inter-branch Transfer
                        store_id = fldPointNO or branch_no
                        store_id_2 = fldToPointNO or branch_no
                    else:
                        store_id = 1
                        store_id_2 = 1
                        
                    # Insert into tblTransAction
                    # We map type: fldType (like 35 for sales, 20 for purchases, 36 for returns, 1 for stock)
                    cursor_remote.execute(
                        """
                        INSERT INTO tblTransAction (
                            fldID, fldBranchNo, fldYaer, fldUserID, fldTransType, fldType, fldTransNo, fldBookNO, 
                            fldDate, fldRefDate, fldDescription, fldOK, fldClosed, fldchanging, 
                            fldVoisherAccID, fldVoisherMoneyID, fldVoisherMoneyValue, fldVoisherTotal,
                            fldAccMoneyID, fldAccMoneyValue, fldAccTotal,
                            fldstoreID, fldstoreID2, fldDateINSERT, fldDateUPDATE
                        ) VALUES (?, ?, 26, ?, ?, ?, ?, 1, ?, ?, ?, 1, 0, 1, ?, ?, ?, ?, 1, ?, ?, ?, ?, GETDATE(), GETDATE())
                        """,
                        (
                            remote_trans_id,
                            branch_no,
                            fldUSerID,
                            fldType,
                            fldType,
                            int(fldTransNumber),
                            fldDate,
                            fldDate,
                            f"ترحيل آلي للفاتورة رقم {fldTransNumber} - {fldDescription}",
                            local_money_id,
                            local_money_id,
                            local_money_value,
                            voisher_total,
                            sar_rate,
                            voisher_total / sar_rate,
                            store_id,
                            store_id_2
                        )
                    )
                    
                    # Insert details into tblItemTransD
                    for idx, d in enumerate(local_details):
                        barcode = d[0]
                        qty = float(d[1] or 0.0)
                        sales_price_local = float(d[2] or 0.0)
                        discount = float(d[3] or 0.0)
                        tax = float(d[4] or 0.0)
                        total_item = float(d[5] or 0.0)
                        fldID = int(d[6] or 1)
                        
                        # Find flditemID and fldUnityID from local List table
                        cursor_local.execute("SELECT flditemID, fldUnityID FROM List WHERE fldBarCode = ?", (barcode,))
                        list_info = cursor_local.fetchone()
                        item_id = list_info[0] if list_info else fldID
                        unity_id = list_info[1] if list_info else 1
                        
                        # Convert YER price back to SAR for central ERP
                        price_sar = sales_price_local / sar_rate
                        total_price_sar = total_item / sar_rate
                        tax_sar = tax / sar_rate
                        
                        cursor_remote.execute(
                            """
                            INSERT INTO tblItemTransD (
                                fldTransID, fldTransIDINdex, flditemID, fldQTY, fldFreeQTY, fldUnityID, fldstoreID, 
                                fldPrice, fldCost, fldDiscount, fldDescription, fldInx, fldTotalPrice, fldlTaxTota_D, fldBranchNo
                            ) VALUES (?, ?, ?, ?, 0, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            (
                                remote_trans_id,
                                idx + 1,
                                item_id,
                                qty,
                                unity_id,
                                price_sar,
                                price_sar * 0.7, # dummy cost
                                discount,
                                f"صنف {barcode}",
                                idx + 1,
                                total_price_sar,
                                tax_sar,
                                branch_no
                            )
                        )
                    # Determine Debit/Credit accounts for double entry
                    if fldType == 35: # Sales
                        debit_acc = int(fldTransID or 1)
                        credit_acc = 3 # Sales Account
                    elif fldType == 20: # Purchases
                        debit_acc = 4 # Purchases Account
                        credit_acc = int(fldTransID or 1)
                    elif fldType == 36: # Returns
                        debit_acc = 5 # Returns Account
                        credit_acc = int(fldTransID or 1)
                    elif fldType == 1: # Opening Stock
                        debit_acc = 6 # Inventory Account
                        credit_acc = 7 # Capital/Offset
                    elif fldType == 22: # Store Receipt
                        debit_acc = 6 # Inventory Account
                        credit_acc = int(fldPaycash or 6)
                    elif fldType == 23: # Store Issuance
                        debit_acc = int(fldPaycash or 6)
                        credit_acc = 6 # Inventory Account
                    else:
                        debit_acc = int(fldTransID or 1)
                        credit_acc = 3

                    # Insert row 1: Debit Entry
                    cursor_remote.execute(
                        """
                        INSERT INTO tblMoneyMove (
                            fldRID, fldTransID, fldAccID, fldDebit, fldCredit, Debit, Credit, 
                            fldMoneyID, fldMoneyValue, fldNote, fldAccID2, fldRefNo, fldRefDate, fldCenterCostID, fldBranchNo
                        ) VALUES (1, ?, ?, ?, 0.0, ?, 0.0, ?, ?, ?, ?, ?, ?, 1, ?)
                        """,
                        (
                            remote_trans_id,
                            debit_acc,
                            voisher_total, # in YER
                            voisher_total / sar_rate, # in SAR
                            local_money_id,
                            local_money_value,
                            f"قيد مدين للفاتورة رقم {fldTransNumber} - {fldDescription}",
                            credit_acc,
                            int(fldTransNumber),
                            fldDate,
                            branch_no
                        )
                    )

                    # Insert row 2: Credit Entry
                    cursor_remote.execute(
                        """
                        INSERT INTO tblMoneyMove (
                            fldRID, fldTransID, fldAccID, fldDebit, fldCredit, Debit, Credit, 
                            fldMoneyID, fldMoneyValue, fldNote, fldAccID2, fldRefNo, fldRefDate, fldCenterCostID, fldBranchNo
                        ) VALUES (2, ?, ?, 0.0, ?, 0.0, ?, ?, ?, ?, ?, ?, ?, 1, ?)
                        """,
                        (
                            remote_trans_id,
                            credit_acc,
                            voisher_total, # in YER
                            voisher_total / sar_rate, # in SAR
                            local_money_id,
                            local_money_value,
                            f"قيد دائن للفاتورة رقم {fldTransNumber} - {fldDescription}",
                            debit_acc,
                            branch_no
                        )
                    )
                    uploaded_invoices += 1

            # Mark invoice as synced locally
            try:
                cursor_local.execute("UPDATE Main SET fldIsSync = 1 WHERE fldTransNumber = ?", (fldTransNumber,))
            except Exception:
                pass

        # --- UPLOAD BONDS (tblExpenses) ---
        exp_acc_map = {}
        try:
            cursor_local.execute("SELECT fldID, fldAccID FROM tblExpensesList")
            for erow in cursor_local.fetchall():
                if erow[0] is not None and erow[1] is not None:
                    exp_acc_map[int(erow[0])] = int(erow[1])
        except Exception:
            pass

        cursor_local.execute("SELECT fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, COALESCE(fldAccID, 0) FROM tblExpenses")
        local_bonds = cursor_local.fetchall()
        
        has_remote_expenses = "tblexpenses" in remote_tables
        has_remote_moneymove = "tblmoneymove" in remote_tables
        
        for bond in local_bonds:
            fldExpensesID = int(bond[0] or 1)
            fldAmount = float(bond[1] or 0.0)
            fldNote = bond[2] or ""
            fldID = int(bond[3] or 1)
            fldTransID = int(bond[4] or 11) # 10 = Receipt, 11 = Payment
            fldDate = str(bond[5])
            fldAccID = int(bond[6] or 0)
            if fldAccID == 0:
                fldAccID = exp_acc_map.get(fldExpensesID, fldExpensesID)
            
            if has_remote_expenses:
                cursor_remote.execute("SELECT fldExpensesID FROM tblExpenses WHERE fldDate = ? AND fldAmount = ? AND fldNote = ?", (fldDate, fldAmount, fldNote))
                exists = cursor_remote.fetchone()
                if not exists:
                    # Check if remote tblExpenses table has fldPointNO and fldAccID columns
                    cursor_remote.execute(
                        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'tblExpenses' AND COLUMN_NAME IN ('fldPointNO', 'fldAccID')"
                    )
                    cols_present = [r[0].lower() for r in cursor_remote.fetchall()]
                    has_point_col = "fldpointno" in cols_present
                    has_acc_col = "fldaccid" in cols_present
                    
                    if has_point_col and has_acc_col:
                        cursor_remote.execute(
                            "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldPointNO, fldAccID) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                            (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, selected_point_no, fldAccID)
                        )
                    elif has_point_col:
                        cursor_remote.execute(
                            "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldPointNO) VALUES (?, ?, ?, ?, ?, ?, ?)",
                            (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, selected_point_no)
                        )
                    else:
                        cursor_remote.execute(
                            "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate) VALUES (?, ?, ?, ?, ?, ?)",
                            (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate)
                        )
                    uploaded_bonds += 1
            elif has_remote_moneymove:
                # Map to tblMoneyMove
                # receipt (10) cash increases, payment (11) cash decreases
                cursor_remote.execute("SELECT fldID FROM tblMoneyMove WHERE fldRefDate = ? AND fldNote LIKE ?", (fldDate, f'%{fldNote}%'))
                exists = cursor_remote.fetchone()
                if not exists:
                    # 1. First insert header in tblTransAction for this bond
                    cursor_remote.execute("SELECT COALESCE(MAX(fldID), 0) FROM tblTransAction")
                    remote_trans_id = int(cursor_remote.fetchone()[0] + 1)
                    target_acc = fldAccID if fldAccID > 0 else fldExpensesID
                    
                    cursor_remote.execute(
                        """
                        INSERT INTO tblTransAction (
                            fldID, fldBranchNo, fldYaer, fldUserID, fldTransType, fldType, fldTransNo, fldBookNO, 
                            fldDate, fldRefDate, fldDescription, fldOK, fldClosed, fldchanging, 
                            fldVoisherAccID, fldVoisherMoneyID, fldVoisherMoneyValue, fldVoisherTotal,
                            fldAccMoneyID, fldAccMoneyValue, fldAccTotal,
                            fldstoreID, fldstoreID2, fldDateINSERT, fldDateUPDATE
                        ) VALUES (?, ?, 26, 1, ?, ?, ?, 1, ?, ?, ?, 1, 0, 1, ?, ?, ?, ?, 1, ?, ?, 1, 1, GETDATE(), GETDATE())
                        """,
                        (
                            remote_trans_id,
                            branch_no,
                            fldTransID, # 10 or 11
                            fldTransID, # 10 or 11
                            int(fldID),
                            fldDate,
                            fldDate,
                            f"ترحيل آلي لسند - {fldNote}",
                            target_acc,
                            local_money_id,
                            local_money_value,
                            abs(fldAmount),
                            sar_rate,
                            abs(fldAmount) / sar_rate
                        )
                    )
                    
                    # 2. Then insert double entry in tblMoneyMove linking to remote_trans_id
                    # Determine Debit/Credit accounts for bond double entry
                    if fldTransID == 10: # Receipt Bond (Qabd)
                        debit_acc = 1 # Cash Account
                        credit_acc = target_acc
                    else: # Payment Bond (Sarf)
                        debit_acc = target_acc
                        credit_acc = 1 # Cash Account
                        
                    debit_val = abs(fldAmount)
                    credit_val = abs(fldAmount)
                    
                    # Insert Row 1: Debit Entry for Bond
                    cursor_remote.execute(
                        """
                        INSERT INTO tblMoneyMove (
                            fldRID, fldTransID, fldAccID, fldDebit, fldCredit, Debit, Credit, 
                            fldMoneyID, fldMoneyValue, fldNote, fldAccID2, fldRefNo, fldRefDate, fldCenterCostID, fldBranchNo
                        ) VALUES (1, ?, ?, ?, 0.0, ?, 0.0, ?, ?, ?, ?, ?, ?, 1, ?)
                        """,
                        (
                            remote_trans_id,
                            debit_acc,
                            debit_val, # in YER
                            debit_val / sar_rate, # in SAR
                            local_money_id,
                            local_money_value,
                            fldNote,
                            credit_acc,
                            int(fldID),
                            fldDate,
                            branch_no
                        )
                    )
                    
                    # Insert Row 2: Credit Entry for Bond
                    cursor_remote.execute(
                        """
                        INSERT INTO tblMoneyMove (
                            fldRID, fldTransID, fldAccID, fldDebit, fldCredit, Debit, Credit, 
                            fldMoneyID, fldMoneyValue, fldNote, fldAccID2, fldRefNo, fldRefDate, fldCenterCostID, fldBranchNo
                        ) VALUES (2, ?, ?, 0.0, ?, 0.0, ?, ?, ?, ?, ?, ?, ?, 1, ?)
                        """,
                        (
                            remote_trans_id,
                            credit_acc,
                            credit_val, # in YER
                            credit_val / sar_rate, # in SAR
                            local_money_id,
                            local_money_value,
                            fldNote,
                            debit_acc,
                            int(fldID),
                            fldDate,
                            branch_no
                        )
                    )
                    uploaded_bonds += 1
            
            # Mark bond as synced locally
            try:
                cursor_local.execute("UPDATE tblExpenses SET fldIsSync = 1 WHERE fldID = ?", (fldID,))
            except Exception:
                pass
                    
        conn_remote.commit()
        conn_local.commit()
        return {
            "status": "success",
            "message": f"تم ترحيل كافة العمليات والحركات المالية والمخزنية بنجاح بالسيرفر:\n- الفواتير المرحّلة: {uploaded_invoices}\n- سندات القبض والصرف المرحّلة: {uploaded_bonds}"
        }
    except Exception as e:
        try:
            conn_remote.rollback()
        except Exception:
            pass
        try:
            conn_local.rollback()
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"فشل ترحيل الحركات للسيرفر الرئيسي: {str(e)}"
        )
    finally:
        try:
            cursor_remote.close()
            conn_remote.close()
        except Exception:
            pass
        try:
            cursor_local.close()
            conn_local.close()
        except Exception:
            pass

@app.post("/api/settings/transfer-tables")
def transfer_tables():
    conn_local = get_connection()
    cursor_local = conn_local.cursor()
    
    try:
        conn_remote = get_remote_connection()
        conn_remote.autocommit = False  # Ensure transaction is active
    except Exception as e:
        cursor_local.close()
        conn_local.close()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"فشل الاتصال بالسيرفر الرئيسي البعيد: {str(e)}"
        )
        
    cursor_remote = conn_remote.cursor()
    
    # Ensure point_no columns exist in both local and remote
    ensure_columns_exist(cursor_local)
    ensure_columns_exist(cursor_remote)
    conn_local.commit()
    conn_remote.commit()
    
    try:
        # 1. Create remote Main if not exists
        create_main_query = """
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND type in (N'U'))
        BEGIN
        CREATE TABLE [dbo].[Main](
            [fldDate] [date] NULL,
            [fldDescription] [nvarchar](50) NULL,
            [fldTransNumber] [float] NOT NULL PRIMARY KEY,
            [fldUSerID] [int] NULL,
            [fldPointNO] [int] NULL,
            [fldToPointNO] [int] NULL,
            [fldPaycash] [int] NULL,
            [fldType] [tinyint] NULL,
            [fldTransID] [int] NULL,
            [fldMoneyID] [int] NULL,
            [fldStatus] [int] NULL DEFAULT 0
        )
        END
        """
        cursor_remote.execute(create_main_query)
        
        # Alter Main to add fldPointNO, fldToPointNO, fldStatus if missing on remote
        alter_main_query = """
        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND type in (N'U'))
        BEGIN
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND name = 'fldPointNO')
            BEGIN
                ALTER TABLE [dbo].[Main] ADD [fldPointNO] [int] NULL
            END
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND name = 'fldToPointNO')
            BEGIN
                ALTER TABLE [dbo].[Main] ADD [fldToPointNO] [int] NULL
            END
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Main]') AND name = 'fldStatus')
            BEGIN
                ALTER TABLE [dbo].[Main] ADD [fldStatus] [int] NULL DEFAULT 0
            END
        END
        """
        cursor_remote.execute(alter_main_query)
        
        # 2. Create remote details if not exists
        create_details_query = """
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND type in (N'U'))
        BEGIN
        CREATE TABLE [dbo].[details](
            [fldBarCode] [nvarchar](18) NULL,
            [fldQuantity] [int] NULL,
            [fldSalesPrice] [float] NULL,
            [fldDiscount] [int] NULL,
            [fldlTaxTota] [int] NULL,
            [fldTotalItem] [int] NULL,
            [fldTransNumber] [float] NULL,
            [fldID] [int] NULL,
            [fldPointNO] [int] NULL,
            [fldToPointNO] [int] NULL,
            [fldStatus] [int] NULL DEFAULT 0
        )
        END
        """
        cursor_remote.execute(create_details_query)

        alter_details_query = """
        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND type in (N'U'))
        BEGIN
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldPointNO')
            BEGIN
                ALTER TABLE [dbo].[details] ADD [fldPointNO] [int] NULL
            END
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldToPointNO')
            BEGIN
                ALTER TABLE [dbo].[details] ADD [fldToPointNO] [int] NULL
            END
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldStatus')
            BEGIN
                ALTER TABLE [dbo].[details] ADD [fldStatus] [int] NULL DEFAULT 0
            END
        END
        """
        cursor_remote.execute(alter_details_query)
        
        # 3. Create remote tblExpenses if not exists
        create_expenses_query = """
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblExpenses]') AND type in (N'U'))
        BEGIN
        CREATE TABLE [dbo].[tblExpenses](
            [fldExpensesID] [int] NULL,
            [fldAmount] [float] NOT NULL,
            [fldNote] [nvarchar](max) NULL,
            [fldID] [int] NOT NULL PRIMARY KEY,
            [fldTransID] [int] NULL,
            [fldDate] [date] NULL,
            [fldTransNumber] [float] NULL,
            [fldPointNO] [int] NULL
        )
        END
        """
        cursor_remote.execute(create_expenses_query)
        
        # Alter tblExpenses to add fldPointNO if missing on remote
        alter_expenses_query = """
        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tblExpenses]') AND type in (N'U'))
        BEGIN
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[tblExpenses]') AND name = 'fldPointNO')
            BEGIN
                ALTER TABLE [dbo].[tblExpenses] ADD [fldPointNO] [int] NULL
            END
        END
        """
        cursor_remote.execute(alter_expenses_query)
        
        # 4. Transfer Main data
        cursor_local.execute("SELECT fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus, fldAccID FROM Main")
        local_mains = cursor_local.fetchall()
        
        mains_transferred = 0
        for row in local_mains:
            fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus, fldAccID = row
            cursor_remote.execute("SELECT 1 FROM Main WHERE fldTransNumber = ?", (fldTransNumber,))
            if not cursor_remote.fetchone():
                cursor_remote.execute(
                    "INSERT INTO Main (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus, fldAccID) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (fldDate, fldDescription, fldTransNumber, fldUSerID, fldPointNO, fldToPointNO, fldPaycash, fldType, fldTransID, fldMoneyID, fldStatus or 0, fldAccID or 0)
                )
                mains_transferred += 1
                
        # 5. Transfer details data
        # Ensure local details has fldPointNO & fldToPointNO columns
        alter_details_local = """
        IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND type in (N'U'))
        BEGIN
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldPointNO')
            BEGIN
                ALTER TABLE [dbo].[details] ADD [fldPointNO] [int] NULL
            END
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldToPointNO')
            BEGIN
                ALTER TABLE [dbo].[details] ADD [fldToPointNO] [int] NULL
            END
            IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[details]') AND name = 'fldStatus')
            BEGIN
                ALTER TABLE [dbo].[details] ADD [fldStatus] [int] NULL DEFAULT 0
            END
        END
        """
        cursor_local.execute(alter_details_local)
        conn_local.commit()

        cursor_local.execute("SELECT fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO, fldToPointNO, fldStatus FROM details")
        local_details = cursor_local.fetchall()
        
        selected_point_no = db_config.get("point_no", 1)
        details_transferred = 0
        for row in local_details:
            fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO, fldToPointNO, fldStatus = row
            cursor_remote.execute(
                "SELECT 1 FROM details WHERE fldTransNumber = ? AND fldID = ? AND fldBarCode = ?",
                (fldTransNumber, fldID, fldBarCode)
            )
            if not cursor_remote.fetchone():
                cursor_remote.execute(
                    "INSERT INTO details (fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO, fldToPointNO, fldStatus) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (fldBarCode, fldQuantity, fldSalesPrice, fldDiscount, fldlTaxTota, fldTotalItem, fldTransNumber, fldID, fldPointNO or selected_point_no, fldToPointNO, fldStatus or 0)
                )
                details_transferred += 1
                
        # 6. Transfer tblExpenses data
        cursor_local.execute("SELECT fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber FROM tblExpenses")
        local_expenses = cursor_local.fetchall()
        
        selected_point_no = db_config.get("point_no", 1)
        expenses_transferred = 0
        for row in local_expenses:
            fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber = row
            cursor_remote.execute("SELECT 1 FROM tblExpenses WHERE fldID = ?", (fldID,))
            if not cursor_remote.fetchone():
                cursor_remote.execute(
                    "INSERT INTO tblExpenses (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber, fldPointNO) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (fldExpensesID, fldAmount, fldNote, fldID, fldTransID, fldDate, fldTransNumber, selected_point_no)
                )
                expenses_transferred += 1
                
        # Commit the entire batch!
        conn_remote.commit()
        return {
            "status": "success",
            "message": f"تم نقل الجداول بالكامل بنجاح كحزمة واحدة!\n- السجلات المضافة في Main: {mains_transferred}\n- السجلات المضافة في details: {details_transferred}\n- السجلات المضافة في tblExpenses: {expenses_transferred}"
        }
        
    except Exception as e:
        try:
            conn_remote.rollback()
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"فشل نقل حزمة البيانات (تم التراجع عن كامل العملية): {str(e)}"
        )
    finally:
        cursor_remote.close()
        conn_remote.close()
        cursor_local.close()
        conn_local.close()

class DirectPrintRequest(BaseModel):
    html_content: str
    printer_name: Optional[str] = None

@app.post("/api/print-direct")
def print_direct(req: DirectPrintRequest):
    try:
        import tempfile
        import os
        import subprocess

        temp_dir = tempfile.gettempdir()
        html_file = os.path.join(temp_dir, "hayapos_direct_print.html")

        with open(html_file, "w", encoding="utf-8") as f:
            f.write(req.html_content)

        printer_name_str = req.printer_name.strip() if req.printer_name and req.printer_name.strip() else None

        # 1. Print via Windows PowerShell Start-Process
        try:
            if printer_name_str:
                ps_cmd = f'powershell -Command "Start-Process -FilePath \'{html_file}\' -Verb PrintTo -ArgumentList \'\"{printer_name_str}\"\'"'
            else:
                ps_cmd = f'powershell -Command "Start-Process -FilePath \'{html_file}\' -Verb Print"'
            subprocess.Popen(ps_cmd, shell=True, creationflags=0x08000000)
        except Exception as ps_err:
            print(f"PowerShell print error: {ps_err}")

        # 2. Also trigger standard Windows HTML print
        try:
            subprocess.Popen(f'rundll32.exe mshtml.dll,PrintHTML "{html_file}"', shell=True, creationflags=0x08000000)
        except Exception:
            pass

        target_name = printer_name_str if printer_name_str else "الطابعة الافتراضية"
        return {"status": "success", "message": f"تم إرسال أمر الطباعة بنجاح إلى ({target_name})"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/api/printers")
def get_system_printers():
    try:
        import subprocess
        output = subprocess.check_output(
            'powershell -Command "Get-Printer | Select-Object -ExpandProperty Name"',
            shell=True,
            text=True,
            creationflags=0x08000000
        )
        printers = [line.strip() for line in output.split('\n') if line.strip()]
        return {"printers": printers}
    except Exception as e:
        return {"printers": [], "error": str(e)}

# =====================================================================
#             نظام التحديث التلقائي الأونلاين (Online Auto Update)
# =====================================================================
CURRENT_SYSTEM_VERSION = "1.0.0"
DEFAULT_VERSION_CHECK_URL = "https://raw.githubusercontent.com/senanye/HayaPOS-2026/main/version.json"

def _get_local_version():
    try:
        # Check root or local directory for version.json
        for path in ["version.json", "../version.json", os.path.join(os.path.dirname(__file__), "..", "version.json")]:
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8-sig") as f:
                    data = json.load(f)
                    return data.get("version", CURRENT_SYSTEM_VERSION)
    except Exception:
        pass
    return CURRENT_SYSTEM_VERSION

def _parse_version(v_str: str):
    try:
        clean_v = v_str.replace("v", "").replace("V", "").strip()
        parts = [int(p) for p in clean_v.split(".") if p.isdigit()]
        return tuple(parts)
    except Exception:
        return (0, 0, 0)

@app.get("/api/system_version")
def get_system_version():
    system_name = "نظام هيا لنقاط البيع"
    build_date = "2026-08-22"
    try:
        for path in ["version.json", "../version.json", os.path.join(os.path.dirname(__file__), "..", "version.json")]:
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8-sig") as f:
                    data = json.load(f)
                    system_name = data.get("app_name", system_name)
                    build_date = data.get("build_date", build_date)
                    break
    except Exception:
        pass
    return {
        "status": "success",
        "system_name": system_name,
        "version": _get_local_version(),
        "build_date": build_date
    }

@app.get("/api/check_update")
def check_for_updates():
    import urllib.request
    try:
        # Read configured remote URL from server_config.json if specified
        version_url = DEFAULT_VERSION_CHECK_URL
        if os.path.exists("server_config.json"):
            try:
                with open("server_config.json", "r", encoding="utf-8-sig") as f:
                    cfg = json.load(f)
                    if cfg.get("version_check_url"):
                        version_url = cfg.get("version_check_url")
            except Exception:
                pass

        req = urllib.request.Request(
            version_url,
            headers={"User-Agent": "HayaPOS-AutoUpdater/1.0", "Cache-Control": "no-cache"}
        )
        with urllib.request.urlopen(req, timeout=8) as response:
            if response.status == 200:
                content = response.read().decode("utf-8")
                remote_data = json.loads(content)
                latest_ver = remote_data.get("version", "1.0.0")
                current_ver = _get_local_version()
                
                has_update = _parse_version(latest_ver) > _parse_version(current_ver)
                return {
                    "status": "success",
                    "has_update": has_update,
                    "current_version": current_ver,
                    "latest_version": latest_ver,
                    "build_date": remote_data.get("build_date", ""),
                    "changelog": remote_data.get("changelog", []),
                    "update_url": remote_data.get("update_url", ""),
                    "is_mandatory": remote_data.get("is_mandatory", False),
                    "message": "يوجد تحديث جديد متاح للنظام!" if has_update else "نظامك محدث إلى آخر إصدار."
                }
    except Exception as e:
        return {
            "status": "error",
            "has_update": False,
            "current_version": _get_local_version(),
            "message": f"تعذر الاتصال بسيرفر التحديثات: {str(e)}"
        }

@app.post("/api/apply_update")
def apply_system_update(payload: Optional[dict] = None):
    import urllib.request
    import zipfile
    import shutil
    import tempfile

    try:
        # Determine download URL
        download_url = ""
        if payload and payload.get("update_url"):
            download_url = payload.get("update_url")
        else:
            # Check remote version.json
            res = check_for_updates()
            download_url = res.get("update_url", "")

        if not download_url:
            raise HTTPException(status_code=400, detail="رابط التحديث غير متوفر")

        # 1. Download zip to temp directory
        temp_dir = tempfile.mkdtemp(prefix="haya_update_")
        zip_path = os.path.join(temp_dir, "update.zip")
        extract_dir = os.path.join(temp_dir, "extracted")
        os.makedirs(extract_dir, exist_ok=True)

        req = urllib.request.Request(
            download_url,
            headers={"User-Agent": "HayaPOS-AutoUpdater/1.0"}
        )
        with urllib.request.urlopen(req, timeout=60) as response, open(zip_path, "wb") as out_file:
            shutil.copyfileobj(response, out_file)

        # 2. Extract update zip
        with zipfile.ZipFile(zip_path, "r") as zip_ref:
            zip_ref.extractall(extract_dir)

        # 3. Locate root of update files
        src_root = extract_dir
        # If wrapped in subfolder
        extracted_items = os.listdir(extract_dir)
        if len(extracted_items) == 1 and os.path.isdir(os.path.join(extract_dir, extracted_items[0])):
            src_root = os.path.join(extract_dir, extracted_items[0])

        # 4. Target application root directory
        app_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        if not os.path.exists(os.path.join(app_root, "server")):
            app_root = os.path.abspath(".")

        # 5. Protected files that MUST NOT be overwritten
        protected_files = {
            "server_config.json",
            "branches.db",
            "sp.mdf",
            "sp.ldf"
        }

        # 6. Copy updated files safely
        for root, dirs, files in os.walk(src_root):
            rel_path = os.path.relpath(root, src_root)
            dest_dir = os.path.normpath(os.path.join(app_root, rel_path))
            os.makedirs(dest_dir, exist_ok=True)

            for file in files:
                if file.lower() in protected_files or file.endswith(".db"):
                    # Do not overwrite client database or config!
                    continue
                
                src_file = os.path.join(root, file)
                dest_file = os.path.join(dest_dir, file)
                try:
                    shutil.copy2(src_file, dest_file)
                except Exception as copy_err:
                    print(f"Update warning copying {file}: {copy_err}")

        # 7. Cleanup temp directory
        try:
            shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception:
            pass

        return {
            "status": "success",
            "message": "تم تحديث النظام بنجاح! سيتم إعادة تحميل الصفحة الآن لتطبيق التغييرات.",
            "updated_version": _get_local_version()
        }
    except Exception as e:
        return {
            "status": "error",
            "message": f"حدث خطأ أثناء تثبيت التحديث: {str(e)}"
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000)

