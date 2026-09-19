int compareBatchNames(dynamic first, dynamic second) {
  final firstName = (first['name'] as String? ?? '').trim();
  final secondName = (second['name'] as String? ?? '').trim();
  final firstMatch = RegExp(
    r'(\d+).*?(boys?|girls?)',
    caseSensitive: false,
  ).firstMatch(firstName);
  final secondMatch = RegExp(
    r'(\d+).*?(boys?|girls?)',
    caseSensitive: false,
  ).firstMatch(secondName);

  if (firstMatch == null && secondMatch == null) {
    return firstName.toLowerCase().compareTo(secondName.toLowerCase());
  }
  if (firstMatch == null) return 1;
  if (secondMatch == null) return -1;

  final gradeComparison = int.parse(
    firstMatch.group(1)!,
  ).compareTo(int.parse(secondMatch.group(1)!));
  if (gradeComparison != 0) return gradeComparison;

  final firstGender = firstMatch.group(2)!.toLowerCase();
  final secondGender = secondMatch.group(2)!.toLowerCase();
  final genderComparison = _genderRank(
    firstGender,
  ).compareTo(_genderRank(secondGender));
  if (genderComparison != 0) return genderComparison;

  return firstName.toLowerCase().compareTo(secondName.toLowerCase());
}

int _genderRank(String gender) => gender.startsWith('boy') ? 0 : 1;

List<dynamic> sortBatches(List<dynamic> batches) {
  final sortedBatches = List<dynamic>.from(batches);
  sortedBatches.sort(compareBatchNames);
  return sortedBatches;
}

int compareStudentNames(dynamic first, dynamic second) {
  final firstName = (first['name'] as String? ?? '').trim().toLowerCase();
  final secondName = (second['name'] as String? ?? '').trim().toLowerCase();
  return firstName.compareTo(secondName);
}

List<dynamic> sortStudents(List<dynamic> students) {
  final sortedStudents = List<dynamic>.from(students);
  sortedStudents.sort(compareStudentNames);
  return sortedStudents;
}
