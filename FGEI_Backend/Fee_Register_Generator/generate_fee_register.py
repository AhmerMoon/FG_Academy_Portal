from __future__ import annotations

import base64
import gzip
import json
import os
import re
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import inch
from reportlab.pdfgen import canvas
from supabase import create_client


BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "output"
OUTPUT_PDF = OUTPUT_DIR / "Fee_Tracking_Register_2026-27.pdf"

MONTHS = ["Oct", "Nov", "Dec", "Jan", "Feb", "Mar"]
CLASS_ORDER = [
    "9th Boys",
    "9th Girls",
    "10th Boys",
    "10th Girls",
    "11th Boys",
    "11th Girls",
    "12th Boys",
    "12th Girls",
]
SHEET_NAMES = {
    "9th Boys": "9B",
    "9th Girls": "9G",
    "10th Boys": "10B",
    "10th Girls": "10G",
    "11th Boys": "11B",
    "11th Girls": "11G",
    "12th Boys": "12B",
    "12th Girls": "12G",
}
MANUAL_NAME_ALIASES = {
    "mabdullah": "muhammadabdullahtariq",
    "minsa": "minsasaher",
    "abeeha": "abeehaalam",
    "waniaabbas": "wania",
    "abdulmoizahmed": "abdulmoiz",
    "abdulrehmanarib": "abdurrehman",
    "muhammadhassan": "muhammadhassanzia",
    "nabiranaveed": "nabeeranaveed",
    "ammar": "ammarasad",
    "haleema": "haleemaashnab",
}
EXTRA_BLANK_ROWS = 7

# October 2026 fees extracted from the user-provided reference workbook.
# Keeping this snapshot inside the generator makes the output reproducible and
# means the old workbook is not required every time the BAT file is run.
_FEE_REFERENCE_BLOB = (
    "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"
    "GitG//wHGvRDGPxIAAA=="
)


def _load_reference() -> dict[str, list[list[Any]]]:
    packed = base64.b64decode(_FEE_REFERENCE_BLOB)
    return json.loads(gzip.decompress(packed).decode("utf-8"))


def _tokens(value: str) -> list[str]:
    text = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    text = text.lower().replace("mohammad", "muhammad").replace("mohd", "muhammad")
    return re.findall(r"[a-z0-9]+", text)


def _variants(value: str) -> set[str]:
    tokens = _tokens(value)
    variants = {"".join(tokens)}
    if tokens and tokens[0] in {"muhammad", "m", "syed", "syeda"}:
        variants.add("".join(tokens[1:]))
    return {item for item in variants if item}


def _name_score(left: str, right: str) -> float:
    left_variants = _variants(left)
    right_variants = _variants(right)
    left_key = "".join(_tokens(left))
    right_key = "".join(_tokens(right))
    if MANUAL_NAME_ALIASES.get(left_key) == right_key:
        return 1.0
    if left_variants & right_variants:
        return 1.0
    return max(
        SequenceMatcher(None, a, b).ratio()
        for a in left_variants
        for b in right_variants
    )


def _match_class(
    students: list[dict[str, Any]],
    reference_rows: list[list[Any]],
) -> list[dict[str, Any]]:
    available = [
        {"source_name": str(row[0]), "fee": int(row[1]), "used": False}
        for row in reference_rows
    ]
    results: list[dict[str, Any]] = []

    # Strong matches are assigned first so one old row cannot be reused.
    pairs: list[tuple[float, int, int]] = []
    for student_index, student in enumerate(students):
        for source_index, source in enumerate(available):
            score = _name_score(str(student["name"]), source["source_name"])
            pairs.append((score, student_index, source_index))
    pairs.sort(reverse=True)

    assigned_students: set[int] = set()
    assignments: dict[int, tuple[int, float]] = {}
    for score, student_index, source_index in pairs:
        if score < 0.80:
            break
        if student_index in assigned_students or available[source_index]["used"]:
            continue

        # Avoid guessing where two old names score almost the same.
        alternatives = sorted(
            (
                pair_score
                for pair_score, pair_student, pair_source in pairs
                if pair_student == student_index
                and not available[pair_source]["used"]
                and pair_source != source_index
            ),
            reverse=True,
        )
        second_score = alternatives[0] if alternatives else 0.0
        if score < 0.93 and score - second_score < 0.05:
            continue

        assigned_students.add(student_index)
        available[source_index]["used"] = True
        assignments[student_index] = (source_index, score)

    for index, student in enumerate(students):
        assignment = assignments.get(index)
        if assignment is None:
            results.append(
                {
                    **student,
                    "fee": None,
                    "source_name": None,
                    "match_score": None,
                    "match_status": "Unmatched - fee left blank",
                }
            )
            continue
        source_index, score = assignment
        source = available[source_index]
        results.append(
            {
                **student,
                "fee": source["fee"],
                "source_name": source["source_name"],
                "match_score": score,
                "match_status": "Exact" if score == 1.0 else "Fuzzy",
            }
        )
    return results


def _load_env() -> None:
    candidates = [BASE_DIR / ".env", BASE_DIR.parent / ".env"]
    for path in candidates:
        if path.exists():
            load_dotenv(path)
            break


