import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


import 'models/auth_models.dart';
import 'models/block_utils.dart';
import 'models/subscription_models.dart';
import 'services/firebase_store.dart';

const List<String> kBlockOptions = <String>[
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
];

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.currentUser,
    required this.onLogout,
  });

  final AuthUser currentUser;
  final Future<void> Function() onLogout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseStore _store = FirebaseStore();
  final TextEditingController _searchController = TextEditingController();
  late final List<String> _monthKeys;

  List<House> _houses = <House>[];
  List<PaymentEntry> _payments = <PaymentEntry>[];
  List<StaffUser> _staffList = <StaffUser>[];
  late String _selectedMonthKey;
  late DateTimeRange _reportRange;
  late DateTimeRange _historyRange;
  bool _isLoading = true;
  bool _isDesktop = false;
  int _selectedIndex = 0;
  PaymentStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _monthKeys = buildRecentMonthKeys(futureCount: 12, pastCount: 24);
    _selectedMonthKey = monthKeyFromDate(DateTime.now());
    _reportRange = _currentMonthRange();
    _historyRange = _currentMonthRange();
    _searchController.addListener(() {
      setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final houses = await _store.getHouses();
      final payments = await _store.getPayments();
      List<StaffUser> staff = <StaffUser>[];
      if (widget.currentUser.isAdmin) {
        staff = await _store.getStaffList();
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _houses = _sortHouses(houses);
        _payments = _sortPayments(payments);
        _staffList = staff;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
      _showMessage('Could not load saved data.');
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'You will need the admin username and password to open the app again.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await widget.onLogout();
  }

  List<House> _sortHouses(List<House> houses) {
    final sorted = List<House>.from(houses);
    sorted.sort((House a, House b) {
      final aKey = a.houseNumber.trim().isEmpty
          ? a.familyName.toLowerCase()
          : a.houseNumber.toLowerCase();
      final bKey = b.houseNumber.trim().isEmpty
          ? b.familyName.toLowerCase()
          : b.houseNumber.toLowerCase();
      final primary = aKey.compareTo(bKey);
      if (primary != 0) {
        return primary;
      }
      return a.familyName.toLowerCase().compareTo(b.familyName.toLowerCase());
    });
    return sorted;
  }

  List<PaymentEntry> _sortPayments(List<PaymentEntry> payments) {
    final sorted = List<PaymentEntry>.from(payments);
    sorted.sort((PaymentEntry a, PaymentEntry b) {
      final dateCompare = b.paidOn.compareTo(a.paidOn);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return b.monthKey.compareTo(a.monthKey);
    });
    return sorted;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> get _assignedBlocks {
    return normalizeBlockCodes(widget.currentUser.assignedBlocks);
  }

  List<String> get _availableBlocks {
    return kBlockOptions;
  }

  bool _canAccessHouse(House house) {
    if (widget.currentUser.isAdmin) {
      return true;
    }

    final assignedBlocks = _assignedBlocks.toSet();
    if (assignedBlocks.isEmpty) {
      return false;
    }

    return assignedBlocks.contains(normalizeBlockCode(house.block));
  }

  List<House> get _accessibleHouses {
    if (widget.currentUser.isAdmin) {
      return _houses;
    }

    return _houses.where(_canAccessHouse).toList();
  }

  Set<String> get _accessibleHouseIds {
    return _accessibleHouses.map((House house) => house.id).toSet();
  }

  List<PaymentEntry> get _accessiblePayments {
    if (widget.currentUser.isAdmin) {
      return _payments;
    }

    final allowedHouseIds = _accessibleHouseIds;
    return _payments
        .where(
          (PaymentEntry payment) => allowedHouseIds.contains(payment.houseId),
        )
        .toList();
  }

  String _blockLabel(String block) {
    final normalized = normalizeBlockCode(block);
    if (normalized.isEmpty) {
      return 'No block';
    }
    return 'Block $normalized';
  }

  List<House> get _filteredHouses {
    final query = _searchController.text.trim().toLowerCase();

    return _accessibleHouses.where((House house) {
      if (query.isNotEmpty) {
        final haystack = <String>[
          house.familyName,
          house.houseNumber,
          house.phoneNumber,
          house.block,
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) {
          return false;
        }
      }

      if (_statusFilter != null) {
        final status = _statusFor(house, _selectedMonthKey);
        if (status.status != _statusFilter) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  HouseMonthStatus _statusFor(House house, String monthKey) {
    final amountPaid = _payments
        .where(
          (PaymentEntry payment) =>
              payment.houseId == house.id && payment.monthKey == monthKey,
        )
        .fold<double>(
          0,
          (double sum, PaymentEntry payment) => sum + payment.amount,
        );

    final balance = house.monthlyFee - amountPaid;
    if (amountPaid <= 0) {
      return HouseMonthStatus(
        status: PaymentStatus.unpaid,
        amountPaid: 0,
        balance: house.monthlyFee,
      );
    }
    if (balance <= 0) {
      return HouseMonthStatus(
        status: PaymentStatus.paid,
        amountPaid: amountPaid,
        balance: 0,
      );
    }

    return HouseMonthStatus(
      status: PaymentStatus.partial,
      amountPaid: amountPaid,
      balance: balance,
    );
  }

  MonthSummary _summaryForMonth(String monthKey) {
    var paidHouses = 0;
    var partialHouses = 0;
    var unpaidHouses = 0;
    var totalExpected = 0.0;
    var totalCollected = 0.0;
    final houses = _accessibleHouses;

    for (final House house in houses) {
      final status = _statusFor(house, monthKey);
      totalExpected += house.monthlyFee;
      totalCollected += status.amountPaid;

      switch (status.status) {
        case PaymentStatus.unpaid:
          unpaidHouses++;
          break;
        case PaymentStatus.partial:
          partialHouses++;
          break;
        case PaymentStatus.paid:
          paidHouses++;
          break;
      }
    }

    return MonthSummary(
      totalHouses: houses.length,
      paidHouses: paidHouses,
      partialHouses: partialHouses,
      unpaidHouses: unpaidHouses,
      totalExpected: totalExpected,
      totalCollected: totalCollected,
    );
  }

  List<_BlockCollectionSummary> _blockSummariesForMonth(String monthKey) {
    final grouped = <String, _BlockCollectionSummary>{};

    for (final House house in _accessibleHouses) {
      final normalizedBlock = normalizeBlockCode(house.block);
      final blockKey = normalizedBlock.isEmpty ? 'UNASSIGNED' : normalizedBlock;
      final status = _statusFor(house, monthKey);
      final existing =
          grouped[blockKey] ??
          _BlockCollectionSummary(
            block: blockKey,
            totalHouses: 0,
            paidHouses: 0,
            totalExpected: 0,
            totalCollected: 0,
          );

      grouped[blockKey] = _BlockCollectionSummary(
        block: blockKey,
        totalHouses: existing.totalHouses + 1,
        paidHouses: existing.paidHouses +
            (status.status == PaymentStatus.paid ? 1 : 0),
        totalExpected: existing.totalExpected + house.monthlyFee,
        totalCollected: existing.totalCollected + status.amountPaid,
      );
    }

    final summaries = grouped.values.toList();
    summaries.sort((a, b) => a.block.compareTo(b.block));
    return summaries;
  }

  List<House> _housesForBlock(String block) {
    return _accessibleHouses.where((House house) {
      final normalizedHouseBlock = normalizeBlockCode(house.block);
      if (block == 'UNASSIGNED') {
        return normalizedHouseBlock.isEmpty;
      }
      return normalizedHouseBlock == block;
    }).toList();
  }

  List<PaymentEntry> _paymentsForBlockMonth(String block, String monthKey) {
    final houseIds = _housesForBlock(block).map((House house) => house.id).toSet();
    final entries = _accessiblePayments.where((PaymentEntry payment) {
      return houseIds.contains(payment.houseId) && payment.monthKey == monthKey;
    }).toList();
    entries.sort((PaymentEntry a, PaymentEntry b) {
      final dateCompare = b.paidOn.compareTo(a.paidOn);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return b.amount.compareTo(a.amount);
    });
    return entries;
  }

  Future<void> _openBlockDetailsPage(
    _BlockCollectionSummary summary,
    String monthKey,
  ) async {
    final entries = _paymentsForBlockMonth(summary.block, monthKey);
    final houses = _housesForBlock(summary.block);
    final bundles = houses.map((House house) => _HouseStatusBundle(
      house: house,
      status: _statusFor(house, monthKey),
    )).toList();
    final housesById = <String, House>{
      for (final House house in houses) house.id: house,
    };

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _BlockDetailsPage(
          summary: summary,
          monthKey: monthKey,
          bundles: bundles,
          entries: entries,
          housesById: housesById,
          onHouseTap: (House house) => _showHouseDetails(house),
        ),
      ),
    );
  }

  List<PaymentEntry> _paymentsForHouse(String houseId) {
    final entries = _accessiblePayments
        .where((PaymentEntry payment) => payment.houseId == houseId)
        .toList();
    entries.sort((PaymentEntry a, PaymentEntry b) {
      final monthCompare = b.monthKey.compareTo(a.monthKey);
      if (monthCompare != 0) {
        return monthCompare;
      }
      return b.paidOn.compareTo(a.paidOn);
    });
    return entries;
  }

  DateTimeRange _currentMonthRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  String _formatDateRange(DateTimeRange range) {
    return '${formatShortDate(range.start)} - ${formatShortDate(range.end)}';
  }

  String _fileDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${day}-${month}-${date.year}';
  }

  String _formatReceiptDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthStr = months[date.month - 1];
    final dayStr = date.day.toString().padLeft(2, '0');
    return '$dayStr-$monthStr-${date.year}';
  }

  House? _houseForId(String houseId) {
    for (final House house in _accessibleHouses) {
      if (house.id == houseId) {
        return house;
      }
    }
    return null;
  }

  List<PaymentEntry> _paymentsForRange(DateTimeRange range) {
    final start = _startOfDay(range.start);
    final end = _endOfDay(range.end);
    final entries = _accessiblePayments.where((PaymentEntry payment) {
      return !payment.paidOn.isBefore(start) && !payment.paidOn.isAfter(end);
    }).toList();
    entries.sort((PaymentEntry a, PaymentEntry b) {
      return b.paidOn.compareTo(a.paidOn);
    });
    return entries;
  }

  double _totalForPayments(List<PaymentEntry> entries) {
    return entries.fold<double>(
      0,
      (double sum, PaymentEntry entry) => sum + entry.amount,
    );
  }

  Future<void> _pickReportRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _reportRange,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      saveText: 'Apply',
    );

    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      _reportRange = picked;
    });
  }

  Future<void> _pickHistoryRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _historyRange,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      saveText: 'Apply',
    );

    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      _historyRange = picked;
    });
  }

  Future<Uint8List> _buildTransactionPdf({
    required DateTimeRange range,
    required List<PaymentEntry> entries,
  }) async {
    final pdf = pw.Document();
    final total = _totalForPayments(entries);
    final uniqueHouses = entries
        .map((PaymentEntry item) => item.houseId)
        .toSet();

    final tableRows = entries.map((PaymentEntry entry) {
      final house = _houseForId(entry.houseId);
      final familyName = house == null ? 'Unknown house' : house.familyName;
      final block = house == null ? '-' : (house.block.trim().isEmpty ? '-' : house.block.trim());
      final houseNumber = house == null ? '-' : (house.houseNumber.trim().isEmpty ? '-' : house.houseNumber.trim());

      return <String>[
        formatShortDate(entry.paidOn),
        block,
        houseNumber,
        familyName,
        formatMonthKey(entry.monthKey),
        formatCurrency(entry.amount),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return <pw.Widget>[
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF173E44),
                borderRadius: pw.BorderRadius.circular(18),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    'Payment Transaction Report',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Date range: ${_formatDateRange(range)}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              children: <pw.Widget>[
                pw.Expanded(
                  child: _pdfSummaryCard(
                    label: 'Transactions',
                    value: entries.length.toString(),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _pdfSummaryCard(
                    label: 'Houses',
                    value: uniqueHouses.length.toString(),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _pdfSummaryCard(
                    label: 'Total collected',
                    value: formatCurrency(total),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.TableHelper.fromTextArray(
              headers: const <String>[
                'Paid date',
                'Block',
                'House No.',
                'House Name',
                'Month',
                'Amount',
              ],
              data: tableRows,
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFECE7DD),
              ),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF102326),
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.black,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(
                color: PdfColor.fromInt(0xFFCFD4D5),
                width: 0.4,
              ),
              columnWidths: <int, pw.TableColumnWidth>{
                0: const pw.FixedColumnWidth(60),
                1: const pw.FixedColumnWidth(40),
                2: const pw.FixedColumnWidth(60),
                3: const pw.FlexColumnWidth(1.6),
                4: const pw.FlexColumnWidth(1.3),
                5: const pw.FixedColumnWidth(68),
              },
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfSummaryCard({required String label, required String value}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF6F3EC),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE0DAD0)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromInt(0xFF5E6C6E),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF102326),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTransactionPdf() async {
    final entries = _paymentsForRange(_reportRange);
    if (entries.isEmpty) {
      _showMessage('No payment transactions found in this date range.');
      return;
    }

    try {
      final bytes = await _buildTransactionPdf(
        range: _reportRange,
        entries: entries,
      );
      final filename =
          'Payment-Transactions-${_fileDate(_reportRange.start)}-to-${_fileDate(_reportRange.end)}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (_) {
      _showMessage('Could not generate the PDF report. Please try again.');
    }
  }


  Future<Uint8List> _buildPaymentReceiptPdf({
    required House house,
    required PaymentEntry entry,
  }) async {
    final pdf = pw.Document();
    
    final hash = entry.id.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase();
    final receiptNo = 'RCT-$hash';

    final blockLabel = house.block.trim().isEmpty ? '-' : house.block.trim();
    final houseNumberLabel = house.houseNumber.trim().isEmpty ? '-' : house.houseNumber.trim();
    final phoneLabel = house.phoneNumber.trim().isEmpty ? '-' : house.phoneNumber.trim();

    final primary = PdfColor.fromInt(0xFF0D47A1); // Deep Blue
    final secondary = PdfColor.fromInt(0xFF1976D2);
    final accent = PdfColor.fromInt(0xFFFFC107); // Amber
    final bgLight = PdfColor.fromInt(0xFFF3F4F6); // Gray-100
    final textDark = PdfColor.fromInt(0xFF1F2937); // Gray-800
    final textMuted = PdfColor.fromInt(0xFF6B7280); // Gray-500

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(0),
        build: (pw.Context context) {
          return pw.Container(
            color: PdfColors.white,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                // Header section
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(24),
                  decoration: pw.BoxDecoration(
                    color: primary,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'MURSHIDUL ANAM SANGAM',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: pw.BoxDecoration(
                              color: accent,
                              borderRadius: pw.BorderRadius.circular(12),
                            ),
                            child: pw.Text(
                              'RECEIPT',
                              style: pw.TextStyle(
                                color: primary,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ]
                      ),
                      pw.SizedBox(height: 16),
                      pw.Text(
                        'Receipt No: $receiptNo',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 11),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Date: ${_formatReceiptDate(DateTime.now())}',
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                
                // Content section
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(24),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Member Details
                        pw.Text(
                          'BILLED TO',
                          style: pw.TextStyle(
                            color: secondary,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(16),
                          decoration: pw.BoxDecoration(
                            color: bgLight,
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                house.familyName,
                                style: pw.TextStyle(
                                  color: textDark,
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 6),
                              pw.Row(
                                children: [
                                  pw.Text('Block / House: ', style: pw.TextStyle(color: textMuted, fontSize: 11)),
                                  pw.Text('$blockLabel / $houseNumberLabel', style: pw.TextStyle(color: textDark, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                                ]
                              ),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                children: [
                                  pw.Text('Phone: ', style: pw.TextStyle(color: textMuted, fontSize: 11)),
                                  pw.Text(phoneLabel, style: pw.TextStyle(color: textDark, fontSize: 11)),
                                ]
                              ),
                            ],
                          ),
                        ),
                        
                        pw.SizedBox(height: 24),
                        
                        // Payment Details
                        pw.Text(
                          'PAYMENT DETAILS',
                          style: pw.TextStyle(
                            color: secondary,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(16),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: bgLight, width: 2),
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Subscription Month', style: pw.TextStyle(color: textDark, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                                  pw.Text(formatMonthKey(entry.monthKey), style: pw.TextStyle(color: textDark, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                                ]
                              ),
                              pw.SizedBox(height: 8),
                              pw.Divider(color: bgLight),
                              pw.SizedBox(height: 8),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Amount Paid', style: pw.TextStyle(color: textDark, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                                  pw.Text('Rs. ${entry.amount.toInt()}', style: pw.TextStyle(color: primary, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                                ]
                              ),
                            ],
                          ),
                        ),
                        
                        pw.SizedBox(height: 32),
                        
                        // Footer
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('Collected By', style: pw.TextStyle(color: textMuted, fontSize: 10)),
                                pw.SizedBox(height: 4),
                                pw.Text(widget.currentUser.username, style: pw.TextStyle(color: textDark, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                              ]
                            ),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Container(
                                  width: 100,
                                  height: 1,
                                  color: textMuted,
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text('Signature', style: pw.TextStyle(color: textMuted, fontSize: 10)),
                              ]
                            ),
                          ]
                        ),
                        
                        pw.Spacer(),
                        
                        pw.Center(
                          child: pw.Text(
                            'Thank you for your contribution',
                            style: pw.TextStyle(
                              color: secondary,
                              fontSize: 11,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        ),
                      ]
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _sharePaymentReceipt(House house, PaymentEntry entry) async {
    try {
      final bytes = await _buildPaymentReceiptPdf(house: house, entry: entry);
      final hash = entry.id.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase();
      final filename = 'RCT-$hash.pdf';
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (_) {
      _showMessage('Could not share the receipt. Please try again.');
    }
  }

  List<_HouseStatusBundle> _bundlesForMonth(String monthKey) {
    final bundles = _accessibleHouses
        .map(
          (House house) => _HouseStatusBundle(
            house: house,
            status: _statusFor(house, monthKey),
          ),
        )
        .toList();

    bundles.sort((_HouseStatusBundle a, _HouseStatusBundle b) {
      final rankCompare = _statusRank(
        a.status.status,
      ).compareTo(_statusRank(b.status.status));
      if (rankCompare != 0) {
        return rankCompare;
      }
      final balanceCompare = b.status.balance.compareTo(a.status.balance);
      if (balanceCompare != 0) {
        return balanceCompare;
      }
      return a.house.familyName.toLowerCase().compareTo(
        b.house.familyName.toLowerCase(),
      );
    });
    return bundles;
  }

  List<StaffUser> _sortStaffList(List<StaffUser> staff) {
    final sorted = List<StaffUser>.from(staff);
    sorted.sort((StaffUser a, StaffUser b) {
      final nameCompare = a.fullName.toLowerCase().compareTo(
        b.fullName.toLowerCase(),
      );
      if (nameCompare != 0) {
        return nameCompare;
      }
      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });
    return sorted;
  }

  int _statusRank(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.unpaid:
        return 0;
      case PaymentStatus.partial:
        return 1;
      case PaymentStatus.paid:
        return 2;
    }
  }

  void _updateMonth(String value) {
    setState(() {
      _selectedMonthKey = value;
    });
  }

  Future<void> _openHouseForm({House? house}) async {
    final result = await showModalBottomSheet<House>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => HouseFormSheet(house: house),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      final updated = List<House>.from(_houses);
      final index = updated.indexWhere((House item) => item.id == result.id);
      if (index == -1) {
        updated.add(result);
      } else {
        updated[index] = result;
      }
      _houses = _sortHouses(updated);
    });

    try {
      await _store.saveHouse(result);
      _showMessage(house == null ? 'House added.' : 'House updated.');
    } catch (_) {
      _showMessage('Could not save data. Please try again.');
    }
  }

  Future<void> _openStaffForm({StaffUser? staff}) async {
    final result = await showModalBottomSheet<StaffUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) =>
          StaffFormSheet(staff: staff, availableBlocks: _availableBlocks),
    );

    if (!mounted || result == null) {
      return;
    }

    final duplicate = _staffList.any(
      (StaffUser item) =>
          item.username == result.username && item.username != staff?.username,
    );
    if (duplicate) {
      _showMessage('That username is already used by another staff account.');
      return;
    }

    setState(() {
      final updated = List<StaffUser>.from(_staffList)
        ..removeWhere((StaffUser item) => item.username == staff?.username)
        ..removeWhere((StaffUser item) => item.username == result.username)
        ..add(result);
      _staffList = _sortStaffList(updated);
    });

    try {
      await _store.saveStaff(result);
      if (staff != null && staff.username != result.username) {
        await _store.deleteStaff(staff.username);
      }
      _showMessage(
        staff == null ? 'Staff account created.' : 'Staff account updated.',
      );
    } catch (_) {
      await _loadData();
      _showMessage('Could not save staff right now. Please try again.');
    }
  }

  Future<void> _openPaymentForm(House house, {String? monthKey, PaymentEntry? payment}) async {
    final initialMonthKey = payment?.monthKey ?? monthKey ?? _selectedMonthKey;
    final defaultStatus = _statusFor(house, initialMonthKey);
    final defaultAmount = payment?.amount ?? (defaultStatus.balance > 0
        ? defaultStatus.balance
        : house.monthlyFee);

    final result = await showModalBottomSheet<List<PaymentDraft>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => PaymentFormSheet(
        house: house,
        monthKeys: _monthKeys,
        initialMonthKey: initialMonthKey,
        defaultAmount: defaultAmount,
        payment: payment,
      ),
    );

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    if (payment != null) {
      final draft = result.first;
      final updatedPayment = PaymentEntry(
        id: payment.id,
        houseId: house.id,
        monthKey: draft.monthKey,
        amount: draft.amount,
        paidOn: draft.paidOn,
        note: draft.note,
      );

      setState(() {
        final index = _payments.indexWhere((p) => p.id == payment.id);
        if (index != -1) {
          _payments[index] = updatedPayment;
          _payments = _sortPayments(_payments);
        }
      });

      try {
        await _store.savePayment(updatedPayment);
        
        final hash = updatedPayment.id.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase();
        final receiptNo = 'RCT-$hash';
        
        await _store.saveReceipt(<String, dynamic>{
          'receiptNo': receiptNo,
          'paymentId': updatedPayment.id,
          'date': _formatReceiptDate(DateTime.now()),
          'name': house.familyName,
          'blockHouseNo': '${house.block.trim()}/${house.houseNumber.trim()}',
          'phone': house.phoneNumber,
          'amountPaid': updatedPayment.amount,
          'paymentDate': _formatReceiptDate(updatedPayment.paidOn),
          'collectedBy': widget.currentUser.username,
          'monthKey': updatedPayment.monthKey,
        }, receiptNo);

        _showMessage('Payment updated.');
      } catch (_) {
        _showMessage('Could not update payment. Please try again.');
      }
      return;
    }

    final now = DateTime.now();
    final newPayments = result.asMap().entries.map((entry) {
      final draft = entry.value;
      return PaymentEntry(
        id: '${now.microsecondsSinceEpoch}_${entry.key}_${draft.monthKey}',
        houseId: house.id,
        monthKey: draft.monthKey,
        amount: draft.amount,
        paidOn: draft.paidOn,
        note: draft.note,
      );
    }).toList();

    setState(() {
      _payments = _sortPayments(<PaymentEntry>[...newPayments, ..._payments]);
    });

    try {
      final count = newPayments.length;
      for (final payment in newPayments) {
        await _store.savePayment(payment);
        
        final hash = payment.id.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase();
        final receiptNo = 'RCT-$hash';
        
        await _store.saveReceipt(<String, dynamic>{
          'receiptNo': receiptNo,
          'paymentId': payment.id,
          'date': _formatReceiptDate(DateTime.now()),
          'name': house.familyName,
          'blockHouseNo': '${house.block.trim()}/${house.houseNumber.trim()}',
          'phone': house.phoneNumber,
          'amountPaid': payment.amount,
          'paymentDate': _formatReceiptDate(payment.paidOn),
          'collectedBy': widget.currentUser.username,
          'monthKey': payment.monthKey,
        }, receiptNo);
      }
      _showMessage(
        count == 1
            ? 'Payment saved for ${house.familyName}.'
            : '$count months saved for ${house.familyName}.',
      );
    } catch (_) {
      _showMessage('Could not save data. Please try again.');
    }
  }

  Future<void> _deleteHouse(House house) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete house?'),
          content: Text(
            'This will remove ${house.familyName} and all payment history for that house.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    final paymentsToDelete = _payments
        .where((PaymentEntry item) => item.houseId == house.id)
        .toList();

    setState(() {
      _houses = _houses.where((House item) => item.id != house.id).toList();
      _payments = _payments
          .where((PaymentEntry item) => item.houseId != house.id)
          .toList();
    });

    try {
      await _store.deleteHouse(house.id);
      for (final p in paymentsToDelete) {
        await _store.deletePayment(p.id);
      }
      _showMessage('House deleted.');
    } catch (_) {
      _showMessage('Could not sync deletion. Please try again.');
    }
  }

  Future<void> _deleteStaff(StaffUser staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete staff?'),
          content: Text(
            'This will remove the staff account for ${staff.fullName}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _staffList = _staffList
          .where((StaffUser item) => item.username != staff.username)
          .toList();
    });

    try {
      await _store.deleteStaff(staff.username);
      _showMessage('Staff account deleted.');
    } catch (_) {
      await _loadData();
      _showMessage('Could not delete the staff account. Please try again.');
    }
  }

  Future<void> _deletePayment(PaymentEntry payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete payment?'),
          content: Text(
            'This will remove the payment of ${formatCurrency(payment.amount)} for ${formatMonthKey(payment.monthKey)}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _payments = _payments.where((p) => p.id != payment.id).toList();
    });

    try {
      await _store.deletePayment(payment.id);
      _showMessage('Payment deleted.');
    } catch (_) {
      _showMessage('Could not delete payment. Please try again.');
    }
  }

  Future<void> _showHouseDetails(House house) async {
    if (!_canAccessHouse(house)) {
      _showMessage('You do not have access to this house.');
      return;
    }

    final action = await Navigator.of(context).push<_HouseDetailsAction>(
      MaterialPageRoute<_HouseDetailsAction>(
        builder: (BuildContext context) => _HouseDetailsPage(
          house: house,
          selectedMonthKey: _selectedMonthKey,
          getStatus: () => _statusFor(house, _selectedMonthKey),
          getEntries: () => _paymentsForHouse(house.id),
          showAdminDetails: widget.currentUser.isAdmin,
          canViewPaymentHistory: true,
          canEdit: widget.currentUser.isAdmin,
          canCollect: true,
          canShareReceipt: true,
          onShareReceipt: (PaymentEntry entry) =>
              _sharePaymentReceipt(house, entry),
          onEditPayment: (PaymentEntry entry) =>
              _openPaymentForm(house, payment: entry),
          onDeletePayment: (PaymentEntry entry) => _deletePayment(entry),
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _HouseDetailsAction.edit:
        await _openHouseForm(house: house);
        break;
      case _HouseDetailsAction.collect:
        await _openPaymentForm(house, monthKey: _selectedMonthKey);
        break;
    }
  }

  int get _actualIndex => _selectedIndex;

  bool get _showsTopHeader {
    if (!widget.currentUser.isAdmin) {
      return true;
    }
    return _actualIndex != 1;
  }

  String? get _pageTitle {
    if (!widget.currentUser.isAdmin && _actualIndex == 1) {
      return null;
    }

    switch (_actualIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return null;
      case 2:
        return 'Reports';
      case 3:
        return 'History';
      case 4:
        return 'Staff Management';
      default:
        return 'Masjid Subscription';
    }
  }

  String? get _pageSubtitle {
    if (!widget.currentUser.isAdmin && _actualIndex == 0) {
      if (_assignedBlocks.length == 1) {
        return 'Overview for ${_blockLabel(_assignedBlocks.first).toLowerCase()} houses.';
      }
      if (_assignedBlocks.isEmpty) {
        return 'Overview for your assigned house collection area.';
      }
      return 'Overview for your assigned blocks.';
    }

    if (!widget.currentUser.isAdmin && _actualIndex == 1) {
      if (_assignedBlocks.length == 1) {
        return 'You can view only ${_blockLabel(_assignedBlocks.first).toLowerCase()} houses.';
      }
      if (_assignedBlocks.isEmpty) {
        return 'You can view only houses from your assigned block.';
      }
      return 'You can view only houses from your assigned blocks.';
    }

    switch (_actualIndex) {
      case 0:
        return 'A Monthly overview for the masjid committee.';
      case 1:
        return null;
      case 2:
        return 'See paid, partial, and pending houses in one clean report.';
      case 3:
        return 'View previous payments and filter by date range.';
      case 4:
        return 'Manage staff accounts and their assigned blocks.';
      default:
        return 'Track subscriptions with clarity.';
    }
  }

  IconData? get _pageIcon {
    if (!widget.currentUser.isAdmin && _actualIndex == 1) {
      return Icons.home_work_rounded;
    }

    switch (_actualIndex) {
      case 0:
        return Icons.space_dashboard_rounded;
      case 1:
        return null;
      case 2:
        return Icons.analytics_rounded;
      case 3:
        return Icons.history_rounded;
      case 4:
        return Icons.people_alt_rounded;
      default:
        return Icons.mosque_rounded;
    }
  }

  List<_HeaderBadgeData>? _headerBadges(MonthSummary summary) {
    if (!widget.currentUser.isAdmin && _actualIndex == 0) {
      return <_HeaderBadgeData>[
        _HeaderBadgeData(
          icon: Icons.calendar_month_rounded,
          label: formatMonthKey(_selectedMonthKey),
        ),
        _HeaderBadgeData(
          icon: Icons.apartment_rounded,
          label: _assignedBlocks.isEmpty
              ? 'No block assigned'
              : _assignedBlocks.map(_blockLabel).join(', '),
        ),
        _HeaderBadgeData(
          icon: Icons.home_work_rounded,
          label: '${summary.totalHouses} houses',
        ),
      ];
    }

    if (!widget.currentUser.isAdmin && _actualIndex == 1) {
      return <_HeaderBadgeData>[
        _HeaderBadgeData(
          icon: Icons.apartment_rounded,
          label: _assignedBlocks.isEmpty
              ? 'No block assigned'
              : _assignedBlocks.map(_blockLabel).join(', '),
        ),
        _HeaderBadgeData(
          icon: Icons.home_work_rounded,
          label: '${summary.totalHouses} houses',
        ),
      ];
    }

    switch (_actualIndex) {
      case 0:
        return <_HeaderBadgeData>[
          _HeaderBadgeData(
            icon: Icons.calendar_month_rounded,
            label: formatMonthKey(_selectedMonthKey),
          ),
          _HeaderBadgeData(
            icon: Icons.apartment_rounded,
            label: '${summary.totalHouses} houses',
          ),
          _HeaderBadgeData(
            icon: Icons.flag_rounded,
            label: '${formatCurrency(summary.totalDue)} due',
          ),
        ];
      case 1:
        return null;
      case 2:
        return <_HeaderBadgeData>[
          _HeaderBadgeData(
            icon: Icons.calendar_month_rounded,
            label: formatMonthKey(_selectedMonthKey),
          ),
          _HeaderBadgeData(
            icon: Icons.check_circle_outline_rounded,
            label: '${summary.paidHouses} paid',
          ),
          _HeaderBadgeData(
            icon: Icons.pending_actions_rounded,
            label: '${summary.unpaidHouses} pending',
          ),
        ];
      case 3:
        return <_HeaderBadgeData>[
          _HeaderBadgeData(
            icon: Icons.date_range_rounded,
            label: _formatDateRange(_historyRange),
          ),
        ];
      case 4:
        return <_HeaderBadgeData>[
          _HeaderBadgeData(
            icon: Icons.groups_rounded,
            label: '${_staffList.length} members',
          ),
        ];
      default:
        return const <_HeaderBadgeData>[];
    }
  }

  Widget _buildSelectedView(MonthSummary summary) {
    switch (_actualIndex) {
      case 0:
        return _DashboardView(
          key: const ValueKey<String>('dashboard'),
          monthKeys: _monthKeys,
          selectedMonthKey: _selectedMonthKey,
          onMonthChanged: _updateMonth,
          summary: summary,
          blockSummaries: widget.currentUser.isAdmin
              ? _blockSummariesForMonth(_selectedMonthKey)
              : const <_BlockCollectionSummary>[],
          onBlockSummaryTap: widget.currentUser.isAdmin
              ? (_BlockCollectionSummary summary) =>
                    _openBlockDetailsPage(summary, _selectedMonthKey)
              : null,
          dueBundles: _bundlesForMonth(_selectedMonthKey)
              .where(
                (_HouseStatusBundle bundle) =>
                    bundle.status.status != PaymentStatus.paid,
              )
              .take(6)
              .toList(),
          hasHouses: _accessibleHouses.isNotEmpty,
          canAddHouse: widget.currentUser.isAdmin,
          emptyStateTitle: widget.currentUser.isAdmin
              ? 'Create the masjid collection register'
              : _assignedBlocks.isEmpty
              ? 'No block assigned'
              : 'No houses in your block',
          emptyStateMessage: widget.currentUser.isAdmin
              ? 'Use this app to store all houses, monthly subscription amounts, paid houses, and pending dues on your phone.'
              : _assignedBlocks.isEmpty
              ? 'Ask an admin to assign a block to this staff account.'
              : 'There are no saved houses in your assigned block yet.',
          onAddHouse: () => _openHouseForm(),
          onCollectPayment: _openPaymentForm,
        );
      case 1:
        return KeyedSubtree(
          key: const ValueKey<String>('houses'),
          child: _buildHousesView(),
        );
      case 2:
        return KeyedSubtree(
          key: const ValueKey<String>('reports'),
          child: _buildReportsView(),
        );
      case 3:
        return KeyedSubtree(
          key: const ValueKey<String>('history'),
          child: _buildHistoryView(),
        );
      case 4:
        return KeyedSubtree(
          key: const ValueKey<String>('staff'),
          child: _buildStaffView(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  List<_NavItem> get _navItems {
    if (widget.currentUser.isAdmin) {
      return const <_NavItem>[
        _NavItem(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard_rounded,
          label: 'Dashboard',
        ),
        _NavItem(
          icon: Icons.home_work_outlined,
          selectedIcon: Icons.home_work_rounded,
          label: 'Houses',
        ),
        _NavItem(
          icon: Icons.assessment_outlined,
          selectedIcon: Icons.assessment_rounded,
          label: 'Reports',
        ),
        _NavItem(
          icon: Icons.history_outlined,
          selectedIcon: Icons.history_rounded,
          label: 'History',
        ),
        _NavItem(
          icon: Icons.people_alt_outlined,
          selectedIcon: Icons.people_alt_rounded,
          label: 'Staff',
        ),
      ];
    }
    return const <_NavItem>[
      _NavItem(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
      _NavItem(
        icon: Icons.home_work_outlined,
        selectedIcon: Icons.home_work_rounded,
        label: 'Houses',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summaryForMonth(_selectedMonthKey);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 720;
    _isDesktop = isDesktop;

    if (isDesktop) {
      return _buildDesktopLayout(summary);
    }
    return _buildMobileLayout(summary);
  }

  Widget _buildDesktopLayout(MonthSummary summary) {
    return Scaffold(
      body: Row(
        children: <Widget>[
          _DesktopSidebar(
            selectedIndex: _selectedIndex,
            navItems: _navItems,
            user: widget.currentUser,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            onRefresh: _loadData,
            onLogout: _confirmLogout,
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                const _BackdropDecor(),
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Desktop page header bar
                      _DesktopPageHeader(
                        title: _pageTitle ?? 'Murshidul Anam Sangam',
                        subtitle: _pageSubtitle,
                        icon: _pageIcon,
                        badges: _headerBadges(summary),
                        onRefresh: _loadData,
                        canAddHouse: _actualIndex == 1 && widget.currentUser.isAdmin,
                        onAddHouse: () => _openHouseForm(),
                      ),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : LayoutBuilder(
                                builder: (BuildContext ctx, BoxConstraints constraints) {
                                  // Center content horizontally with a max width, but fill all height
                                  final effectiveWidth = constraints.maxWidth.clamp(0.0, 1100.0);
                                  return Row(
                                    children: <Widget>[
                                      if (constraints.maxWidth > 1100)
                                        SizedBox(width: (constraints.maxWidth - 1100) / 2),
                                      Expanded(
                                        child: _DesktopContentConstraint(
                                          availableWidth: effectiveWidth,
                                          child: AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 320),
                                            switchInCurve: Curves.easeOutCubic,
                                            switchOutCurve: Curves.easeInCubic,
                                            transitionBuilder: (Widget child, Animation<double> animation) {
                                              final offsetAnimation = Tween<Offset>(
                                                begin: const Offset(0, 0.02),
                                                end: Offset.zero,
                                              ).animate(animation);
                                              return FadeTransition(
                                                opacity: animation,
                                                child: SlideTransition(
                                                  position: offsetAnimation,
                                                  child: child,
                                                ),
                                              );
                                            },
                                            child: _buildSelectedView(summary),
                                          ),
                                        ),
                                      ),
                                      if (constraints.maxWidth > 1100)
                                        SizedBox(width: (constraints.maxWidth - 1100) / 2),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(MonthSummary summary) {
    return Scaffold(
      extendBody: true,
      floatingActionButton: _actualIndex == 1 && widget.currentUser.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openHouseForm(),
              icon: const Icon(Icons.add_home_work_outlined),
              label: const Text('Add House'),
            )
          : null,
      body: Stack(
        children: <Widget>[
          const _BackdropDecor(),
          SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                if (_showsTopHeader && _actualIndex != 1) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                    child: _TopHeader(
                      title: _pageTitle,
                      subtitle: _pageSubtitle,
                      icon: _pageIcon,
                      badges: _headerBadges(summary),
                      user: widget.currentUser,
                      onRefresh: _loadData,
                      onLogout: _confirmLogout,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_showsTopHeader) const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                final offsetAnimation = Tween<Offset>(
                                  begin: const Offset(0, 0.02),
                                  end: Offset.zero,
                                ).animate(animation);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: offsetAnimation,
                                    child: child,
                                  ),
                                );
                              },
                          child: _buildSelectedView(summary),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _SleekPanel(
          padding: EdgeInsets.zero,
          borderRadius: 28,
          child: NavigationBar(
            labelTextStyle: WidgetStateProperty.all(const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            )),
            backgroundColor: Colors.transparent,
            elevation: 0,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: widget.currentUser.isAdmin
                ? const <NavigationDestination>[
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard_rounded),
                      label: 'Dashboard',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.home_work_outlined),
                      selectedIcon: Icon(Icons.home_work_rounded),
                      label: 'Houses',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.assessment_outlined),
                      selectedIcon: Icon(Icons.assessment_rounded),
                      label: 'Reports',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_outlined),
                      selectedIcon: Icon(Icons.history_rounded),
                      label: 'History',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_alt_outlined),
                      selectedIcon: Icon(Icons.people_alt_rounded),
                      label: 'Staff',
                    ),
                  ]
                : const <NavigationDestination>[
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard_rounded),
                      label: 'Dashboard',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.home_work_outlined),
                      selectedIcon: Icon(Icons.home_work_rounded),
                      label: 'Houses',
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryView() {
    final rangedPayments = _paymentsForRange(_historyRange);
    final total = _totalForPayments(rangedPayments);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _SleekPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionTitle(
                  title: 'Transaction History',
                  subtitle: 'View past payments filtered by date.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: InfoPill(
                        icon: Icons.date_range_rounded,
                        label: _formatDateRange(_historyRange),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickHistoryRange,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Change date'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'Total Collected',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        formatCurrency(total),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: rangedPayments.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: _EmptyStateCard(
                    title: 'No transactions',
                    message: 'No payments found in the selected date range.',
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(16, 2, 16,
                      _isDesktop ? 32 : 120),
                  itemCount: rangedPayments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final entry = rangedPayments[index];
                    final house = _houseForId(entry.houseId);
                    final houseLabel = house == null
                        ? 'Unknown house'
                        : house.houseNumber.trim().isEmpty
                        ? house.familyName
                        : '${house.familyName} • House ${house.houseNumber}';
                    return _TransactionPreviewRow(
                      title: houseLabel,
                      subtitle:
                          '${formatShortDate(entry.paidOn)} • ${formatMonthKey(entry.monthKey)}${entry.note.trim().isEmpty ? '' : ' • ${entry.note.trim()}'}',
                      amount: formatCurrency(entry.amount),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHousesView() {
    if (_houses.isEmpty && widget.currentUser.isAdmin) {
      return _EmptyStateView(
        title: 'Start with your first house',
        message:
            'Add houses under the masjid and set each family’s monthly subscription amount.',
        actionLabel: 'Add first house',
        onAction: () => _openHouseForm(),
      );
    }

    if (_houses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _EmptyStateCard(
            title: 'No houses yet',
            message: 'The admin has not added any houses yet.',
          ),
        ),
      );
    }

    if (!widget.currentUser.isAdmin && _assignedBlocks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _EmptyStateCard(
            title: 'No block assigned',
            message: 'Ask an admin to assign a block to this staff account.',
          ),
        ),
      );
    }

    if (!widget.currentUser.isAdmin && _accessibleHouses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _EmptyStateCard(
            title: 'No houses in your block',
            message: 'There are no saved houses in your assigned block yet.',
          ),
        ),
      );
    }

    final houses = _filteredHouses;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _SleekPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: widget.currentUser.isAdmin
                        ? 'Search family, house number, block, or phone'
                        : 'Search family, house number, or block',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest.withAlpha(80),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<PaymentStatus?>(
                            value: _statusFilter,
                            isDense: true,
                            isExpanded: true,
                            icon: const Icon(
                              Icons.filter_list_rounded,
                              size: 20,
                            ),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('All Houses'),
                              ),
                              DropdownMenuItem(
                                value: PaymentStatus.paid,
                                child: Text('Paid'),
                              ),
                              DropdownMenuItem(
                                value: PaymentStatus.partial,
                                child: Text('Partial'),
                              ),
                              DropdownMenuItem(
                                value: PaymentStatus.unpaid,
                                child: Text('Nonpaid'),
                              ),
                            ],
                            onChanged: (PaymentStatus? val) {
                              setState(() {
                                _statusFilter = val;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 176,
                      child: MonthDropdown(
                        monthKeys: _monthKeys,
                        selectedMonthKey: _selectedMonthKey,
                        onChanged: _updateMonth,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: houses.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: _EmptyStateCard(
                    title: 'No matching houses',
                    message: 'Try a different name, number, or phone search.',
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(20, 2, 16,
                      _isDesktop ? 32 : 150),
                  itemCount: houses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (BuildContext context, int index) {
                    final house = houses[index];
                    final status = _statusFor(house, _selectedMonthKey);

                    return _HouseCard(
                      house: house,
                      monthKey: _selectedMonthKey,
                      status: status,
                      blockLabel: _blockLabel(house.block),
                      showAdminDetails: widget.currentUser.isAdmin,
                      showAdminActions: widget.currentUser.isAdmin,
                      onTap: () => _showHouseDetails(house),
                      onMenuSelected: (String action) async {
                        if (action == 'view') {
                          await _showHouseDetails(house);
                        } else if (action == 'collect') {
                          await _openPaymentForm(house);
                        } else if (action == 'edit' &&
                            widget.currentUser.isAdmin) {
                          await _openHouseForm(house: house);
                        } else if (action == 'delete' &&
                            widget.currentUser.isAdmin) {
                          await _deleteHouse(house);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReportsView() {
    if (_accessibleHouses.isEmpty) {
      return _EmptyStateView(
        title: 'Reports will appear here',
        message:
            'Once you add houses, you can see who paid, who is pending, and the monthly collection total.',
        actionLabel: 'Add first house',
        onAction: () => _openHouseForm(),
      );
    }

    final bundles = _bundlesForMonth(_selectedMonthKey);
    final summary = _summaryForMonth(_selectedMonthKey);
    final rangedPayments = _paymentsForRange(_reportRange);
    final rangedTotal = _totalForPayments(rangedPayments);
    final uniqueRangeHouses = rangedPayments
        .map((PaymentEntry item) => item.houseId)
        .toSet()
        .length;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16,
          _isDesktop ? 32 : 120),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SleekPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _SectionTitle(
                        title: 'Monthly report',
                        subtitle:
                            'Check who paid and how much is still due this month.',
                      ),
                    ),
                    SizedBox(
                      width: 176,
                      child: MonthDropdown(
                        monthKeys: _monthKeys,
                        selectedMonthKey: _selectedMonthKey,
                        onChanged: _updateMonth,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    SummaryCountCard(
                      label: 'Paid',
                      value: summary.paidHouses.toString(),
                      color: const Color(0xFF2E7D32),
                      icon: Icons.check_circle_rounded,
                    ),
                    SummaryCountCard(
                      label: 'Partial',
                      value: summary.partialHouses.toString(),
                      color: const Color(0xFFB26A00),
                      icon: Icons.timelapse_rounded,
                    ),
                    SummaryCountCard(
                      label: 'Pending',
                      value: summary.unpaidHouses.toString(),
                      color: const Color(0xFFB42318),
                      icon: Icons.pending_actions_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primary.withAlpha(10),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    'Expected ${formatCurrency(summary.totalExpected)} • Collected ${formatCurrency(summary.totalCollected)} • Due ${formatCurrency(summary.totalDue)}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SleekPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionTitle(
                  title: 'Transaction PDF report',
                  subtitle:
                      'Choose a paid date range and export all payment transactions as PDF.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    InfoPill(
                      icon: Icons.date_range_rounded,
                      label: _formatDateRange(_reportRange),
                    ),
                    InfoPill(
                      icon: Icons.receipt_long_rounded,
                      label: '${rangedPayments.length} transactions',
                    ),
                    InfoPill(
                      icon: Icons.home_work_rounded,
                      label: '$uniqueRangeHouses houses',
                    ),
                    InfoPill(
                      icon: Icons.currency_rupee_rounded,
                      label: formatCurrency(rangedTotal),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickReportRange,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Select date range'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: rangedPayments.isEmpty
                            ? null
                            : _exportTransactionPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export PDF'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (rangedPayments.isEmpty)
                  const _EmptyStateCard(
                    title: 'No transactions in this range',
                    message:
                        'Choose another date range to create a PDF payment report.',
                  )
                else ...<Widget>[
                  Text(
                    'Preview',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...rangedPayments.take(6).map((PaymentEntry entry) {
                    final house = _houseForId(entry.houseId);
                    final houseLabel = house == null
                        ? 'Unknown house'
                        : house.houseNumber.trim().isEmpty
                        ? house.familyName
                        : '${house.familyName} • House ${house.houseNumber}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TransactionPreviewRow(
                        title: houseLabel,
                        subtitle:
                            '${formatShortDate(entry.paidOn)} • ${formatMonthKey(entry.monthKey)}${entry.note.trim().isEmpty ? '' : ' • ${entry.note.trim()}'}',
                        amount: formatCurrency(entry.amount),
                      ),
                    );
                  }),
                  if (rangedPayments.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${rangedPayments.length - 6} more transactions in PDF',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
         
         
        ],
      ),
    );
  }

  Widget _buildStaffView() {
    final blocks = _availableBlocks;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16,
          _isDesktop ? 32 : 120),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SleekPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionTitle(
                  title: 'Staff access',
                  subtitle:
                      'Create a staff login for one block and limit house access to that block only.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    InfoPill(
                      icon: Icons.groups_rounded,
                      label: '${_staffList.length} staff',
                    ),
                    InfoPill(
                      icon: Icons.apartment_rounded,
                      label: '${blocks.length} blocks',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openStaffForm(),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add staff account'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_staffList.isEmpty)
            _EmptyStateCard(
              title: 'No staff accounts yet',
              message: 'Create a staff login and assign one block here.',
              actionLabel: 'Create staff',
              onAction: () => _openStaffForm(),
            )
          else
            ..._staffList.map(
              (StaffUser staff) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SleekPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _MonogramAvatar(
                            label: staff.fullName,
                            color: Theme.of(context).colorScheme.primary,
                            size: 48,
                            borderRadius: 16,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  staff.fullName,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '@${staff.username}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (String action) async {
                              if (action == 'edit') {
                                await _openStaffForm(staff: staff);
                              } else if (action == 'delete') {
                                await _deleteStaff(staff);
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                const <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'edit',
                                    child: Text('Edit staff'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('Delete staff'),
                                  ),
                                ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: staff.blocks
                            .map(
                              (String block) => InfoPill(
                                icon: Icons.apartment_rounded,
                                label: _blockLabel(block),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    super.key,
    required this.monthKeys,
    required this.selectedMonthKey,
    required this.onMonthChanged,
    required this.summary,
    required this.blockSummaries,
    required this.onBlockSummaryTap,
    required this.dueBundles,
    required this.hasHouses,
    required this.canAddHouse,
    required this.emptyStateTitle,
    required this.emptyStateMessage,
    required this.onAddHouse,
    required this.onCollectPayment,
  });

  final List<String> monthKeys;
  final String selectedMonthKey;
  final ValueChanged<String> onMonthChanged;
  final MonthSummary summary;
  final List<_BlockCollectionSummary> blockSummaries;
  final ValueChanged<_BlockCollectionSummary>? onBlockSummaryTap;
  final List<_HouseStatusBundle> dueBundles;
  final bool hasHouses;
  final bool canAddHouse;
  final String emptyStateTitle;
  final String emptyStateMessage;
  final VoidCallback onAddHouse;
  final Future<void> Function(House house, {String? monthKey}) onCollectPayment;

  @override
  Widget build(BuildContext context) {
    if (!hasHouses) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _EmptyStateCard(
            title: emptyStateTitle,
            message: emptyStateMessage,
            actionLabel: canAddHouse ? 'Add first house' : null,
            onAction: canAddHouse ? onAddHouse : null,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    // Use actual content area width from desktop constraint, fallback to MediaQuery
    final desktopConstraint = _DesktopContentConstraint.maybeOf(context);
    final isDesktop = desktopConstraint != null;
    final width = desktopConstraint?.availableWidth ?? MediaQuery.sizeOf(context).width;
    final cardWidth = width > 600 ? (width - 44) / 2 : double.infinity;
    final bottomPad = isDesktop ? 32.0 : 120.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(
                colors: <Color>[
                  Color(0xFF112F33),
                  Color(0xFF1B5757),
                  Color(0xFFB27C4A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x24112F33),
                  blurRadius: 34,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Stack(
              children: <Widget>[
                Positioned(
                  top: -36,
                  right: -10,
                  child: Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(18),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -42,
                  left: -18,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(14),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Wrap(
                    //   spacing: 10,
                    //   runSpacing: 10,
                    //   children: <Widget>[
                    //     _HeroBadge(
                    //       icon: Icons.calendar_month_rounded,
                    //       label: formatMonthKey(selectedMonthKey),
                    //     ),
                    //     _HeroBadge(
                    //       icon: Icons.home_work_rounded,
                    //       label: '${summary.totalHouses} houses',
                    //     ),
                    //   ],
                    // ),
                    // const SizedBox(height: 20),
                    MonthDropdown(
                      monthKeys: monthKeys,
                      selectedMonthKey: selectedMonthKey,
                      onChanged: onMonthChanged,
                      inverse: true,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${summary.paidHouses} of ${summary.totalHouses} houses fully paid',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: summary.collectionProgress,
                        minHeight: 9,
                        backgroundColor: Colors.white.withAlpha(34),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              SizedBox(
                width: cardWidth,
                child: MetricCard(
                  title: 'Expected',
                  value: formatCurrency(summary.totalExpected),
                  note: '${summary.totalHouses} houses this month',
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: MetricCard(
                  title: 'Collected',
                  value: formatCurrency(summary.totalCollected),
                  note: 'Updated for ${formatMonthKey(selectedMonthKey)}',
                  icon: Icons.payments_outlined,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: MetricCard(
                  title: 'Pending',
                  value: summary.unpaidHouses.toString(),
                  note: '${summary.partialHouses} houses are partially paid',
                  icon: Icons.hourglass_bottom_rounded,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: MetricCard(
                  title: 'Still due',
                  value: formatCurrency(summary.totalDue),
                  note: 'Balance remaining this month',
                  icon: Icons.flag_outlined,
                ),
              ),
            ],
          ),
          if (blockSummaries.isNotEmpty) ...<Widget>[
            const SizedBox(height: 22),
            const _SectionTitle(
              title: 'Block collection',
              subtitle:
                  'Track expected, collected, and due amounts for each block this month.',
            ),
            const SizedBox(height: 12),
            ...blockSummaries.map(
              (_BlockCollectionSummary summary) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BlockCollectionCard(
                  summary: summary,
                  onTap: onBlockSummaryTap == null
                      ? null
                      : () => onBlockSummaryTap!(summary),
                ),
              ),
            ),
          ],
         
        ],
      ),
    );
  }
}

class _HouseDetailsPage extends StatefulWidget {
  const _HouseDetailsPage({
    required this.house,
    required this.selectedMonthKey,
    required this.getStatus,
    required this.getEntries,
    required this.showAdminDetails,
    required this.canViewPaymentHistory,
    required this.canEdit,
    required this.canCollect,
    required this.canShareReceipt,
    required this.onShareReceipt,
    required this.onEditPayment,
    required this.onDeletePayment,
  });

  final House house;
  final String selectedMonthKey;
  final HouseMonthStatus Function() getStatus;
  final List<PaymentEntry> Function() getEntries;
  final bool showAdminDetails;
  final bool canViewPaymentHistory;
  final bool canEdit;
  final bool canCollect;
  final bool canShareReceipt;
  final Future<void> Function(PaymentEntry entry) onShareReceipt;
  final Future<void> Function(PaymentEntry entry) onEditPayment;
  final Future<void> Function(PaymentEntry entry) onDeletePayment;

  @override
  State<_HouseDetailsPage> createState() => _HouseDetailsPageState();
}

class _HouseDetailsPageState extends State<_HouseDetailsPage> {
  late HouseMonthStatus _status;
  late List<PaymentEntry> _entries;
  String _selectedYearFilter = 'All';

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    _status = widget.getStatus();
    _entries = widget.getEntries();
  }

  Future<void> _handleEdit(PaymentEntry entry) async {
    await widget.onEditPayment(entry);
    if (mounted) {
      setState(() {
        _refreshData();
      });
    }
  }

  Future<void> _handleDelete(PaymentEntry entry) async {
    await widget.onDeletePayment(entry);
    if (mounted) {
      setState(() {
        _refreshData();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _status;
    final entries = _entries;
    final house = widget.house;

    // Extract all unique years from entries
    final List<String> availableYears = ['All'];
    for (final entry in entries) {
      final year = entry.monthKey.split('-')[0];
      if (year.length == 4 && !availableYears.contains(year)) {
        availableYears.add(year);
      }
    }
    // Sort years descending (except 'All')
    if (availableYears.length > 2) {
      final sub = availableYears.sublist(1);
      sub.sort((a, b) => b.compareTo(a));
      availableYears.replaceRange(1, availableYears.length, sub);
    }

    if (!availableYears.contains(_selectedYearFilter)) {
      _selectedYearFilter = 'All';
    }

    final filteredEntries = _selectedYearFilter == 'All'
        ? entries
        : entries.where((e) => e.monthKey.startsWith(_selectedYearFilter)).toList();
    final selectedMonthKey = widget.selectedMonthKey;
    final showAdminDetails = widget.showAdminDetails;
    final canEdit = widget.canEdit;
    final canCollect = widget.canCollect;
    final canViewPaymentHistory = widget.canViewPaymentHistory;
    final canShareReceipt = widget.canShareReceipt;
    final statusColor = paymentStatusColor(status.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          house.houseNumber.trim().isEmpty
              ? 'House details'
              : 'House ${house.houseNumber}',
        ),
      ),
      body: Stack(
        children: <Widget>[
          const _BackdropDecor(),
          SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _HeroSheetCard(
                    eyebrow: house.houseNumber.trim().isEmpty
                        ? 'House profile'
                        : 'House ${house.houseNumber}',
                    title: house.familyName,
                    subtitle:
                        'Monthly plan ${formatCurrency(house.monthlyFee)}',
                    icon: Icons.home_work_rounded,
                    accentColors: const <Color>[
                      Color(0xFF112F33),
                      Color(0xFF2A6A64),
                      Color(0xFFB17C4B),
                    ],
                    trailing: StatusChip(status: status.status, soft: true),
                  ),
                  const SizedBox(height: 16),
                  _SleekPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Status for ${formatMonthKey(selectedMonthKey)}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              formatCurrency(
                                status.balance > 0
                                    ? status.balance
                                    : status.amountPaid,
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Collected ${formatCurrency(status.amountPaid)} of ${formatCurrency(house.monthlyFee)}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: status.progressFor(house.monthlyFee),
                            minHeight: 9,
                            backgroundColor: statusColor.withAlpha(28),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          status.balance > 0
                              ? 'Remaining due: ${formatCurrency(status.balance)}'
                              : 'This month is fully paid.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            InfoPill(
                              icon: Icons.currency_rupee_rounded,
                              label:
                                  '${formatCurrency(house.monthlyFee)} / month',
                            ),
                            if (house.block.trim().isNotEmpty)
                              InfoPill(
                                icon: Icons.apartment_rounded,
                                label: 'Block ${house.block}',
                              ),
                            if (showAdminDetails &&
                                house.phoneNumber.trim().isNotEmpty)
                              InfoPill(
                                icon: Icons.call_outlined,
                                label: house.phoneNumber,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showAdminDetails &&
                      house.notes.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    _SleekPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Notes',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            house.notes,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (canEdit || canCollect) ...<Widget>[
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        if (canEdit)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(_HouseDetailsAction.edit),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit'),
                            ),
                          ),
                        if (canEdit && canCollect) const SizedBox(width: 12),
                        if (canCollect)
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(_HouseDetailsAction.collect),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Collect'),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (canViewPaymentHistory) ...<Widget>[
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionTitle(
                          title: 'Payment history',
                          subtitle: 'Latest collections linked to this house.',
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            formatCurrency(
                              (filteredEntries.fold(
                                0.0,
                                (sum, entry) => sum + entry.amount,
                              ))
                                  .round()
                                  .toDouble(),
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (availableYears.length > 2) ...<Widget>[
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: availableYears.map((String year) {
                            final isSelected = _selectedYearFilter == year;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: _YearFilterChip(
                                label: year,
                                isSelected: isSelected,
                                onTap: () {
                                  setState(() {
                                    _selectedYearFilter = year;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (filteredEntries.isEmpty)
                      const _EmptyStateCard(
                        title: 'No payments found',
                        message:
                            'No payments recorded matching the selected filter.',
                      )
                    else
                      ...filteredEntries.map(
                        (PaymentEntry entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SleekPanel(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withAlpha(16),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Icons.receipt_long_rounded,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        formatMonthKey(entry.monthKey),
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${formatShortDate(entry.paidOn)}${entry.note.trim().isEmpty ? '' : ' • ${entry.note}'}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Text(
                                      formatCurrency(entry.amount),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    if (canShareReceipt || canEdit) ...<Widget>[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        alignment: WrapAlignment.end,
                                        children: <Widget>[
                                          if (canShareReceipt)
                                            _SmallActionChip(
                                              icon: Icons.share_outlined,
                                              // label: 'Share',
                                              onTap: () => widget.onShareReceipt(entry),
                                              color: scheme.primary,
                                            ),
                                          if (canEdit) ...[
                                            // _SmallActionChip(
                                            //   icon: Icons.edit_outlined,
                                            //   label: 'Edit',
                                            //   onTap: () {
                                            //     _handleEdit(entry);
                                            //   },
                                            //   color: scheme.secondary,
                                            // ),
                                            
                                            _SmallActionChip(
                                              icon: Icons.delete_outline_rounded,
                                              
                                              onTap: () {
                                                _handleDelete(entry);
                                              },
                                              color: scheme.error,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearFilterChip extends StatelessWidget {
  const _YearFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outline.withAlpha(40),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: scheme.primary.withAlpha(40),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: isSelected ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SmallActionChip extends StatelessWidget {
  const _SmallActionChip({
    required this.icon,
    // required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  // final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withAlpha(40), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            
          ],
        ),
      ),
    );
  }
}

class HouseFormSheet extends StatefulWidget {
  const HouseFormSheet({super.key, this.house});

  final House? house;

  @override
  State<HouseFormSheet> createState() => _HouseFormSheetState();
}

class _HouseFormSheetState extends State<HouseFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _familyController;
  late final TextEditingController _houseNumberController;
  late final TextEditingController _phoneController;
  late final TextEditingController _feeController;
  late final TextEditingController _notesController;
  late String _selectedBlock;

  @override
  void initState() {
    super.initState();
    _familyController = TextEditingController(
      text: widget.house?.familyName ?? '',
    );
    _houseNumberController = TextEditingController(
      text: widget.house?.houseNumber ?? '',
    );
    _selectedBlock = kBlockOptions.contains(widget.house?.block)
        ? widget.house!.block
        : kBlockOptions.first;
    _phoneController = TextEditingController(
      text: widget.house?.phoneNumber ?? '',
    );
    _feeController = TextEditingController(
      text: widget.house == null
          ? ''
          : formatCurrency(widget.house!.monthlyFee).replaceFirst('Rs ', ''),
    );
    _notesController = TextEditingController(text: widget.house?.notes ?? '');
  }

  @override
  void dispose() {
    _familyController.dispose();
    _houseNumberController.dispose();
    _phoneController.dispose();
    _feeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final amount = double.parse(_feeController.text.trim());
    final existing = widget.house;
    final house = House(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      familyName: _familyController.text.trim(),
      houseNumber: _houseNumberController.text.trim(),
      block: _selectedBlock,
      phoneNumber: _phoneController.text.trim(),
      monthlyFee: amount,
      notes: _notesController.text.trim(),
    );

    Navigator.of(context).pop(house);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SheetHandle(),
                  const SizedBox(height: 18),
                  _HeroSheetCard(
                    eyebrow: widget.house == null
                        ? 'New record'
                        : 'Update record',
                    title: widget.house == null
                        ? 'Add new house'
                        : 'Edit house',
                    subtitle:
                        'Save each family and their monthly subscription amount.',
                    icon: Icons.home_work_rounded,
                    accentColors: const <Color>[
                      Color(0xFF112F33),
                      Color(0xFF285E59),
                      Color(0xFFB27C4A),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SleekPanel(
                    child: Column(
                      children: <Widget>[
                        TextFormField(
                          controller: _familyController,
                          decoration: const InputDecoration(
                            labelText: 'Family / house name',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter the family or house name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _houseNumberController,
                          decoration: const InputDecoration(
                            labelText: 'House number',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _selectedBlock,
                          decoration: const InputDecoration(labelText: 'Block'),
                          items: kBlockOptions
                              .map(
                                (String block) => DropdownMenuItem<String>(
                                  value: block,
                                  child: Text('Block $block'),
                                ),
                              )
                              .toList(),
                          onChanged: (String? value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedBlock = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                          ),
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _feeController,
                          decoration: const InputDecoration(
                            labelText: 'Monthly subscription amount (Rs)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (String? value) {
                            final amount = double.tryParse(value?.trim() ?? '');
                            if (amount == null || amount <= 0) {
                              return 'Enter a valid monthly amount';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(labelText: 'Notes'),
                          minLines: 3,
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        widget.house == null ? 'Save house' : 'Update house',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StaffFormSheet extends StatefulWidget {
  const StaffFormSheet({super.key, this.staff, required this.availableBlocks});

  final StaffUser? staff;
  final List<String> availableBlocks;

  @override
  State<StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends State<StaffFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late String _selectedBlock;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.staff?.fullName ?? '',
    );
    _usernameController = TextEditingController(
      text: widget.staff?.username ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.staff?.password ?? '',
    );
    final initialBlock = widget.staff != null && widget.staff!.blocks.isNotEmpty
        ? widget.staff!.blocks.first
        : '';
    _selectedBlock = widget.availableBlocks.contains(initialBlock)
        ? initialBlock
        : widget.availableBlocks.first;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final staff = StaffUser(
      username: _usernameController.text.trim().toLowerCase(),
      fullName: _fullNameController.text.trim(),
      password: _passwordController.text,
      blocks: <String>[_selectedBlock],
    );

    Navigator.of(context).pop(staff);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SheetHandle(),
                  const SizedBox(height: 18),
                  _HeroSheetCard(
                    eyebrow: widget.staff == null
                        ? 'New staff'
                        : 'Update staff',
                    title: widget.staff == null
                        ? 'Create staff account'
                        : 'Edit staff account',
                    subtitle:
                        'Assign block access so staff can only view the houses in their own block.',
                    icon: Icons.people_alt_rounded,
                    accentColors: const <Color>[
                      Color(0xFF112F33),
                      Color(0xFF285E59),
                      Color(0xFFB27C4A),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SleekPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        TextFormField(
                          controller: _fullNameController,
                          decoration: const InputDecoration(
                            labelText: 'Staff name',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter the staff name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter a username';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (String? value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter a password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: _selectedBlock,
                          decoration: const InputDecoration(
                            labelText: 'Assigned block',
                          ),
                          items: widget.availableBlocks
                              .map(
                                (String block) => DropdownMenuItem<String>(
                                  value: block,
                                  child: Text('Block $block'),
                                ),
                              )
                              .toList(),
                          onChanged: (String? value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedBlock = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        widget.staff == null
                            ? 'Save staff account'
                            : 'Update staff account',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentFormSheet extends StatefulWidget {
  const PaymentFormSheet({
    super.key,
    required this.house,
    required this.monthKeys,
    required this.initialMonthKey,
    required this.defaultAmount,
    this.payment,
  });

  final House house;
  final List<String> monthKeys;
  final String initialMonthKey;
  final double defaultAmount;
  final PaymentEntry? payment;

  @override
  State<PaymentFormSheet> createState() => _PaymentFormSheetState();
}

class _PaymentFormSheetState extends State<PaymentFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late String _selectedMonthKey;
  late String _fromMonthKey;
  late String _toMonthKey;
  bool _isBulk = false;
  DateTime _paidOn = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.payment != null) {
      final p = widget.payment!;
      _selectedMonthKey = p.monthKey;
      _fromMonthKey = p.monthKey;
      _toMonthKey = p.monthKey;
      _amountController = TextEditingController(
        text: p.amount == p.amount.roundToDouble()
            ? p.amount.toStringAsFixed(0)
            : p.amount.toStringAsFixed(2),
      );
      _noteController = TextEditingController(text: p.note);
      _paidOn = p.paidOn;
      _isBulk = false;
    } else {
      _selectedMonthKey = widget.initialMonthKey;
      _fromMonthKey = widget.initialMonthKey;
      _toMonthKey = widget.initialMonthKey;
      _amountController = TextEditingController(
        text: widget.defaultAmount == widget.defaultAmount.roundToDouble()
            ? widget.defaultAmount.toStringAsFixed(0)
            : widget.defaultAmount.toStringAsFixed(2),
      );
      _noteController = TextEditingController();
      _paidOn = DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _paidOn = picked;
    });
  }

  List<String> _monthsBetween(String fromKey, String toKey) {
    // Build all months between two keys without relying on monthKeys list
    final fromParts = fromKey.split('-');
    final toParts = toKey.split('-');
    if (fromParts.length != 2 || toParts.length != 2) return <String>[fromKey];
    var fromYear = int.tryParse(fromParts[0]) ?? DateTime.now().year;
    var fromMonth = int.tryParse(fromParts[1]) ?? DateTime.now().month;
    var toYear = int.tryParse(toParts[0]) ?? DateTime.now().year;
    var toMonth = int.tryParse(toParts[1]) ?? DateTime.now().month;

    // Ensure from <= to
    if (DateTime(fromYear, fromMonth).isAfter(DateTime(toYear, toMonth))) {
      final tmpY = fromYear;
      fromYear = toYear;
      toYear = tmpY;
      final tmpM = fromMonth;
      fromMonth = toMonth;
      toMonth = tmpM;
    }

    final result = <String>[];
    var y = fromYear;
    var m = fromMonth;
    while (!DateTime(y, m).isAfter(DateTime(toYear, toMonth))) {
      result.add(monthKeyFromDate(DateTime(y, m)));
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }
    return result;
  }

  Future<void> _pickMonthForKey(
    String currentKey,
    ValueChanged<String> onPicked,
  ) async {
    final parts = currentKey.split('-');
    final initYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    final initMonth = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initYear, initMonth, 1),
      firstDate: DateTime(DateTime.now().year - 5, 1),
      lastDate: DateTime(DateTime.now().year + 3, 12),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select month',
      fieldHintText: 'Month/Year',
    );

    if (picked == null || !mounted) return;
    onPicked(monthKeyFromDate(picked));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final amount = double.parse(_amountController.text.trim());
    final note = _noteController.text.trim();

    if (_isBulk) {
      final months = _monthsBetween(_fromMonthKey, _toMonthKey);
      final drafts = months
          .map(
            (m) => PaymentDraft(
              monthKey: m,
              amount: amount,
              paidOn: _paidOn,
              note: note,
            ),
          )
          .toList();
      Navigator.of(context).pop(drafts);
    } else {
      Navigator.of(context).pop(<PaymentDraft>[
        PaymentDraft(
          monthKey: _selectedMonthKey,
          amount: amount,
          paidOn: _paidOn,
          note: note,
        ),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SheetHandle(),
                  const SizedBox(height: 18),
                  _HeroSheetCard(
                    eyebrow: widget.house.houseNumber.trim().isEmpty
                        ? 'Payment entry'
                        : 'House ${widget.house.houseNumber}',
                    title: 'Record payment',
                    subtitle:
                        '${widget.house.familyName} • ${formatCurrency(widget.house.monthlyFee)} monthly',
                    icon: Icons.payments_rounded,
                    accentColors: const <Color>[
                      Color(0xFF183135),
                      Color(0xFF2A6A64),
                      Color(0xFFC18A53),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SleekPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Bulk toggle row
                        if (widget.payment == null)
                          Row(
                            children: <Widget>[
                              const Icon(Icons.date_range_rounded, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Bulk subscription',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Switch(
                                value: _isBulk,
                                onChanged: (bool val) {
                                  setState(() {
                                    _isBulk = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        if (!_isBulk) ...<Widget>[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _pickMonthForKey(
                                _selectedMonthKey,
                                (k) => setState(() => _selectedMonthKey = k),
                              ),
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text(
                                'Month: ${formatMonthKey(_selectedMonthKey)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ] else ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            'Select a month range to save each month separately.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickMonthForKey(
                                    _fromMonthKey,
                                    (k) => setState(() => _fromMonthKey = k),
                                  ),
                                  icon: const Icon(
                                    Icons.calendar_month_outlined,
                                  ),
                                  label: Text(
                                    'From: ${formatMonthKey(_fromMonthKey)}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickMonthForKey(
                                    _toMonthKey,
                                    (k) => setState(() => _toMonthKey = k),
                                  ),
                                  icon: const Icon(Icons.event_rounded),
                                  label: Text(
                                    'To: ${formatMonthKey(_toMonthKey)}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final months = _monthsBetween(
                                _fromMonthKey,
                                _toMonthKey,
                              );
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withAlpha(12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${months.length} month${months.length == 1 ? '' : 's'} selected: ${months.map(formatMonthKey).join(', ')}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _amountController,
                          decoration: InputDecoration(
                            labelText: _isBulk
                                ? 'Amount per month (Rs)'
                                : 'Amount received (Rs)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (String? value) {
                            final amount = double.tryParse(value?.trim() ?? '');
                            if (amount == null || amount <= 0) {
                              return 'Enter a valid amount';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text('Paid on ${formatShortDate(_paidOn)}'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _noteController,
                          decoration: const InputDecoration(labelText: 'Note'),
                          minLines: 2,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Builder(
                    builder: (context) {
                      final label = _isBulk
                          ? () {
                              final months = _monthsBetween(
                                _fromMonthKey,
                                _toMonthKey,
                              );
                              return 'Save ${months.length} month${months.length == 1 ? '' : 's'}';
                            }()
                          : 'Save payment';
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: Text(label),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentDraft {
  const PaymentDraft({
    required this.monthKey,
    required this.amount,
    required this.paidOn,
    required this.note,
  });

  final String monthKey;
  final double amount;
  final DateTime paidOn;
  final String note;
}

enum _HouseDetailsAction { edit, collect }

class _HouseStatusBundle {
  const _HouseStatusBundle({required this.house, required this.status});

  final House house;
  final HouseMonthStatus status;
}

class _BlockCollectionSummary {
  const _BlockCollectionSummary({
    required this.block,
    required this.totalHouses,
    required this.paidHouses,
    required this.totalExpected,
    required this.totalCollected,
  });

  final String block;
  final int totalHouses;
  final int paidHouses;
  final double totalExpected;
  final double totalCollected;

  double get totalDue {
    final due = totalExpected - totalCollected;
    return due > 0 ? due : 0;
  }

  double get progress {
    if (totalExpected <= 0) {
      return 0;
    }
    return (totalCollected / totalExpected).clamp(0, 1).toDouble();
  }
}

class _BlockDetailsPage extends StatefulWidget {
  const _BlockDetailsPage({
    super.key,
    required this.summary,
    required this.monthKey,
    required this.bundles,
    required this.entries,
    required this.housesById,
    this.onHouseTap,
  });

  final _BlockCollectionSummary summary;
  final String monthKey;
  final List<_HouseStatusBundle> bundles;
  final List<PaymentEntry> entries;
  final Map<String, House> housesById;
  final void Function(House)? onHouseTap;

  @override
  State<_BlockDetailsPage> createState() => _BlockDetailsPageState();
}

class _BlockDetailsPageState extends State<_BlockDetailsPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_HouseStatusBundle> get _filteredBundles {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.bundles;
    }
    return widget.bundles.where((bundle) {
      final house = bundle.house;
      final haystack = <String>[
        house.familyName,
        house.houseNumber,
        house.phoneNumber,
        house.block,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _openCollectionsPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _BlockTransactionsPage(
          summary: widget.summary,
          monthKey: widget.monthKey,
          entries: widget.entries,
          housesById: widget.housesById,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blockLabel = widget.summary.block == 'UNASSIGNED'
        ? 'Unassigned'
        : 'Block ${widget.summary.block}';

    final filtered = _filteredBundles;

    return Scaffold(
      appBar: AppBar(
        title: Text('$blockLabel Details'),
      ),
      body: widget.bundles.isEmpty
          ? const Center(
              child: Text('No houses found in this block.'),
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: _SleekPanel(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search family, house number, or phone',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.trim().isEmpty
                            ? null
                            : IconButton(
                                onPressed: _searchController.clear,
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('No matching houses found.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (BuildContext context, int index) {
                            final bundle = filtered[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GestureDetector(
                                onTap: () => widget.onHouseTap?.call(bundle.house),
                                child: _ReportRowCard(
                                  house: bundle.house,
                                  status: bundle.status,
                                  blockLabel: blockLabel,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCollectionsPage(context),
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('Collections'),
      ),
    );
  }
}

class _BlockTransactionsPage extends StatelessWidget {
  const _BlockTransactionsPage({
    required this.summary,
    required this.monthKey,
    required this.entries,
    required this.housesById,
  });

  final _BlockCollectionSummary summary;
  final String monthKey;
  final List<PaymentEntry> entries;
  final Map<String, House> housesById;

  @override
  Widget build(BuildContext context) {
    final blockLabel = summary.block == 'UNASSIGNED'
        ? 'Unassigned'
        : 'Block ${summary.block}';

    return Scaffold(
      appBar: AppBar(
        title: Text('$blockLabel Collections'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: <Widget>[
              _HeroSheetCard(
                eyebrow: formatMonthKey(monthKey),
                title: '$blockLabel collections',
                subtitle:
                    '${entries.length} transaction${entries.length == 1 ? '' : 's'} • Collected ${formatCurrency(summary.totalCollected)}',
                icon: Icons.receipt_long_rounded,
                accentColors: const <Color>[
                  Color(0xFF112F33),
                  Color(0xFF2A6A64),
                  Color(0xFFB27C4A),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: entries.isEmpty
                    ? const _EmptyStateCard(
                        title: 'No collections yet',
                        message:
                            'There are no payment transactions for this block in the selected month.',
                      )
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final entry = entries[index];
                          final house = housesById[entry.houseId];
                          final houseLabel = house == null
                              ? 'Unknown house'
                              : house.houseNumber.trim().isEmpty
                              ? house.familyName
                              : '${house.familyName} • House ${house.houseNumber}';
                          return _TransactionPreviewRow(
                            title: houseLabel,
                            subtitle:
                                '${formatShortDate(entry.paidOn)}${entry.note.trim().isEmpty ? '' : ' • ${entry.note.trim()}'}',
                            amount: formatCurrency(entry.amount),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBadgeData {
  const _HeaderBadgeData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

// ─────────────────────────────────────────────
// Desktop-only widgets
// ─────────────────────────────────────────────

/// InheritedWidget that provides the actual desktop content area width
/// to child widgets, bypassing MediaQuery which returns the full screen width.
class _DesktopContentConstraint extends InheritedWidget {
  const _DesktopContentConstraint({
    required this.availableWidth,
    required super.child,
  });

  final double availableWidth;

  static _DesktopContentConstraint? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_DesktopContentConstraint>();
  }

  @override
  bool updateShouldNotify(_DesktopContentConstraint oldWidget) {
    return oldWidget.availableWidth != availableWidth;
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.navItems,
    required this.user,
    required this.onDestinationSelected,
    required this.onRefresh,
    required this.onLogout,
  });

  final int selectedIndex;
  final List<_NavItem> navItems;
  final AuthUser user;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF0B1F24),
            Color(0xFF0E2A30),
            Color(0xFF132F35),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 32,
            offset: Offset(8, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 24),
            // Logo + App name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: Image.asset(
                      'assets/images/masjid_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.mosque_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Murshidul Anam',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'Sangam',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withAlpha(160),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Divider label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'NAVIGATION',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withAlpha(90),
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Nav items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: navItems.length,
                itemBuilder: (BuildContext context, int index) {
                  final item = navItems[index];
                  final isSelected = selectedIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => onDestinationSelected(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: isSelected
                                ? Colors.white.withAlpha(22)
                                : Colors.transparent,
                            border: isSelected
                                ? Border.all(
                                    color: Colors.white.withAlpha(30),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                isSelected ? item.selectedIcon : item.icon,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withAlpha(140),
                                size: 22,
                              ),
                              const SizedBox(width: 14),
                              Text(
                                item.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white.withAlpha(160),
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              if (isSelected) ...<Widget>[
                                const Spacer(),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFC18A53),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Bottom user section
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9F7347).withAlpha(60),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF9F7347).withAlpha(80),
                          ),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              user.fullName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user.isAdmin ? 'Admin' : 'Staff',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white.withAlpha(130),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _SidebarIconButton(
                          icon: Icons.refresh_rounded,
                          tooltip: 'Refresh',
                          onTap: onRefresh,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SidebarIconButton(
                          icon: Icons.logout_rounded,
                          tooltip: 'Sign out',
                          onTap: onLogout,
                          isDestructive: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDestructive
                  ? Colors.red.withAlpha(30)
                  : Colors.white.withAlpha(14),
              border: Border.all(
                color: isDestructive
                    ? Colors.red.withAlpha(60)
                    : Colors.white.withAlpha(20),
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: isDestructive
                    ? Colors.red.withAlpha(200)
                    : Colors.white.withAlpha(160),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopPageHeader extends StatelessWidget {
  const _DesktopPageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badges,
    required this.onRefresh,
    required this.canAddHouse,
    required this.onAddHouse,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<_HeaderBadgeData>? badges;
  final VoidCallback onRefresh;
  final bool canAddHouse;
  final VoidCallback onAddHouse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(200),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withAlpha(28),
          ),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A0E2A30),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF0E2A30), Color(0xFF9F7347)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: const Color(0xFF0E2A30),
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (badges != null && badges!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: badges!
                        .map(
                          (_HeaderBadgeData badge) => _DesktopBadge(
                            icon: badge.icon,
                            label: badge.label,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          if (canAddHouse) ...<Widget>[
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onAddHouse,
              icon: const Icon(Icons.add_home_work_outlined, size: 18),
              label: const Text('Add House'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF173E44),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopBadge extends StatelessWidget {
  const _DesktopBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2A30).withAlpha(10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF0E2A30).withAlpha(25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: const Color(0xFF0E2A30)),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: const Color(0xFF0E2A30),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropDecor extends StatelessWidget {
  const _BackdropDecor();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -140,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x40C18A53), Color(0x00C18A53)],
                ),
              ),
            ),
          ),
          Positioned(
            top: 80,
            left: -90,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x351A5E57), Color(0x001A5E57)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -40,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x24112F33), Color(0x00112F33)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badges,
    required this.user,
    required this.onRefresh,
    required this.onLogout,
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<_HeaderBadgeData>? badges;
  final AuthUser user;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFF0E2A30),
            Color(0xFF173E44),
            Color(0xFF9F7347),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x26112F33),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -34,
            right: -18,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(14),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(18),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withAlpha(28)),
                    ),

                    child: Image.asset(
                      'assets/images/masjid_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        icon ?? Icons.mosque_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (title != null)
                          Text(
                            title!,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withAlpha(204),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: onRefresh,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withAlpha(18),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    onSelected: (String value) {
                      if (value == 'logout') {
                        onLogout();
                      }
                    },
                    tooltip: 'Account',
                    color: Colors.white,
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            enabled: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  user.fullName,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@${user.username}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'logout',
                            child: Row(
                              children: <Widget>[
                                Icon(Icons.logout_rounded),
                                SizedBox(width: 10),
                                Text('Sign out'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            enabled: false,
                            child: Center(
                              child: Text(
                                'Version: 1.1',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withAlpha(26)),
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (badges != null && badges!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: badges!
                      .map(
                        (_HeaderBadgeData badge) =>
                            _HeroBadge(icon: badge.icon, label: badge.label),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SleekPanel extends StatelessWidget {
  const _SleekPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 30,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(232),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: scheme.outline.withAlpha(28)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140E2A30),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _HouseCard extends StatelessWidget {
  const _HouseCard({
    required this.house,
    required this.monthKey,
    required this.status,
    required this.blockLabel,
    required this.showAdminDetails,
    required this.showAdminActions,
    required this.onTap,
    required this.onMenuSelected,
  });

  final House house;
  final String monthKey;
  final HouseMonthStatus status;
  final String blockLabel;
  final bool showAdminDetails;
  final bool showAdminActions;
  final VoidCallback onTap;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = paymentStatusColor(status.status);
    final houseMeta = <String>[
      house.houseNumber.trim().isEmpty
          ? 'House number not added'
          : 'House ${house.houseNumber}',
      if (house.block.trim().isNotEmpty) blockLabel,
    ].join(' • ');

    return _SleekPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _MonogramAvatar(
                      label: house.familyName,
                      color: statusColor,
                      size: 46,
                      borderRadius: 16,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            house.familyName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            houseMeta,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        StatusChip(status: status.status),
                        PopupMenuButton<String>(
                          onSelected: onMenuSelected,
                          icon: const Icon(Icons.more_horiz_rounded),
                          itemBuilder: (BuildContext context) {
                            return <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                value: 'view',
                                child: Text('View details'),
                              ),
                              const PopupMenuItem<String>(
                                value: 'collect',
                                child: Text('Record payment'),
                              ),
                              if (showAdminActions)
                                const PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('Edit house'),
                                ),
                              if (showAdminActions)
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Text('Delete house'),
                                ),
                            ];
                          },
                        ),
                      ],
                    ),
                  ],
                ),

                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: <Widget>[
                    InfoPill(
                      icon: Icons.currency_rupee_rounded,
                      label: '${formatCurrency(house.monthlyFee)} / month',
                    ),
                    if (house.block.trim().isNotEmpty)
                      InfoPill(
                        icon: Icons.apartment_rounded,
                        label: blockLabel,
                      ),
                    if (showAdminDetails && house.phoneNumber.trim().isNotEmpty)
                      InfoPill(
                        icon: Icons.call_outlined,
                        label: house.phoneNumber,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        formatMonthKey(monthKey),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      status.status == PaymentStatus.paid
                          ? 'Received ${formatCurrency(status.amountPaid)}'
                          : 'Due ${formatCurrency(status.balance)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: status.progressFor(house.monthlyFee),
                    minHeight: 8,
                    backgroundColor: statusColor.withAlpha(24),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
                if (showAdminDetails &&
                    house.notes.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    house.notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportRowCard extends StatelessWidget {
  const _ReportRowCard({
    required this.house,
    required this.status,
    required this.blockLabel,
  });

  final House house;
  final HouseMonthStatus status;
  final String blockLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = paymentStatusColor(status.status);
    final details = <String>[
      if (house.houseNumber.trim().isNotEmpty) 'House ${house.houseNumber}',
      if (house.block.trim().isNotEmpty) blockLabel,
      formatCurrency(house.monthlyFee),
    ].join(' • ');

    return _SleekPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          _MonogramAvatar(label: house.familyName, color: statusColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        house.familyName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    StatusChip(status: status.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: status.progressFor(house.monthlyFee),
                    minHeight: 7,
                    backgroundColor: statusColor.withAlpha(22),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                status.status == PaymentStatus.paid
                    ? formatCurrency(status.amountPaid)
                    : formatCurrency(status.balance),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status.status == PaymentStatus.paid ? 'Collected' : 'Due',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionPreviewRow extends StatelessWidget {
  const _TransactionPreviewRow({
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final String title;
  final String subtitle;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withAlpha(14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonogramAvatar extends StatelessWidget {
  const _MonogramAvatar({
    required this.label,
    required this.color,
    this.size = 56,
    this.borderRadius = 20,
  });

  final String label;
  final Color color;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final letter = label.trim().isEmpty ? 'H' : label.trim()[0].toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[color.withAlpha(225), color.withAlpha(150)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Text(
          letter,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 50,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline.withAlpha(70),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _HeroSheetCard extends StatelessWidget {
  const _HeroSheetCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColors,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> accentColors;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: accentColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withAlpha(28)),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withAlpha(188),
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withAlpha(215),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
  });

  final String title;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _SleekPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const Spacer(),
              Container(
                width: 34,
                height: 6,
                decoration: BoxDecoration(
                  color: scheme.secondary.withAlpha(95),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockCollectionCard extends StatelessWidget {
  const _BlockCollectionCard({required this.summary, this.onTap});

  final _BlockCollectionSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final blockLabel = summary.block == 'UNASSIGNED'
        ? 'Unassigned'
        : 'Block ${summary.block}';

    return _SleekPanel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlpha(12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          summary.block == 'UNASSIGNED' ? '?' : summary.block,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            blockLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${summary.paidHouses} of ${summary.totalHouses} houses fully paid',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          formatCurrency(summary.totalCollected),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (onTap != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            'View transactions',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: summary.progress,
                    minHeight: 8,
                    backgroundColor: scheme.primary.withAlpha(12),
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    InfoPill(
                      icon: Icons.home_work_rounded,
                      label: '${summary.totalHouses} houses',
                    ),
                    InfoPill(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Expected ${formatCurrency(summary.totalExpected)}',
                    ),
                    InfoPill(
                      icon: Icons.payments_outlined,
                      label: 'Collected ${formatCurrency(summary.totalCollected)}',
                    ),
                    InfoPill(
                      icon: Icons.flag_outlined,
                      label: 'Due ${formatCurrency(summary.totalDue)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MonthDropdown extends StatelessWidget {
  const MonthDropdown({
    super.key,
    required this.monthKeys,
    required this.selectedMonthKey,
    required this.onChanged,
    this.inverse = false,
  });

  final List<String> monthKeys;
  final String selectedMonthKey;
  final ValueChanged<String> onChanged;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = inverse ? Colors.white.withAlpha(18) : Colors.white;
    final borderColor = inverse
        ? Colors.white.withAlpha(24)
        : scheme.outline.withAlpha(36);
    final selectedTextColor = inverse ? Colors.white : scheme.onSurface;
    final menuTextColor = scheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedMonthKey,
          isExpanded: true,
          iconEnabledColor: selectedTextColor,
          dropdownColor: Colors.white,
          style: TextStyle(
            color: menuTextColor,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          selectedItemBuilder: (BuildContext context) {
            return monthKeys
                .map(
                  (String key) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMonthKey(key),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selectedTextColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
                .toList();
          },
          items: monthKeys
              .map(
                (String key) => DropdownMenuItem<String>(
                  value: key,
                  child: Text(
                    formatMonthKey(key),
                    style: TextStyle(
                      color: menuTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            onChanged(value);
          },
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.soft = false});

  final PaymentStatus status;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final color = paymentStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: soft ? Colors.white.withAlpha(18) : color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: soft ? Colors.white.withAlpha(26) : color.withAlpha(50),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            paymentStatusIcon(status),
            size: 14,
            color: soft ? Colors.white : color,
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              color: soft ? Colors.white : color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withAlpha(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryCountCard extends StatelessWidget {
  const SummaryCountCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withAlpha(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateView extends StatelessWidget {
  const _EmptyStateView({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _EmptyStateCard(
          title: title,
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _SleekPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF19373B), Color(0xFFB27C4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.home_work_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

Color paymentStatusColor(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.unpaid:
      return const Color(0xFFB42318);
    case PaymentStatus.partial:
      return const Color(0xFFB26A00);
    case PaymentStatus.paid:
      return const Color(0xFF2E7D32);
  }
}

IconData paymentStatusIcon(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.unpaid:
      return Icons.error_outline_rounded;
    case PaymentStatus.partial:
      return Icons.timelapse_rounded;
    case PaymentStatus.paid:
      return Icons.check_circle_outline_rounded;
  }
}
