import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:invoice_app/view_invoice_page.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:invoice_app/edit_invoice_page.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:invoice_app/add_pdf_page.dart';
import 'package:intl/intl.dart';
import 'main.dart';
import 'settings_page.dart';

final String supabaseUrl = dotenv.env['SUPABASE_URL']!;
final String supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

class AgentDashboard extends StatefulWidget {
  final Function(bool) onThemeChanged;
  final bool isDarkMode; // Pass the theme change callback

  const AgentDashboard({
    Key? key,
    required this.isDarkMode,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  _AgentDashboardState createState() => _AgentDashboardState();
}

class _AgentDashboardState extends State<AgentDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  bool _isInitialLoading = true;
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;

  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> invoices = [];
  TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<Map<String, dynamic>>> _filteredInvoices =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  List<Map<String, dynamic>> _allInvoices = [];
  final ValueNotifier<String> _selectedCategory = ValueNotifier<String>("all");
  String? _userName;
  String? _userEmail;
  String? _userPhotoUrl;
  final ValueNotifier<bool> _isCategoryLoading = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isLoading = ValueNotifier(false);
  ValueNotifier<bool> _isDeleting = ValueNotifier(false);
  bool isDeleting = false;
  final List<String> _sortOptions = [
    'Date: Newest',
    'Date: Oldest',
    'Latest Invoice Numbers',
    'Oldest Invoice Numbers',
    'Customer Name A-Z',
    'Customer Name Z-A',
  ];
  String _selectedSortOption = 'Date: Newest';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _selectedCategory.value = "All";

    _fetchUserDetails().then((_) {
      _authenticateAndFetchInvoices().then((_) {
        setState(() {
          _isInitialLoading = false;
        });
      });
    });
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

  Future<void> _authenticateAndFetchInvoices() async {
    try {
      final supabase = Supabase.instance.client;

      // Sign in with Google
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        print("Google Sign-In canceled.");
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final googleAccessToken = googleAuth.idToken;

      if (googleAccessToken == null) {
        print("Failed to retrieve Google OAuth Token.");
        return;
      }
      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAccessToken,
      );

      if (response.user != null) {
        final supabaseAccessToken = response.session?.accessToken;
        if (supabaseAccessToken != null) {
          await _fetchInvoices("all");
        } else {
          print("Failed to retrieve Supabase access token.");
        }
      } else {
        print("Supabase Authentication Failed: ${response}");
      }
    } catch (e) {
      print("Authentication Error: $e");
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

  void _filterInvoices() {
    _isCategoryLoading.value = true;
    String query = _searchController.text.trim().toLowerCase();
    List<Map<String, dynamic>> filtered = _allInvoices.where((invoice) {
      String customerName = invoice['customer_name']?.toLowerCase() ?? "";
      String invoiceNo = invoice['invoice_no']?.toLowerCase() ?? "";

      bool matchesQuery = query.isEmpty ||
          customerName.contains(query) ||
          invoiceNo.contains(query);

      return matchesQuery;
    }).toList();

    // Sorting logic based on selected option
    switch (_selectedSortOption) {
      case 'Date: Newest':
        filtered.sort((a, b) => _parseDate(b['date_invoice'])
            .compareTo(_parseDate(a['date_invoice'])));
        break;
      case 'Date: Oldest':
        filtered.sort((a, b) => _parseDate(a['date_invoice'])
            .compareTo(_parseDate(b['date_invoice'])));
        break;
      case 'Latest Invoice Numbers':
        filtered.sort(
            (a, b) => (b['invoice_no'] ?? '').compareTo(a['invoice_no'] ?? ''));
        break;
      case 'Oldest Invoice Numbers':
        filtered.sort(
            (a, b) => (a['invoice_no'] ?? '').compareTo(b['invoice_no'] ?? ''));
        break;
      case 'Customer Name A-Z':
        filtered.sort((a, b) => (a['customer_name'] ?? '')
            .toLowerCase()
            .compareTo((b['customer_name'] ?? '').toLowerCase()));
        break;
      case 'Customer Name Z-A':
        filtered.sort((a, b) => (b['customer_name'] ?? '')
            .toLowerCase()
            .compareTo((a['customer_name'] ?? '').toLowerCase()));
        break;
    }

    Future.microtask(() {
      _filteredInvoices.value = filtered;
      _isCategoryLoading.value = false;
    });
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

  /// **Logout Function**
  void _logout() async {
    try {
      await GoogleSignIn().signOut();
      await _auth.signOut();
      Navigator.pushReplacementNamed(context, '/'); // Redirect to login
    } catch (e) {
      print("Logout error: $e");
    }
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

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'unpaid':
        return Colors.red; // 🔴 Urgent, needs action
      case 'paid':
        return Colors.green; // 🟢 Payment received
      case 'confirmed':
        return Colors.orange; // 🟠 Confirmed but not reviewed
      case 'reviewed':
        return Colors.blue; // 🔵 Reviewed by management
      default:
        return Colors.grey; // ❔ Unknown status
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

  Future<List<Map<String, dynamic>>> _fetchInvoices(String category) async {
    final supabase = Supabase.instance.client;
    final String? accessToken = supabase.auth.currentSession?.accessToken;

    if (accessToken == null) {
      print(
          "❌ Error: Supabase accessToken is null. User might not be logged in.");
      return [];
    }

    try {
      String url = category == "all"
          ? '$supabaseUrl/rest/v1/invoices' // No status filter for "all"
          : '$supabaseUrl/rest/v1/invoices?status=eq.$category'; // Filter by category

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'apikey': supabaseAnonKey,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        return jsonData.cast<Map<String, dynamic>>();
      } else {
        print("❌ Failed to fetch invoices: ${response.body}");
        return [];
      }
    } catch (e) {
      print("❌ Error fetching invoices: $e");
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> _streamInvoices(String category) {
    final user = supabase.auth.currentUser;
    final agentName =
        user?.userMetadata?['name']?.trim() ?? ""; // Get logged-in agent's name

    print("🟡 Debug: Logged-in Agent Name: '$agentName'");
    print("🔵 Debug: Selected Category: '$category'");

    return supabase
        .from('invoices')
        .stream(primaryKey: ['id']).map((List<Map<String, dynamic>> data) {
      print("📦 Raw Invoices from Supabase: $data");

      final filteredInvoices = data.where((invoice) {
        final nameInDB = invoice['agent_name']?.trim() ?? "";
        final statusInDB = invoice['status']?.trim().toLowerCase() ?? "";
        final nameMatches = nameInDB.toLowerCase() == agentName.toLowerCase();
        final categoryLower = category.trim().toLowerCase();
        final categoryMatches = categoryLower == "all" ||
            categoryLower.isEmpty ||
            statusInDB == categoryLower;

        if (!nameMatches) {
          print("⚠️ Name mismatch: '$nameInDB' != '$agentName'");
        }
        if (!categoryMatches) {
          print(
              "⚠️ Status mismatch: Invoice status '$statusInDB' does not match category '$category'");
        }

        return nameMatches && categoryMatches;
      }).toList();
      return filteredInvoices;
    });
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return "N/A";

    try {
      DateTime date = DateTime.parse(dateString);
      return DateFormat("d MMMM yyyy").format(date); // Example: 14 March 2024
    } catch (e) {
      return "Invalid Date";
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
      selected: _selectedCategory.value == status,
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

  Widget _buildInvoiceList(String category, String agentName) {
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

        return Stack(
          children: [
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      children: [
                        Text("Sort by:",
                            style: TextStyle(fontWeight: FontWeight.bold)),
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
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search by customer or invoice number...",
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: ValueListenableBuilder<bool>(
                        valueListenable: _isCategoryLoading,
                        builder: (context, isLoading, child) {
                          return isLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
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
                  child: ValueListenableBuilder<List<Map<String, dynamic>>>(
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
                          String? filePath;
                          if (fullPdfUrl != null && fullPdfUrl.isNotEmpty) {
                            Uri uri = Uri.parse(fullPdfUrl);
                            filePath = uri.pathSegments.last;
                          }
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
                            key: Key(invoice['invoice_no'] ??
                                invoice['id'].toString()),
                            direction: DismissDirection.none,
                            child: InkWell(
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            invoice['customer_name'] ??
                                                'Unknown Customer',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                          PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'view' &&
                                                  fullPdfUrl != null &&
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
                                              } else if (value == 'edit' &&
                                                  filePath != null &&
                                                  filePath.isNotEmpty) {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        EditInvoicePage(
                                                      documentId: invoice['id']
                                                          .toString(),
                                                      pdfUrl: fullPdfUrl,
                                                      invoice: invoice,
                                                    ),
                                                  ),
                                                );
                                              } else {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          "No PDF attached.")),
                                                );
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'view',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.visibility,
                                                        color: Colors.black54),
                                                    SizedBox(width: 10),
                                                    Text("View Invoice"),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            icon: const Icon(Icons.more_vert),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Hotel: ${invoice['hotel'] ?? 'Unknown Hotel'}",
                                        style:
                                            TextStyle(color: Colors.grey[700]),
                                      ),
                                      Text(
                                        "Invoice Date: ${_formatDate(invoice['date_invoice'])}",
                                        style:
                                            TextStyle(color: Colors.grey[700]),
                                      ),
                                      Text(
                                        "Sent: ${_formatDate(invoice['date'])}",
                                        style:
                                            TextStyle(color: Colors.grey[700]),
                                      ),
                                      Text(
                                        "Status: ${invoice['status'] ?? 'N/A'}",
                                        style: TextStyle(
                                          color: _getStatusColor(
                                              invoice['status']),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            if (isDeleting) _buildLoadingOverlay(),
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
                    "Agent Dashboard",
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
                          Color.fromARGB(255, 134, 204, 200),
                          Color.fromARGB(255, 179, 179, 181)
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
                    MaterialPageRoute(builder: (context) => AddPDFPage()),
                  );
                },
              ),
              const SizedBox(width: 5),
            ],
          ),
          drawer: Drawer(
            child: Column(
              children: [
                UserAccountsDrawerHeader(
                  accountName: Text(
                    _userName ?? "Unknown User",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  accountEmail: Text(
                    _userEmail ?? "No Email",
                    style: TextStyle(
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
                            ? Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 40,
                              )
                            : null,
                      );
                    },
                  ),
                  decoration: BoxDecoration(
                    gradient: widget.isDarkMode
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.black87,
                              Colors.blueGrey.shade900,
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue.shade900,
                              Colors.blue.shade600,
                              Colors.purple.shade500,
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
                _buildDrawerItem("All Invoices", "all"),
                _buildDrawerItem("Unpaid", "unpaid"),
                _buildDrawerItem("Paid", "paid"),
                _buildDrawerItem("Confirmed", "confirmed"),
                _buildDrawerItem("Reviewed", "reviewed"),
              ],
            ),
          ),
          body: ValueListenableBuilder<String>(
            valueListenable: _selectedCategory,
            builder: (context, isLoading, _) {
              return _buildInvoiceList(_selectedCategory.value, accessToken);
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
