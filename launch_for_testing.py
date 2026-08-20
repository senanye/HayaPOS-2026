import subprocess
import sys
import os
import time
import webbrowser

root_dir = r"d:\AndroidStudio\POS2026"
os.chdir(root_dir)

print("1. Starting API Server on port 9000...")
api_process = subprocess.Popen(
    [sys.executable, "server/server.py"],
    cwd=root_dir,
    creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS if os.name == 'nt' else 0
)

print("2. Starting No-Cache Web Server on port 8888...")
web_process = subprocess.Popen(
    [sys.executable, "server/web_server.py", "8888"],
    cwd=root_dir,
    creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS if os.name == 'nt' else 0
)

time.sleep(3)

print("3. Opening browser at http://localhost:8888...")
webbrowser.open("http://localhost:8888")

print("SUCCESS: Haya POS System is running at http://localhost:8888")
