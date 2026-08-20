import os
import shutil

root_dir = r"d:\AndroidStudio\POS2026"
pkg_dir = os.path.join(root_dir, "هيا 88")
zip_output = os.path.join(root_dir, "هيا_88.zip")

print("1. Creating packaging folder 'هيا 88'...")
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

# Create batch launcher inside the package folder
bat_content = """@echo off
chcp 65001 > nul
title نظام هيا 88 لنقاط البيع - Haya POS 88
color 0B
echo ======================================================================
echo                       نظام هيا 88 لنقاط البيع
echo               Haya POS 88 System - الإصدار الشامل
echo ======================================================================
echo.

cd /d "%~dp0"

echo [1/2] جاري تشغيل خادم البيانات والـ API على المنفذ 9000...
start "Haya 88 API Server" /min python server/server.py

echo [2/2] جاري تشغيل خادم تطبيق الويب على المنفذ 8888...
start "Haya 88 Web Server" /min python -m http.server 8888 --directory web

timeout /t 3 > nul

echo.
echo [3/3] فتح النظام في المتصفح...
start http://localhost:8888

echo.
echo ======================================================================
echo  تم تشغيل نظام هيا 88 بنجاح! 🚀
echo  رابط النظام المباشر: http://localhost:8888
echo ======================================================================
echo.
pause
"""

bat_path = os.path.join(pkg_dir, "تشغيل_تطبيق_هيا_88.bat")
with open(bat_path, "w", encoding="utf-8") as f:
    f.write(bat_content)

# Also create launcher in root directory for quick access
root_bat_path = os.path.join(root_dir, "تشغيل_تطبيق_هيا_88.bat")
root_bat_content = bat_content.replace("--directory web", "--directory build\\web")
with open(root_bat_path, "w", encoding="utf-8") as f:
    f.write(root_bat_content)

# Also create README text in the package
readme_content = """نظام هيا 88 لنقاط البيع (Haya POS 88)
=====================================
طريقة التشغيل:
1. انقر نقراً مزدوجاً على ملف "تشغيل_تطبيق_هيا_88.bat"
2. سيتم تشغيل الخوادم تلقائياً وفتح النظام في المتصفح على الرابط:
   http://localhost:8888

المميزات:
- دعم كامل للفروع وقواعد بيانات SQLite و SQL Server
- تسجيل دخول آمن لكافة المستخدمين مع التحقق الصارم من كلمات المرور
- نظام المبيعات، المرتجعات، سندات الصرف والقبض، وتقارير الأرباح والمخزون.
"""
with open(os.path.join(pkg_dir, "تعليمات_التشغيل.txt"), "w", encoding="utf-8") as f:
    f.write(readme_content)

print("4. Creating ZIP archive 'هيا_88.zip'...")
if os.path.exists(zip_output):
    os.remove(zip_output)

shutil.make_archive(os.path.join(root_dir, "هيا_88"), 'zip', root_dir, "هيا 88")

file_size_mb = os.path.getsize(zip_output) / (1024 * 1024)
print(f"SUCCESS: Package 'هيا_88.zip' created successfully ({file_size_mb:.2f} MB)!")
