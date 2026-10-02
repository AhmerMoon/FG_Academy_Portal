class FeeAuditClassStudentRow {
  final String paymentMonth;
  final String classCode;
  final String batchName;
  final int classLevel;
  final String levelGroup;

  final String subjectGroup;
  final int groupOrder;
  final int groupSrNo;

  final String studentName;
  final String status;

  final double defaultFee;
  final double amountPaid;

  final double teacherShare;
  final double nts;
  final double building;
  final double admin;
  final double organizer;
  final double ecc;

  final double math;
  final double physics;
  final double computer;
  final double chemistry;
  final double english;
  final double biology;

  const FeeAuditClassStudentRow({
    required this.paymentMonth,
    required this.classCode,
    required this.batchName,
    required this.classLevel,
    required this.levelGroup,
    required this.subjectGroup,
    required this.groupOrder,
    required this.groupSrNo,
    required this.studentName,
    required this.status,
    required this.defaultFee,
    required this.amountPaid,
    required this.teacherShare,
    required this.nts,
    required this.building,
    required this.admin,
    required this.organizer,
    required this.ecc,
    required this.math,
    required this.physics,
    required this.computer,
    required this.chemistry,
    required this.english,
    required this.biology,
  });

  factory FeeAuditClassStudentRow.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return FeeAuditClassStudentRow(
      paymentMonth: json['payment_month']?.toString() ?? '',
      classCode: json['class_code']?.toString() ?? '',
      batchName: json['batch_name']?.toString() ?? '',
      classLevel: (json['class_level'] as num?)?.toInt() ?? 0,
      levelGroup: json['level_group']?.toString() ?? '',
      subjectGroup: json['subject_group']?.toString() ?? 'Other',
      groupOrder: (json['group_order'] as num?)?.toInt() ?? 99,
      groupSrNo: (json['group_sr_no'] as num?)?.toInt() ?? 0,
      studentName: json['student_name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unpaid',
      defaultFee: number('default_fee'),
      amountPaid: number('amount_paid'),
      teacherShare: number('teacher_share_total'),
      nts: number('nts_fund'),
      building: number('building_fund'),
      admin: number('admin_fund'),
      organizer: number('organizer_fund'),
      ecc: number('ecc_fund'),
      math: number('math_share'),
      physics: number('physics_share'),
      computer: number('computer_share'),
      chemistry: number('chemistry_share'),
      english: number('english_share'),
      biology: number('biology_share'),
    );
  }
}

class FeeAuditClassTotal {
  final String paymentMonth;
  final String classCode;
  final String batchName;
  final int classLevel;
  final String levelGroup;

  final int totalStudents;
  final int paidStudents;
  final int unpaidStudents;

  final double collection;
  final double teacherShare;
  final double nts;
  final double building;
  final double admin;
  final double organizer;
  final double ecc;
  final double totalDistributed;

  final double math;
  final double physics;
  final double computer;
  final double chemistry;
  final double english;
  final double biology;

  const FeeAuditClassTotal({
    required this.paymentMonth,
    required this.classCode,
    required this.batchName,
    required this.classLevel,
    required this.levelGroup,
    required this.totalStudents,
    required this.paidStudents,
    required this.unpaidStudents,
    required this.collection,
    required this.teacherShare,
    required this.nts,
    required this.building,
    required this.admin,
    required this.organizer,
    required this.ecc,
    required this.totalDistributed,
    required this.math,
    required this.physics,
    required this.computer,
    required this.chemistry,
    required this.english,
    required this.biology,
  });

