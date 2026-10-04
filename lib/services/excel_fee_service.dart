import 'dart:convert';

import '../models/excel_fee_models.dart';
import '../utils/excel_fee_bridge.dart';

class ExcelFeeService {
  bool get isSupported => isExcelFeeBridgeSupported;

  Future<ExcelFeeCatalog> fetchCatalog() async {
    final raw = await listExcelFeeWorkbooksJson();

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw StateError('Invalid Excel bridge response.');
    }

    final json = Map<String, dynamic>.from(decoded);

    if (json['ok'] != true) {
      throw StateError(
        json['error']?.toString() ??
            'Could not list '
                'Excel fee files.',
      );
    }

    return ExcelFeeCatalog.fromJson(json);
  }

  Future<ExcelFeeWorkbook> fetchWorkbook(String fileName) async {
    final raw = await readExcelFeeWorkbookJson(fileName);

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw StateError(
        'Invalid Excel workbook '
        'response.',
      );
    }

    final json = Map<String, dynamic>.from(decoded);

    if (json['ok'] != true) {
      throw StateError(
        json['error']?.toString() ??
            'Could not read '
                'Excel workbook.',
      );
    }

    return ExcelFeeWorkbook.fromJson(json);
  }
}
