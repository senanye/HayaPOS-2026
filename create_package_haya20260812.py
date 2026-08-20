import os
import zipfile

root_dir = r"d:\AndroidStudio\POS2026"
pkg_name = "هيا20260812"
zip_output_1 = os.path.join(root_dir, "هيا20260812.zip")
zip_output_2 = os.path.join(root_dir, "هيا_20260812.zip")

print("1. Packing files into zip using zipfile module...")

bat_content = """@echo off
chcp 65001 > nul
title نظام هيا لنقاط البيع - Haya POS 20260812
color 0B
echo ======================================================================
echo                 نظام هيا لنقاط البيع - إصدار 20260812
echo               Haya POS System - Release 20260812
echo ======================================================================
echo.

cd /d "%~dp0"

:: 1. Auto-detect Python executable
set "PYTHON_EXE="
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
    "%PYTHON_EXE%" -m pip install fastapi uvicorn pydantic requests --quiet
)

echo [2/3] جاري تشغيل خادم البيانات والـ API على المنفذ 9000...
start "Haya 20260812 API Server" /min "%PYTHON_EXE%" server/server.py

echo [3/3] جاري تشغيل خادم واجهة الويب على المنفذ 8888...
start "Haya 20260812 Web Server" /min "%PYTHON_EXE%" -m http.server 8888 --directory web

ping -n 3 127.0.0.1 >nul

echo.
echo فتح النظام في المتصفح...
start http://localhost:8888

echo.
echo ======================================================================
echo  تم تشغيل نظام هيا 20260812 بنجاح!
echo  الرابط في المتصفح: http://localhost:8888
echo  يرجى ابقاء هذه النافذة مفتوحة طوال فترة عملك على النظام
echo ======================================================================
echo.
pause
"""

readme_content = """نظام هيا لنقاط البيع (Haya POS) - إصدار 20260812
======================================================
طريقة التشغيل على جهاز العميل:
1. انقر نقراً مزدوجاً على ملف "تشغيل_تطبيق_هيا20260812.bat" أو "تشغيل_النظام.bat".
2. يقوم الملف الذكي بالتحقق التلقائي من بايثون ومكتبات الـ API وتشغيل الخوادم وفتح المتصفح تلقائياً على الرابط:
   http://localhost:8888

أهم الميزات والتحديثات المضمنة في إصدار 20260812:
------------------------------------------------------
1. استوديو وتصميم وطباعة ملصقات الباركود الحرارية (Barcode Label Studio):
   - دعم كامل للطباعة عبر المتصفح والطباعة المباشرة الحرارية بدون نوافذ معلقة.
   - تعديل ترتيب ومحاذاة وأحجام الحقول بحرية كاملة وقوالب جاهزة.
2. حفظ رقم العملة (fldMoneyID) ورقم الحساب (fldAccID) في جدول Main لجميع الفواتير والسندات المالية.
3. دعم كامل لنقاط البيع والمبيعات والمردودات والمشتريات وأوامر الصرف والتوريد والتحويلات.
"""

with zipfile.ZipFile(zip_output_1, 'w', zipfile.ZIP_DEFLATED) as zipf:
    # 1. Add web bundle
    web_dir = os.path.join(root_dir, "build", "web")
    for root, dirs, files in os.walk(web_dir):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, web_dir)
            arc_name = os.path.join(pkg_name, "web", rel_path)
            zipf.write(full_path, arc_name)

    # 2. Add server bundle
    server_dir = os.path.join(root_dir, "server")
    for root, dirs, files in os.walk(server_dir):
        for file in files:
            if file.endswith('.pyc') or '__pycache__' in root:
                continue
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, server_dir)
            arc_name = os.path.join(pkg_name, "server", rel_path)
            zipf.write(full_path, arc_name)

    # 3. Add batch files and readme
    zipf.writestr(f"{pkg_name}/تشغيل_تطبيق_هيا20260812.bat", bat_content.encode('utf-8'))
    zipf.writestr(f"{pkg_name}/تشغيل_النظام.bat", bat_content.encode('utf-8'))
    zipf.writestr(f"{pkg_name}/تعليمات_التشغيل.txt", readme_content.encode('utf-8'))

# Duplicate to alternative zip name
import shutil
shutil.copyfile(zip_output_1, zip_output_2)

file_size_mb = os.path.getsize(zip_output_1) / (1024 * 1024)
print(f"SUCCESS: Package '{zip_output_1}' created successfully ({file_size_mb:.2f} MB)!")
