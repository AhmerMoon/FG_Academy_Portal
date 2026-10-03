import os
import json
import base64
import time
import calendar
import warnings

from datetime import datetime
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from supabase import create_client, Client

import pandas as pd
import dataframe_image as dfi
import pywhatkit as kit


# ============================================================
# CONFIGURATION
# ============================================================

warnings.filterwarnings("ignore")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

ENV_PATH = os.path.join(BASE_DIR, ".env")

load_dotenv(ENV_PATH)


SUPABASE_URL = os.environ.get("SUPABASE_URL", "").strip()

SUPABASE_SECRET_KEY = os.environ.get(
    "SUPABASE_SECRET_KEY",
    "",
).strip()


SEND_WHATSAPP = (
    os.environ.get(
        "SEND_WHATSAPP",
        "false",
    )
    .strip()
    .lower()
    in {"1", "true", "yes", "on"}
)


WHATSAPP_WAIT_TIME = 20

WHATSAPP_CLOSE_TIME = 5

BETWEEN_GROUPS_DELAY = 5

MAX_SEND_ATTEMPTS = 2


# ============================================================
# ENV / KEY VALIDATION
# ============================================================

def validate_environment():
    if not SUPABASE_URL:
        raise RuntimeError(
            "SUPABASE_URL is missing from .env"
        )

    if not SUPABASE_SECRET_KEY:
        raise RuntimeError(
            "SUPABASE_SECRET_KEY is missing from .env"
        )

    # New Supabase publishable key accidentally supplied.
    if SUPABASE_SECRET_KEY.startswith(
        "sb_publishable_"
    ):
        raise RuntimeError(
            "SUPABASE_SECRET_KEY contains a publishable key. "
            "Use the server-side sb_secret_ key instead."
        )

    # Legacy Supabase JWT keys can be inspected safely
    # without knowing their signing secret.
    if SUPABASE_SECRET_KEY.count(".") == 2:
        try:
            payload_part = (
                SUPABASE_SECRET_KEY
                .split(".")[1]
            )

            padding = "=" * (
                -len(payload_part) % 4
            )

            payload = json.loads(
                base64.urlsafe_b64decode(
                    payload_part + padding
                ).decode("utf-8")
            )

            role = payload.get("role")

            if role == "anon":
                raise RuntimeError(
                    "The .env still contains the old anon key. "
                    "Use the Supabase service_role / secret key "
                    "for this trusted local automation."
                )

        except RuntimeError:
            raise

        except Exception:
            # If an unfamiliar key format cannot be decoded,
            # let Supabase validate it when connecting.
            pass


validate_environment()


# ============================================================
# SUPABASE ADMIN CLIENT
# ============================================================

supabase: Client = create_client(
    SUPABASE_URL,
    SUPABASE_SECRET_KEY,
)


# ============================================================
# HELPERS
# ============================================================

def pakistan_now():
    return datetime.now(
        ZoneInfo("Asia/Karachi")
    )


def safe_filename(value):
    invalid_chars = '<>:"/\\|?*'

    cleaned = value

    for char in invalid_chars:
        cleaned = cleaned.replace(
            char,
            "_",
        )

    return cleaned.replace(
        " ",
        "_",
    )


def send_whatsapp_image(
    group_id,
    image_path,
    caption_text,
    batch_name,
):
    """
    Returns:
        True  -> successfully sent
        False -> failed after retries
    """

    for attempt in range(
        1,
        MAX_SEND_ATTEMPTS + 1,
    ):
        try:
            print(
                f"📲 WhatsApp attempt "
                f"{attempt}/{MAX_SEND_ATTEMPTS}: "
                f"{batch_name}"
            )

            kit.sendwhats_image(
                receiver=group_id,
                img_path=image_path,
                caption=caption_text,
                wait_time=WHATSAPP_WAIT_TIME,
                tab_close=True,
                close_time=WHATSAPP_CLOSE_TIME,
            )

            print(
                f"✅ Sent successfully: "
                f"{batch_name}"
            )

            return True

        except Exception as error:
            print(
                f"❌ WhatsApp attempt "
                f"{attempt} failed for "
                f"{batch_name}: {error}"
            )

            if attempt < MAX_SEND_ATTEMPTS:
                print(
                    "🔁 Retrying in 8 seconds..."
                )

                time.sleep(8)

    return False