  factory FeeAuditClassTotal.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return FeeAuditClassTotal(
      paymentMonth: json['payment_month']?.toString() ?? '',
      classCode: json['class_code']?.toString() ?? '',
      batchName: json['batch_name']?.toString() ?? '',
      classLevel: (json['class_level'] as num?)?.toInt() ?? 0,
      levelGroup: json['level_group']?.toString() ?? '',
      totalStudents: (json['total_students'] as num?)?.toInt() ?? 0,
      paidStudents: (json['paid_students'] as num?)?.toInt() ?? 0,
      unpaidStudents: (json['unpaid_students'] as num?)?.toInt() ?? 0,
      collection: number('total_collection'),
      teacherShare: number('teacher_share_total'),
      nts: number('nts_fund'),
      building: number('building_fund'),
      admin: number('admin_fund'),
      organizer: number('organizer_fund'),
      ecc: number('ecc_fund'),
      totalDistributed: number('total_distributed'),
      math: number('math_share'),
      physics: number('physics_share'),
      computer: number('computer_share'),
      chemistry: number('chemistry_share'),
      english: number('english_share'),
      biology: number('biology_share'),
    );
  }

  double subjectAmount(String subject) {
    switch (subject) {
      case 'Math':
        return math;
      case 'Phy':
        return physics;
      case 'Comp':
        return computer;
      case 'Chem':
        return chemistry;
      case 'Eng':
        return english;
      case 'Bio':
        return biology;
      default:
        return 0;
    }
  }
}

class FeeAuditSubjectRow {
  final String subjectCode;
  final String teacherName;
  final int displayOrder;
  final Map<String, double> classAmounts;
  final double totalAmount;

  const FeeAuditSubjectRow({
    required this.subjectCode,
    required this.teacherName,
    required this.displayOrder,
    required this.classAmounts,
    required this.totalAmount,
  });

  factory FeeAuditSubjectRow.fromSsc(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return FeeAuditSubjectRow(
      subjectCode: json['subject_code']?.toString() ?? '',
      teacherName: json['teacher_name']?.toString() ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 99,
      classAmounts: {
        '9B': number('amount_9b'),
        '9G': number('amount_9g'),
        '10B': number('amount_10b'),
        '10G': number('amount_10g'),
      },
      totalAmount: number('total_amount'),
    );
  }

  factory FeeAuditSubjectRow.fromHssc(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return FeeAuditSubjectRow(
      subjectCode: json['subject_code']?.toString() ?? '',
      teacherName: json['teacher_name']?.toString() ?? '',
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 99,
      classAmounts: {
        'XIB': number('amount_xib'),
        'XIG': number('amount_xig'),
        'XIIB': number('amount_xiib'),
        'XIIG': number('amount_xiig'),
      },
      totalAmount: number('total_amount'),
    );
  }
}

class FeeAuditFinalRow {
  final String groupName;

  final int paidStudents;
  final int unpaidStudents;

  final double collection;
  final double teacher;
  final double nts;
  final double building;
  final double admin;
  final double organizer;
  final double ecc;
  final double total;

  final int displayOrder;

  const FeeAuditFinalRow({
    required this.groupName,
    required this.paidStudents,
    required this.unpaidStudents,
    required this.collection,
    required this.teacher,
    required this.nts,
    required this.building,
    required this.admin,
    required this.organizer,
    required this.ecc,
    required this.total,
    required this.displayOrder,
  });

  factory FeeAuditFinalRow.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return FeeAuditFinalRow(
      groupName: json['group_name']?.toString() ?? '',
      paidStudents: (json['paid_students'] as num?)?.toInt() ?? 0,
      unpaidStudents: (json['unpaid_students'] as num?)?.toInt() ?? 0,
      collection: number('total_collection'),
      teacher: number('teacher_share_total'),
      nts: number('nts_fund'),
      building: number('building_fund'),
      admin: number('admin_fund'),
      organizer: number('organizer_fund'),
      ecc: number('ecc_fund'),
      total: number('total_distributed'),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 99,
    );
  }
}

class FeeAuditStaffRow {
  final int displayOrder;
  final String name;
  final String designation;
  final String sourceType;

  final double? sharePayment;
  final double? ntsPayment;
  final double totalPayment;

  final String? remarks;
  final bool isTotal;

  const FeeAuditStaffRow({
    required this.displayOrder,
    required this.name,
    required this.designation,
    required this.sourceType,
    required this.sharePayment,
    required this.ntsPayment,
    required this.totalPayment,
    required this.remarks,
    required this.isTotal,
  });