def _fetch_active_students() -> dict[str, list[dict[str, Any]]]:
    _load_env()
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SECRET_KEY", "").strip()
    if not url or not key:
        raise RuntimeError(
            "SUPABASE_URL or SUPABASE_SECRET_KEY is missing. "
            "Keep .env in this folder or its parent folder."
        )

    client = create_client(url, key)
    batches = client.table("batches").select("id,name,class_level").execute().data
    students = (
        client.table("students")
        .select("id,name,batch_id")
        .eq("is_archived", False)
        .execute()
        .data
    )
    batch_names = {str(row["id"]): str(row["name"]) for row in batches}
    grouped = {name: [] for name in CLASS_ORDER}
    for student in students:
        class_name = batch_names.get(str(student.get("batch_id")))
        if class_name in grouped:
            grouped[class_name].append(student)
    for class_students in grouped.values():
        class_students.sort(key=lambda row: str(row.get("name", "")).casefold())
    return grouped


def _prepare_rows(
    grouped: dict[str, list[dict[str, Any]]],
) -> tuple[dict[str, list[dict[str, Any]]], list[dict[str, Any]]]:
    reference = _load_reference()
    pages: dict[str, list[dict[str, Any]]] = {}
    audit_rows: list[dict[str, Any]] = []
    for class_name in CLASS_ORDER:
        matches = _match_class(grouped[class_name], reference.get(class_name, []))
        pages[class_name] = matches
        for row in matches:
            audit_rows.append({"class_name": class_name, **row})
    return pages, audit_rows


def _draw_centered(
    pdf: canvas.Canvas,
    text: str,
    center_x: float,
    baseline_y: float,
    font_name: str,
    font_size: float,
) -> None:
    pdf.setFont(font_name, font_size)
    pdf.drawCentredString(center_x, baseline_y, text)


def _build_pdf(pages: dict[str, list[dict[str, Any]]]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT_DIR / ".Fee_Tracking_Register_2026-27.tmp.pdf"
    if temporary.exists():
        temporary.unlink()

    page_width, page_height = A4
    margin = 0.2 * inch
    usable_width = page_width - (2 * margin)
    pdf = canvas.Canvas(str(temporary), pagesize=A4, pageCompression=1)
    pdf.setTitle("Fee Tracking Register 2026-27")

    for class_name in CLASS_ORDER:
        rows = pages[class_name]
        center_x = page_width / 2
        _draw_centered(
            pdf,
            "FGEIs Evening Coaching Classes Wah Cantt.",
            center_x,
            page_height - margin - 14,
            "Helvetica-Bold",
            15,
        )
        _draw_centered(
            pdf,
            f"{class_name} - Fee Tracking Register (Oct 2026 to Mar 2027)",
            center_x,
            page_height - margin - 32,
            "Helvetica-Bold",
            11.5,
        )

        table_top = page_height - margin - 43
        table_bottom = margin
        body_count = len(rows) + EXTRA_BLANK_ROWS
        total_rows = body_count + 1
        row_height = (table_top - table_bottom) / total_rows
        body_font_size = min(11.2, max(9.7, row_height * 0.56))
        header_font_size = min(11.5, max(10.0, row_height * 0.58))

        serial_width = 30.0
        name_width = 198.0
        month_width = (usable_width - serial_width - name_width) / 6
        column_widths = [serial_width, name_width] + [month_width] * 6
        x_positions = [margin]
        for width in column_widths:
            x_positions.append(x_positions[-1] + width)

        # White background only. All visual structure comes from black lines.
        pdf.setFillColorRGB(1, 1, 1)
        pdf.rect(
            margin,
            table_bottom,
            usable_width,
            table_top - table_bottom,
            stroke=0,
            fill=1,
        )
        pdf.setStrokeColorRGB(0, 0, 0)
        pdf.setFillColorRGB(0, 0, 0)
        pdf.setLineWidth(0.65)

        for x in x_positions:
            pdf.line(x, table_bottom, x, table_top)
        for index in range(total_rows + 1):
            y = table_top - (index * row_height)
            pdf.setLineWidth(1.0 if index in {0, 1, total_rows} else 0.55)
            pdf.line(margin, y, margin + usable_width, y)

        headers = ["Sr.", "Student Name", *MONTHS]
        header_y = table_top - row_height
        text_y = header_y + ((row_height - header_font_size) / 2) + 2.2
        pdf.setFont("Helvetica-Bold", header_font_size)
        for column, header in enumerate(headers):
            center = (x_positions[column] + x_positions[column + 1]) / 2
            pdf.drawCentredString(center, text_y, header)

        pdf.setFont("Helvetica", body_font_size)
        for index, student in enumerate(rows, start=1):
            row_bottom = table_top - ((index + 1) * row_height)
            baseline = row_bottom + ((row_height - body_font_size) / 2) + 2.0
            pdf.drawCentredString(
                (x_positions[0] + x_positions[1]) / 2,
                baseline,
                str(index),
            )
            pdf.drawString(x_positions[1] + 4, baseline, str(student["name"]))
            fee = student.get("fee")
            if fee is not None:
                pdf.drawCentredString(
                    (x_positions[2] + x_positions[3]) / 2,
                    baseline,
                    f"{int(fee):,}",
                )

        pdf.showPage()

    pdf.save()
    os.replace(temporary, OUTPUT_PDF)


def main() -> None:
    print("Fetching active students from Supabase...")
    grouped = _fetch_active_students()
    pages, audit_rows = _prepare_rows(grouped)
    print("Creating print-ready PDF...")
    _build_pdf(pages)

    matched = sum(row["fee"] is not None for row in audit_rows)
    unmatched = [row for row in audit_rows if row["fee"] is None]
    print(f"Done: {len(audit_rows)} active students, {matched} fees matched.")
    print(f"Fees left blank for {len(unmatched)} unmatched students.")
    print(f"PDF: {OUTPUT_PDF}")
    if unmatched:
        print("\nBlank-fee students:")
        for row in unmatched:
            print(f"- {row['class_name']}: {row['name']}")


if __name__ == "__main__":
    main()


