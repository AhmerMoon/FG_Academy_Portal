
import argparse
import base64
import calendar
import json
import os
import sys
import time
import warnings

from datetime import datetime
from pathlib import Path
from uuid import UUID
from zoneinfo import ZoneInfo

import dataframe_image as dfi
import pandas as pd
import pywhatkit as kit
from dotenv import load_dotenv
from supabase import Client, create_client


# ============================================================
# ILMRISE ACADEMY - WHATSAPP ATTENDANCE AUTOMATION
# ============================================================

warnings.filterwarnings("ignore")

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

ACADEMY_NAME = "IlmRise Academy"

SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip()
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY", "").strip()

SEND_WHATSAPP = os.getenv(
    "SEND_WHATSAPP", "false"
).strip().lower() in {"1", "true", "yes", "on"}

WHATSAPP_WAIT_TIME = 20
WHATSAPP_CLOSE_TIME = 5
BETWEEN_GROUPS_DELAY = 5
MAX_SEND_ATTEMPTS = 2


def validate_environment():
    if not SUPABASE_URL:
        raise RuntimeError("SUPABASE_URL missing from .env")

    if not SUPABASE_SECRET_KEY:
        raise RuntimeError(
            "SUPABASE_SECRET_KEY missing from .env"
        )

    if SUPABASE_SECRET_KEY.startswith("sb_publishable_"):
        raise RuntimeError(
            "Publishable key cannot run backend automation. "
            "Use a trusted server-side secret key."
        )

    if SUPABASE_SECRET_KEY.count(".") == 2:
        try:
            part = SUPABASE_SECRET_KEY.split(".")[1]
            part += "=" * (-len(part) % 4)

            payload = json.loads(
                base64.urlsafe_b64decode(part)
            )

            if payload.get("role") == "anon":
                raise RuntimeError(
                    "Anon key cannot run backend automation."
                )
        except RuntimeError:
            raise
        except Exception:
            pass


validate_environment()

supabase: Client = create_client(
    SUPABASE_URL,
    SUPABASE_SECRET_KEY,
)


def pakistan_now():
    return datetime.now(ZoneInfo("Asia/Karachi"))


def safe_filename(value):
    value = str(value)

    for char in '<>:"/\\|?*':
        value = value.replace(char, "_")

    return "_".join(value.split())


def get_month_details():
    now = pakistan_now()

    year = now.year
    month = now.month

    _, last_day = calendar.monthrange(year, month)

    start_date = f"{year}-{month:02d}-01"
    end_date = f"{year}-{month:02d}-{last_day:02d}"

    valid_days = [
        day
        for day in range(1, last_day + 1)
        if datetime(year, month, day).weekday() != 6
    ]

    return (
        start_date,
        end_date,
        valid_days,
        now.strftime("%b %Y"),
    )


def get_target_batches(batch_id=None):
    query = (
        supabase.table("batches")
        .select("id, name, whatsapp_group_id")
    )

    if batch_id is not None:
        query = query.eq("id", batch_id)

    result = query.execute()
    rows = result.data or []

    if batch_id is not None and not rows:
        raise RuntimeError(
            "Selected batch was not found in Supabase."
        )

    batches = []

    for batch in rows:
        group_id = str(
            batch.get("whatsapp_group_id") or ""
        ).strip()

        if not group_id:
            if batch_id is not None:
                raise RuntimeError(
                    "Selected batch has no WhatsApp Group ID. "
                    "Configure its group before sending."
                )

            print(
                "Skipping batch without WhatsApp group:",
                batch.get("name"),
            )
            continue

        batches.append(batch)

    return batches


def send_whatsapp_image(
    group_id,
    image_path,
    caption_text,
    batch_name,
):
    for attempt in range(1, MAX_SEND_ATTEMPTS + 1):
        try:
            print(
                f"WhatsApp attempt {attempt}/"
                f"{MAX_SEND_ATTEMPTS}: {batch_name}"
            )

            kit.sendwhats_image(
                receiver=group_id,
                img_path=str(image_path),
                caption=caption_text,
                wait_time=WHATSAPP_WAIT_TIME,
                tab_close=True,
                close_time=WHATSAPP_CLOSE_TIME,
            )

            print(
                f"WhatsApp send command completed: "
                f"{batch_name}"
            )
            return True

        except Exception as error:
            print(
                f"WhatsApp failed for {batch_name}: "
                f"{error}"
            )

            if attempt < MAX_SEND_ATTEMPTS:
                time.sleep(8)

    return False