  factory FeeAuditStaffRow.fromJson(Map<String, dynamic> json) {
    double? nullableNumber(String key) {
      final value = json[key];

      if (value == null) return null;

      return (value as num).toDouble();
    }

    return FeeAuditStaffRow(
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 99,
      name: json['staff_name']?.toString() ?? '',
      designation: json['designation']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? '',
      sharePayment: nullableNumber('share_payment'),
      ntsPayment: nullableNumber('nts_payment'),
      totalPayment: (json['total_payment'] as num?)?.toDouble() ?? 0,
      remarks: json['remarks']?.toString(),
      isTotal: json['is_total'] == true,
    );
  }
}

class FeeAuditMeta {
  final String paymentMonth;
  final String reportTitle;

  final double previousEccBalance;
  final double currentEccCollection;
  final double totalEccBalance;
  final double expenses;
  final double closingEccBalance;

  final String expensesLabel;
  final String closingBalanceLabel;
  final String sopRemark;
  final String approvalNote;

  const FeeAuditMeta({
    required this.paymentMonth,
    required this.reportTitle,
    required this.previousEccBalance,
    required this.currentEccCollection,
    required this.totalEccBalance,
    required this.expenses,
    required this.closingEccBalance,
    required this.expensesLabel,
    required this.closingBalanceLabel,
    required this.sopRemark,
    required this.approvalNote,
  });

  factory FeeAuditMeta.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return FeeAuditMeta(
      paymentMonth: json['payment_month']?.toString() ?? '',
      reportTitle: json['report_title']?.toString() ?? '',
      previousEccBalance: number('previous_ecc_balance'),
      currentEccCollection: number('current_ecc_collection'),
      totalEccBalance: number('total_ecc_balance'),
      expenses: number('expenses'),
      closingEccBalance: number('closing_ecc_balance'),
      expensesLabel: json['expenses_label']?.toString() ?? 'Expenses',
      closingBalanceLabel:
          json['closing_balance_label']?.toString() ?? 'Closing ECC Balance',
      sopRemark: json['sop_remark']?.toString() ?? '',
      approvalNote: json['approval_note']?.toString() ?? '',
    );
  }
}

class FeeAuditReportBundle {
  final String paymentMonth;

  final List<FeeAuditClassStudentRow> students;
  final List<FeeAuditClassTotal> classTotals;

  final List<FeeAuditSubjectRow> sscSubjects;
  final List<FeeAuditSubjectRow> hsscSubjects;

  final List<FeeAuditFinalRow> finalSummary;
  final List<FeeAuditStaffRow> staff;

  final FeeAuditMeta meta;

  const FeeAuditReportBundle({
    required this.paymentMonth,
    required this.students,
    required this.classTotals,
    required this.sscSubjects,
    required this.hsscSubjects,
    required this.finalSummary,
    required this.staff,
    required this.meta,
  });

  static const List<String> classOrder = [
    '9B',
    '9G',
    '10B',
    '10G',
    'XIB',
    'XIG',
    'XIIB',
    'XIIG',
  ];

  List<String> get availableClassCodes {
    final found = classTotals.map((item) => item.classCode).toSet();

    return classOrder.where(found.contains).toList();
  }

  List<FeeAuditClassStudentRow> studentsForClass(String code) {
    final values = students.where((item) => item.classCode == code).toList();

    values.sort((a, b) {
      final groupCompare = a.groupOrder.compareTo(b.groupOrder);

      if (groupCompare != 0) {
        return groupCompare;
      }

      return a.groupSrNo.compareTo(b.groupSrNo);
    });

    return values;
  }

  FeeAuditClassTotal? totalForClass(String code) {
    for (final item in classTotals) {
      if (item.classCode == code) {
        return item;
      }
    }

    return null;
  }

  FeeAuditFinalRow? summaryFor(String group) {
    for (final item in finalSummary) {
      if (item.groupName == group) {
        return item;
      }
    }

    return null;
  }
}
