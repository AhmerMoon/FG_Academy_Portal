class FeeBatch {
  final String id;
  final String name;
  final int classLevel;

  const FeeBatch({
    required this.id,
    required this.name,
    required this.classLevel,
  });

  factory FeeBatch.fromJson(Map<String, dynamic> json) {
    return FeeBatch(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? 'Batch',
      classLevel: (json['class_level'] as num?)?.toInt() ?? 0,
    );
  }
}

class FeeStudentEntry {
  final String studentId;
  final String batchId;
  final String name;
  final double defaultFee;
  final List<String> subjects;

  final String? paymentId;
  final String paymentMonth;
  final String status;
  final double amountPaid;

  final String remarks;

  const FeeStudentEntry({
    required this.studentId,
    required this.batchId,
    required this.name,
    required this.defaultFee,
    required this.subjects,
    required this.paymentId,
    required this.paymentMonth,
    required this.status,
    required this.amountPaid,
    required this.remarks,
  });

  bool get isPaid => status == 'paid';

  factory FeeStudentEntry.fromRows({
    required Map<String, dynamic> student,
    required Map<String, dynamic>? payment,
    required String paymentMonth,
  }) {
    final rawSubjects = student['stream'];

    return FeeStudentEntry(
      studentId: student['id'].toString(),
      batchId: student['batch_id'].toString(),
      name: student['name']?.toString() ?? 'Student',
      defaultFee: (student['default_fee'] as num?)?.toDouble() ?? 0,
      subjects: rawSubjects is List
          ? rawSubjects.map((item) => item.toString()).toList()
          : const [],
      paymentId: payment?['id']?.toString(),
      paymentMonth: payment?['payment_month']?.toString() ?? paymentMonth,
      status: payment?['status']?.toString() ?? 'unpaid',
      amountPaid: (payment?['amount_paid'] as num?)?.toDouble() ?? 0,
      remarks: student['fee_remarks']?.toString() ?? '',
    );
  }

  FeeStudentEntry copyWith({
    String? paymentId,
    String? status,
    double? amountPaid,
    String? paymentMonth,
    String? remarks,
  }) {
    return FeeStudentEntry(
      studentId: studentId,
      batchId: batchId,
      name: name,
      defaultFee: defaultFee,
      subjects: subjects,
      paymentId: paymentId ?? this.paymentId,
      paymentMonth: paymentMonth ?? this.paymentMonth,
      status: status ?? this.status,
      amountPaid: amountPaid ?? this.amountPaid,
      remarks: remarks ?? this.remarks,
    );
  }
}

class FeeSummaryRow {
  final String paymentMonth;
  final DateTime? monthStart;
  final String section;
  final String groupName;
  final String itemName;
  final double amount;
  final int paidStudents;
  final int unpaidStudents;
  final int sortOrder;

  const FeeSummaryRow({
    required this.paymentMonth,
    required this.monthStart,
    required this.section,
    required this.groupName,
    required this.itemName,
    required this.amount,
    required this.paidStudents,
    required this.unpaidStudents,
    required this.sortOrder,
  });

  factory FeeSummaryRow.fromJson(Map<String, dynamic> json) {
    return FeeSummaryRow(
      paymentMonth: json['payment_month']?.toString() ?? '',
      monthStart: json['month_start'] == null
          ? null
          : DateTime.tryParse(json['month_start'].toString()),
      section: json['section']?.toString() ?? '',
      groupName: json['group_name']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      paidStudents: (json['paid_students'] as num?)?.toInt() ?? 0,
      unpaidStudents: (json['unpaid_students'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

String feeSubjectLabel(String code) {
  switch (code) {
    case 'Phy':
      return 'Physics';
    case 'Chem':
      return 'Chemistry';
    case 'Math':
      return 'Mathematics';
    case 'Eng':
      return 'English';
    case 'Comp':
      return 'Computer';
    case 'Bio':
      return 'Biology';
    default:
      return code;
  }
}
