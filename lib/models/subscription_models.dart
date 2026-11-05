import 'package:cloud_firestore/cloud_firestore.dart';

import 'block_utils.dart';

class House {
  const House({
    required this.id,
    required this.familyName,
    required this.houseNumber,
    required this.phoneNumber,
    required this.monthlyFee,
    required this.notes,
    this.block = '',
  });

  final String id;
  final String familyName;
  final String houseNumber;
  final String phoneNumber;
  final double monthlyFee;
  final String notes;
  final String block; // e.g. 'A', 'B', 'C'

  House copyWith({
    String? id,
    String? familyName,
    String? houseNumber,
    String? phoneNumber,
    double? monthlyFee,
    String? notes,
    String? block,
  }) {
    return House(
      id: id ?? this.id,
      familyName: familyName ?? this.familyName,
      houseNumber: houseNumber ?? this.houseNumber,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      monthlyFee: monthlyFee ?? this.monthlyFee,
      notes: notes ?? this.notes,
      block: normalizeBlockCode(block ?? this.block),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'familyName': familyName,
      'houseNumber': houseNumber,
      'phoneNumber': phoneNumber,
      'monthlyFee': monthlyFee,
      'notes': notes,
      'block': normalizeBlockCode(block),
    };
  }

  factory House.fromJson(Map<String, dynamic> json) {
    final rawFee = json['monthlyFee'];
    return House(
      id: '${json['id'] ?? ''}',
      familyName: '${json['familyName'] ?? ''}',
      houseNumber: '${json['houseNumber'] ?? ''}',
      phoneNumber: '${json['phoneNumber'] ?? ''}',
      monthlyFee: rawFee is num
          ? rawFee.toDouble()
          : double.tryParse('$rawFee') ?? 0,
      notes: '${json['notes'] ?? ''}',
      block: normalizeBlockCode('${json['block'] ?? ''}'),
    );
  }

  factory House.fromFirestore(Map<String, dynamic> data, String documentId) {
    final json = Map<String, dynamic>.from(data);
    json['id'] = documentId;
    return House.fromJson(json);
  }

  Map<String, dynamic> toFirestore() {
    final json = toJson();
    json.remove('id'); // ID is stored as the document key
    return json;
  }
}

class PaymentEntry {
  const PaymentEntry({
    required this.id,
    required this.houseId,
    required this.monthKey,
    required this.amount,
    required this.paidOn,
    required this.note,
  });

  final String id;
  final String houseId;
  final String monthKey;
  final double amount;
  final DateTime paidOn;
  final String note;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'houseId': houseId,
      'monthKey': monthKey,
      'amount': amount,
      'paidOn': paidOn.toIso8601String(),
      'note': note,
    };
  }

  factory PaymentEntry.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    return PaymentEntry(
      id: '${json['id'] ?? ''}',
      houseId: '${json['houseId'] ?? ''}',
      monthKey: '${json['monthKey'] ?? ''}',
      amount: rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse('$rawAmount') ?? 0,
      paidOn: DateTime.tryParse('${json['paidOn'] ?? ''}') ?? DateTime.now(),
      note: '${json['note'] ?? ''}',
    );
  }

  factory PaymentEntry.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    final rawAmount = data['amount'];

    DateTime paidOnDate;
    if (data['paidOn'] is Timestamp) {
      paidOnDate = (data['paidOn'] as Timestamp).toDate();
    } else {
      paidOnDate =
          DateTime.tryParse('${data['paidOn'] ?? ''}') ?? DateTime.now();
    }

    String monthKeyStr = '';
    if (data['monthKey'] is Timestamp) {
      final date = (data['monthKey'] as Timestamp).toDate();
      monthKeyStr = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    } else {
      monthKeyStr = '${data['monthKey'] ?? ''}';
    }

    return PaymentEntry(
      id: documentId,
      houseId: '${data['houseId'] ?? ''}',
      monthKey: monthKeyStr,
      amount: rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse('$rawAmount') ?? 0,
      paidOn: paidOnDate,
      note: '${data['note'] ?? ''}',
    );
  }

  Map<String, dynamic> toFirestore() {
    DateTime? monthKeyDate;
    try {
      final parts = monthKey.split('-');
      if (parts.length >= 2) {
        monthKeyDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
      }
    } catch (_) {}

    return <String, dynamic>{
      'houseId': houseId,
      'monthKey': monthKeyDate != null
          ? Timestamp.fromDate(monthKeyDate)
          : monthKey,
      'amount': amount,
      'paidOn': Timestamp.fromDate(paidOn),
      'note': note,
    };
  }
}

enum PaymentStatus { unpaid, partial, paid }

extension PaymentStatusLabel on PaymentStatus {
  String get label {
    switch (this) {
      case PaymentStatus.unpaid:
        return 'Unpaid';
      case PaymentStatus.partial:
        return 'Partial';
      case PaymentStatus.paid:
        return 'Paid';
    }
  }
}

class HouseMonthStatus {
  const HouseMonthStatus({
    required this.status,
    required this.amountPaid,
    required this.balance,
  });

  final PaymentStatus status;
  final double amountPaid;
  final double balance;

  double progressFor(double monthlyFee) {
    if (monthlyFee <= 0) {
      return 0;
    }
    return (amountPaid / monthlyFee).clamp(0, 1).toDouble();
  }
}

class MonthSummary {
  const MonthSummary({
    required this.totalHouses,
    required this.paidHouses,
    required this.partialHouses,
    required this.unpaidHouses,
    required this.totalExpected,
    required this.totalCollected,
  });

  final int totalHouses;
  final int paidHouses;
  final int partialHouses;
  final int unpaidHouses;
  final double totalExpected;
  final double totalCollected;

  double get totalDue {
    final due = totalExpected - totalCollected;
    return due > 0 ? due : 0;
  }

  double get collectionProgress {
    if (totalExpected <= 0) {
      return 0;
    }
    return (totalCollected / totalExpected).clamp(0, 1).toDouble();
  }
}

const List<String> _monthNames = <String>[
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

const List<String> _monthShortNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String monthKeyFromDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  return '${date.year}-$month';
}

String formatMonthKey(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) {
    return monthKey;
  }

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) {
    return monthKey;
  }

  return '${_monthNames[month - 1]} $year';
}

String formatShortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  return '$day ${_monthShortNames[date.month - 1]} ${date.year}';
}

String formatCurrency(double amount) {
  final hasDecimals = amount != amount.roundToDouble();
  return 'Rs ${amount.toStringAsFixed(hasDecimals ? 2 : 0)}';
}

List<String> buildRecentMonthKeys({
  DateTime? anchor,
  int futureCount = 6,
  int pastCount = 18,
}) {
  final reference = anchor ?? DateTime.now();
  final list = <String>[];

  for (var i = futureCount; i > 0; i--) {
    list.add(
      monthKeyFromDate(DateTime(reference.year, reference.month + i, 1)),
    );
  }

  for (var i = 0; i < pastCount; i++) {
    list.add(
      monthKeyFromDate(DateTime(reference.year, reference.month - i, 1)),
    );
  }

  return list;
}
