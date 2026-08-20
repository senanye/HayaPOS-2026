import os
import shutil

root_dir = r"d:\AndroidStudio\POS2026"
pkg_name = "هيا 20260808"
pkg_dir = os.path.join(root_dir, pkg_name)
zip_output_1 = os.path.join(root_dir, "هيا_20260808.zip")
zip_output_2 = os.path.join(root_dir, "هيا 20260808.zip")

print(f"1. Creating packaging folder '{pkg_name}'...")
if os.path.exists(pkg_dir):
    shutil.rmtree(pkg_dir)
os.makedirs(pkg_dir, exist_ok=True)

# Copy web build
web_src = os.path.join(root_dir, "build", "web")
web_dst = os.path.join(pkg_dir, "web")
print(f"2. Copying web bundle from {web_src} to {web_dst}...")
shutil.copytree(web_src, web_dst)

# Copy server files
server_src = os.path.join(root_dir, "server")
server_dst = os.path.join(pkg_dir, "server")
print(f"3. Copying server files from {server_src} to {server_dst}...")
shutil.copytree(server_src, server_dst)

# Create smart batch launcher inside the package folder
bat_content = """@echo off
chcp 65001 > nul
title نظام هيا لنقاط البيع - Haya POS 20260808
color 0B
echo ======================================================================
echo                 نظام هيا لنقاط البيع - إصدار 20260808
echo               Haya POS System - Release 20260808
echo ======================================================================
echo.

cd /d "%~dp0"

:: 1. Auto-detect Python executable
set "PYTHON_EXE="
where python >nul 2>nul
if %errorlevel% equ 0 (
    set "PYTHON_EXE=python"
) else (
    where py >nul 2>nul
    if %errorlevel% equ 0 (
        set "PYTHON_EXE=py"
    ) else (
        if exist "%LOCALAPPDATA%\\Programs\\Python\\Python312\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python312\\python.exe"
        if exist "%LOCALAPPDATA%\\Programs\\Python\\Python311\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python311\\python.exe"
        if exist "%LOCALAPPDATA%\\Programs\\Python\\Python310\\python.exe" set "PYTHON_EXE=%LOCALAPPDATA%\\Programs\\Python\\Python310\\python.exe"
        if exist "%ProgramFiles%\\Python312\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python312\\python.exe"
        if exist "%ProgramFiles%\\Python311\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python311\\python.exe"
        if exist "%ProgramFiles%\\Python310\\python.exe" set "PYTHON_EXE=%ProgramFiles%\\Python310\\python.exe"
        if exist "C:\\Python312\\python.exe" set "PYTHON_EXE=C:\\Python312\\python.exe"
        if exist "C:\\Python311\\python.exe" set "PYTHON_EXE=C:\\Python311\\python.exe"
        if exist "C:\\Python310\\python.exe" set "PYTHON_EXE=C:\\Python310\\python.exe"
    )
)

if "%PYTHON_EXE%"=="" (
    color 0C
    echo.
    echo ======================================================================
    echo  [تنبيه هام] لم يتم العثور على بايثون (Python) مثبت على جهاز العميل!
    echo ======================================================================
    echo.
    echo  لتشغيل خادم النظام، يرجى تثبيت Python (الإصدار 3.10 أو أحدث).
    echo  ملاحظة هامة: عند التثبيت، تأكد من وضع علامة صح على:
    echo  [x] Add python.exe to PATH
    echo.
    echo  رابط التحميل المباشر: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

echo [1/3] فحص وتجهيز مكتبات خادم البيانات والـ API...
"%PYTHON_EXE%" -c "import fastapi, uvicorn, pydantic" >nul 2>nul
if %errorlevel% neq 0 (
    echo جاري تثبيت حزم خادم الـ API تلقائياً (fastapi uvicorn pydantic)...
    "%PYTHON_EXE%" -m pip install fastapi uvicorn pydantic --quiet
)

echo [2/3] جاري تشغيل خادم البيانات والـ API على المنفذ 9000...
start "Haya 20260808 API Server" /min "%PYTHON_EXE%" server/server.py

echo [3/3] جاري تشغيل خادم واجهة الويب على المنفذ 8888...
start "Haya 20260808 Web Server" /min "%PYTHON_EXE%" -m http.server 8888 --directory web

timeout /t 2 > nul

echo.
echo فتح النظام في المتصفح...
start http://localhost:8888

echo.
echo ======================================================================
echo  تم تشغيل نظام هيا 20260808 بنجاح! 🚀
echo  الرابط في المتصفح: http://localhost:8888
echo  (يرجى إبقاء هذه النافذة مفتوحة طوال فترة عملك على النظام)
echo ======================================================================
echo.
pause
"""

bat_path = os.path.join(pkg_dir, "تشغيل_تطبيق_هيا_20260808.bat")
with open(bat_path, "w", encoding="utf-8") as f:
    f.write(bat_content)

bat_path_alt = os.path.join(pkg_dir, "تشغيل_النظام.bat")
with open(bat_path_alt, "w", encoding="utf-8") as f:
    f.write(bat_content)

# Also create launcher in root directory for quick access
root_bat_path = os.path.join(root_dir, "تشغيل_تطبيق_هيا_20260808.bat")
root_bat_content = bat_content.replace("--directory web", "--directory build\\web")
with open(root_bat_path, "w", encoding="utf-8") as f:
    f.write(root_bat_content)

root_bat_alt = os.path.join(root_dir, "تشغيل_النظام.bat")
with open(root_bat_alt, "w", encoding="utf-8") as f:
    f.write(root_bat_content)

# Also create README text in the package
readme_content = """نظام هيا لنقاط البيع (Haya POS) - إصدار 20260808
======================================================
طريقة التشغيل على جهاز العميل:
1. انقر نقراً مزدوجاً على ملف "تشغيل_تطبيق_هيا_20260808.bat" أو "تشغيل_النظام.bat".
2. يقوم الملف الذكي بالتحقق التلقائي من بايثون ومكتبات الـ API وتشغيل الخوادم وفتح المتصفح تلقائياً على الرابط:
   http://localhost:8888

أهم الميزات المضمنة في إصدار 20260808:
--------------------------------------
1. شاشة السندات المالية (Bonds): خيار "سند صرف (Payment)" هو الخيار الافتراضي المفعل والمميز باللون الأحمر مع إشارات واضحة لمنع أخطاء المستخدمين.
2. لوحة تحرير وتعديل بيانات الفرع المباشرة في SQLite مع فحص الاتصال والحفظ الفوري.
3. منع تكرار بنود السندات وحفظ متعدد الحسابات والأسطر بسلاسة.
4. الربط المزدوج مع SQLite محلياً و SQL Server عن بعد.
5. شاشات المبيعات، المشتريات، المرتجعات، كشف الحساب، وتقارير المخزون والأرباح.
"""
with open(os.path.join(pkg_dir, "تعليمات_التشغيل.txt"), "w", encoding="utf-8") as f:
    f.write(readme_content)

print(f"4. Creating ZIP archive for '{pkg_name}'...")
if os.path.exists(zip_output_1):
    os.remove(zip_output_1)
if os.path.exists(zip_output_2):
    os.remove(zip_output_2)

shutil.make_archive(os.path.join(root_dir, "هيا_20260808"), 'zip', root_dir, pkg_name)
shutil.copyfile(zip_output_1, zip_output_2)

file_size_mb = os.path.getsize(zip_output_1) / (1024 * 1024)
print(f"SUCCESS: Package '{zip_output_1}' and '{zip_output_2}' created successfully ({file_size_mb:.2f} MB)!")
