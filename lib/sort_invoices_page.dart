import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'main.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SortInvoicesPage extends StatefulWidget {
  @override
  _SortInvoicesPageState createState() => _SortInvoicesPageState();
}

class _SortInvoicesPageState extends State<SortInvoicesPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _sortedInvoices = [];
  List<Map<String, dynamic>> _yearlyOverviewData = [];
  List<Map<String, dynamic>> _yearlyAndMonthlyStatsData = [];
  String _selectedSortOption = 'date_invoice';
  bool _isAscending = true;
  String _searchQuery = '';
  double largestAmount = 0.0;
  int? _selectedMonth;
  int _selectedYear = DateTime.now().year; // Default: current year
  int _currentSection = 1;
  int? selectedMonth;
  String? _selectedAgentName;
  late Future<List<String>> _yearsFuture;
  String exportLog = "";
  bool isExporting = false;
  bool isDone = false;

  void _changeSection(int section) {
    setState(() {
      _currentSection = section;
    });
  }

  double _calculateTotalAmountForMonth() {
    double total = 0.0;

    for (var invoice in _invoices) {
      if (invoice['date_invoice'] != null) {
        try {
          DateTime invoiceDate = DateTime.parse(invoice['date_invoice']);
          print("Invoice Date: ${invoice['date_invoice']}");
          if (invoiceDate.month.toString() == _selectedMonth) {
            total += double.tryParse(invoice['amount'].toString()) ?? 0.0;
          }
        } catch (e) {
          print("Error parsing date: $e");
        }
      }
    }

    return total;
  }

  List<Map<String, dynamic>> _getFilteredAndSortedInvoices() {
    List<Map<String, dynamic>> filteredInvoices =
        _sortedInvoices.where((invoice) {
      if (invoice['date_invoice'] != null) {
        try {
          DateTime invoiceDate = DateTime.parse(invoice['date_invoice']);
          int invoiceYear = invoiceDate.year;
          int invoiceMonth = invoiceDate.month;
          String invoiceAgent =
              (invoice['agent_name'] ?? "").trim().toLowerCase();

          int currentYear = DateTime.now().year;
          int? filterYear = _selectedYear ?? currentYear;
          int? filterMonth = _selectedMonth;
          String filterAgent = _selectedAgentName?.trim().toLowerCase() ?? '';

          bool yearMatches = filterYear == null || invoiceYear == filterYear;
          bool monthMatches =
              filterMonth == null || invoiceMonth == filterMonth;
          bool agentMatches =
              filterAgent.isEmpty || invoiceAgent == filterAgent;

          return yearMatches && monthMatches && agentMatches;
        } catch (e) {
          print("Error parsing date: $e");
          return false;
        }
      }
      return false;
    }).toList();

    // Sorting Logic
    if (_selectedSortOption != null &&
        _invoices.isNotEmpty &&
        _invoices.first.containsKey(_selectedSortOption)) {
      filteredInvoices.sort((a, b) {
        var valueA = a[_selectedSortOption] ?? '';
        var valueB = b[_selectedSortOption] ?? '';

        if (valueA is num && valueB is num) {
          return _isAscending
              ? valueA.compareTo(valueB)
              : valueB.compareTo(valueA);
        } else if (valueA is String && valueB is String) {
          return _isAscending
              ? valueA.compareTo(valueB)
              : valueB.compareTo(valueA);
        }
        return 0;
      });
    }

    return filteredInvoices;
  }

  /// **Show Notification on Invoice Download Completion**
  void showDownloadNotification(String filePath) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'invoice_download_channel',
      'Invoice Downloads',
      channelDescription: 'Notification when an invoice is downloaded',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      largeIcon: DrawableResourceAndroidBitmap(
          '@android:drawable/stat_sys_download_done'),
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Download Complete',
      'Invoice saved at $filePath',
      platformChannelSpecifics,
    );
  }

  Future<void> exportInvoices() async {
    List<Map<String, dynamic>> invoicesToExport = [];
    if (_currentSection == 1) {
      invoicesToExport =
          _getFilteredAndSortedInvoices(); // Data from Invoice Table
    } else if (_currentSection == 2) {
      invoicesToExport = _getYearlyOverviewData(); // Data from Yearly Overview
    } else {
      invoicesToExport =
          _getYearlyAndMonthlyStatsData(); // Data from Yearly & Monthly Stats
    }
    await exportInvoicesToExcel(invoicesToExport);
  }

  Future<void> exportToExcel() async {
    setState(() {
      isExporting = true;
    });

    try {
      await exportInvoicesToExcel(_invoices);
      setState(() {
        isExporting = false;
        isDone = true;
      });
      Future.delayed(Duration(seconds: 2), () {
        setState(() {
          isDone = false;
        });
      });
    } catch (e) {
      setState(() {
        isExporting = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Export failed: $e")));
    }
  }

  Future<void> exportInvoicesToExcel(
      List<Map<String, dynamic>> invoices) async {
    if (invoices.isEmpty) {
      return;
    }
    if (await Permission.storage.request().isDenied) {
      return;
    }
    Directory? appDocDir = await getExternalStorageDirectory();
    if (appDocDir == null) {
      return;
    }
    String downloadsPath = "${appDocDir.path}/Download";
    await Directory(downloadsPath).create(recursive: true);
    String filePath =
        "$downloadsPath/Invoices_${DateTime.now().toIso8601String()}.xlsx";
    File file = File(filePath);

    try {
      final xls.Workbook workbook = xls.Workbook();
      final xls.Worksheet sheet = workbook.worksheets[0];
      List<String> headers = invoices.first.keys.toList();
      for (int i = 0; i < headers.length; i++) {
        sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
      }
      for (int i = 0; i < invoices.length; i++) {
        Map<String, dynamic> invoice = invoices[i];
        for (int j = 0; j < headers.length; j++) {
          var value = invoice[headers[j]];
          if (value is num) {
            sheet.getRangeByIndex(i + 2, j + 1).setNumber(value.toDouble());
          } else {
            sheet.getRangeByIndex(i + 2, j + 1).setText(value.toString());
          }
        }
      }

      final List<int> bytes = workbook.saveAsStream();
      await file.writeAsBytes(bytes);
      workbook.dispose();
      OpenFilex.open(filePath);
    } catch (e) {
      print("Error saving file: $e");
    }
  }

  void initiateExport() async {
    List<Map<String, dynamic>> invoices = [];
    if (_currentSection == 1) {
      invoices = await _fetchSortedInvoices().first;
    } else if (_currentSection == 2) {
      invoices = _yearlyOverviewData.isNotEmpty
          ? _formatYearlyOverviewData(_yearlyOverviewData.first)
          : [];
    } else {
      invoices = _yearlyAndMonthlyStatsData.isNotEmpty
          ? _formatYearlyAndMonthlyStats(_yearlyAndMonthlyStatsData.first)
          : [];
    }

    await exportInvoicesToExcel(invoices);
  }

  Stream<List<Map<String, dynamic>>> _fetchSortedInvoices() {
    return supabase
        .from('invoices')
        .stream(primaryKey: ['id'])
        .order('date_invoice', ascending: false)
        .map((data) {
          List<Map<String, dynamic>> filteredInvoices = data.where((invoice) {
            String? dateString = invoice['date_invoice'];
            if (dateString == null || dateString.isEmpty) return false;
            DateTime? invoiceDate = DateTime.tryParse(dateString);
            if (invoiceDate == null) return false;
            bool matchesYear = invoiceDate.year == _selectedYear;
            bool matchesMonth =
                _selectedMonth == null || invoiceDate.month == _selectedMonth;
            String agentName =
                (invoice['agent_name'] ?? "").trim().toLowerCase();
            String filterAgent =
                (_selectedAgentName ?? "").trim().toLowerCase();
            bool matchesAgent =
                filterAgent.isEmpty || agentName.contains(filterAgent);

            return matchesYear && matchesMonth && matchesAgent;
          }).toList();
          return filteredInvoices;
        });
  }

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year; // Default to current year
    _fetchSortedInvoices().listen((data) {
      setState(() {
        _sortedInvoices = data;
      });
    });
    _streamYearlySummary(_selectedYear.toString()).listen((data) {
      setState(() {
        if (data is List) {
          _yearlyOverviewData = List<Map<String, dynamic>>.from(data as List);
        } else if (data is Map<String, dynamic>) {
          _yearlyOverviewData = [data];
        }
      });
    });
    _fetchYearlyAndMonthlyStats().listen((data) {
      setState(() {
        _yearlyAndMonthlyStatsData = List<Map<String, dynamic>>.from(data);
      });
    });
  }

  Future<List<String>> _fetchYearsFromSupabase() async {
    final response =
        await Supabase.instance.client.from('invoices').select('date_invoice');
    Set<String> years = response
        .map((row) {
          if (row['date_invoice'] != null) {
            try {
              DateTime date = DateTime.parse(row['date_invoice']);
              return date.year.toString();
            } catch (e) {
              print("Error parsing date: $e");
            }
          }
          return '';
        })
        .where((year) => year.isNotEmpty)
        .cast<String>()
        .toSet();

    List<String> sortedYears = years.toList()..sort((a, b) => b.compareTo(a));

    if (sortedYears.isNotEmpty) {
      _selectedYear ??= int.parse(sortedYears.first);
    }

    return sortedYears;
  }

  Future<List<String>> _fetchAvailableYears() async {
    final response =
        await Supabase.instance.client.from('invoices').select('date_invoice');

    Set<String> uniqueYears = response.map<String>((invoice) {
      return DateTime.parse(invoice['date_invoice']).year.toString();
    }).toSet();

    return uniqueYears.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  List<Map<String, dynamic>> _formatYearlyOverviewData(
      Map<String, dynamic> data) {
    List<Map<String, dynamic>> formattedData = [];
    Map<int, dynamic> monthlyData = data['monthly_data'] ?? {};
    for (int month = 1; month <= 12; month++) {
      var details = monthlyData[month] ??
          {'amount': 0.0, 'total_agents': 0, 'total_invoices': 0};

      formattedData.add({
        'Month': DateFormat.MMMM().format(DateTime(0, month)),
        'Total Amount': details['amount'] ?? 0.0,
        'Total Agents': details['total_agents'] ?? 0,
        'Total Invoices': details['total_invoices'] ?? 0,
      });
    }

    return formattedData;
  }

  List<Map<String, dynamic>> _formatYearlyAndMonthlyStats(
      Map<String, dynamic> stats) {
    return [
      {
        'Statistic': 'Agent with Highest Sales',
        'Value': stats['top_agent_sales'] ?? 'N/A'
      },
      {
        'Statistic': 'Agent with Most Invoices',
        'Value': stats['top_agent_invoices'] ?? 'N/A'
      },
      {
        'Statistic': 'Most Booked Hotel',
        'Value': stats['most_frequent_hotel'] ?? 'N/A'
      },
      {
        'Statistic': 'Highest Single-Day Sale',
        'Value': stats['highest_single_day_sale']?.toString() ?? 'N/A'
      },
    ];
  }

  List<Map<String, dynamic>> _getYearlyOverviewData() {
    return _yearlyOverviewData;
  }

  List<Map<String, dynamic>> _getYearlyAndMonthlyStatsData() {
    return _yearlyAndMonthlyStatsData;
  }

  Map<String, String> calculateStats(
    List<Map<String, dynamic>> invoices,
    int selectedYear,
    int? selectedMonth,
  ) {
    Map<String, double> agentSales = {};
    Map<String, int> agentInvoiceCount = {};
    Map<String, int> hotelBookings = {};
    Map<String, double> dailySales = {};
    double highestInvoiceAmount = 0.0;
    String highestInvoiceAgent = "N/A";
    String highestInvoiceHotel = "N/A";
    String highestInvoiceDate = "N/A";
    for (var invoice in invoices) {
      String agent = invoice['agent_name'] ?? 'Unknown';
      String hotel = invoice['hotel'] ?? 'Unknown';
      double amount = (invoice['total_amount'] ?? 0).toDouble();
      String? dateString = invoice['date_invoice'];

      if (dateString == null || dateString.isEmpty) continue;
      DateTime? invoiceDate = DateTime.tryParse(dateString);
      if (invoiceDate == null) continue;
      if (invoiceDate.year != selectedYear ||
          (selectedMonth != null && invoiceDate.month != selectedMonth)) {
        continue;
      }
      agentSales[agent] = (agentSales[agent] ?? 0) + amount;
      agentInvoiceCount[agent] = (agentInvoiceCount[agent] ?? 0) + 1;
      hotelBookings[hotel] = (hotelBookings[hotel] ?? 0) + 1;
      String dailyKey =
          "$agent-${invoiceDate.toIso8601String().substring(0, 10)}";
      dailySales[dailyKey] = (dailySales[dailyKey] ?? 0) + amount;
      if (amount > highestInvoiceAmount) {
        highestInvoiceAmount = amount;
        highestInvoiceAgent = agent;
        highestInvoiceHotel = hotel;
        highestInvoiceDate = DateFormat('dd MMM yyyy').format(invoiceDate);
      }
    }
    String topAgent = "N/A";
    double topAgentSales = 0.0;

    agentSales.forEach((agent, sales) {
      if (sales > topAgentSales) {
        topAgent = agent;
        topAgentSales = sales;
      }
    });
    String mostInvoicesAgent = "N/A";
    int mostInvoicesCount = 0;

    agentInvoiceCount.forEach((agent, count) {
      if (count > mostInvoicesCount) {
        mostInvoicesAgent = agent;
        mostInvoicesCount = count;
      }
    });
    String mostBookedHotel = "N/A";
    int maxHotelBookings = 0;

    hotelBookings.forEach((hotel, count) {
      if (count > maxHotelBookings) {
        mostBookedHotel = hotel;
        maxHotelBookings = count;
      }
    });

    String topDailyAgent = "N/A";
    double highestSingleDaySales = 0.0;

    dailySales.forEach((key, sales) {
      if (sales > highestSingleDaySales) {
        topDailyAgent = key.split('-')[0];
        highestSingleDaySales = sales;
      }
    });

    return {
      'topAgentSales': "$topAgent - RM${topAgentSales.toStringAsFixed(2)}",
      'topAgentInvoices': "$mostInvoicesAgent - ${mostInvoicesCount} invoices",
      'topHotel': "$mostBookedHotel - $maxHotelBookings bookings",
      'topDailyAgent': topDailyAgent,
      'topDailyAgentAmount': highestSingleDaySales.toStringAsFixed(2),
      'largestInvoice':
          "$highestInvoiceAgent - RM${highestInvoiceAmount.toStringAsFixed(2)}",
      'largestInvoiceHotel': highestInvoiceHotel,
      'largestInvoiceDate': highestInvoiceDate,
      'largestInvoiceDetails': "$highestInvoiceHotel on $highestInvoiceDate",
    };
  }

  String _formatDate(String? date) {
    if (date == null) return "N/A";
    try {
      return DateTime.parse(date).toLocal().toString().split(' ')[0];
    } catch (e) {
      print("Error parsing date: $e");
      return "Invalid Date";
    }
  }

  int? _getSortColumnIndex() {
    switch (_selectedSortOption) {
      case 'agent_name':
        return 0;
      case 'date_invoice':
        return 1;
      case 'amount':
        return 2;
      default:
        return null;
    }
  }

  Widget _buildInvoiceTable() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _fetchSortedInvoices(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text("No invoices available"));
        }

        List<Map<String, dynamic>> invoices = snapshot.data!;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
              columnSpacing: 20,
              headingRowHeight: 50,
              border: TableBorder.all(),
              columns: const [
                DataColumn(label: Text('Agent Name')),
                DataColumn(label: Text('Total Amount')),
              ],
              rows: invoices.map((invoice) {
                return DataRow(cells: [
                  DataCell(Text(invoice['agent_name'] ?? 'N/A')),
                  DataCell(Text("\RM${invoice['amount'] ?? 0}")),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _calculateMonthlyStats(
      List<Map<String, dynamic>> invoices) {
    Map<String, dynamic> monthlyStats = {};

    for (var invoice in invoices) {
      DateTime? date = DateTime.tryParse(invoice['date_invoice'] ?? '');
      String month = date != null
          ? "${date.year}-${date.month.toString().padLeft(2, '0')}"
          : 'Unknown Month';

      String agent = invoice['agent_name'] ?? 'Unknown Agent';
      String hotel = invoice['hotel']?.isNotEmpty == true
          ? invoice['hotel']
          : 'Unknown Hotel';
      double amount = (invoice['amount'] as num?)?.toDouble() ?? 0.0;

      if (!monthlyStats.containsKey(month)) {
        monthlyStats[month] = {
          'month': month,
          'amount': 0.0,
          'total_invoices': 0,
          'top_agent': <String, double>{},
          'most_booked_hotel': <String, int>{},
        };
      }
      monthlyStats[month]['amount'] += amount;
      monthlyStats[month]['total_invoices'] += 1;
      monthlyStats[month]['top_agent'][agent] =
          (monthlyStats[month]['top_agent'][agent] ?? 0) + amount;
      monthlyStats[month]['most_booked_hotel'][hotel] =
          (monthlyStats[month]['most_booked_hotel'][hotel] ?? 0) + 1;
    }

    return monthlyStats.values.map((e) => e as Map<String, dynamic>).toList();
  }

  List<Map<String, dynamic>> _calculateYearlyStats(
      List<Map<String, dynamic>> invoices) {
    Map<String, dynamic> yearlyStats = {};
    for (var invoice in invoices) {
      String year =
          DateTime.tryParse(invoice['date_invoice'] ?? '')?.year.toString() ??
              'Unknown Year';
      String agent = invoice['agent_name'] ?? 'Unknown Agent';
      String hotel = invoice['hotel']?.isNotEmpty == true
          ? invoice['hotel']
          : 'Unknown Hotel';
      double amount = (invoice['amount'] as num?)?.toDouble() ?? 0.0;

      if (!yearlyStats.containsKey(year)) {
        yearlyStats[year] = {
          'year': year,
          'amount': 0.0,
          'total_invoices': 0,
          'top_agent': <String, double>{},
          'most_booked_hotel': <String, int>{},
        };
      }

      yearlyStats[year]['amount'] += amount;
      yearlyStats[year]['total_invoices'] += 1;
      yearlyStats[year]['top_agent'][agent] =
          (yearlyStats[year]['top_agent'][agent] ?? 0) + amount;
      yearlyStats[year]['most_booked_hotel'][hotel] =
          (yearlyStats[year]['most_booked_hotel'][hotel] ?? 0) + 1;
    }

    return yearlyStats.values.map((e) => e as Map<String, dynamic>).toList();
  }

  String _getMaxEntry(Map<String, dynamic> data) {
    if (data.isEmpty) return "No Data";
    var validEntries = data.entries
        .where((e) => e.value is num)
        .map((e) => MapEntry(e.key, (e.value as num).toDouble()))
        .toList();

    if (validEntries.isEmpty) return "No Data";
    return validEntries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Stream<List<Map<String, dynamic>>> _fetchYearlyAndMonthlyStats() async* {
    if (_invoices.isEmpty) {
      print("No invoices available.");
      yield [];
      return;
    }
    Map<int, Map<String, dynamic>> yearlyStats = {};
    Map<String, Map<String, dynamic>> monthlyStats = {};
    Map<String, int> agentInvoiceCount = {};
    Map<String, int> hotelBookingCount = {};
    Map<String, double> dailySales = {};

    for (var invoice in _invoices) {
      String agent = invoice['agent_name'] ?? 'Unknown';
      String hotel = invoice['hotel'] ?? 'Unknown';
      double amount = (invoice['amount'] ?? 0).toDouble();
      String? dateString = invoice['date_invoice'];

      if (dateString == null || dateString.isEmpty) {
        continue;
      }
      DateTime? invoiceDate = DateTime.tryParse(dateString);
      if (invoiceDate == null) {
        continue;
      }

      int year = invoiceDate.year;
      String month =
          "${invoiceDate.year}-${invoiceDate.month.toString().padLeft(2, '0')}";
      String dayKey = "${invoiceDate.toIso8601String().split('T')[0]}-$agent";
      yearlyStats.putIfAbsent(
          year,
          () => {
                'year': year.toString(),
                'amount': 0.0,
                'total_invoices': 0,
                'top_agent': <String, double>{},
                'most_booked_hotel': <String, int>{}
              });

      monthlyStats.putIfAbsent(
          month,
          () => {
                'month': month,
                'amount': 0.0,
                'total_invoices': 0,
                'top_agent': <String, double>{},
                'most_booked_hotel': <String, int>{}
              });

      agentInvoiceCount[agent] = (agentInvoiceCount[agent] ?? 0) + 1;
      hotelBookingCount[hotel] = (hotelBookingCount[hotel] ?? 0) + 1;
      dailySales[dayKey] = (dailySales[dayKey] ?? 0) + amount;
      yearlyStats[year]?['amount'] =
          (yearlyStats[year]?['amount'] as double? ?? 0.0) + amount;

      yearlyStats[year]?['total_invoices'] =
          (yearlyStats[year]?['total_invoices'] as int? ?? 0) + 1;

      (yearlyStats[year]?['top_agent'] as Map<String, double>?)?[agent] =
          ((yearlyStats[year]?['top_agent'] as Map<String, double>?)?[agent] ??
                  0) +
              amount;

      (yearlyStats[year]?['most_booked_hotel'] as Map<String, int>?)?[hotel] =
          ((yearlyStats[year]?['most_booked_hotel']
                      as Map<String, int>?)?[hotel] ??
                  0) +
              1;

      monthlyStats[month]?['amount'] =
          (monthlyStats[month]?['amount'] as double? ?? 0.0) + amount;

      monthlyStats[month]?['total_invoices'] =
          (monthlyStats[month]?['total_invoices'] as int? ?? 0) + 1;

      (monthlyStats[month]?['top_agent'] as Map<String, double>?)?[agent] =
          ((monthlyStats[month]?['top_agent']
                      as Map<String, double>?)?[agent] ??
                  0) +
              amount;

      (monthlyStats[month]?['most_booked_hotel'] as Map<String, int>?)?[hotel] =
          ((monthlyStats[month]?['most_booked_hotel']
                      as Map<String, int>?)?[hotel] ??
                  0) +
              1;
    }

    String topAgentInvoices = agentInvoiceCount.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
    String topHotel = hotelBookingCount.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
    var highestSingleDaySale =
        dailySales.entries.reduce((a, b) => a.value > b.value ? a : b);
    String topDailyAgent = highestSingleDaySale.key.split('-').last;
    double topDailyAgentAmount = highestSingleDaySale.value;
    Map<String, dynamic> finalStats = {
      'topAgentInvoices': topAgentInvoices,
      'topHotel': topHotel,
      'topDailyAgent': topDailyAgent,
      'topDailyAgentAmount': topDailyAgentAmount.toStringAsFixed(2),
    };

    List<Map<String, dynamic>> results = [];
    results.addAll(yearlyStats.values);
    results.addAll(monthlyStats.values);
    results.add(finalStats);

    if (results.isEmpty) {
      yield [];
    } else {
      yield results;
    }
  }

  Stream<List<Map<String, dynamic>>> _streamMonthlyBreakdown(String year) {
    return Supabase.instance.client
        .from('invoices')
        .stream(primaryKey: ['id']).map((response) {
      Map<int, List<Map<String, dynamic>>> monthlyInvoices = {};

      for (var invoice in response) {
        DateTime date = DateTime.parse(invoice['date_invoice']);
        if (date.year.toString() == year) {
          int month = date.month;
          monthlyInvoices.putIfAbsent(month, () => []).add(invoice);
        }
      }
      List<Map<String, dynamic>> monthlyData = [];
      for (int month = 1; month <= 12; month++) {
        var invoices = monthlyInvoices[month] ?? [];

        double totalAmount =
            invoices.fold(0, (sum, invoice) => sum + (invoice['amount'] ?? 0));
        Set<String> uniqueAgents =
            invoices.map((invoice) => invoice['agent_name'].toString()).toSet();

        monthlyData.add({
          'month': "Month $month",
          'amount': totalAmount,
          'total_agents': uniqueAgents.length,
          'total_invoices': invoices.length,
        });
      }
      return monthlyData;
    });
  }

  Stream<Map<String, dynamic>> _streamYearlySummary(String year) {
    return Supabase.instance.client
        .from('invoices')
        .stream(primaryKey: ['id']).map((response) {
      var filteredInvoices = response.where((invoice) {
        return invoice['date_invoice'] != null &&
            DateTime.parse(invoice['date_invoice']).year.toString() == year;
      }).toList();

      double totalAmount = 0.0;
      Set<String> uniqueAgents = {};
      int totalInvoices = filteredInvoices.length;
      Map<int, Map<String, dynamic>> monthlyData = {};

      for (int month = 1; month <= 12; month++) {
        monthlyData[month] = {
          'amount': 0.0,
          'total_agents': <String>{},
          'total_invoices': 0
        };
      }

      for (var invoice in filteredInvoices) {
        double amount = (invoice['amount'] is int)
            ? (invoice['amount'] as int).toDouble()
            : (invoice['amount'] ?? 0.0);

        String agent = invoice['agent_name'].toString();
        int month = DateTime.parse(invoice['date_invoice']).month;
        totalAmount += amount;
        uniqueAgents.add(agent);
        monthlyData[month]!['amount'] += amount;
        monthlyData[month]!['total_agents'].add(agent);
        monthlyData[month]!['total_invoices'] += 1;
      }

      monthlyData.forEach((month, data) {
        data['total_agents'] = data['total_agents'].length;
      });

      return {
        'amount': totalAmount,
        'total_agents': uniqueAgents.length,
        'total_invoices': totalInvoices,
        'monthly_data': monthlyData,
      };
    });
  }

  Widget _buildYearlyOverview() {
    if (_selectedYear == null) {
      return Center(child: Text("Please select a year"));
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _streamYearlySummary(_selectedYear.toString()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint("Error in _streamYearlySummary: ${snapshot.error}");
          return Center(
              child: Text("Failed to load yearly data\n${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          debugPrint("No data received in _streamYearlySummary");
          return Center(child: Text("Failed to load yearly data"));
        }

        var data = snapshot.data!;

        return Column(
          children: [
            _buildMonthlyBreakdownTable(_selectedYear.toString(), data),
            Text(
                "Total Amount: RM${(data['amount'] as num).toStringAsFixed(2)}"),
          ],
        );
      },
    );
  }

  Widget _buildYearlyStatCard(String title, String value) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value, style: TextStyle(fontSize: 16)),
        leading: Icon(Icons.bar_chart, color: Colors.blue),
      ),
    );
  }

  Widget _buildMonthlyBreakdownTable(
      String year, Map<String, dynamic> yearlyData) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20.0,
        columns: [
          DataColumn(label: Text('Month')),
          DataColumn(label: Text('Total Amount')),
        ],
        rows: List.generate(12, (index) {
          var monthData = yearlyData['monthly_data']?[index + 1] ?? {};
          return DataRow(cells: [
            DataCell(Text(_getMonthName(index + 1))),
            DataCell(
                Text("\$${(monthData['amount'] ?? 0).toStringAsFixed(2)}")),
          ]);
        }),
      ),
    );
  }

  String _getMonthName(int month) {
    List<String> months = [
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
      "December"
    ];
    return months[month - 1];
  }

  Widget _buildYearlyAndMonthlyStats() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _fetchSortedInvoices(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error loading data: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text("No records available."));
        }

        List<Map<String, dynamic>> _invoices = snapshot.data!;
        Map<String, String> stats =
            calculateStats(_invoices, _selectedYear, _selectedMonth);

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Invoice Insights ($_selectedYear ${_selectedMonth != null ? '(${DateFormat.MMMM().format(DateTime(0, _selectedMonth!))})' : 'Full Year'})",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              _buildStatCard(
                "Agent with Highest Sales in an invoice",
                stats['largestInvoice'] ?? 'N/A',
                stats['largestInvoiceDetails'] ?? 'N/A',
              ),
              _buildStatCard(
                "Agent with Highest Sales",
                stats['topAgentSales'] ?? 'N/A',
                stats['topAgentDetails'] ?? '',
              ),
              _buildStatCard(
                "Agent with Most Invoices",
                stats['topAgentInvoices'] ?? 'N/A',
              ),
              _buildStatCard(
                "Most Frequently Booked Hotel",
                stats['topHotel'] ?? 'N/A',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, [String? details]) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 16)),
            if (details != null)
              Text(details, style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
        leading: Icon(Icons.bar_chart, color: Colors.blue),
      ),
    );
  }

  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    List<Map<String, dynamic>> filteredInvoices =
        _getFilteredAndSortedInvoices();

    return Scaffold(
      appBar: AppBar(title: const Text("Invoice Dashboard")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "The sorting automatically fetches invoices for the current year (${_selectedYear ?? DateTime.now().year}). "
              "Use the dropdowns below for more accurate filtering by month and year.",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.justify,
            ),

            SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                DropdownButton<int>(
                  value: _selectedMonth,
                  hint: Text("Select Month"),
                  items: List.generate(12, (index) {
                    return DropdownMenuItem<int>(
                      value: index + 1,
                      child: Text(
                          DateFormat.MMMM().format(DateTime(0, index + 1))),
                    );
                  }),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedMonth = newValue;
                      });
                    }
                  },
                ),
                DropdownButton<int>(
                  value: _selectedYear,
                  hint: Text("Select Year"),
                  items: List.generate(10, (index) {
                    int year = DateTime.now().year - index;
                    return DropdownMenuItem<int>(
                      value: year,
                      child: Text(year.toString()),
                    );
                  }),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedYear = newValue;
                        _selectedMonth = null;
                      });
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 10),
            if (_currentSection == 1) ...[
              TextField(
                decoration: InputDecoration(
                  labelText: "Agent Name",
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _selectedAgentName = value.isEmpty ? null : value;
                  });
                },
              ),
            ],
            SizedBox(height: 30),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var section in [
                    {"title": "Invoice Table", "id": 1},
                    {"title": "Yearly Overview", "id": 2},
                    {"title": "Yearly Records", "id": 3}
                  ])
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            // backgroundColor: isDarkMode
                            //     ? const Color.fromARGB(115, 128, 126, 143)
                            //     : const Color.fromARGB(
                            //         255, 102, 170, 226), // Adapt color
                            elevation: _currentSection == section["id"] ? 6 : 2,
                            side: BorderSide(
                              color: _currentSection == section["id"]
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),

                            backgroundColor: _currentSection == section["id"]
                                ? (isDarkMode
                                    ? const Color.fromARGB(255, 88, 54, 182)
                                    : Colors.blueAccent)
                                : (isDarkMode
                                    ? const Color.fromARGB(115, 128, 126, 143)
                                    : const Color.fromARGB(255, 102, 170, 226)),

                            foregroundColor:
                                isDarkMode ? Colors.white : Colors.white,
                            padding: EdgeInsets.symmetric(
                                vertical: 16, horizontal: 10),
                          ),
                          onPressed: () => _changeSection(section["id"] as int),
                          child: Text(
                            section["title"] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: 30),

            // Section Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _currentSection == 1
                        ? _buildInvoiceTable()
                        : _currentSection == 2
                            ? _buildYearlyOverview()
                            : _buildYearlyAndMonthlyStats(),
                    SizedBox(height: 10),
                    if (_currentSection != 3) ...[
                      AnimatedSwitcher(
                        duration: Duration(milliseconds: 500),
                        child: isDone
                            ? Icon(Icons.check_circle,
                                color: Colors.green,
                                size: 40,
                                key: ValueKey("check"))
                            : ElevatedButton(
                                key: ValueKey("button"),
                                onPressed: isExporting ? null : initiateExport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[100],
                                  foregroundColor: Colors.black,
                                  padding: EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 20),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: AnimatedSwitcher(
                                  duration: Duration(milliseconds: 300),
                                  child: isExporting
                                      ? SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Image.asset('assets/excel_icon.png',
                                                height: 24),
                                            SizedBox(width: 8),
                                            Text("Export to Excel"),
                                          ],
                                        ),
                                ),
                              ),
                      ),
                    ],
                    SizedBox(height: 10),
                    if (exportLog.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          exportLog,
                          style: TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