# ============================================================
# REPORT GENERATION
# ============================================================

def generate_batch_report(
    batch,
    start_date,
    end_date,
    valid_days,
    month_name,
):
    batch_id = batch["id"]

    batch_name = batch["name"]


    print(
        f"🔄 Processing Batch: "
        f"{batch_name}"
    )


    # --------------------------------------------------------
    # STUDENTS
    # --------------------------------------------------------

    students_res = (
        supabase
        .table("students")
        .select("id, name")
        .eq(
            "batch_id",
            batch_id,
        )
        .order("name")
        .execute()
    )


    students_data = (
        students_res.data or []
    )


    if not students_data:
        print(
            f"⚠️ Skipping {batch_name}: "
            "No students found."
        )

        return None


    df_students = pd.DataFrame(
        students_data
    )


    df_students["Sr No"] = (
        range(
            1,
            len(df_students) + 1,
        )
    )


    df_students.rename(
        columns={
            "name": "Name of Student"
        },
        inplace=True,
    )


    # --------------------------------------------------------
    # MONTH ATTENDANCE
    # --------------------------------------------------------

    att_res = (
        supabase
        .table("attendance")
        .select(
            "student_id, date, status"
        )
        .eq(
            "batch_id",
            batch_id,
        )
        .gte(
            "date",
            start_date,
        )
        .lte(
            "date",
            end_date,
        )
        .execute()
    )


    attendance_data = (
        att_res.data or []
    )


    if attendance_data:
        df_att = pd.DataFrame(
            attendance_data
        )
    else:
        df_att = pd.DataFrame(
            columns=[
                "student_id",
                "date",
                "status",
            ]
        )


    # --------------------------------------------------------
    # ATTENDANCE PIVOT
    #
    # IMPORTANT:
    # Pivot by student_id, not student name.
    # Two students having the same name will therefore
    # not corrupt/merge their attendance.
    # --------------------------------------------------------

    if not df_att.empty:
        status_map = {
            "present": "P",
            "absent": "A",
            "leave": "L",
        }


        df_att["status_short"] = (
            df_att["status"].map(
                status_map
            )
        )


        df_att = df_att.dropna(
            subset=["date"]
        ).copy()


        df_att["day"] = (
            pd.to_datetime(
                df_att["date"]
            )
            .dt.day
            .astype(int)
        )


        # If somehow more than one record exists for
        # a student/day, keep the last one rather than
        # crashing pivot().
        pivot_df = df_att.pivot_table(
            index="student_id",
            columns="day",
            values="status_short",
            aggfunc="last",
        )


        df_final = (
            df_students[
                [
                    "id",
                    "Sr No",
                    "Name of Student",
                ]
            ]
            .merge(
                pivot_df,
                how="left",
                left_on="id",
                right_index=True,
            )
        )

    else:
        df_final = df_students[
            [
                "id",
                "Sr No",
                "Name of Student",
            ]
        ].copy()


    # Internal UUID is not displayed.
    df_final.drop(
        columns=["id"],
        inplace=True,
        errors="ignore",
    )


    # --------------------------------------------------------
    # COMPLETE MONTH COLUMNS
    # Sunday is intentionally excluded.
    # --------------------------------------------------------

    for day in valid_days:
        if day not in df_final.columns:
            df_final[day] = ""


    columns_order = [
        "Sr No",
        "Name of Student",
    ] + valid_days


    df_final = df_final[
        columns_order
    ]


    df_final = df_final.fillna("")


    # --------------------------------------------------------
    # STYLING
    # --------------------------------------------------------

    styles = [
        {
            "selector": "table",
            "props": [
                (
                    "border-collapse",
                    "collapse",
                ),
                (
                    "border",
                    "2px solid black",
                ),
                (
                    "min-width",
                    "1250px",
                ),
            ],
        },

        {
            "selector": "th",
            "props": [
                (
                    "border",
                    "1px solid black !important",
                ),
                (
                    "padding",
                    "10px 15px",
                ),
                (
                    "background-color",
                    "#f0f0f0",
                ),
                (
                    "text-align",
                    "center",
                ),
            ],
        },

        {
            "selector": "td",
            "props": [
                (
                    "border",
                    "1px solid black !important",
                ),
                (
                    "padding",
                    "10px 15px",
                ),
                (
                    "text-align",
                    "center",
                ),
            ],
        },

        {
            "selector": "tbody tr",
            "props": [
                (
                    "background-color",
                    "white !important",
                ),
            ],
        },

        {
            "selector": "td:nth-child(2)",
            "props": [
                (
                    "text-align",
                    "left",
                ),
                (
                    "white-space",
                    "nowrap",
                ),
                (
                    "padding-left",
                    "15px",
                ),
                (
                    "min-width",
                    "250px",
                ),
            ],
        },

        {
            "selector": "caption",
            "props": [
                (
                    "caption-side",
                    "top",
                ),
                (
                    "text-align",
                    "center",
                ),
                (
                    "margin-bottom",
                    "20px",
                ),
                (
                    "color",
                    "black",
                ),
            ],
        },
    ]


    caption_html = (
        "<span "
        "style='font-size: 22px; "
        "font-weight: bold;'>"
        "FGEIs Evening Coaching Classes"
        "</span>"

        "<hr "
        "style='border: 0; "
        "border-top: 2px solid black; "
        "margin: 10px 0;'>"

        "<span "
        "style='font-size: 22px; "
        "font-weight: bold;'>"
        f"Attendance Report for Month of "
        f"{month_name} for {batch_name}"
        "</span>"
    )


    styled_df = (
        df_final
        .style
        .set_table_styles(styles)
        .set_caption(caption_html)
        .hide(axis="index")
    )


    # --------------------------------------------------------
    # PNG
    # --------------------------------------------------------

    filename = (
        f"{safe_filename(batch_name)}"
        "_Attendance.png"
    )


    image_path = os.path.join(
        BASE_DIR,
        filename,
    )


    dfi.export(
        styled_df,
        image_path,
        max_cols=-1,
        max_rows=-1,
    )


    print(
        f"✅ Image Rendered: "
        f"{image_path}"
    )


    return image_path


