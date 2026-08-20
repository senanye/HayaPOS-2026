import os
import subprocess

desktop_dir = os.path.join(os.environ.get("USERPROFILE", "C:\\Users\\user1"), "Desktop")
shortcut_path = os.path.join(desktop_dir, "نظام هيا 2026.lnk")
target_bat = r"d:\AndroidStudio\POS2026\تشغيل_تطبيق_هيا_2026.bat"
working_dir = r"d:\AndroidStudio\POS2026"

ps_command = f"""
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut('{shortcut_path}')
$Shortcut.TargetPath = '{target_bat}'
$Shortcut.WorkingDirectory = '{working_dir}'
$Shortcut.Description = 'نظام هيا 2026 لنقاط البيع'
$Shortcut.Save()
"""

try:
    subprocess.run(["powershell", "-Command", ps_command], check=True)
    print(f"Shortcut created successfully at {shortcut_path}")
except Exception as e:
    print(f"Error creating shortcut: {e}")
