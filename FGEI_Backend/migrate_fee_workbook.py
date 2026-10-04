from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any


CLASS_SHEETS = [
    "9B",
    "9G",
    "10B",
    "10G",
    "XIB",
    "XIG",
    "XIIB",
    "XIIG",
]

SUMMARY_SHEETS = [
    "Payment Summary & Breakdown",
    "Subject totals (9 & 10)",
    "Subject Totals (XI & XII)",
]


def normalize(value: Any) -> str:
    if value is None:
        return ""

    return re.sub(
        r"\s+",
        " ",
        str(value).replace("\n", " "),
    ).strip().lower()


def col_letter(number: int) -> str:
    result = ""

    while number:
        number, remainder = divmod(
            number - 1,
            26,
        )

        result = (
            chr(65 + remainder)
            + result
        )

    return result


def find_header_column(
    ws,
    wanted: str,
) -> tuple[int, int]:
    wanted = normalize(wanted)

    for row in range(1, 11):
        for col in range(1, 31):
            value = normalize(
                ws.Cells(row, col).Value2
            )

            if value == wanted:
                return row, col

    raise RuntimeError(
        f"{ws.Name}: "
        f"'{wanted}' header not found."
    )


def snapshot_formulas(ws) -> dict[str, Any]:
    result: dict[str, Any] = {}

    used = ws.UsedRange

    first_row = used.Row
    first_col = used.Column

    last_row = (
        first_row
        + used.Rows.Count
        - 1
    )

    last_col = (
        first_col
        + used.Columns.Count
        - 1
    )

    for row in range(
        first_row,
        last_row + 1,
    ):
        for col in range(
            first_col,
            last_col + 1,
        ):
            cell = ws.Cells(
                row,
                col,
            )

            try:
                has_formula = bool(
                    cell.HasFormula
                )
            except Exception:
                has_formula = False

            if not has_formula:
                continue

            value = cell.Value2

            # Build address ourselves.
            # Example: A1, D15, AA42
            address = (
                f"{col_letter(col)}{row}"
            )

            result[address] = value

    return result

def compare_snapshots(
    before: dict[str, Any],
    after: dict[str, Any],
    sheet_name: str,
) -> list[str]:
    problems: list[str] = []
  
    addresses = set(before) | set(after)

    for address in sorted(addresses):
        old = before.get(address)
        new = after.get(address)

        if isinstance(
            old,
            (int, float),
        ) and isinstance(
            new,
            (int, float),
        ):
            if abs(
                float(old)
                - float(new)
            ) > 0.01:
                problems.append(
                    f"{sheet_name}!{address}: "
                    f"{old} -> {new}"
                )

            continue

        if old != new:
            problems.append(
                f"{sheet_name}!{address}: "
                f"{old!r} -> {new!r}"
            )

    return problems


def get_formula(cell) -> str | None:
    try:
        formula = cell.Formula2

        if isinstance(
            formula,
            str,
        ) and formula.startswith("="):
            return formula
    except Exception:
        pass

    try:
        formula = cell.Formula

        if isinstance(
            formula,
            str,
        ) and formula.startswith("="):
            return formula
    except Exception:
        pass

    return None


def set_formula(
    cell,
    formula: str,
) -> None:
    try:
        cell.Formula2 = formula
        return
    except Exception:
        pass

    cell.Formula = formula


def replace_fee_references(
    formula: str,
    source_column: str,
    counted_column: str,
) -> str:
    source = re.escape(
        source_column
    )

    # Examples:
    # D3
    # $D$3
    # D$3
    # $D3
    cell_pattern = re.compile(
        rf"(?<![A-Z0-9_])"
        rf"(\$?){source}"
        rf"(\$?\d+)"
        rf"(?![A-Z0-9_])",
        re.IGNORECASE,
    )

    result = cell_pattern.sub(
        lambda match:
            f"{match.group(1)}"
            f"{counted_column}"
            f"{match.group(2)}",
        formula,
    )

    # Whole-column references if any.
    whole_column_pattern = re.compile(
        rf"(?<![A-Z0-9_])"
        rf"(\$?){source}:"
        rf"(\$?){source}"
        rf"(?![A-Z0-9_])",
        re.IGNORECASE,
    )

    result = whole_column_pattern.sub(
        lambda match:
            f"{match.group(1)}"
            f"{counted_column}:"
            f"{match.group(2)}"
            f"{counted_column}",
        result,
    )

    return result


def is_number(
    value: Any,
) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
    )