# ============================================================
# MASTER AUTOMATION
# ============================================================

def process_all_batches():
    print()
    print(
        "🚀 FG Academy Attendance "
        "Automation Starting..."
    )
    print()


    if SEND_WHATSAPP:
        print(
            "📲 WhatsApp sending: ENABLED"
        )
    else:
        print(
            "🧪 WhatsApp sending: DISABLED "
            "(PNG generation test mode)"
        )


    print()


    # --------------------------------------------------------
    # BATCHES
    # --------------------------------------------------------

    batches_res = (
        supabase
        .table("batches")
        .select(
            "id, name, whatsapp_group_id"
        )
        .execute()
    )


    batches = [
        batch
        for batch in (
            batches_res.data or []
        )
        if batch.get(
            "whatsapp_group_id"
        )
        and str(
            batch.get(
                "whatsapp_group_id"
            )
        ).strip()
    ]


    if not batches:
        print(
            "❌ No batch with a WhatsApp "
            "Group ID was found."
        )

        return


    # --------------------------------------------------------
    # CURRENT MONTH
    # --------------------------------------------------------

    now = pakistan_now()

    year = now.year

    month = now.month


    _, last_day = (
        calendar.monthrange(
            year,
            month,
        )
    )


    start_date = (
        f"{year}-"
        f"{month:02d}-01"
    )


    end_date = (
        f"{year}-"
        f"{month:02d}-"
        f"{last_day:02d}"
    )


    # Python weekday:
    # Monday = 0
    # Sunday = 6
    valid_days = [
        day
        for day in range(
            1,
            last_day + 1,
        )
        if datetime(
            year,
            month,
            day,
        ).weekday()
        != 6
    ]


    month_name = now.strftime(
        "%b %Y"
    )


    # --------------------------------------------------------
    # RESULTS
    # --------------------------------------------------------

    generated_batches = []

    sent_batches = []

    failed_batches = []

    skipped_batches = []


    total_batches = len(batches)


    # --------------------------------------------------------
    # PROCESS
    # --------------------------------------------------------

    for index, batch in enumerate(
        batches,
        start=1,
    ):
        batch_name = batch["name"]

        group_id = str(
            batch["whatsapp_group_id"]
        ).strip()


        print()
        print("=" * 70)

        print(
            f"[{index}/{total_batches}] "
            f"{batch_name}"
        )

        print("=" * 70)


        try:
            image_path = (
                generate_batch_report(
                    batch=batch,
                    start_date=start_date,
                    end_date=end_date,
                    valid_days=valid_days,
                    month_name=month_name,
                )
            )


            if image_path is None:
                skipped_batches.append(
                    batch_name
                )

                continue


            generated_batches.append(
                batch_name
            )


            if not SEND_WHATSAPP:
                continue


            caption_text = (
                "Assalam o Alaikum,\n"
                "Attached is the automated "
                "attendance report for "
                f"{batch_name} "
                f"({month_name})."
            )


            success = (
                send_whatsapp_image(
                    group_id=group_id,
                    image_path=image_path,
                    caption_text=caption_text,
                    batch_name=batch_name,
                )
            )


            if success:
                sent_batches.append(
                    batch_name
                )
            else:
                failed_batches.append(
                    batch_name
                )


            if (
                SEND_WHATSAPP
                and index < total_batches
            ):
                print(
                    f"⏳ Waiting "
                    f"{BETWEEN_GROUPS_DELAY} "
                    "seconds..."
                )

                time.sleep(
                    BETWEEN_GROUPS_DELAY
                )


        except Exception as error:
            print(
                f"❌ Error processing "
                f"{batch_name}: "
                f"{error}"
            )

            failed_batches.append(
                batch_name
            )


    # --------------------------------------------------------
    # FINAL SUMMARY
    # --------------------------------------------------------

    print()
    print("=" * 70)

    print(
        "🎉 AUTOMATION FINISHED"
    )

    print("=" * 70)

    print(
        f"📄 Reports generated: "
        f"{len(generated_batches)}"
    )


    if SEND_WHATSAPP:
        print(
            f"✅ WhatsApp sent: "
            f"{len(sent_batches)}"
        )

        print(
            f"❌ WhatsApp failed: "
            f"{len(failed_batches)}"
        )


    print(
        f"⚠️ Batches skipped: "
        f"{len(skipped_batches)}"
    )


    if failed_batches:
        print()
        print(
            "Failed batches:"
        )

        for name in failed_batches:
            print(
                f" - {name}"
            )


    if skipped_batches:
        print()
        print(
            "Skipped batches:"
        )

        for name in skipped_batches:
            print(
                f" - {name}"
            )


    print()


# ============================================================
# START
# ============================================================

if __name__ == "__main__":
    try:
        process_all_batches()

    except Exception as error:
        print()
        print(
            "❌ AUTOMATION STOPPED"
        )

        print(
            f"Reason: {error}"
        )

        print()
        print(
            "Check .env, Supabase key, "
            "internet connection and "
            "database permissions."
        )

        raise