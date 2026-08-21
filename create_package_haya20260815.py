import os
import zipfile
import shutil
import json

root_dir = r"d:\AndroidStudio\POS2026"
pkg_name = "هيا21082026"
zip_output = os.path.join(root_dir, f"{pkg_name}.zip")
folder_output = os.path.join(root_dir, pkg_name)

print(f"1. Preparing Package: {pkg_name}...")

bat_content = """@echo off
chcp 65001 > nul
title نظام هيا لنقاط البيع - إصدار 21082026
color 0B
echo ======================================================================
echo                نظام هيا لنقاط البيع - إصدار 21082026
echo                Haya POS System - Release 21082026
echo                    الحقوق محفوظة م. علي سنان
echo ======================================================================
echo.

cd /d "%~dp0"

:: 0. Free busy ports (9000 & 8888) if leftover from previous run
powershell -Command "Get-NetTCPConnection -LocalPort 9000,8888 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }" >nul 2>nul

:: 1. Auto-detect Python executable (Portable or System)
set "PYTHON_EXE="
if exist "python_env\\python.exe" (
    set "PYTHON_EXE=python_env\\python.exe"
    echo [OK] تم العثور على بيئة بايثون المحمولة المدمجة.
    goto :found_python
)

where python >nul 2>nul
if %errorlevel% equ 0 set "PYTHON_EXE=python"
if defined PYTHON_EXE goto :found_python

where py >nul 2>nul
if %errorlevel% equ 0 set "PYTHON_EXE=py"
if defined PYTHON_EXE goto :found_python

if exist "%LOCALAPPDATA%\\Programs\\Python\\Python314\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python314\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%LOCALAPPDATA%\\Programs\\Python\\Python313\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python313\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%LOCALAPPDATA%\\Programs\\Python\\Python312\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python312\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%LOCALAPPDATA%\\Programs\\Python\\Python311\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python311\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%LOCALAPPDATA%\\Programs\\Python\\Python310\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python310\\python.exe"
if defined PYTHON_EXE goto :found_python

if exist "%ProgramFiles%\\Python314\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python314\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%ProgramFiles%\\Python313\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python313\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%ProgramFiles%\\Python312\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python312\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%ProgramFiles%\\Python311\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python311\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "%ProgramFiles%\\Python310\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python310\\python.exe"
if defined PYTHON_EXE goto :found_python

if exist "C:\\Python314\\python.exe" set "PYTHON_EXE=C:\\Python314\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "C:\\Python313\\python.exe" set "PYTHON_EXE=C:\\Python313\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "C:\\Python312\\python.exe" set "PYTHON_EXE=C:\\Python312\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "C:\\Python311\\python.exe" set "PYTHON_EXE=C:\\Python311\\python.exe"
if defined PYTHON_EXE goto :found_python
if exist "C:\\Python310\\python.exe" set "PYTHON_EXE=C:\\Python310\\python.exe"
if defined PYTHON_EXE goto :found_python

:no_python
color 0C
echo.
echo ======================================================================
echo  [تنبيه هام] لم يتم العثور على بايثون مثبت على هذا الجهاز!
echo ======================================================================
echo.
echo  لتشغيل خادم النظام، يرجى تثبيت Python 3.10 أو أحدث.
echo  ملاحظة هامة: عند التثبيت، تأكد من وضع علامة صح على:
echo  [x] Add python.exe to PATH
echo.
echo  رابط التحميل المباشر: https://www.python.org/downloads/
echo.
pause
exit /b 1

:found_python
echo [1/3] فحص وتجهيز مكتبات خادم البيانات والـ API...
"%PYTHON_EXE%" -c "import fastapi, uvicorn, pydantic" >nul 2>nul
if %errorlevel% neq 0 (
    echo جاري تثبيت حزم خادم الـ API تلقائيا...
    "%PYTHON_EXE%" -m pip install fastapi uvicorn pydantic pyodbc requests --quiet
)

echo [2/3] جاري تشغيل خادم البيانات والـ API على المنفذ 9000...
start "Haya POS 21082026 API Server" /min "%PYTHON_EXE%" server/server.py

echo [3/3] جاري تشغيل خادم واجهة الويب على المنفذ 8888...
start "Haya POS 21082026 Web Server" /min "%PYTHON_EXE%" -m http.server 8888 --directory web

ping -n 3 127.0.0.1 >nul

echo.
echo فتح النظام في المتصفح...
start http://localhost:8888

echo.
echo ======================================================================
echo  تم تشغيل نظام هيا 21082026 بنجاح!
echo  الرابط في المتصفح: http://localhost:8888
echo  الحقوق محفوظة م. علي سنان
echo  يرجى ابقاء هذه النوافذ مفتوحة طوال فترة عملك على النظام
echo ======================================================================
echo.
pause
"""