def migrate_sheet(
    ws,
    excel,
) -> tuple[int, int]:
    header_row, fee_col = (
        find_header_column(
            ws,
            "fees",
        )
    )

    _, name_col = (
        find_header_column(
            ws,
            "name",
        )
    )

    # Prevent accidental double migration.
    header_values = {}

    for col in range(1, 40):
        text = normalize(
            ws.Cells(
                header_row,
                col,
            ).Value2
        )

        if text:
            header_values[text] = col

    already_status = (
        "status"
        in header_values
    )

    already_counted = (
        "counted_fee"
        in header_values
    )

    if already_status or already_counted:
        if (
            already_status
            and already_counted
        ):
            print(
                f"[SKIP] "
                f"{ws.Name}: "
                f"already migrated."
            )

            return 0, 0

        raise RuntimeError(
            f"{ws.Name}: "
            "partially migrated workbook "
            "detected."
        )

    fee_letter = col_letter(
        fee_col
    )

    # ---------------------------------------------------------
    # Insert STATUS + REMARKS immediately after FEES.
    # Excel itself updates shifted formulas/references.
    # ---------------------------------------------------------

    ws.Columns(
        fee_col + 1
    ).EntireColumn.Insert()

    ws.Columns(
        fee_col + 2
    ).EntireColumn.Insert()

    status_col = fee_col + 1
    remarks_col = fee_col + 2

    ws.Cells(
        header_row,
        status_col,
    ).Value2 = "STATUS"

    ws.Cells(
        header_row,
        remarks_col,
    ).Value2 = "REMARKS"

    # Copy header formatting from FEES.
    try:
        ws.Cells(
            header_row,
            fee_col,
        ).Copy()

        ws.Cells(
            header_row,
            status_col,
        ).PasteSpecial(-4122)

        ws.Cells(
            header_row,
            fee_col,
        ).Copy()

        ws.Cells(
            header_row,
            remarks_col,
        ).PasteSpecial(-4122)

        excel.CutCopyMode = False

        ws.Cells(
            header_row,
            status_col,
        ).Value2 = "STATUS"

        ws.Cells(
            header_row,
            remarks_col,
        ).Value2 = "REMARKS"
    except Exception:
        pass

    ws.Columns(
        status_col
    ).ColumnWidth = 12

    ws.Columns(
        remarks_col
    ).ColumnWidth = 22

    # ---------------------------------------------------------
    # Hidden helper columns at far right.
    # ---------------------------------------------------------

    used = ws.UsedRange

    used_last_col = (
        used.Column
        + used.Columns.Count
        - 1
    )

    counted_col = (
        used_last_col + 1
    )

    portal_id_col = (
        counted_col + 1
    )

    ws.Cells(
        header_row,
        counted_col,
    ).Value2 = "COUNTED_FEE"

    ws.Cells(
        header_row,
        portal_id_col,
    ).Value2 = "PORTAL_STUDENT_ID"

    ws.Columns(
        counted_col
    ).Hidden = True

    ws.Columns(
        portal_id_col
    ).Hidden = True

    counted_letter = col_letter(
        counted_col
    )

    status_letter = col_letter(
        status_col
    )

    fee_letter = col_letter(
        fee_col
    )

    # ---------------------------------------------------------
    # Identify real student rows.
    # ---------------------------------------------------------

    used = ws.UsedRange

    last_row = (
        used.Row
        + used.Rows.Count
        - 1
    )

    student_rows: list[int] = []

    for row in range(
        header_row + 1,
        last_row + 1,
    ):
        name = ws.Cells(
            row,
            name_col,
        ).Value2

        fee = ws.Cells(
            row,
            fee_col,
        ).Value2

        if (
            normalize(name)
            and is_number(fee)
        ):
            student_rows.append(row)

    if not student_rows:
        raise RuntimeError(
            f"{ws.Name}: "
            "no student rows found."
        )

    # ---------------------------------------------------------
    # September migration:
    # all current students start as PAID.
    #
    # COUNTED_FEE:
    # Paid   -> FEES
    # Unpaid -> 0
    # ---------------------------------------------------------

    for row in student_rows:
        status_cell = ws.Cells(
            row,
            status_col,
        )

        status_cell.Value2 = "Paid"

        try:
            status_cell.Validation.Delete()
        except Exception:
            pass

        try:
            status_cell.Validation.Add(
                3,  # xlValidateList
                1,  # xlValidAlertStop
                1,  # xlBetween
                "Paid,Unpaid",
            )
        except Exception:
            pass

        counted_formula = (
            f'=IF('
            f'LOWER(TRIM('
            f'{status_letter}{row}'
            f'))="paid",'
            f'{fee_letter}{row},'
            f'0)'
        )

        set_formula(
            ws.Cells(
                row,
                counted_col,
            ),
            counted_formula,
        )

    # ---------------------------------------------------------
    # Redirect existing financial formulas:
    #
    # old:
    # =D3:D48*0.6
    #
    # new:
    # =Q3:Q48*0.6
    #
    # Only local formulas are changed.
    # External sheet references are left alone.
    # ---------------------------------------------------------

    used = ws.UsedRange

    first_row = used.Row
    first_col = used.Column

    last_row = (
        first_row
        + used.Rows.Count
        - 1
    )

    last_col = (
        first_col
        + used.Columns.Count
        - 1
    )

    rewritten = 0

    for row in range(
        first_row,
        last_row + 1,
    ):
        for col in range(
            first_col,
            last_col + 1,
        ):
            if col in (
                counted_col,
                portal_id_col,
            ):
                continue

            cell = ws.Cells(
                row,
                col,
            )

            formula = get_formula(
                cell
            )

            if not formula:
                continue

            # Class sheets are expected to use
            # local calculations. Don't touch
            # external references.
            if "!" in formula:
                continue

            updated = (
                replace_fee_references(
                    formula,
                    fee_letter,
                    counted_letter,
                )
            )

            if updated != formula:
                set_formula(
                    cell,
                    updated,
                )

                rewritten += 1

    if rewritten == 0:
        raise RuntimeError(
            f"{ws.Name}: "
            "no fee formulas were redirected."
        )

    print(
        f"[OK] {ws.Name}: "
        f"{len(student_rows)} students, "
        f"{rewritten} formulas updated."
    )

    return (
        len(student_rows),
        rewritten,
    )


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--file",
        required=True,
        help=(
            "Path to monthly "
            "Excel workbook."
        ),
    )

    args = parser.parse_args()

    workbook_path = Path(
        args.file
    ).resolve()

    if not workbook_path.exists():
        print(
            f"ERROR: File not found: "
            f"{workbook_path}"
        )

        raise SystemExit(1)

    try:
        import pythoncom
        import win32com.client
    except ImportError:
        print(
            "ERROR: pywin32 missing."
        )

        raise SystemExit(1)

    pythoncom.CoInitialize()

    excel = None
    workbook = None

    try:
        excel = (
            win32com.client.DispatchEx(
                "Excel.Application"
            )
        )

        excel.Visible = False
        excel.DisplayAlerts = False
        excel.ScreenUpdating = False
        excel.EnableEvents = False

        workbook = (
            excel.Workbooks.Open(
                str(workbook_path),
                UpdateLinks=0,
                ReadOnly=False,
                IgnoreReadOnlyRecommended=True,
                AddToMru=False,
            )
        )

        print(
            f"Workbook: "
            f"{workbook_path}"
        )

        print(
            "\nCalculating original workbook..."
        )

        excel.CalculateFullRebuild()

        # Snapshot summary values BEFORE change.
        before = {}

        for name in SUMMARY_SHEETS:
            before[name] = (
                snapshot_formulas(
                    workbook.Worksheets(
                        name
                    )
                )
            )

        total_students = 0
        total_formulas = 0

        print(
            "\nMigrating class sheets...\n"
        )

        for sheet_name in CLASS_SHEETS:
            ws = workbook.Worksheets(
                sheet_name
            )

            students, formulas = (
                migrate_sheet(
                    ws,
                    excel,
                )
            )

            total_students += students
            total_formulas += formulas

        print(
            "\nRecalculating migrated workbook..."
        )

        excel.CalculateFullRebuild()

        # -----------------------------------------------------
        # Verify summary outputs did NOT change.
        # -----------------------------------------------------

        problems: list[str] = []

        for name in SUMMARY_SHEETS:
            after = snapshot_formulas(
                workbook.Worksheets(
                    name
                )
            )

            problems.extend(
                compare_snapshots(
                    before[name],
                    after,
                    name,
                )
            )

        if problems:
            print(
                "\nVERIFICATION FAILED."
            )

            print(
                "Workbook will NOT be saved.\n"
            )

            for problem in problems[:30]:
                print(
                    f" - {problem}"
                )

            raise RuntimeError(
                "Financial totals changed "
                "during migration."
            )

        print(
            "\nVerification PASSED."
        )

        print(
            "Existing summary values "
            "are unchanged."
        )

        workbook.Save()

        print(
            "\n=================================="
        )

        print(
            "MIGRATION SUCCESSFUL"
        )

        print(
            "=================================="
        )

        print(
            f"Students migrated: "
            f"{total_students}"
        )

        print(
            f"Formulas redirected: "
            f"{total_formulas}"
        )

        print(
            f"Saved: {workbook_path}"
        )

        print(
            "\nPaid = counted in calculations"
        )

        print(
            "Unpaid = zero in calculations"
        )

    except Exception as exc:
        print(
            f"\nERROR: {exc}"
        )

        if workbook is not None:
            try:
                workbook.Close(
                    SaveChanges=False
                )
            except Exception:
                pass

            workbook = None

        raise SystemExit(1)

    finally:
        if workbook is not None:
            try:
                workbook.Close(
                    SaveChanges=False
                )
            except Exception:
                pass

        if excel is not None:
            try:
                excel.Quit()
            except Exception:
                pass

        pythoncom.CoUninitialize()


if __name__ == "__main__":
    main()