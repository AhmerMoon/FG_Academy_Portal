class FeeMonth {
  FeeMonth._();

  static const List<String> abbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sept',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> fullNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String fromDate(DateTime date) {
    return fromParts(date.year, date.month);
  }

  static String fromParts(int year, int month) {
    if (month < 1 || month > 12) {
      throw ArgumentError('Month must be between 1 and 12.');
    }

    return '${abbreviations[month - 1]}-$year';
  }

  static DateTime? parse(String value) {
    final parts = value.split('-');

    if (parts.length != 2) return null;

    final month = abbreviations.indexOf(parts[0]) + 1;
    final year = int.tryParse(parts[1]);

    if (month <= 0 || year == null) return null;

    return DateTime(year, month);
  }

  static List<String> newestFirst(Iterable<String> months) {
    final values = months.toSet().toList();

    values.sort((first, second) {
      final firstDate = parse(first);
      final secondDate = parse(second);

      if (firstDate == null && secondDate == null) {
        return second.compareTo(first);
      }

      if (firstDate == null) return 1;
      if (secondDate == null) return -1;

      return secondDate.compareTo(firstDate);
    });

    return values;
  }
}
