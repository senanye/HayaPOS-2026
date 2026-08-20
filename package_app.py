import os
import shutil

root_dir = r"d:\AndroidStudio\POS2026"
pkg_dir = os.path.join(root_dir, "هيا 2026")
zip_output = os.path.join(root_dir, "هيا_2026.zip")

print("1. Creating packaging folder...")
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

# Create batch launcher
bat_content = """@echo off
chcp 65001 > nul
title نظام هيا 2026 لنقاط البيع - Haya POS 2026
echo =======================================================
echo           جاري تشغيل نظام هيا 2026 لنقاط البيع
echo =======================================================

cd /d "%~dp0"

echo [1/2] تشغيل خادم البيانات والـ API...
start /b python server/server.py

echo [2/2] تشغيل خادم تطبيق الويب...
start /b python -m http.server 8888 --directory web

timeout /t 3 > nul

echo فتح النظام في المتصفح...
start http://localhost:8888

echo =======================================================
echo        تم تشغيل النظام بنجاح! الرابط: http://localhost:8888
echo =======================================================
"""

bat_path = os.path.join(pkg_dir, "تشغيل_تطبيق_هيا_2026.bat")
with open(bat_path, "w", encoding="utf-8") as f:
    f.write(bat_content)

# Also put bat in root dir for convenience
root_bat_path = os.path.join(root_dir, "تشغيل_تطبيق_هيا_2026.bat")
with open(root_bat_path, "w", encoding="utf-8") as f:
    f.write(bat_content.replace("--directory web", "--directory build\\web"))

print("4. Creating ZIP archive...")
if os.path.exists(zip_output):
    os.remove(zip_output)

shutil.make_archive(os.path.join(root_dir, "هيا_2026"), 'zip', root_dir, "هيا 2026")
print(f"SUCCESS: Package created at {zip_output}")