def generate_batch_report(
    batch,
    start_date,
    end_date,
    valid_days,
    month_name,
):
    batch_id = batch["id"]
    batch_name = batch["name"]

    print(f"Generating report: {batch_name}")

    # Students in this batch only.
    students_res = (
        supabase.table("students")
        .select("id, name")
        .eq("batch_id", batch_id)
        .order("name")
        .execute()
    )

    students_data = students_res.data or []

    if not students_data:
        print(f"No students in {batch_name}. Skipping.")
        return None

    students_df = pd.DataFrame(students_data)
    students_df["Sr No"] = range(
        1, len(students_df) + 1
    )

    students_df.rename(
        columns={"name": "Name of Student"},
        inplace=True,
    )

    # Monthly attendance for selected batch.
    attendance_res = (
        supabase.table("attendance")
        .select("student_id, date, status")
        .eq("batch_id", batch_id)
        .gte("date", start_date)
        .lte("date", end_date)
        .execute()
    )

    attendance_data = attendance_res.data or []

    if attendance_data:
        attendance_df = pd.DataFrame(attendance_data)

        attendance_df["status_short"] = (
            attendance_df["status"].map(
                {
                    "present": "P",
                    "absent": "A",
                    "leave": "L",
                }
            )
        )

        attendance_df = attendance_df.dropna(
            subset=["date"]
        ).copy()

        attendance_df["day"] = pd.to_datetime(
            attendance_df["date"]
        ).dt.day.astype(int)

        # Use UUID, never student name, for grouping.
        pivot_df = attendance_df.pivot_table(
            index="student_id",
            columns="day",
            values="status_short",
            aggfunc="last",
        )

        final_df = students_df[
            ["id", "Sr No", "Name of Student"]
        ].merge(
            pivot_df,
            how="left",
            left_on="id",
            right_index=True,
        )

    else:
        final_df = students_df[
            ["id", "Sr No", "Name of Student"]
        ].copy()

    final_df.drop(
        columns=["id"],
        inplace=True,
        errors="ignore",
    )

    for day in valid_days:
        if day not in final_df.columns:
            final_df[day] = ""

    final_df = final_df[
        ["Sr No", "Name of Student"] + valid_days
    ].fillna("")

    styles = [
        {
            "selector": "table",
            "props": [
                ("border-collapse", "collapse"),
                ("border", "2px solid black"),
                ("min-width", "1250px"),
            ],
        },
        {
            "selector": "th",
            "props": [
                ("border", "1px solid black"),
                ("padding", "10px 15px"),
                ("background-color", "#f0f0f0"),
                ("text-align", "center"),
            ],
        },
        {
            "selector": "td",
            "props": [
                ("border", "1px solid black"),
                ("padding", "10px 15px"),
                ("text-align", "center"),
            ],
        },
        {
            "selector": "tbody tr",
            "props": [
                ("background-color", "white"),
            ],
        },
        {
            "selector": "td:nth-child(2)",
            "props": [
                ("text-align", "left"),
                ("white-space", "nowrap"),
                ("padding-left", "15px"),
                ("min-width", "250px"),
            ],
        },
        {
            "selector": "caption",
            "props": [
                ("caption-side", "top"),
                ("text-align", "center"),
                ("margin-bottom", "20px"),
                ("color", "black"),
            ],
        },
    ]

    caption_html = (
        "<span style='font-size:22px;"
        "font-weight:bold;'>"
        f"{ACADEMY_NAME}"
        "</span>"
        "<hr style='border:0;"
        "border-top:2px solid black;"
        "margin:10px 0;'>"
        "<span style='font-size:22px;"
        "font-weight:bold;'>"
        "Attendance Report for Month of "
        f"{month_name} for {batch_name}"
        "</span>"
    )

    styled_df = (
        final_df.style
        .set_table_styles(styles)
        .set_caption(caption_html)
        .hide(axis="index")
    )

    filename = (
        f"{safe_filename(batch_name)}_Attendance.png"
    )

    image_path = BASE_DIR / filename

    dfi.export(
        styled_df,
        str(image_path),
        max_cols=-1,
        max_rows=-1,
    )

    print(f"Image generated: {image_path}")

    return image_path


