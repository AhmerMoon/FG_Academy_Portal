class ExcelFeeFile {
  final String fileName;
  final int year;
  final int month;
  final String label;
  final String modifiedAt;

  const ExcelFeeFile({
    required this.fileName,
    required this.year,
    required this.month,
    required this.label,
    required this.modifiedAt,
  });

  factory ExcelFeeFile.fromJson(Map<String, dynamic> json) {
    return ExcelFeeFile(
      fileName: json['fileName']?.toString() ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      month: (json['month'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
      modifiedAt: json['modifiedAt']?.toString() ?? '',
    );
  }
}

class ExcelFeeCatalog {
  final String dataDir;
  final List<ExcelFeeFile> files;

  const ExcelFeeCatalog({required this.dataDir, required this.files});

  factory ExcelFeeCatalog.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as List? ?? const [];

    return ExcelFeeCatalog(
      dataDir: json['dataDir']?.toString() ?? '',
      files: rawFiles
          .whereType<Map>()
          .map((item) => ExcelFeeFile.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class ExcelFeeSheet {
  final String name;
  final int rowCount;
  final int columnCount;

  final List<List<Object?>> rows;

  const ExcelFeeSheet({
    required this.name,
    required this.rowCount,
    required this.columnCount,
    required this.rows,
  });

  factory ExcelFeeSheet.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List? ?? const [];

    final rows = rawRows.map((raw) {
      if (raw is List) {
        return List<Object?>.from(raw);
      }

      return <Object?>[raw];
    }).toList();

    return ExcelFeeSheet(
      name: json['name']?.toString() ?? 'Sheet',
      rowCount: (json['rowCount'] as num?)?.toInt() ?? rows.length,
      columnCount: (json['columnCount'] as num?)?.toInt() ?? 0,
      rows: rows,
    );
  }
}

class ExcelFeeWorkbook {
  final ExcelFeeFile file;

  final String dataDir;
  final String generatedAt;

  final Map<String, double> keyMetrics;

  final List<ExcelFeeSheet> sheets;

  const ExcelFeeWorkbook({
    required this.file,
    required this.dataDir,
    required this.generatedAt,
    required this.keyMetrics,
    required this.sheets,
  });

  factory ExcelFeeWorkbook.fromJson(Map<String, dynamic> json) {
    final rawMetrics = json['keyMetrics'];

    final metrics = <String, double>{};

    if (rawMetrics is Map) {
      for (final entry in rawMetrics.entries) {
        final value = entry.value;

        if (value is num) {
          metrics[entry.key.toString()] = value.toDouble();
        }
      }
    }

    final rawSheets = json['sheets'] as List? ?? const [];

    return ExcelFeeWorkbook(
      file: ExcelFeeFile.fromJson(
        Map<String, dynamic>.from(json['file'] as Map? ?? const {}),
      ),
      dataDir: json['dataDir']?.toString() ?? '',
      generatedAt: json['generatedAt']?.toString() ?? '',
      keyMetrics: metrics,
      sheets: rawSheets
          .whereType<Map>()
          .map(
            (item) => ExcelFeeSheet.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}
