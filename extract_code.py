
import os
import re
import subprocess
from pathlib import Path
from datetime import datetime

# ============================================================
# ACADEMY PORTAL - COMPLETE CODEBASE EXPORTER
# Includes Flutter, Supabase, Python Backend and Configs
# Read-only: does not modify existing project files
# ============================================================

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "academy_full_codebase.txt"

# Include schema JSON if available.
INCLUDE_SCHEMA_REFERENCE = True

# Main source folders and allowed extensions
SOURCE_FOLDERS = {
    "lib": {".dart"},
    "test": {".dart"},
    "integration_test": {".dart"},
    "FGEI_Backend": {".py", ".bat", ".ps1"},
    "supabase/migrations": {".sql"},
    ".github/workflows": {".yml", ".yaml"},
}

# Exact supporting files
EXTRA_FILES = [
    "pubspec.yaml",
    "analysis_options.yaml",
    "vercel.json",
    "firebase.json",

    # Android build and permissions
    "android/app/build.gradle.kts",
    "android/build.gradle.kts",
    "android/settings.gradle.kts",
    "android/app/src/main/AndroidManifest.xml",

    # Web deployment
    "web/index.html",
    "web/manifest.json",

    # Windows build
    "windows/CMakeLists.txt",
    "windows/runner/CMakeLists.txt",

    # Project documentation / migrations
    "docs/Academy_Antigravity_Final_Changes_Prompt.txt",
    "docs/Academy_Portal_Final_Cleanup.sql",
]

if INCLUDE_SCHEMA_REFERENCE:
    EXTRA_FILES.append(
        "docs/Academy_Supabase_Schema_Reference.json"
    )

# Other platform-specific code
EXTRA_PATTERNS = [
    "android/app/src/main/**/*.kt",
    "android/app/src/main/**/*.java",
    "windows/runner/*.cpp",
    "windows/runner/*.h",
]

SKIP_DIRS = {
    ".git",
    ".dart_tool",
    ".idea",
    ".vscode",
    "build",
    ".gradle",
    ".venv",
    "venv",
    "node_modules",
    "__pycache__",
    "attendance_reports",
    "output",
}

# Never export these potentially sensitive files.
BLOCKED_NAMES = {
    ".env",
    ".env.local",
    ".env.production",
    ".env.development",
    "key.properties",
    "local.properties",
    "google-services.json",
    "googleservice-info.plist",
    "service-account.json",
    "credentials.json",
    "secrets.json",
    "mcp_config.json",
    "pubspec.lock",
}

BLOCKED_SUFFIXES = {
    ".jks",
    ".keystore",
    ".p12",
    ".pem",
    ".key",
    ".db",
    ".sqlite",
    ".xlsx",
    ".xls",
    ".png",
    ".jpg",
    ".jpeg",
    ".pdf",
    ".zip",
    ".apk",
    ".aab",
}

MAX_FILE_SIZE = 3 * 1024 * 1024


def safe_to_include(path):
    if not path.is_file():
        return False

    relative = path.relative_to(ROOT)

    if any(part in SKIP_DIRS for part in relative.parts):
        return False

    name = path.name.lower()

    if name in BLOCKED_NAMES:
        return False

    if name.startswith(".env"):
        return False

    if path.suffix.lower() in BLOCKED_SUFFIXES:
        return False

    if path.stat().st_size > MAX_FILE_SIZE:
        return False

    return True


def collect_files():
    collected = set()

    # Main source folders
    for folder, allowed_extensions in SOURCE_FOLDERS.items():
        folder_path = ROOT / folder

        if not folder_path.is_dir():
            continue

        for path in folder_path.rglob("*"):
            if (
                safe_to_include(path)
                and path.suffix.lower() in allowed_extensions
            ):
                collected.add(path)

    # Exact configuration and documentation files
    for relative_path in EXTRA_FILES:
        path = ROOT / relative_path

        if safe_to_include(path):
            collected.add(path)

    # Other platform-specific source files
    for pattern in EXTRA_PATTERNS:
        for path in ROOT.glob(pattern):
            if safe_to_include(path):
                collected.add(path)

    def sort_key(path):
        relative = path.relative_to(ROOT).as_posix()

        if relative == "lib/main.dart":
            return (0, relative)

        if relative.startswith("lib/"):
            return (1, relative)

        if relative.startswith("supabase/migrations/"):
            return (2, relative)

        if relative.startswith("FGEI_Backend/"):
            return (3, relative)

        return (4, relative)

    return sorted(collected, key=sort_key)