def process_batches(batch_id=None):
    print()
    print(f"{ACADEMY_NAME} Attendance Automation")

    if batch_id:
        print(f"Mode: Single batch ({batch_id})")
    else:
        print("Mode: All batches")

    print(
        "WhatsApp sending:",
        "ENABLED" if SEND_WHATSAPP else
        "DISABLED - PNG only",
    )
    print()

    batches = get_target_batches(batch_id)

    if not batches:
        print("No eligible batches were found.")
        return

    (
        start_date,
        end_date,
        valid_days,
        month_name,
    ) = get_month_details()

    generated = []
    sent = []
    failed = []
    skipped = []

    total = len(batches)

    for index, batch in enumerate(batches, start=1):
        batch_name = batch["name"]
        group_id = str(
            batch["whatsapp_group_id"]
        ).strip()

        print()
        print("=" * 65)
        print(f"[{index}/{total}] {batch_name}")
        print("=" * 65)

        try:
            image_path = generate_batch_report(
                batch=batch,
                start_date=start_date,
                end_date=end_date,
                valid_days=valid_days,
                month_name=month_name,
            )

            if image_path is None:
                skipped.append(batch_name)
                continue

            generated.append(batch_name)

            if SEND_WHATSAPP:
                caption = (
                    "Assalam o Alaikum,\n"
                    "Attached is the attendance report for "
                    f"{batch_name} ({month_name}).\n"
                    f"{ACADEMY_NAME}"
                )

                success = send_whatsapp_image(
                    group_id=group_id,
                    image_path=image_path,
                    caption_text=caption,
                    batch_name=batch_name,
                )

                if success:
                    sent.append(batch_name)
                else:
                    failed.append(batch_name)

            if SEND_WHATSAPP and index < total:
                print(
                    f"Waiting {BETWEEN_GROUPS_DELAY}s "
                    "before next batch..."
                )
                time.sleep(BETWEEN_GROUPS_DELAY)

        except Exception as error:
            print(
                f"Failed to process {batch_name}: "
                f"{error}"
            )
            failed.append(batch_name)

    print()
    print("=" * 65)
    print("AUTOMATION FINISHED")
    print("=" * 65)

    print(f"Reports generated: {len(generated)}")

    if SEND_WHATSAPP:
        print(f"Send commands completed: {len(sent)}")
        print(f"Failed: {len(failed)}")

    print(f"Skipped: {len(skipped)}")

    for name in failed:
        print(f"FAILED: {name}")

    for name in skipped:
        print(f"SKIPPED: {name}")


def main():
    parser = argparse.ArgumentParser(
        description="IlmRise attendance WhatsApp automation"
    )

    parser.add_argument(
        "--batch-id",
        type=str,
        default=None,
        help="UUID of one batch. Omit to process all.",
    )

    args = parser.parse_args()

    if args.batch_id:
        try:
            UUID(args.batch_id)
        except ValueError:
            parser.error(
                "--batch-id must be a valid batch UUID."
            )

    # Prevent multiple automation processes from
    # sending to WhatsApp simultaneously on Windows.
    lock_file = BASE_DIR / "automation.lock"

    with open(lock_file, "a+b") as lock:
        if os.name == "nt":
            import msvcrt

            lock.seek(0)

            if lock.read(1) == b"":
                lock.seek(0)
                lock.write(b"0")
                lock.flush()

            lock.seek(0)

            try:
                msvcrt.locking(
                    lock.fileno(),
                    msvcrt.LK_NBLCK,
                    1,
                )
            except OSError:
                raise RuntimeError(
                    "Another WhatsApp automation is running. "
                    "Finish it before starting another."
                )

        try:
            process_batches(args.batch_id)
        finally:
            if os.name == "nt":
                lock.seek(0)
                msvcrt.locking(
                    lock.fileno(),
                    msvcrt.LK_UNLCK,
                    1,
                )


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print()
        print("AUTOMATION STOPPED")
        print(f"Reason: {error}")
        print(
            "Check .env, Supabase, Python environment, "
            "WhatsApp Web and internet connection."
        )
        sys.exit(1)
