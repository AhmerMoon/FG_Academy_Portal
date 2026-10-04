from __future__ import annotations

import argparse
import json
import re
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any


FILE_PATTERN = re.compile(
    r"^Fee_(\d{4})-(\d{2})\.xlsx$",
    re.IGNORECASE,
)

PRIMARY_SHEET_ORDER = [
    "Payment Summary & Breakdown",
    "Subject totals (9 & 10)",
    "Subject Totals (XI & XII)",
    "9B",
    "9G",
    "10B",
    "10G",
    "XIB",
    "XIG",
    "XIIB",
    "XIIG",
]

# Old/helper sheets which should not appear in the test UI.
EXCLUDED_SHEETS = {
    "Sheet1",
    "Sheet3",
    "Recheck",
    "Summay (Admin & NTS Staff)",
}

MONTH_NAMES = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]


def _emit(
    payload: dict[str, Any],
    exit_code: int = 0,
) -> None:
    print(
        json.dumps(
            payload,
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )

    raise SystemExit(exit_code)


def _normalize_text(value: Any) -> str:
    if value is None:
        return ""

    text = (
        str(value)
        .replace("\r", " ")
        .replace("\n", " ")
    )

    return re.sub(
        r"\s+",
        " ",
        text,
    ).strip().lower()


def _is_blank(value: Any) -> bool:
    return (
        value is None
        or (
            isinstance(value, str)
            and value.strip() == ""
        )
    )


def _json_value(value: Any) -> Any:
    if value is None:
        return None

    if isinstance(
        value,
        (str, int, float, bool),
    ):
        return value

    if isinstance(value, Decimal):
        return float(value)

    if isinstance(
        value,
        (datetime, date),
    ):
        return value.isoformat()

    return str(value)


def _to_matrix(
    raw: Any,
) -> list[list[Any]]:
    if raw is None:
        return [[None]]

    if isinstance(raw, tuple):
        if not raw:
            return []

        if isinstance(raw[0], tuple):
            return [
                [
                    _json_value(cell)
                    for cell in row
                ]
                for row in raw
            ]

        return [
            [
                _json_value(cell)
                for cell in raw
            ]
        ]

    return [[_json_value(raw)]]


def _trim_matrix(
    matrix: list[list[Any]],
) -> list[list[Any]]:
    if not matrix:
        return []

    width = max(
        (len(row) for row in matrix),
        default=0,
    )

    rows = [
        row + [None] * (width - len(row))
        for row in matrix
    ]

    # Remove completely blank top rows.
    while rows and all(
        _is_blank(value)
        for value in rows[0]
    ):
        rows.pop(0)

    # Remove completely blank bottom rows.
    while rows and all(
        _is_blank(value)
        for value in rows[-1]
    ):
        rows.pop()

    if not rows:
        return []

    # Remove completely blank left columns.
    while (
        rows
        and rows[0]
        and all(
            _is_blank(row[0])
            for row in rows
        )
    ):
        for row in rows:
            row.pop(0)

    # Remove completely blank right columns.
    while (
        rows
        and rows[0]
        and all(
            _is_blank(row[-1])
            for row in rows
        )
    ):
        for row in rows:
            row.pop()

    return rows


def _file_metadata(
    path: Path,
) -> dict[str, Any] | None:
    match = FILE_PATTERN.match(path.name)

    if match is None:
        return None

    year = int(match.group(1))
    month = int(match.group(2))

    if month < 1 or month > 12:
        return None

    modified = datetime.fromtimestamp(
        path.stat().st_mtime
    ).isoformat(
        timespec="seconds",
    )

    return {
        "fileName": path.name,
        "year": year,
        "month": month,
        "label": (
            f"{MONTH_NAMES[month - 1]} {year}"
        ),
        "modifiedAt": modified,
    }


def _discover_files(
    data_dir: Path,
) -> list[dict[str, Any]]:
    data_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    files: list[dict[str, Any]] = []

    for path in data_dir.iterdir():
        if not path.is_file():
            continue

        metadata = _file_metadata(path)

        if metadata is not None:
            files.append(metadata)

    # Latest month first.
    files.sort(
        key=lambda item: (
            int(item["year"]),
            int(item["month"]),
        ),
        reverse=True,
    )

    return files


def _extract_key_metrics(
    matrix: list[list[Any]],
) -> dict[str, float]:
    """
    Reads the TOTAL row from Payment Summary & Breakdown
    by matching labels - NOT fixed row/column positions.
    """

    header_index: int | None = None

    for index, row in enumerate(matrix):
        labels = [
            _normalize_text(value)
            for value in row
        ]

        has_class = "class" in labels

        has_collection = any(
            "total collection" in label
            for label in labels
        )

        if has_class and has_collection:
            header_index = index
            break

    if header_index is None:
        return {}

    header = matrix[header_index]

    columns: dict[str, int] = {}

    for index, value in enumerate(header):
        label = _normalize_text(value)

        if "total collection" in label:
            columns["collection"] = index

        elif label.startswith("teacher"):
            columns["teacher"] = index

        elif "nts" in label:
            columns["nts"] = index

        elif "building" in label:
            columns["building"] = index

        elif label.startswith("admin"):
            columns["admin"] = index

        elif label.startswith("organizer"):
            columns["organizer"] = index

        elif label.startswith("ecc"):
            columns["ecc"] = index

    total_row: list[Any] | None = None

    for row in matrix[
        header_index + 1 :
    ]:
        first_value = next(
            (
                _normalize_text(value)
                for value in row
                if not _is_blank(value)
            ),
            "",
        )

        if first_value == "total":
            total_row = row
            break

    if total_row is None:
        return {}

    metrics: dict[str, float] = {}

    for key, column_index in columns.items():
        if column_index >= len(total_row):
            continue

        value = total_row[column_index]

        if isinstance(value, bool):
            continue

        if isinstance(value, (int, float)):
            metrics[key] = float(value)

    return metrics


def _read_workbook(
    data_dir: Path,
    file_name: str,
) -> dict[str, Any]:
    # Prevent path traversal.
    safe_name = Path(file_name).name

    if safe_name != file_name:
        raise ValueError(
            "Invalid workbook file name."
        )

    # IMPORTANT:
    # Resolve the file INSIDE Fee_Data first.
    workbook_path = (
        data_dir / safe_name
    ).resolve()

    if not workbook_path.exists():
        raise FileNotFoundError(
            f"Workbook not found: "
            f"{workbook_path}"
        )

    # Metadata must also use the full workbook path.
    metadata = _file_metadata(
        workbook_path
    )

    if metadata is None:
        raise ValueError(
            "Workbook name must use "
            "Fee_YYYY-MM.xlsx format."
        )

    try:
        import pythoncom
        import win32com.client
    except ImportError as exc:
        raise RuntimeError(
            "pywin32 is not installed. "
            "Run: "
            ".venv\\Scripts\\python.exe "
            "-m pip install pywin32"
        ) from exc
    
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

        # Disable any workbook macros while reading.
        try:
            excel.AutomationSecurity = 3
        except Exception:
            pass

        try:
            excel.AskToUpdateLinks = False
        except Exception:
            pass

        workbook = excel.Workbooks.Open(
            str(workbook_path),
            UpdateLinks=0,
            ReadOnly=True,
            IgnoreReadOnlyRecommended=True,
            AddToMru=False,
        )

        try:
            # xlCalculationAutomatic
            excel.Calculation = -4105
        except Exception:
            pass

        # Excel itself performs ALL calculations.
        # Python performs no financial maths.
        excel.CalculateFullRebuild()

        sheets: list[
            dict[str, Any]
        ] = []

        for worksheet in workbook.Worksheets:
            name = str(
                worksheet.Name
            )

            if name in EXCLUDED_SHEETS:
                continue

            used_range = (
                worksheet.UsedRange
            )

            matrix = _trim_matrix(
                _to_matrix(
                    used_range.Value2
                )
            )

            if not matrix:
                continue

            row_count = len(matrix)

            column_count = max(
                (
                    len(row)
                    for row in matrix
                ),
                default=0,
            )

            sheets.append(
                {
                    "name": name,
                    "rowCount": row_count,
                    "columnCount": column_count,
                    "rows": matrix,
                }
            )

        order = {
            name: index
            for index, name
            in enumerate(
                PRIMARY_SHEET_ORDER
            )
        }

        sheets.sort(
            key=lambda item: (
                order.get(
                    str(item["name"]),
                    999,
                ),
                str(item["name"]),
            )
        )

        summary_sheet = next(
            (
                item
                for item in sheets
                if item["name"]
                == "Payment Summary & Breakdown"
            ),
            None,
        )

        metrics = (
            _extract_key_metrics(
                summary_sheet["rows"]
            )
            if summary_sheet
            is not None
            else {}
        )

        return {
            "ok": True,
            "file": metadata,
            "dataDir": str(
                data_dir.resolve()
            ),
            "generatedAt": (
                datetime.now()
                .isoformat(
                    timespec="seconds"
                )
            ),
            "keyMetrics": metrics,
            "sheets": sheets,
        }

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


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "FG Academy local "
            "Excel fee bridge"
        )
    )

    subparsers = (
        parser.add_subparsers(
            dest="command",
            required=True,
        )
    )

    list_parser = (
        subparsers.add_parser(
            "list",
            help=(
                "List local monthly "
                "fee workbooks"
            ),
        )
    )

    list_parser.add_argument(
        "--data-dir",
        required=True,
    )

    read_parser = (
        subparsers.add_parser(
            "read",
            help=(
                "Read one monthly "
                "fee workbook"
            ),
        )
    )

    read_parser.add_argument(
        "--data-dir",
        required=True,
    )

    read_parser.add_argument(
        "--file",
        required=True,
    )

    return parser.parse_args()


def main() -> None:
    args = _parse_args()

    data_dir = (
        Path(args.data_dir)
        .expanduser()
        .resolve()
    )

    try:
        if args.command == "list":
            _emit(
                {
                    "ok": True,
                    "dataDir": str(
                        data_dir
                    ),
                    "files":
                        _discover_files(
                            data_dir
                        ),
                }
            )

        if args.command == "read":
            _emit(
                _read_workbook(
                    data_dir,
                    args.file,
                )
            )

        raise ValueError(
            "Unsupported command."
        )

    except SystemExit:
        raise

    except Exception as exc:
        _emit(
            {
                "ok": False,
                "error": str(exc),
                "errorType":
                    type(exc).__name__,
            },
            exit_code=1,
        )


if __name__ == "__main__":
    main()