def redact_secrets(text):
    """
    Redact common embedded tokens.
    Still manually inspect the export before sharing.
    """

    patterns = [
        r"sb_secret_[A-Za-z0-9_-]+",
        r"sb_publishable_[A-Za-z0-9_-]+",
        r"sk-[A-Za-z0-9_-]{20,}",
        r"ghp_[A-Za-z0-9_]+",
        r"gho_[A-Za-z0-9_]+",
        r"ghs_[A-Za-z0-9_]+",
        r"github_pat_[A-Za-z0-9_]+",
    ]

    for pattern in patterns:
        text = re.sub(
            pattern,
            "[REDACTED_TOKEN]",
            text,
            flags=re.IGNORECASE,
        )

    return text


def get_git_info():
    try:
        result = subprocess.run(
            ["git", "status", "--short"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=10,
            check=False,
        )

        if result.returncode == 0:
            return result.stdout.strip() or "Clean working tree"

        return "Git status unavailable"

    except Exception:
        return "Git status unavailable"


def read_file(path):
    try:
        return path.read_text(encoding="utf-8")

    except UnicodeDecodeError:
        return path.read_text(
            encoding="latin-1",
            errors="replace",
        )

    except Exception as error:
        return f"// ERROR READING FILE: {error}"


def export_codebase():
    print("=" * 60)
    print("ACADEMY PORTAL - COMPLETE CODEBASE EXPORT")
    print("=" * 60)

    if not (ROOT / "lib").is_dir():
        print("ERROR: Flutter lib folder not found.")
        print(f"Current folder: {ROOT}")
        return

    files = collect_files()

    if not files:
        print("No source files found.")
        return

    with OUTPUT.open("w", encoding="utf-8") as out:

        # Header
        out.write("=" * 90 + "\n")
        out.write("ACADEMY PORTAL - FULL CODEBASE REVIEW\n")
        out.write("=" * 90 + "\n")

        out.write(f"Project Root: {ROOT}\n")
        out.write(
            f"Exported At: {datetime.now().isoformat()}\n"
        )
        out.write(f"Total Files: {len(files)}\n\n")

        # Git state
        out.write("=" * 90 + "\n")
        out.write("GIT WORKING TREE STATUS\n")
        out.write("=" * 90 + "\n")
        out.write(get_git_info() + "\n\n")

        # File index
        out.write("=" * 90 + "\n")
        out.write("COMPLETE INCLUDED FILE INDEX\n")
        out.write("=" * 90 + "\n")

        for index, path in enumerate(files, start=1):
            relative = path.relative_to(ROOT).as_posix()
            out.write(f"{index:03d}. {relative}\n")

        out.write("\n\n")

        # All selected source files
        for index, path in enumerate(files, start=1):

            relative = path.relative_to(ROOT).as_posix()

            print(f"[{index}/{len(files)}] {relative}")

            content = read_file(path)
            content = redact_secrets(content)

            out.write("\n")
            out.write("=" * 90 + "\n")
            out.write(f"FILE START: {relative}\n")
            out.write("=" * 90 + "\n\n")

            out.write(content)

            if not content.endswith("\n"):
                out.write("\n")

            out.write("\n")
            out.write("=" * 90 + "\n")
            out.write(f"FILE END: {relative}\n")
            out.write("=" * 90 + "\n")

    size_mb = OUTPUT.stat().st_size / (1024 * 1024)

    print("\n" + "=" * 60)
    print("EXPORT COMPLETED")
    print("=" * 60)
    print(f"Files included: {len(files)}")
    print(f"Output: {OUTPUT}")
    print(f"Size: {size_mb:.2f} MB")
    print("\nReview the TXT for secrets before uploading.")


if __name__ == "__main__":
    export_codebase()