readme_content = """نظام هيا لنقاط البيع (Haya POS) - إصدار 21082026
الحقوق محفوظة م. علي سنان
======================================================
طريقة التشغيل على جهاز العميل:
1. انقر نقراً مزدوجاً على ملف "تشغيل_النظام.bat" أو "تشغيل_تطبيق_هيا21082026.bat".
2. يقوم الملف الذكي بالتحقق التلقائي من بيئة بايثون المدمجة وتشغيل الخوادم وفتح المتصفح تلقائياً على الرابط:
   http://localhost:8888

بيانات الاتصال بقاعدة البيانات (SQL Server):
- لتعديل اسم خادم SQL Server أو اسم قاعدة البيانات أو اسم المستخدم وكلمة المرور:
  افتح ملف "server_config.json" وقم بتعديل البيانات التالية حسب جهازك:
  {
    "server": "SENANSERVER\\SQLEXPRESS",
    "remote_server": "SENANSERVER\\SQLEXPRESS",
    "local_db": "sp",
    "remote_db": "sp",
    "username": "sa",
    "password": "as",
    "port": "",
    "point_no": 71,
    "point_name": "هيا",
    "version_check_url": "https://raw.githubusercontent.com/senanye/HayaPOS-2026/main/version.json"
  }

أهم التحديثات والإصلاحات المضمنة في إصدار 21082026:
------------------------------------------------------
1. تقرير الإحصائية والحركة المالية واليومية الشاملة (كشف الصندوق اليومي من تاريخ إلى تاريخ) مع طباعة وتصدير PDF وإرسال واتساب.
2. تثبيت وحفظ خيار الحفظ مع الطباعة أو الحفظ بدون طباعة على آخر اختيار للمستخدم تلقائياً.
3. إمكانية اختيار وتخصيص اللوجو المطبوع في الفاتورة من ملف صورة يتم اختياره من قبل المستخدم وحفظه في النظام.
4. نظام التحديث الأونلاين التلقائي المباشر عبر مستودع GitHub بضغطة زر واحدة لجميع نقاط البيع.
5. استوديو وطباعة ملصقات الباركود والطباعة الحرارية والتوافق التام مع كافة مقاسات الورق.
6. دعم بيئة بايثون المحمولة المدمجة للتشغيل المباشر لدى العميل دون تثبيت.
7. التحرير الذاتي للمنافذ 9000 و 8888 عند إعادة التشغيل لتفادي أي تعارض.
"""

# Create standalone folder as well
os.makedirs(folder_output, exist_ok=True)

# Copy web files
web_src = os.path.join(root_dir, "build", "web")
web_dst = os.path.join(folder_output, "web")
if os.path.exists(web_dst):
    shutil.rmtree(web_dst, ignore_errors=True)
shutil.copytree(web_src, web_dst)

# Copy server files
server_src = os.path.join(root_dir, "server")
server_dst = os.path.join(folder_output, "server")
if os.path.exists(server_dst):
    shutil.rmtree(server_dst, ignore_errors=True)
shutil.copytree(server_src, server_dst, ignore=shutil.ignore_patterns('*.pyc', '__pycache__', '*.db-journal', 'node_modules', 'wa_auth'))

# Copy python_env if exists in root
py_src = os.path.join(root_dir, "python_env")
py_dst = os.path.join(folder_output, "python_env")
if os.path.exists(py_src) and not os.path.exists(py_dst):
    shutil.copytree(py_src, py_dst)

# Write clean server_config.json
server_cfg_data = {
  "server": "SENANSERVER\\SQLEXPRESS",
  "remote_server": "SENANSERVER\\SQLEXPRESS",
  "local_db": "sp",
  "remote_db": "sp",
  "username": "sa",
  "password": "as",
  "port": "",
  "point_no": 71,
  "point_name": "هيا",
  "logo_base64": "",
  "version_check_url": "https://raw.githubusercontent.com/senanye/HayaPOS-2026/main/version.json"
}
with open(os.path.join(folder_output, "server_config.json"), "w", encoding="utf-8") as f:
    json.dump(server_cfg_data, f, indent=2, ensure_ascii=False)

# Write clean version.json
version_data = {
  "version": "1.0.2",
  "build_date": "2026-08-21",
  "app_name": "نظام هيا لنقاط البيع",
  "engineer": "م. علي سنان",
  "min_required_version": "1.0.0",
  "update_url": "https://raw.githubusercontent.com/senanye/HayaPOS-2026/main/update_latest.zip",
  "github_repo": "https://github.com/senanye/HayaPOS-2026",
  "changelog": [
    "إضافة تقرير الإحصائية والحركة المالية واليومية الشاملة (كشف الصندوق اليومي)",
    "إمكانية طباعة وتصدير التقرير المالي اليومي وتحويله إلى PDF وإرساله عبر الواتساب",
    "حفظ وتثبيت خيار الطباعة التلقائية بحسب تفضيل المستخدم الأخير",
    "إمكانية تخصيص وتحميل شعار (لوجو) الفواتير المطبوعة من ملف صورة",
    "تفعيل فحص وتحديث النسخة أونلاين بضغطة زر واحدة لجميع نقاط البيع",
    "دعم بيئة بايثون المحمولة المدمجة للتشغيل المباشر لدى العميل دون تثبيت",
    "التحرير التلقائي للمنافذ وإعادة التشغيل السلس دون تعليق"
  ],
  "is_mandatory": False
}
with open(os.path.join(folder_output, "version.json"), "w", encoding="utf-8") as f:
    json.dump(version_data, f, indent=2, ensure_ascii=False)

# Write batch files and readme inside folder
with open(os.path.join(folder_output, f"تشغيل_تطبيق_{pkg_name}.bat"), "w", encoding="utf-8") as f:
    f.write(bat_content)

with open(os.path.join(folder_output, "تشغيل_النظام.bat"), "w", encoding="utf-8") as f:
    f.write(bat_content)

with open(os.path.join(folder_output, "تعليمات_التشغيل.txt"), "w", encoding="utf-8") as f:
    f.write(readme_content)

print(f"2. Creating Zip archive '{zip_output}'...")
if os.path.exists(zip_output):
    os.remove(zip_output)

with zipfile.ZipFile(zip_output, 'w', zipfile.ZIP_DEFLATED) as zipf:
    for root, dirs, files in os.walk(folder_output):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, folder_output)
            arc_name = os.path.join(pkg_name, rel_path)
            zipf.write(full_path, arc_name)

file_size_mb = os.path.getsize(zip_output) / (1024 * 1024)
print(f"SUCCESS: Package '{zip_output}' created successfully ({file_size_mb:.2f} MB)!")
