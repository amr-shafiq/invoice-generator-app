import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:invoice_app/view_invoice_page.dart';
import 'package:invoice_app/sort_invoices_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:invoice_app/add_pdf_page_management.dart';
import 'package:intl/intl.dart';
import 'settings_page.dart';
import 'main.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final String supabaseUrl = dotenv.env['SUPABASE_URL']!;
final String supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

class ManagementDashboard extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isDarkMode;
  const ManagementDashboard({
    Key? key,
    required this.isDarkMode,
    required this.onThemeChanged,
  }) : super(key: key);
  @override
  _ManagementDashboardState createState() => _ManagementDashboardState();
}

class _ManagementDashboardState extends State<ManagementDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<Map<String, dynamic>>> _filteredInvoices =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  List<Map<String, dynamic>> _allInvoices = [];
  ValueNotifier<String> _selectedCategory = ValueNotifier<String>("all");
  String? _userName;
  String? _userEmail;
  String? _userPhotoUrl;
  final ValueNotifier<bool> _isCategoryLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isLoading = ValueNotifier(false);
  List<String> _categories = ["All", "Unpaid", "Paid", "Confirmed", "Reviewed"];
  ValueNotifier<bool> _isDeleting = ValueNotifier(false);
  bool _isInitialLoading = true;
  final ValueNotifier<Set<int>> _expandedInvoices = ValueNotifier<Set<int>>({});

  // Firebase Authentication
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;

  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> invoices = [];
  bool isDeleting = false;
  final List<String> _sortOptions = [
    'Date: Newest',
    'Date: Oldest',
    'Latest Invoice Numbers',
    'Oldest Invoice Numbers',
    'Agent Name A-Z',
    'Agent Name Z-A',
  ];

  String _selectedSortOption = 'Date: Newest';
  Set<int> _pinnedInvoices = {};

  @override
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _selectedCategory.value = "All";
    _fetchUserDetails().then((_) {
      setState(() {
        _isInitialLoading = false;
      });
    });
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return "N/A";

    try {
      DateTime date = DateTime.parse(dateString);
      return DateFormat("d MMMM yyyy").format(date);
    } catch (e) {
      return "Invalid Date";
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'unpaid':
        return Colors.red; // Urgent, needs action
      case 'paid':
        return Colors.green; // Payment received
      case 'confirmed':
        return Colors.orange; // Confirmed but not reviewed
      case 'reviewed':
        return Colors.blue; // Reviewed by management
      default:
        return Colors.grey; // Unknown status
    }
  }

  Future<void> _updateInvoiceStatus(String invoiceId, String newStatus) async {
    try {
      await supabase
          .from('invoices')
          .update({'status': newStatus}).match({'id': int.parse(invoiceId)});
      setState(() {});
    } catch (e) {
      print("❌ Error updating status: $e");
    }
  }

  Future<void> _updateInvoiceBookingNo(
      String invoiceId, String newBookingNo) async {
    try {
      await supabase.from('invoices').update(
          {'booking_no': newBookingNo}).match({'id': int.parse(invoiceId)});

      // Get PDF URL
      final response = await supabase
          .from('invoices')
          .select('pdf_url')
          .match({'id': int.parse(invoiceId)});
      if (response.isEmpty || response[0]['pdf_url'] == null) {
        print("❌ No PDF found for this invoice!");
        return;
      }
      String pdfUrl = response[0]['pdf_url'];

      // Download PDF
      final pdfResponse = await http.get(Uri.parse(pdfUrl));
      if (pdfResponse.statusCode != 200) {
        print("❌ Failed to download PDF from Supabase");
        return;
      }

      Uint8List pdfBytes = pdfResponse.bodyBytes;

      // Load and update the PDF
      PdfDocument document = PdfDocument(inputBytes: pdfBytes);
      final PdfForm form = document.form;
      form.setDefaultAppearance(true);

      bool bookingFieldFound = false;
      for (int i = 0; i < form.fields.count; i++) {
        final PdfField field = form.fields[i];
        if (field.name == "BOOKING_NO" && field is PdfTextBoxField) {
          field.readOnly = false;
          field.text = newBookingNo;
          bookingFieldFound = true;
        }
      }

      if (!bookingFieldFound) {
        print("❌ BOOKING_NO field not found in the form!");
      }

      final List<int> updatedBytes = document.saveSync();
      document.dispose();

      // Upload new PDF
      final Directory tempDir = await getTemporaryDirectory();
      File tempFile = File('${tempDir.path}/AMK$invoiceId.pdf');
      await tempFile.writeAsBytes(updatedBytes);
      // Delete old file first
      await supabase.storage.from('invoices').remove(['AMK$invoiceId.pdf']);
      // Upload new file
      await supabase.storage.from('invoices').upload(
            'AMK$invoiceId.pdf',
            tempFile,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );

      setState(() {});
    } catch (e) {
      print("❌ Error updating booking number in PDF: $e");
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onNavTapped(int index) {
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              SettingsPage(onThemeChanged: widget.onThemeChanged),
        ),
      );
    } else if (index == 2) {
      _confirmLogout();
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  DateTime _parseDate(dynamic date) {
    if (date is Timestamp) {
      return date.toDate();
    } else if (date is String) {
      try {
        return DateTime.parse(date);
      } catch (e) {
        print("Error parsing date: $e");
      }
    }
    return DateTime(2000, 1, 1);
  }

  void _confirmDeleteInvoice(String invoiceId, String? pdfUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          content: const Text("Are you sure you want to remove this invoice?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteInvoice(invoiceId, pdfUrl);
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteInvoice(String invoiceId, String? pdfUrl) async {
    final supabase = Supabase.instance.client;

    try {
      await supabase.from('invoices').delete().match({'id': invoiceId});

      // Delete PDF from Supabase Storage (if exist)
      if (pdfUrl != null && pdfUrl.isNotEmpty) {
        Uri uri = Uri.parse(pdfUrl);
        String? path =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;

        if (path != null) {
          await supabase.storage.from('invoices').remove([path]);
        }
      }

      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(
            "Invoice removed successfully",
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.red.shade900
              : const Color.fromARGB(255, 212, 205, 205),
          leading: Icon(
            Icons.error,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.red,
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: Text(
                "OK",
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.blue,
                ),
              ),
            ),
          ],
        ),
      );
      setState(() {});

      // Hide banner after a few seconds
      Future.delayed(Duration(seconds: 3), () {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      });
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete invoice: $error")),
      );
    }
  }

  /// **Logout Confirmation Dialog**
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Logout"),
          content: const Text("Are you sure you want to log out?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              child: const Text("Logout", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  /// **Logout Function**
  void _logout() async {
    try {
      await GoogleSignIn().signOut();
      await _auth.signOut();
      Navigator.pushReplacementNamed(context, '/');
    } catch (e) {
      print("Logout error: $e");
    }
  }

  void _filterInvoices() {
    _isCategoryLoading.value = true;
    String query = _searchController.text.toLowerCase().trim();
    List<Map<String, dynamic>> filtered = _allInvoices.where((invoice) {
      String agentName = invoice['agent_name']?.toLowerCase() ?? '';
      String customerName = invoice['customer_name']?.toLowerCase() ?? '';
      String invoiceNo = invoice['invoice_no']?.toLowerCase() ?? '';
      bool matchesQuery = query.isEmpty ||
          agentName.contains(query) ||
          customerName.contains(query) ||
          invoiceNo.contains(query);

      return matchesQuery;
    }).toList();

    // Sort based on selected option
    switch (_selectedSortOption) {
      case 'Date: Newest':
        filtered.sort(
            (a, b) => _parseDate(b['date']).compareTo(_parseDate(a['date'])));
        break;
      case 'Date: Oldest':
        filtered.sort(
            (a, b) => _parseDate(a['date']).compareTo(_parseDate(b['date'])));
        break;
      case 'Latest Invoice Numbers':
        filtered.sort(
            (a, b) => (b['invoice_no'] ?? 0).compareTo(a['invoice_no'] ?? 0));
        break;
      case 'Oldest Invoice Numbers':
        filtered.sort(
            (a, b) => (a['invoice_no'] ?? 0).compareTo(b['invoice_no'] ?? 0));
        break;
      case 'Agent Name A-Z':
        filtered.sort((a, b) => (a['agent_name'] ?? '')
            .toLowerCase()
            .compareTo((b['agent_name'] ?? '').toLowerCase()));
        break;
      case 'Agent Name Z-A':
        filtered.sort((a, b) => (b['agent_name'] ?? '')
            .toLowerCase()
            .compareTo((a['agent_name'] ?? '').toLowerCase()));
        break;
    }

    Future.microtask(() {
      _filteredInvoices.value = filtered;
      _isCategoryLoading.value = false;
    });
  }

  void _showStatusDialog(
      String invoiceId, String currentStatus, List<String> statusOptions) {
    String selectedStatus = currentStatus;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Change Invoice Status"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return DropdownButton<String>(
                value: selectedStatus,
                onChanged: (newValue) {
                  if (newValue != null) {
                    setState(() {
                      selectedStatus = newValue;
                    });
                  }
                },
                items: statusOptions.map((status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: Text(status),
                  );
                }).toList(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                await _updateInvoiceStatus(invoiceId, selectedStatus);
                Navigator.pop(context);
              },
              child: const Text("Update"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchUserDetails() async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _userName = user.displayName;
        _userEmail = user.email;
        _userPhotoUrl = user.photoURL;
      });
    }
  }

  void _showBookingNoDialog(String invoiceId, String bookingNo) {
    showDialog(
      context: context,
      builder: (context) {
        TextEditingController _controller =
            TextEditingController(text: bookingNo);

        return AlertDialog(
          title: const Text("Edit Booking Number"),
          content: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: "Enter Booking Number"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                String newBookingNo = _controller.text.trim();
                if (newBookingNo.isNotEmpty) {
                  _updateInvoiceBookingNo(invoiceId, newBookingNo);
                }
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<String> _getAccessToken() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not logged in");
      }
      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw Exception("Failed to retrieve Firebase ID Token");
      }
      return idToken;
    } catch (e) {
      print("Error fetching access token: $e");
      throw Exception("Access token fetch failed");
    }
  }

  Widget _buildLoadingOverlay() {
    return _isDeleting.value
        ? Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          )
        : SizedBox.shrink();
  }

  Stream<List<Map<String, dynamic>>> _streamInvoices(String category) {
    final user = supabase.auth.currentUser;
    final agentName = user?.userMetadata?['name']?.trim() ?? "";

    return supabase
        .from('invoices')
        .stream(primaryKey: ['id']).map((List<Map<String, dynamic>> data) {
      final filteredInvoices = data.where((invoice) {
        final statusInDB =
            invoice['status']?.toString().trim().toLowerCase() ?? "";
        final categoryLower = category.trim().toLowerCase();
        final categoryMatches = categoryLower == "all" ||
            categoryLower.isEmpty ||
            statusInDB == categoryLower;
        if (!categoryMatches) {
          print(
              "⚠️ Status mismatch: Invoice status '$statusInDB' does not match category '$category'");
        }
        return categoryMatches;
      }).toList();

      return filteredInvoices;
    });
  }

  void _loadMoreInvoices(String category) {
    if (_isCategoryLoading.value) return;
    _isCategoryLoading.value = true;
    _streamInvoices(category).listen((List<Map<String, dynamic>> newInvoices) {
      if (newInvoices.isNotEmpty) {
        setState(() {
          _filteredInvoices.value.addAll(newInvoices);
        });
      }
      _isCategoryLoading.value = false;
    }, onError: (e) {
      print('Error fetching more invoices: $e');
      _isCategoryLoading.value = false;
    });
  }

  IconData _getIconForStatus(String status) {
    switch (status) {
      case "unpaid":
        return Icons.warning_amber_rounded;
      case "paid":
        return Icons.check_circle_outline;
      case "confirmed":
        return Icons.verified;
      case "reviewed":
        return Icons.rate_review_outlined;
      case "all":
        return Icons.all_inbox;
      default:
        return Icons.filter_list;
    }
  }

  Widget _buildDrawerItem(String title, String status) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: widget.isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      leading: Icon(
        _getIconForStatus(status),
        color: widget.isDarkMode ? Colors.white : Colors.black,
      ),
      tileColor: widget.isDarkMode
          ? const Color.fromARGB(1, 0, 0, 0)
          : const Color.fromARGB(9, 255, 255, 255),
      selectedTileColor: widget.isDarkMode
          ? Colors.blueGrey[700]
          : Colors.blueAccent.withOpacity(0.2),
      selected: _selectedCategory == status,
      onTap: () {
        if (_selectedCategory.value != status) {
          _isCategoryLoading.value = true;
          _selectedCategory.value = status;

          Future.delayed(const Duration(milliseconds: 300), () {
            _isCategoryLoading.value = false;
          });
        }
        Navigator.pop(context);
      },
    );
  }

  Widget _buildInvoiceList(String category) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _streamInvoices(category),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _allInvoices.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return const Center(child: Text("No invoices available."));
        }

        if (!listEquals(_allInvoices, snapshot.data)) {
          _allInvoices = List.from(snapshot.data ?? []);

          Future.microtask(() {
            _filterInvoices();
          });
        }

        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Sort by:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _selectedSortOption,
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedSortOption = newValue;
                          });
                          _filterInvoices();
                        }
                      },
                      items: _sortOptions.map((option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Search by customer or invoice number...",
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  suffixIcon: ValueListenableBuilder<bool>(
                    valueListenable: _isCategoryLoading,
                    builder: (context, isLoading, child) {
                      return isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                if (_searchController.text.isNotEmpty) {
                                  _searchController.clear();
                                }
                                _filterInvoices();
                              },
                            );
                    },
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) => _filterInvoices(),
                onSubmitted: (value) async {
                  _isCategoryLoading.value = true;
                  await Future.microtask(() => _filterInvoices());
                  _isCategoryLoading.value = false;
                },
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: _filteredInvoices,
                    builder: (context, displayedInvoices, child) {
                      if (_isCategoryLoading.value) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (displayedInvoices.isEmpty) {
                        return const Center(child: Text("No invoices found"));
                      }

                      return ListView.builder(
                        itemCount: displayedInvoices.length,
                        itemBuilder: (context, index) {
                          var invoice = displayedInvoices[index];
                          String? fullPdfUrl = invoice['pdf_url'];

                          List<String> statusOptions = [
                            "Pending",
                            "Unpaid",
                            "Paid",
                            "Confirmed",
                            "Reviewed"
                          ];
                          String currentStatus =
                              statusOptions.contains(invoice['status'])
                                  ? invoice['status']
                                  : "Pending";

                          return Dismissible(
                            key: Key(invoice['id'].toString()),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              margin: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            confirmDismiss: (_) async {
                              return await showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Confirm Delete"),
                                  content: const Text(
                                      "Are you sure you want to remove this invoice?"),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text("Cancel"),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text("Delete",
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onDismissed: (_) async {
                              setState(() {
                                isDeleting = true;
                              });

                              await _deleteInvoice(
                                  invoice['id'].toString(), invoice['pdf_url']);

                              setState(() {
                                isDeleting = false;
                                displayedInvoices.removeAt(index);
                              });
                            },
                            child: ValueListenableBuilder<Set<int>>(
                              valueListenable: _expandedInvoices,
                              builder: (context, expandedIndices, _) {
                                final isExpanded =
                                    expandedIndices.contains(index);

                                return Card(
                                  elevation: 3,
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      final updated =
                                          Set<int>.from(expandedIndices);
                                      if (updated.contains(index)) {
                                        updated.remove(index);
                                      } else {
                                        updated.add(index);
                                      }
                                      _expandedInvoices.value = updated;
                                    },
                                    onLongPress: () {
                                      _confirmDeleteInvoice(
                                          invoice['id'].toString(),
                                          invoice['pdf_url']);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedSize(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                      child: Padding(
                                        padding: const EdgeInsets.all(5),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              invoice['agent_name'] ??
                                                  'Unknown',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Invoice Number: ${invoice['invoice_no'] ?? 'N/A'}",
                                              style: TextStyle(
                                                  color: Colors.grey[700]),
                                            ),
                                            if (isExpanded) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                "Invoice Date: ${_formatDate(invoice['date_invoice'])}",
                                                style: TextStyle(
                                                    color: Colors.grey[700]),
                                              ),
                                              Text(
                                                "Uploaded by: ${invoice['uploaded_by'] ?? 'N/A'}",
                                                style: TextStyle(
                                                    color: Colors.grey[700]),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _getStatusColor(
                                                          invoice['status'])
                                                      .withOpacity(0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  "Status: ${invoice['status'] ?? 'N/A'}",
                                                  style: TextStyle(
                                                    color: _getStatusColor(
                                                        invoice['status']),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                "Booking No: ${invoice['booking_no'] ?? 'Not Assigned'}",
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              const SizedBox(height: 6),
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton.icon(
                                                  onPressed: () {
                                                    if (fullPdfUrl != null &&
                                                        fullPdfUrl.isNotEmpty) {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (context) =>
                                                              ViewInvoicePage(
                                                            pdfUrl: fullPdfUrl,
                                                            invoiceNumber: invoice[
                                                                    'invoice_no'] ??
                                                                'Unknown',
                                                          ),
                                                        ),
                                                      );
                                                    } else {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                              "No PDF attached."),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                      Icons.picture_as_pdf),
                                                  label: const Text("View PDF"),
                                                ),
                                              ),
                                              DropdownButtonFormField<String>(
                                                value: currentStatus,
                                                onChanged: (newStatus) {
                                                  if (newStatus != null) {
                                                    _updateInvoiceStatus(
                                                      invoice['id'].toString(),
                                                      newStatus,
                                                    );
                                                  }
                                                },
                                                decoration:
                                                    const InputDecoration(
                                                  labelText: "Change Status",
                                                  border: OutlineInputBorder(),
                                                ),
                                                items:
                                                    statusOptions.map((status) {
                                                  return DropdownMenuItem(
                                                    value: status,
                                                    child: Text(status),
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Icon(
                                                isExpanded
                                                    ? Icons.keyboard_arrow_up
                                                    : Icons.keyboard_arrow_down,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                  if (isDeleting) _buildLoadingOverlay(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getAccessToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Text("Failed to fetch access token."),
            ),
          );
        }
        String accessToken = snapshot.data!;
        return Scaffold(
          appBar: AppBar(
            iconTheme: IconThemeData(
              color: widget.isDarkMode ? Colors.white : Colors.black,
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    "Management Dashboard",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 18,
                      color: widget.isDarkMode ? Colors.white : Colors.black,
                      letterSpacing: 0.8,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.transparent,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.isDarkMode
                      ? [Colors.blueGrey[900]!, Colors.black]
                      : [
                          Colors.purple.shade200,
                          Colors.blue.shade300,
                          Colors.blue.shade200,
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            elevation: 4,
            actions: [
              IconButton(
                icon: Icon(Icons.upload_file,
                    color: widget.isDarkMode ? Colors.white : Colors.black),
                tooltip: "Upload Invoice PDF",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => AddPDFPageManagement()),
                  );
                },
              ),
              const SizedBox(width: 5),
            ],
          ),
          drawer: Drawer(
            child: ListView(
              children: [
                UserAccountsDrawerHeader(
                  accountName: Text(
                    _userName ?? "Unknown User",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  accountEmail: Text(
                    _userEmail ?? "No Email",
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                  currentAccountPicture: FutureBuilder(
                    future: firebase_auth.FirebaseAuth.instance
                        .authStateChanges()
                        .first,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircleAvatar(
                          child: CircularProgressIndicator(),
                        );
                      }
                      firebase_auth.User? user =
                          firebase_auth.FirebaseAuth.instance.currentUser;
                      return CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.transparent,
                        backgroundImage: user?.photoURL != null
                            ? NetworkImage(user!.photoURL!)
                            : null,
                        child: user?.photoURL == null
                            ? const Icon(Icons.person,
                                color: Colors.white, size: 40)
                            : null,
                      );
                    },
                  ),
                  decoration: BoxDecoration(
                    gradient: widget.isDarkMode
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.black87, Colors.blueGrey.shade900],
                          )
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade900,
                              Colors.blue.shade600,
                              Colors.purple.shade500
                            ],
                          ),
                    image: DecorationImage(
                      image: AssetImage(
                        widget.isDarkMode
                            ? "assets/travel_night.jpg"
                            : "assets/travel_day.jpg",
                      ),
                      fit: BoxFit.cover,
                      opacity: 0.3,
                    ),
                  ),
                ),
                ExpansionTile(
                  title: const Text("Invoice List"),
                  leading: const Icon(Icons.list),
                  children: [
                    _buildDrawerItem("All Invoices", "all"),
                    _buildDrawerItem("Unpaid", "unpaid"),
                    _buildDrawerItem("Paid", "paid"),
                    _buildDrawerItem("Confirmed", "confirmed"),
                    _buildDrawerItem("Reviewed", "reviewed"),
                  ],
                ),
                ListTile(
                  title: const Text("Sort Invoices"),
                  leading: const Icon(Icons.sort),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => SortInvoicesPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          body: ValueListenableBuilder<String>(
            valueListenable: _selectedCategory,
            builder: (context, isLoading, _) {
              return _buildInvoiceList(_selectedCategory.value);
            },
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onNavTapped,
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long), label: "Invoices"),
              BottomNavigationBarItem(
                  icon: Icon(Icons.settings), label: "Settings"),
              BottomNavigationBarItem(
                  icon: Icon(Icons.logout), label: "Logout"),
            ],
          ),
        );
      },
    );
  }
}
