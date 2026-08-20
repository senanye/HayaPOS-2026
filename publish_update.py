"""
=====================================================================
 سكربت نشر وتوزيع التحديثات التلقائية عبر GitHub (Haya POS)
=====================================================================
يقوم هذا السكربت بـ:
1. بناء نسخة الويب (Flutter Web Release).
2. تحديث مجلد web/ المحلي.
3. إنشاء وتحديث حزمة التحديث المضغوطة update_latest.zip.
4. تحديث رقم الإصدار وتاريخ النشر في version.json.
5. رفع التحديث تلقائياً إلى مستودع GitHub (Git Push).
"""

import os
import sys
import json
import zipfile
import shutil
import subprocess
from datetime import datetime

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
VERSION_FILE = os.path.join(ROOT_DIR, "version.json")
ZIP_OUTPUT = os.path.join(ROOT_DIR, "update_latest.zip")
WEB_BUILD_DIR = os.path.join(ROOT_DIR, "build", "web")
WEB_DEST_DIR = os.path.join(ROOT_DIR, "web")
SERVER_DIR = os.path.join(ROOT_DIR, "server")

def load_version_info():
    if os.path.exists(VERSION_FILE):
        with open(VERSION_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {
        "version": "1.0.1",
        "build_date": datetime.now().strftime("%Y-%m-%d"),
        "min_required_version": "1.0.0",
        "update_url": "https://raw.githubusercontent.com/senanye/HayaPOS-2026/main/update_latest.zip",
        "github_repo": "https://github.com/senanye/HayaPOS-2026",
        "changelog": [
            "إضافة تقرير الإحصائية والحركة المالية اليومية الشاملة",
            "تحسينات المزامنة والطباعة واللوجو المخصص للفواتير"
        ],
        "is_mandatory": False
    }

def save_version_info(data):
    with open(VERSION_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def run_cmd(cmd, cwd=ROOT_DIR, check=True):
    print(f"--> تشغيل: {cmd}")
    res = subprocess.run(cmd, shell=True, cwd=cwd)
    if check and res.returncode != 0:
        print(f"[خطأ] فشل تنفيذ الأمر: {cmd}")
        sys.exit(res.returncode)
    return res.returncode

def main():
    print("=" * 70)
    print("   نظام نشر التحديثات الأونلاين - Haya POS Release Publisher")
    print("=" * 70)

    ver_data = load_version_info()
    current_ver = ver_data.get("version", "1.0.0")
    print(f"\n[1] الإصدار الحالي للنظام: v{current_ver}")

    # Ask for new version
    custom_ver = input(f"أدخل رقم الإصدار الجديد (اضغط Enter للاستمرار بـ v{current_ver}): ").strip()
    if custom_ver:
        ver_data["version"] = custom_ver.replace("v", "").replace("V", "")
    
    ver_data["build_date"] = datetime.now().strftime("%Y-%m-%d %H:%M")

    # Ask for changelog notes
    print("\n[2] ملاحظات التحديث (Changelog):")
    notes_input = input("أدخل الملاحظات الجديدة (أو اضغط Enter لاستخدام الملاحظات الحالية): ").strip()
    if notes_input:
        ver_data["changelog"] = [note.strip() for note in notes_input.split(";") if note.strip()]

    save_version_info(ver_data)
    print(f"تم حفظ بيانات الإصدار: v{ver_data['version']}")

    # 1. Build Flutter Web
    print("\n[3] جاري بناء نسخة الويب (Flutter Web Release)...")
    flutter_cmd = "flutter build web --release"
    run_cmd(flutter_cmd)

    # 2. Copy build/web to web/
    print("\n[4] جاري تحديث ملفات مجلد web/...")
    if os.path.exists(WEB_BUILD_DIR):
        os.makedirs(WEB_DEST_DIR, exist_ok=True)
        for item in os.listdir(WEB_BUILD_DIR):
            s = os.path.join(WEB_BUILD_DIR, item)
            d = os.path.join(WEB_DEST_DIR, item)
            if os.path.isdir(s):
                if os.path.exists(d):
                    shutil.rmtree(d)
                shutil.copytree(s, d)
            else:
                shutil.copy2(s, d)
        print("تم نسخ ملفات الويب بنجاح.")

    # 3. Create update_latest.zip
    print(f"\n[5] جاري إنشاء حزمة التحديث المضغوطة: {os.path.basename(ZIP_OUTPUT)}...")
    if os.path.exists(ZIP_OUTPUT):
        os.remove(ZIP_OUTPUT)

    with zipfile.ZipFile(ZIP_OUTPUT, "w", zipfile.ZIP_DEFLATED) as zip_f:
        # A. Add web/ folder
        if os.path.exists(WEB_DEST_DIR):
            for root, dirs, files in os.walk(WEB_DEST_DIR):
                for file in files:
                    file_path = os.path.join(root, file)
                    rel_path = os.path.relpath(file_path, ROOT_DIR)
                    zip_f.write(file_path, rel_path)

        # B. Add server/ folder (excluding config and local databases)
        if os.path.exists(SERVER_DIR):
            for root, dirs, files in os.walk(SERVER_DIR):
                for file in files:
                    if file.lower() in ["server_config.json", "branches.db"] or file.endswith(".db") or "__pycache__" in root:
                        continue
                    file_path = os.path.join(root, file)
                    rel_path = os.path.relpath(file_path, ROOT_DIR)
                    zip_f.write(file_path, rel_path)

        # C. Add version.json
        if os.path.exists(VERSION_FILE):
            zip_f.write(VERSION_FILE, "version.json")

    zip_size_mb = os.path.getsize(ZIP_OUTPUT) / (1024 * 1024)
    print(f"تم إنشاء حزمة التحديث بنجاح! الحجم: {zip_size_mb:.2f} MB")

    # 4. Push to Git/GitHub
    print("\n[6] فحص حالة مستودع Git...")
    has_git = os.path.exists(os.path.join(ROOT_DIR, ".git"))
    if has_git:
        push_confirm = input("هل ترغب في رفع التحديث مباشرة إلى GitHub؟ (y/n) [افتراضي y]: ").strip().lower()
        if push_confirm in ["", "y", "yes"]:
            print("جاري رفع التحديثات إلى GitHub...")
            run_cmd("git add version.json update_latest.zip server/ web/", check=False)
            run_cmd(f'git commit -m "Release v{ver_data["version"]} - {ver_data["build_date"]}"', check=False)
            code = run_cmd("git push origin main", check=False)
            if code == 0:
                print("\n" + "=" * 70)
                print(f"🎉 تم نشر التحديث بنجاح! الإصدار v{ver_data['version']} متاح الآن لجميع العملاء.")
                print("=" * 70)
                return

    print("\n" + "=" * 70)
    print(f"تم تجهيز التحديث محلياً v{ver_data['version']}.")
    print("لرفعه إلى GitHub يدوياً، شغّل:")
    print(f"   git add version.json update_latest.zip server/ web/")
    print(f'   git commit -m "Release v{ver_data["version"]}"')
    print(f"   git push origin main")
    print("=" * 70)

if __name__ == "__main__":
    main()
