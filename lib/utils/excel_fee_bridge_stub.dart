bool get isExcelFeeBridgeSupported => false;

Future<String> listExcelFeeWorkbooksJson() {
  throw UnsupportedError(
    'Local Excel fee reports are '
    'available only on Windows.',
  );
}

Future<String> readExcelFeeWorkbookJson(String fileName) {
  throw UnsupportedError(
    'Local Excel fee reports are '
    'available only on Windows.',
  );
}
