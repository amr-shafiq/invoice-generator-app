import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:invoice_app/services/auth_service.dart';

// Store the generated PDF file
File? _pdfFile;
Timer? _debounce;
bool _isLoading = false;

class AddPDFPageManagement extends StatefulWidget {
  @override
  _AddPDFPageState createState() => _AddPDFPageState();
}

class _AddPDFPageState extends State<AddPDFPageManagement> {
  final SupabaseService _supabaseService = SupabaseService();
  final supabase = Supabase.instance.client;
  bool _hasPreviewed = false;
  String initialStatus = "Pending"; // Default status when uploading a PDF
  String? userRole;
  final AuthService _authService = AuthService();
  String? selectedBreakfast;
  // String? agentName;
  String? userEmail;
  String? agentName = "Loading...";
  double hideIfZero(double? value) {
    return (value ?? 0) == 0 ? 0 : value!;
  }

  bool _hasUserEditedRemarks = false;
  bool _hasUserEditedAddOn = false;
  bool _hasUserEditedBreakfast = false;
  bool _hasUserEditedQuantityRoom = false;
  bool _hasUserEditedAgentEmail = false;
  bool _invoiceNumberTypedManually = false;
  bool isNewInvoice = false;
  bool _isUpdatingPDF = false;
  String _lastFetchedInvoiceNo = '';

  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);
  bool _isInvoiceNumberFetched = false;
  bool isUsingAutoFetch = false;
  bool _isManuallySettingInvoiceNumber = false;
  bool success = true;

  void _onTextChanged() {
    if (_debounce?.isActive ?? false) {
      _debounce?.cancel(); // Cancel the previous timer
    }

    // Start a new timer
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _updatePDFPreview(); // Call the preview function after 500ms of inactivity
    });
  }

  String _formatDateForDisplay(dynamic dateValue) {
    try {
      DateTime dateTime;

      if (dateValue is int) {
        // Convert timestamp (milliseconds since epoch) to DateTime
        dateTime = DateTime.fromMillisecondsSinceEpoch(dateValue);
      } else if (dateValue is String) {
        if (dateValue.contains('T')) {
          // Convert ISO 8601 string to DateTime
          dateTime = DateTime.parse(dateValue);
        } else if (dateValue.contains('/')) {
          // Convert dd/MM/yyyy to yyyy-MM-dd
          List<String> parts = dateValue.split('/');
          if (parts.length == 3) {
            dateTime = DateTime.parse("${parts[2]}-${parts[1]}-${parts[0]}");
          } else {
            throw FormatException("Invalid date format");
          }
        } else {
          dateTime = DateTime.parse(dateValue);
        }
      } else {
        throw FormatException("Unsupported date format");
      }

      return DateFormat('dd/MM/yyyy').format(dateTime);
    } catch (e) {
      print("Error parsing date for display: $e");
      return "";
    }
  }

  void _debouncedUpdatePDFPreview() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || _isUpdatingPDF) return;
      _isUpdatingPDF = true;
      await _updatePDFPreview();
      _isUpdatingPDF = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    fetchAgentNameFromFirestore(agentName);
    fetchAndSetAgentName();

    List<TextEditingController> controllers = [
      _fullNameController,
      _invoiceNoController,
      _dateInvoiceController,
      checkInController,
      checkOutController,
      _hotelController,
      _roomTypeController,
      roomRateController,
      _breakfastController,
      _quantityRoomController,
      balanceDueController,
      _bankTransferController,
      amountController,
      totalAmountController,
      paymentController,
      balanceController,
      _agentController,
      agentEmailController,
      RoleController,
      bookingNoController,
      DatelineController,
      _AddOnController,
      _RemarkController,
      statusController,
      surchargeController,
    ];

    for (var controller in controllers) {
      controller.addListener(() {
        if (mounted) {
          _debouncedUpdatePDFPreview(); // 🔥 Updates preview in real time
        }
      });
    }
  }

  void _clearFields() {
    // Clear fields only when invoice number is cleared
    _fullNameController.clear();
    _hotelController.clear();
    _roomTypeController.clear();
    _breakfastController.clear();
    _agentController.clear();
    checkInController.clear();
    checkOutController.clear();
    _quantityRoomController.clear();
    DatelineController.clear();
    _AddOnController.clear();
    _RemarkController.clear();
    _dateInvoiceController.clear();
    agentEmailController.clear();
    RoleController.clear();
    bookingNoController.clear();
    statusController.clear();
    surchargeController.clear();
  }

  void _populateFieldsWithInvoiceDetails(Map<String, dynamic> invoiceDetails) {
    _fullNameController.text = invoiceDetails['customer_name'] ?? "";
    _hotelController.text = invoiceDetails['hotel'] ?? "";
    _roomTypeController.text = invoiceDetails['room_type'] ?? "";
    // Only fill these fields if they haven't been manually cleared by the user
    if (!_hasUserEditedBreakfast && _breakfastController.text.isEmpty) {
      _breakfastController.text = invoiceDetails['breakfast'] ?? "No";
    }
    _agentController.text = invoiceDetails['agent_name'] ?? "";
    checkInController.text = _formatDate(invoiceDetails['check_in'] ?? "");
    checkOutController.text = _formatDate(invoiceDetails['check_out'] ?? "");
    if (!_hasUserEditedQuantityRoom && _quantityRoomController.text.isEmpty) {
      _quantityRoomController.text =
          invoiceDetails['quantity_room']?.toString() ?? "";
    }
    DatelineController.text = _formatDate(invoiceDetails['dateline'] ?? "");
    if (!_hasUserEditedAddOn && _AddOnController.text.isEmpty) {
      _AddOnController.text = invoiceDetails['add_on'] ?? "";
    }
    if (!_hasUserEditedRemarks && _RemarkController.text.isEmpty) {
      _RemarkController.text = invoiceDetails['remarks'] ?? "";
    }
    _dateInvoiceController.text =
        _formatDateForDisplay(invoiceDetails['date_invoice'] ?? "");
    if (!_hasUserEditedAgentEmail && agentEmailController.text.isEmpty) {
      agentEmailController.text = invoiceDetails['agent_email'] ?? "";
    }
    roomRateController.text =
        (invoiceDetails['room_rate'] as num?)?.toString() ?? "";
    amountController.text =
        (invoiceDetails['amount'] as num?)?.toString() ?? "";
    totalAmountController.text =
        (invoiceDetails['total_amount'] as num?)?.toString() ?? "";
    balanceController.text =
        (invoiceDetails['balance'] as num?)?.toString() ?? "";
    balanceDueController.text =
        (invoiceDetails['balance_due'] as num?)?.toString() ?? "";
    paymentController.text =
        (invoiceDetails['payment'] as num?)?.toString() ?? "";

    _bankTransferController.text =
        _formatDate(invoiceDetails['transfer_date'] ?? "");
    surchargeController.text = invoiceDetails['surcharge']?.toString() ?? "";
    RoleController.text = invoiceDetails['role'] ?? "";
  }

  void _showErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content:
            const Text("Failed to fetch invoice details. Please try again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showErrorUpload(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: const Text("Failed to upload invoice. Please try again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // ✅ Remove listeners and dispose controllers
    List<TextEditingController> controllers = [
      _fullNameController,
      _invoiceNoController,
      _dateInvoiceController,
      _hotelController,
      _roomTypeController,
      checkInController,
      checkOutController,
      roomRateController,
      _breakfastController,
      agentEmailController,
      RoleController,
      _quantityRoomController,
      balanceDueController,
      amountController,
      _agentController,
      totalAmountController,
      paymentController,
      balanceController,
      _bankTransferController,
      bookingNoController,
      DatelineController,
      _AddOnController,
      _RemarkController,
      statusController,
      surchargeController,
    ];

    roomRateController.removeListener(_updatePDFPreview);
    _quantityRoomController.removeListener(_updatePDFPreview);
    surchargeController.removeListener(_updatePDFPreview);
    paymentController.removeListener(_updatePDFPreview);

    for (var controller in controllers) {
      controller.dispose();
    }
    _debounce?.cancel();

    super.dispose();
  }

  // Controllers for user inputs
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _invoiceNoController = TextEditingController();
  final TextEditingController _dateInvoiceController = TextEditingController();
  final TextEditingController _hotelController = TextEditingController();
  final TextEditingController _roomTypeController = TextEditingController();
  final TextEditingController checkInController = TextEditingController();
  final TextEditingController checkOutController = TextEditingController();
  final TextEditingController _bankTransferController = TextEditingController();
  final TextEditingController paxController = TextEditingController();
  final TextEditingController roomRateController = TextEditingController();
  final TextEditingController _breakfastController = TextEditingController();
  final TextEditingController _quantityRoomController = TextEditingController();
  final TextEditingController balanceDueController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController _agentController = TextEditingController();
  final TextEditingController totalAmountController = TextEditingController();
  final TextEditingController paymentController = TextEditingController();
  final TextEditingController balanceController = TextEditingController();
  final TextEditingController bookingNoController = TextEditingController();
  final TextEditingController DatelineController = TextEditingController();
  final TextEditingController _AddOnController = TextEditingController();
  final TextEditingController _RemarkController = TextEditingController();
  final TextEditingController statusController = TextEditingController();
  final TextEditingController agentEmailController = TextEditingController();
  final TextEditingController RoleController = TextEditingController();
  final TextEditingController surchargeController = TextEditingController();

  File? _pdfFile; // Store the latest generated PDF

  Future<String?> fetchAgentNameFromFirestore(String? userEmail) async {
    if (userEmail == null) return null;

    var querySnapshot = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: userEmail) // Query by email instead
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      return querySnapshot.docs.first.data()["agent_name"];
    }
    return null;
  }

  void _showCustomDialog(BuildContext context,
      {required String title, required String message}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void fetchAndSetAgentName() async {
    String? userEmail = supabase.auth.currentUser?.email;
    if (userEmail != null) {
      String? name = await fetchAgentNameFromFirestore(userEmail);
      setState(() {
        agentName = name ?? "Unknown"; // Update the displayed name
      });
    }
  }

  Future<void> _fetchUserRole() async {
    String? email = firebase_auth.FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;

    Map<String, String>? roleData = await _authService.checkUserRole(email);
    if (roleData != null) {
      setState(() {
        userRole = roleData["role"]; // 🔹 Update state with user role
      });
    }
  }

  String formatNumber(double? value) {
    if (value == null) return "0.00"; // Default to 0.00 if value is null
    return value.toStringAsFixed(2); // Format to 2 decimal places
  }

  Future<void> fetchInvoiceDetails(String invoiceNumber) async {
    if (_isInvoiceNumberFetched) return;

    try {
      // Step 1: Try to fetch agent invoice firs

      final agentInvoice = await supabase
          .from('invoices')
          .select()
          .eq('invoice_no', invoiceNumber)
          .eq('role', 'agent')
          .order('date', ascending: false)
          .limit(1);

      final agentInvoiceList =
          agentInvoice.isNotEmpty ? agentInvoice.first : null;

      if (agentInvoiceList != null) {
        print("✅ Fetched Agent Invoice Details: $agentInvoice");

        _prefillInvoiceForm(agentInvoiceList);
        return;
      }

      // Step 2: No agent invoice found, check if management one exists
      final managementInvoice = await supabase
          .from('invoices')
          .select()
          .eq('invoice_no', invoiceNumber)
          .eq('role', 'management')
          .order('date', ascending: false)
          .limit(1);

      final managementInvoiceList =
          managementInvoice.isNotEmpty ? managementInvoice.first : null;

      if (managementInvoiceList != null) {
        print("⚠️ Fetched Management Invoice instead: $managementInvoice");

        _showCustomDialog(
          context,
          title: "Management Invoice Detected",
          message:
              "This invoice was uploaded by a management team member, possibly on behalf of an agent who couldn’t access the app.\n\n"
              "You can continue editing this version if appropriate.",
        );

        _prefillInvoiceForm(managementInvoiceList); // ✅ Reuse helper
        return;
      }

      // Step 3: No invoice found at all
      print("❌ No invoice found at all for $invoiceNumber");
      _showCustomDialog(
        context,
        title: "Invoice Not Found",
        message:
            "No invoice exists with this number. Please check for typos or use a valid invoice number.",
      );
    } catch (e) {
      print("🚨 Error fetching invoice: $e");
      _showErrorDialog(context);
    }
  }

  void _prefillInvoiceForm(Map<String, dynamic> invoiceDetails) {
    _fullNameController.text = invoiceDetails['customer_name'] ?? "";
    _hotelController.text = invoiceDetails['hotel'] ?? "";
    _roomTypeController.text = invoiceDetails['room_type'] ?? "";

    if (!_hasUserEditedBreakfast) {
      _breakfastController.text = invoiceDetails['breakfast'] ?? "No";
    }
    _agentController.text = invoiceDetails['agent_name'] ?? "";
    checkInController.text = _formatDate(invoiceDetails['check_in'] ?? "");
    checkOutController.text = _formatDate(invoiceDetails['check_out'] ?? "");
    if (!_hasUserEditedQuantityRoom) {
      _quantityRoomController.text =
          invoiceDetails['quantity_room']?.toString() ?? "";
    }

    balanceController.text = invoiceDetails['balance']?.toString() ?? "";
    balanceDueController.text =
        (invoiceDetails['balance_due'] as num?)?.toString() ?? "";
    amountController.text =
        (invoiceDetails['amount'] as num?)?.toString() ?? "";
    totalAmountController.text =
        (invoiceDetails['total_amount'] as num?)?.toString() ?? "";
    roomRateController.text =
        (invoiceDetails['room_rate'] as num?)?.toString() ?? "";
    paymentController.text =
        (invoiceDetails['payment'] as num?)?.toString() ?? "";
    surchargeController.text =
        (invoiceDetails['surcharge'] as num?)?.toString() ?? "";
    DatelineController.text = _formatDate(invoiceDetails['dateline'] ?? "");

    _bankTransferController.text =
        _formatDate(invoiceDetails['transfer_date'] ?? "");
    if (!_hasUserEditedAddOn) {
      _AddOnController.text = invoiceDetails['add_on'] ?? "";
    }
    if (!_hasUserEditedRemarks) {
      _RemarkController.text = invoiceDetails['remarks'] ?? "";
    }
    _dateInvoiceController.text =
        _formatDateForDisplay(invoiceDetails['date_invoice'] ?? "");
    if (!_hasUserEditedAgentEmail) {
      agentEmailController.text = invoiceDetails['agent_email'] ?? "";
    }

    setState(() {
      _isInvoiceNumberFetched = true;
    });

    isUsingAutoFetch = false;
    _invoiceNumberTypedManually = false;
  }

  void prefillInvoiceFields(Map<String, dynamic> invoiceData) {
    _fullNameController.text = invoiceData['customer_name'] ?? '';
    _hotelController.text = invoiceData['hotel'] ?? '';
    _roomTypeController.text = invoiceData['room_type'] ?? '';
    _agentController.text = invoiceData['agent_name'] ?? '';
    _RemarkController.text = invoiceData['remarks'] ?? '';
    checkInController.text = invoiceData['check_in'] ?? '';
    checkOutController.text = invoiceData['check_out'] ?? '';
    _AddOnController.text = invoiceData['add_on'] ?? '';
    _breakfastController.text = invoiceData['breakfast'] ?? '';
    _quantityRoomController.text = invoiceData['quantity_room'] ?? '';
    DatelineController.text = invoiceData['dateline'] ?? '';
    agentEmailController.text = invoiceData['agent_email'] ?? '';
    roomRateController.text = invoiceData['room_rate'] ?? '';
    surchargeController.text = invoiceData['surcharge'] ?? '';
    // RoleController = invoiceData['role'] ?? '';

    // Handle date parsing
    if (invoiceData['check_in'] != null) {
      _checkInDate = DateTime.tryParse(invoiceData['check_in']);
    }

    if (invoiceData['check_out'] != null) {
      _checkOutDate = DateTime.tryParse(invoiceData['check_out']);
    }
  }

  void _showErrorPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: const Text("Storage permission denied. Please try again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<File> fillInvoiceTemplate(
      {required String customerName,
      required String invoiceNo, // Now a string
      required DateTime dateInvoice,
      required String hotel,
      required String roomType,
      required DateTime checkInDate,
      required DateTime checkOutDate,
      required DateTime bankTransfer,
      required String roomRate,
      required String breakfast,
      required int quantityRoom,
      required String balanceDue,
      required String amount,
      required String agentName1,
      required String totalAmount,
      required String payment,
      required String balance,
      required int? bookingNo,
      required int? surcharge,
      required DateTime dateline,
      required String addOn,
      required String remarks,
      required String status,
      required String agentEmail,
      required String role}) async {
    final ByteData data =
        await rootBundle.load("assets/INVB3758_word_fillable.pdf");
    final List<int> bytes = data.buffer.asUint8List();
    sf.PdfDocument document = sf.PdfDocument(inputBytes: bytes);

    final sf.PdfForm form = document.form;
    // form.setDefaultAppearance(true);

    form.setDefaultAppearance(false);

    // ✅ Format dates properly
    String formattedInvoiceDate = DateFormat('dd/MM/yyyy').format(dateInvoice);
    String formattedBankTransfer =
        DateFormat('dd/MM/yyyy').format(bankTransfer);
    String formattedCheckInDate = DateFormat('d MMMM yyyy').format(checkInDate);
    String formattedCheckOutDate =
        DateFormat('d MMMM yyyy').format(checkOutDate);
    String formattedDateline = DateFormat('d MMMM yyyy').format(dateline);

    final Map<String, dynamic> fields = {
      "CUSTOMER_NAME": customerName,
      "INVOICE_NO": invoiceNo, // Use the generated invoice number
      "DATE": formattedInvoiceDate,
      "BANK_TRANSFER": formattedBankTransfer,
      "HOTEL_NAME": hotel,
      "ROOM_TYPE": roomType,
      "CHECK_IN": formattedCheckInDate,
      "CHECK_OUT": formattedCheckOutDate,
      "ROOM_RATE": roomRate,
      "BREAKFAST_OR_NO": breakfast,
      "QUANTITY": quantityRoom.toString(),
      "BALANCE_DUE": balanceDue.toString(),
      "AMOUNT": amount.toString(),
      "AGENT_NAME": agentName1,
      "TOTAL": totalAmount.toString(),
      "PAYMENT": payment.toString(),
      "BALANCE": balance.toString(),
      "BOOKING_NO": bookingNo ?? "Pending Verification",
      "DATELINE": formattedDateline,
      "ADD_ON": addOn,
      "REMARKS": remarks,
    };

    for (int i = 0; i < form.fields.count; i++) {
      final sf.PdfField field = form.fields[i];
      if (fields.containsKey(field.name) && field is sf.PdfTextBoxField) {
        field.text = fields[field.name].toString();
        if (["ROOM_RATE", "QUANTITY", "AMOUNT", "TOTAL", "PAYMENT", "BALANCE"]
            .contains(field.name)) {
          field.textAlignment = sf.PdfTextAlignment.center;
        }
      }
    }

    final List<int> updatedBytes = document.saveSync();
    document.dispose();

    final output = await getTemporaryDirectory();
    _pdfFile = File(
        "${output.path}/AMK$invoiceNo.pdf"); // 🔥 Use invoiceNo as filename
    await _pdfFile!.writeAsBytes(updatedBytes);

    return _pdfFile!;
  }

  Future<Map<String, dynamic>?> fetchInvoiceByNumber(String invoiceNo) async {
    final invoiceNumber = invoiceNo.toUpperCase();

    // Try to fetch agent invoice first
    final agentInvoiceResponse = await supabase
        .from('invoices')
        .select()
        .eq('invoice_no', invoiceNumber)
        .eq('role', 'agent') // Filter by agent
        .limit(1)
        .maybeSingle();

    if (agentInvoiceResponse != null) {
      print("✅ Found Agent Invoice: $agentInvoiceResponse");
      return agentInvoiceResponse; // Return the agent invoice if found
    }

    // If no agent invoice is found, try to fetch management invoice
    final managementInvoiceResponse = await supabase
        .from('invoices')
        .select()
        .eq('invoice_no', invoiceNumber)
        .eq('role', 'management') // Filter by management
        .limit(1)
        .maybeSingle();

    if (managementInvoiceResponse != null) {
      print("⚠️ Found Management Invoice: $managementInvoiceResponse");
      return managementInvoiceResponse; // Return the management invoice if found
    }

    // If no invoice is found for the provided invoice number
    print("❌ No invoice found for invoice number: $invoiceNumber");
    return null;
  }

  String _formatDate(String? date) {
    if (date == null) return "";
    DateTime parsedDate = DateTime.tryParse(date) ?? DateTime.now();
    return DateFormat('dd/MM/yyyy').format(parsedDate);
  }

  Future<String> generateUniqueInvoiceNumber() async {
    // Fetch only invoices belonging to the current agent
    final response = await supabase.from('invoices').select('invoice_no');
    // .eq('agent_name', agentName); // ✅ Filter by agent_name

    if (response.isEmpty) {
      return "00001"; // ✅ Start fresh if no invoice exists for this agent
    }

    // Extract only valid "ZZZZZ" format invoices
    List<String> validInvoices = response
        .map<String>((row) => row['invoice_no'] as String)
        .where((no) => _isFiveCharFormat(no)) // ✅ Only accept 5-char format
        .toList();

    // ✅ If no valid invoice is found, start at "00001"
    if (validInvoices.isEmpty) {
      return "00001";
    }

    // Sort invoices in descending order and pick the latest one
    validInvoices.sort((a, b) => b.compareTo(a));
    String latestInvoice = validInvoices.first;

    return _incrementFiveCharInvoice(latestInvoice);
  }

// 🔹 Function to check if an invoice follows the "ZZZZZ" pattern
  bool _isFiveCharFormat(String invoiceNo) {
    return RegExp(r'^[\dA-Z]{5}$').hasMatch(invoiceNo);
  }

// 🔹 Increment "ZZZZZ" format invoice number (Digits + Letters)
  String _incrementFiveCharInvoice(String currentNo) {
    List<int> charCodes = List<int>.from(currentNo.codeUnits);

    for (int i = charCodes.length - 1; i >= 0; i--) {
      int charCode = charCodes[i];

      if (charCode == 57) {
        // '9' → 'A'
        charCodes[i] = 65;
        break;
      } else if (charCode == 90) {
        // 'Z' → '0' (rollover)
        charCodes[i] = 48;
      } else {
        charCodes[i] = charCode + 1; // Normal increment
        return String.fromCharCodes(charCodes);
      }
    }

    return String.fromCharCodes(charCodes);
  }

  DateTime parseDate(String? dateString) {
    if (dateString == null || dateString.trim().isEmpty) return DateTime.now();

    try {
      if (dateString.contains('/')) {
        // Handle dd/MM/yyyy format
        List<String> parts = dateString.split('/');
        if (parts.length == 3) {
          return DateTime.parse("${parts[2]}-${parts[1]}-${parts[0]}");
        }
      } else if (dateString.contains('-')) {
        // Handle YYYY-MM-DD or full timestamp format
        return DateTime.parse(dateString);
      }
    } catch (e) {
      print("Error parsing date to DateTime: $e");
    }

    return DateTime.now(); // Default to now if parsing fails
  }

  String? formatDate(String dateString) {
    if (dateString.trim().isEmpty) return null; // ✅ Return null if empty
    try {
      DateFormat inputFormat = DateFormat("dd/MM/yyyy"); // ✅ Your format
      DateFormat outputFormat = DateFormat("yyyy-MM-dd"); // ✅ PostgreSQL format
      DateTime parsedDate = inputFormat.parse(dateString);
      return outputFormat.format(parsedDate); // ✅ Convert to "YYYY-MM-DD"
    } catch (e) {
      print("Error parsing date: $e");
      return null; // ✅ Return null if parsing fails
    }
  }

  String _formatDateForUpload(String dateString) {
    try {
      // Parse the date string (assuming it's in dd/MM/yyyy format)
      DateTime dateTime = DateFormat('dd/MM/yyyy').parse(dateString);
      // Format the date as ISO 8601 for upload
      return dateTime.toIso8601String();
    } catch (e) {
      print("Error parsing date for upload: $e");
      return ""; // Return an empty string if parsing fails
    }
  }

  Future<void> _downloadPDF() async {
    String invoiceNumber = await generateUniqueInvoiceNumber();
    if (_pdfFile == null || !await _pdfFile!.exists()) {
      print("❌ Error: _pdfFile is null or does not exist!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No PDF available to download!")),
      );
      return;
    }

    // ✅ Request permissions for Android 10+ (Scoped Storage)
    if (Platform.isAndroid) {
      final PermissionStatus status = await Permission.storage.request();

      if (status.isDenied || status.isPermanentlyDenied) {
        _showErrorPermissionDialog(context);
        return;
      }
    }

    String? outputPath;

    if (Platform.isAndroid) {
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: "Save Invoice PDF",
        fileName: "Invoice_${invoiceNumber}.pdf",
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } else if (Platform.isIOS) {
      final Directory directory = await getApplicationDocumentsDirectory();
      outputPath = '${directory.path}/Invoice_${invoiceNumber}.pdf';
    }

    if (outputPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("File path is invalid.")),
      );
      return;
    }

    try {
      // ✅ Explicitly read bytes from _pdfFile
      Uint8List bytes = await _pdfFile!.readAsBytes();

      File savedFile = File(outputPath);
      await savedFile.writeAsBytes(bytes);
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(
            "PDF saved successfully at $outputPath",
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.red.shade900 // Darker red for dark mode
              : const Color.fromARGB(
                  255, 212, 205, 205), // Lighter red for light mode
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
      Future.delayed(Duration(seconds: 3), () {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      });
    } catch (e) {
      _showErrorDialog(context);
    }
  }

  Future<String> getAgentNameFromFirestore(String userEmail) async {
    try {
      // Reference to the "users" collection
      CollectionReference usersRef =
          FirebaseFirestore.instance.collection('users');

      // Query Firestore where the email matches the logged-in user's email
      QuerySnapshot querySnapshot =
          await usersRef.where('email', isEqualTo: userEmail).get();

      if (querySnapshot.docs.isNotEmpty) {
        // Get the first matching document and extract `agent_name`
        var userData = querySnapshot.docs.first.data() as Map<String, dynamic>;
        return userData['agent_name'] ?? "Unknown Agent";
      } else {
        return "Unknown Agent"; // No matching user found
      }
    } catch (e) {
      print("Error fetching agent name: $e");
      return "Unknown Agent";
    }
  }

  bool isConfirmedInvoice(String invoiceNumber) {
    // Ensure it's not an invoice currently being created
    return invoiceNumber.startsWith("INV") ||
        int.tryParse(invoiceNumber) == null;
  }

  bool _validateFields() {
    List<TextEditingController> requiredControllers = [
      amountController,
      balanceController,
      balanceDueController,
      roomRateController,
      DatelineController,
      totalAmountController,
      paymentController,
    ];

    // if (userRole == 'management') {
    //   requiredControllers.add(bookingNoController);
    // }

    for (var controller in requiredControllers) {
      if (controller.text.trim().isEmpty) {
        return false; // If any required field is empty, return false
      }
    }

    return true; // All fields are filled
  }

  void _showStatusDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: const Text("Please enter a valid invoice number."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadPDF(String oldInvoiceNumber) async {
    await supabase.auth.refreshSession();
    AuthService authService = AuthService();

    final user = supabase.auth.currentUser;

    if (user == null) {
      print("Error: No authenticated user found.");
      return;
    }

    final agentEmail = user.email ?? "N/A";
    final agentName = user?.userMetadata?['full_name'] ?? "N/A";
    String invoiceNumber = _invoiceNoController.text.trim();

    // Debugging logs to check if staffName is set correctly
    print("Logged-in User: ${user?.email}");
    print("Staff Name: $agentName");

    // Assign values if the text controllers are empty
    if (_agentController.text.isEmpty) {
      _agentController.text = agentName;
    }

    if (agentEmailController.text.isEmpty) {
      agentEmailController.text = agentEmail;
    }

    // If empty, generate a new one
    if (invoiceNumber.isEmpty) {
      if (oldInvoiceNumber.isNotEmpty) {
        invoiceNumber = oldInvoiceNumber;
        _invoiceNoController.text = oldInvoiceNumber;
        print("📌 Reusing old invoice number: $invoiceNumber");
      } else {
        invoiceNumber = await generateUniqueInvoiceNumber();
        print("📌 New invoice number generated: $invoiceNumber");
      }
    }

    String? userEmail = supabase.auth.currentUser?.email;
    print("Using Agent Name in Database: $userEmail"); // Debugging
    if (userEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User not logged in")),
      );
      return;
    }

    Map<String, String>? userInfo = await authService.checkUserRole(userEmail);
    String userRole = userInfo?["role"] ?? "unknown";

    Map<String, dynamic> oldInvoiceDetails = {};

    if (oldInvoiceNumber.trim().isNotEmpty) {
      // Only check Supabase if the user has manually entered an invoice number
      try {
        oldInvoiceDetails = await supabase
            .from('invoices')
            .select()
            .eq('invoice_no', oldInvoiceNumber)
            .single();

        isNewInvoice = false; // ✅ Found in Supabase, so it's not a new one

        // Ensure agent name and email are correctly set
        oldInvoiceDetails['agent_name'] ??= agentName;
        oldInvoiceDetails['agent_email'] ??= agentEmail;

        print(
            "Fetched existing invoice: ${oldInvoiceDetails['agent_name']} - ${oldInvoiceDetails['agent_email']}");
      } catch (e) {
        isNewInvoice = true; // ✅ Invoice not found, treat as new
        print(
            "Invoice number '$oldInvoiceNumber' not found in Supabase. Assigning default values.");
      }
    } else {
      isNewInvoice = true; // ✅ No invoice number entered, treat as new
    }

// 🔹 If it's a new invoice, use default values
    if (isNewInvoice) {
      oldInvoiceDetails = {
        'customer_name': "N/A",
        'hotel': "N/A",
        'room_type': "N/A",
        'check_in': DateTime.now().toIso8601String(),
        'check_out': DateTime.now().toIso8601String(),
        'transfer_date': DateTime.now().toIso8601String(),
        'dateline': DateTime.now().toIso8601String(),
        'room_rate': "0",
        'breakfast': "No",
        'quantity_room': "0",
        'balance_due': "0",
        'surcharge': "0",
        'amount': "0",
        'total_amount': "0",
        'payment': "0",
        'balance': "0",
        'agent_name': agentName,
        'booking_no': "N/A",
        'add_on': "N/A",
        'remarks': "N/A",
        'status': "Pending",
        'agent_email': agentEmail,
        'role': userRole == "management" ? "management" : "Unknown",
      };
    }

    print(
        "Invoice Status: ${isNewInvoice ? 'New (Preview)' : 'Existing (Fetched)'}");

    print("ℹ️ oldInvoiceNumber: $oldInvoiceNumber");
    print("ℹ️ isNewInvoice: $isNewInvoice");

// 🧹 Auto-delete old agent invoice PDF if it exists and is incomplete
    if (oldInvoiceNumber.isNotEmpty) {
      try {
        final previousAgentUpload = await supabase
            .from('invoices')
            .select()
            .eq('invoice_no', oldInvoiceNumber)
            .eq('role', 'agent') // Only check agent uploads
            .maybeSingle();

        if (previousAgentUpload != null) {
          final String? oldPdfUrl = previousAgentUpload['pdf_url'];
          final String? oldBookingNo = previousAgentUpload[
              'booking_number']; // Check if booking is empty
          final bool isIncomplete =
              oldBookingNo == null || oldBookingNo.isEmpty;

          if (oldPdfUrl != null &&
              oldPdfUrl.contains('/storage/v1/object/public/invoices/') &&
              isIncomplete) {
            final String filePath = oldPdfUrl.split('/invoices/').last;

            // 🧹 Remove the old PDF from Supabase storage
            await supabase.storage.from('invoices').remove([filePath]);

            // 🧹 Delete the old invoice record from Supabase
            await supabase
                .from('invoices')
                .delete()
                .eq('invoice_no', oldInvoiceNumber)
                .eq('role', 'agent');

            print("🧹 Deleted incomplete agent invoice: $filePath");
          } else {
            print(
                "✅ Skipped deletion: Agent invoice is valid or already revised.");
          }
        } else {
          print("ℹ️ No previous agent invoice found for deletion.");
        }
      } catch (e) {
        print("⚠️ Failed to auto-delete previous agent invoice: $e");
      }
    } else {
      print(
          "ℹ️ Conditions for auto-delete not met (either oldInvoiceNumber is empty or isNewInvoice is true).");
    }

// Ensure oldInvoiceDetails has default values
    oldInvoiceDetails = oldInvoiceDetails.isNotEmpty
        ? oldInvoiceDetails
        : {
            'customer_name': "N/A",
            'hotel': "N/A",
            'room_type': "N/A",
            'check_in': DateTime.now().toIso8601String(),
            'check_out': DateTime.now().toIso8601String(),
            'transfer_date': DateTime.now().toIso8601String(),
            'dateline': DateTime.now().toIso8601String(),
            'room_rate': "0",
            'breakfast': "No",
            'quantity_room': "0",
            'balance_due': "0",
            'surcharge': "0",
            'amount': "0",
            'total_amount': "0",
            'payment': "0",
            'balance': "0",
            'agent_name': "N/A",
            'booking_no': "N/A",
            'add_on': "N/A",
            'remarks': "N/A",
            'status': "Pending",
            'agent_email': "N/A",
            'role': userRole == "management" ? "management" : "Unknown",
          };

    // Parse dates from old invoice details or use current values from controllers
    DateTime dateInvoice = _dateInvoiceController.text.isNotEmpty
        ? parseDate(_formatDateForDisplay(_dateInvoiceController.text))
        : DateTime.parse(oldInvoiceDetails['date_invoice'] ??
            DateTime.now().toIso8601String());
    DateTime checkInDate = checkInController.text.isNotEmpty
        ? parseDate(formatDate(checkInController.text))
        : DateTime.parse(
            oldInvoiceDetails['check_in'] ?? DateTime.now().toIso8601String());
    DateTime checkOutDate = checkOutController.text.isNotEmpty
        ? parseDate(formatDate(checkOutController.text))
        : DateTime.parse(
            oldInvoiceDetails['check_out'] ?? DateTime.now().toIso8601String());
    DateTime bankTransfer = _bankTransferController.text.isNotEmpty
        ? parseDate(formatDate(_bankTransferController.text))
        : DateTime.parse(oldInvoiceDetails['transfer_date'] ??
            DateTime.now().toIso8601String());
    DateTime dateline = DatelineController.text.isNotEmpty
        ? parseDate(formatDate(DatelineController.text))
        : DateTime.parse(
            oldInvoiceDetails['dateline'] ?? DateTime.now().toIso8601String());

    // Determine the agent/staff name
    String agentName1 =
        (oldInvoiceNumber.isNotEmpty && oldInvoiceDetails.isNotEmpty)
            ? oldInvoiceDetails['agent_name'] ??
                "N/A" // Fetch agent name from existing invoice
            : (userRole == "management"
                ? agentName
                : "N/A"); // Assign management staff name for new invoices

    // Generate the PDF with the old invoice number and updated details
    File originalPdfFile = await fillInvoiceTemplate(
      customerName: _fullNameController.text.isNotEmpty
          ? _fullNameController.text
          : oldInvoiceDetails['customer_name'] ?? "N/A",
      invoiceNo: oldInvoiceNumber, // Reuse the old invoice number
      dateInvoice: dateInvoice,
      hotel: _hotelController.text.isNotEmpty
          ? _hotelController.text
          : oldInvoiceDetails['hotel'] ?? "N/A",
      roomType: _roomTypeController.text.isNotEmpty
          ? _roomTypeController.text
          : oldInvoiceDetails['room_type'] ?? "N/A",
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      bankTransfer: bankTransfer,
      roomRate: formatNumber(double.tryParse(roomRateController.text.isNotEmpty
          ? roomRateController.text
          : oldInvoiceDetails['room_rate'].toString())), // Format as string
      breakfast: _breakfastController.text.isNotEmpty
          ? _breakfastController.text
          : oldInvoiceDetails['breakfast'] ?? "No",
      quantityRoom: int.tryParse(_quantityRoomController.text.isNotEmpty
              ? _quantityRoomController.text
              : oldInvoiceDetails['quantity_room'].toString()) ??
          0,
      balanceDue: formatNumber(double.tryParse(balanceDueController
              .text.isNotEmpty
          ? balanceDueController.text
          : oldInvoiceDetails['balance_due'].toString())), // Format as string
      surcharge: surchargeController.text.isNotEmpty
          ? int.tryParse(surchargeController.text)
          : (oldInvoiceDetails['surcharge'] != null
              ? int.tryParse(oldInvoiceDetails['surcharge'].toString())
              : 0),
      amount: formatNumber(double.tryParse(amountController.text.isNotEmpty
          ? amountController.text
          : oldInvoiceDetails['amount'].toString())), // Format as string
      totalAmount: formatNumber(double.tryParse(totalAmountController
              .text.isNotEmpty
          ? totalAmountController.text
          : oldInvoiceDetails['total_amount'].toString())), // Format as string
      payment: formatNumber(double.tryParse(paymentController.text.isNotEmpty
          ? paymentController.text
          : oldInvoiceDetails['payment'].toString())), // Format as string
      balance: formatNumber(double.tryParse(balanceController.text.isNotEmpty
          ? balanceController.text
          : oldInvoiceDetails['balance'].toString())), // Format as string
      agentName1: agentName1,
      bookingNo: bookingNoController.text.isNotEmpty
          ? int.tryParse(bookingNoController.text)
          : (oldInvoiceDetails['booking_no'] != null
              ? int.tryParse(oldInvoiceDetails['booking_no'].toString())
              : 0),

      dateline: dateline,
      addOn: _AddOnController.text.isNotEmpty
          ? _AddOnController.text
          : oldInvoiceDetails['add_on'] ?? "N/A",
      remarks: _RemarkController.text.isNotEmpty
          ? _RemarkController.text
          : (_RemarkController.text.isEmpty &&
                  oldInvoiceDetails['remarks'] != null)
              ? "" // Leave it empty if user deletes it
              : oldInvoiceDetails['remarks'] ?? "N/A",

      status: statusController.text.isNotEmpty
          ? statusController.text
          : oldInvoiceDetails['status'] ?? "N/A",
      agentEmail: agentEmailController.text.isNotEmpty
          ? agentEmailController.text
          : oldInvoiceDetails['agent_email'] ?? "N/A",
      role: userRole == "management"
          ? "management"
          : RoleController.text.isNotEmpty
              ? RoleController.text
              : oldInvoiceDetails['role'] ?? "Unknown",
    );

    if (!_validateFields()) {
      // ❌ Show an error message if fields are missing
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please fill in all required fields before uploading."),
          backgroundColor: Colors.red,
        ),
      );
      return; // Stop the function
    }

    final double roomRate = double.tryParse(roomRateController.text) ??
        (oldInvoiceDetails['room_rate'] ?? 0.0);
    final int quantityRoom = int.tryParse(_quantityRoomController.text) ??
        (oldInvoiceDetails['quantity_room'] ?? 0);
    final int surcharge = int.tryParse(surchargeController.text) ??
        (oldInvoiceDetails['surcharge'] ?? 0);
    final double payment = double.tryParse(paymentController.text) ??
        (oldInvoiceDetails['payment'] ?? 0.0);

// Step 1: Calculate amount, total_amount, balance_due, and balance
    final double amount = roomRate * quantityRoom;
    final double totalAmount = amount + surcharge;
    final double balanceDue = payment - totalAmount;
    final double balance = balanceDue;

// Step 2: Check if uploaded by management
    final bool isManagementUpload = userRole == "management";

    String determineStatus() {
      if (!isManagementUpload) {
        if (payment == 0) return "Unpaid";
        if (balanceDue < 0) return "Pending";
        return "Paid";
      } else {
        if (payment == 0 || balanceDue < 0) return "Confirmed";
        if (balanceDue >= 0) return "Reviewed";
        return "Confirmed"; // fallback
      }
    }

    final String autoStatus = determineStatus();

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = "INV${invoiceNumber}_management_$timestamp.pdf";

    print("🔹 Logged-in User Email: $agentEmail");
    print("🔹 Logged-in User Name: $agentName");
    print(
        "🔹 Fetched Invoice Agent: ${oldInvoiceDetails['agent_name'] ?? 'N/A'}");
    print("🔹 Final Used Agent Name: ${_agentController.text}");

    try {
      // Upload the updated PDF to Supabase storage
      await supabase.storage.from('invoices').upload(fileName, originalPdfFile);

      final filePublicUrl =
          supabase.storage.from('invoices').getPublicUrl(fileName);

      // Insert or update the invoice record in the database
      await supabase.from('invoices').upsert({
        'pdf_url': filePublicUrl,
        'agent_name': _agentController.text,
        'agent_email': agentEmailController.text,
        'user_id': supabase.auth.currentUser?.id,
        'customer_name': _fullNameController.text.isNotEmpty
            ? _fullNameController.text
            : oldInvoiceDetails['customer_name'] ?? "N/A",
        'invoice_no': invoiceNumber,
        'date_invoice': dateInvoice.toIso8601String(),
        'hotel': _hotelController.text.isNotEmpty
            ? _hotelController.text
            : oldInvoiceDetails['hotel'] ?? "N/A",
        'room_type': _roomTypeController.text.isNotEmpty
            ? _roomTypeController.text
            : oldInvoiceDetails['room_type'] ?? "N/A",
        'check_in': checkInDate.toIso8601String(),
        'check_out': checkOutDate.toIso8601String(),
        'room_rate': double.tryParse(roomRateController.text.isNotEmpty
            ? roomRateController.text
            : oldInvoiceDetails['room_rate'].toString()),
        'breakfast': _breakfastController.text.isNotEmpty
            ? _breakfastController.text
            : oldInvoiceDetails['breakfast'] ?? "N/A",
        'quantity_room': int.tryParse(_quantityRoomController.text.isNotEmpty
            ? _quantityRoomController.text
            : oldInvoiceDetails['quantity_room'].toString()),
        'balance_due': balanceDue,
        // 'balance_due': double.tryParse(balanceDueController.text.isNotEmpty
        //     ? balanceDueController.text
        //     : oldInvoiceDetails['balance_due'].toString()),
        'surcharge': surchargeController.text.isNotEmpty
            ? int.tryParse(surchargeController.text)
            : (oldInvoiceDetails['surcharge'] != null
                ? int.tryParse(oldInvoiceDetails['surcharge'].toString())
                : null),
        'amount': amount,
        // 'amount': double.tryParse(amountController.text.isNotEmpty
        //     ? amountController.text
        //     : oldInvoiceDetails['amount'].toString()),
        // 'total_amount': double.tryParse(totalAmountController.text.isNotEmpty
        //     ? totalAmountController.text
        //     : oldInvoiceDetails['total_amount'].toString()),
        'payment': double.tryParse(paymentController.text.isNotEmpty
            ? paymentController.text
            : oldInvoiceDetails['payment'].toString()),
        'total_amount': totalAmount,
        'balance': balance,
        // 'balance': double.tryParse(balanceController.text.isNotEmpty
        //     ? balanceController.text
        //     : oldInvoiceDetails['balance'].toString()),
        // 'status': initialStatus,
        'date': DateTime.now().toIso8601String(),
        'transfer_date': bankTransfer.toIso8601String(),
        'booking_no': bookingNoController.text.isNotEmpty
            ? int.tryParse(bookingNoController.text)
            : (oldInvoiceDetails['booking_no'] != null
                ? int.tryParse(oldInvoiceDetails['booking_no'].toString())
                : null),
        'dateline': dateline.toIso8601String(),
        'add_on': _AddOnController.text.isNotEmpty
            ? _AddOnController.text
            : oldInvoiceDetails['add_on'] ?? "N/A",
        'remarks': _RemarkController.text.isNotEmpty
            ? _RemarkController.text
            : oldInvoiceDetails['remarks'] ?? "N/A",
        'status': autoStatus,
        'role': userRole == "management"
            ? "management"
            : oldInvoiceDetails['role'] ?? "Unknown",
        'uploaded_by': agentName,
      });

      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(
            "Invoice report has been uploaded",
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.blueGrey // Darker red for dark mode
              : Colors.lightBlue[50], // Lighter red for light mode
          leading: Icon(
            Icons.check_circle, // Use success icon instead of error
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.green,
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

      // Auto-dismiss after 3 seconds
      Future.delayed(Duration(seconds: 3), () {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      });
    } catch (e) {
      print("Error uploading file: $e");
      _showErrorUpload(context);
    }
  }

  Future<void> _updatePDFPreview() async {
    await supabase.auth.refreshSession();
    String invoiceNumber = _invoiceNoController.text.trim();
    bool isManagement = userRole == "management";
    firebase_auth.User? user = firebase_auth.FirebaseAuth.instance.currentUser;
    String staffName = user?.displayName ?? "Unknown Staff";

    // Skip if the PDF is already being generated
    if (_isLoading.value) return;

    _isLoading.value = true;
    _pdfFile = null;

    Map<String, dynamic>? previousInvoice;
    if (invoiceNumber.isNotEmpty) {
      previousInvoice = await fetchInvoiceByNumber(invoiceNumber);

      if (previousInvoice == null) {
        print("❌ Invoice number not found. Please check the number.");
        setState(() => _isLoading.value = false);
        // success = false;
        return;
      }
    } else if (isManagement && invoiceNumber.isEmpty) {
      invoiceNumber = await generateUniqueInvoiceNumber();
      print("📌 New invoice number generated: $invoiceNumber");
    } else {
      print("Invoice number is required!");
      setState(() => _isLoading.value = false);
      return;
    }

    if (previousInvoice != null) {
      print("📄 Found previous invoice, pre-filling data...");

      if (_fullNameController.text.isEmpty) {
        _fullNameController.text = previousInvoice['customer_name'] ?? '';
      }
      if (_hotelController.text.isEmpty) {
        _hotelController.text = previousInvoice['hotel'] ?? '';
      }
      if (_roomTypeController.text.isEmpty) {
        _roomTypeController.text = previousInvoice['room_type'] ?? '';
      }
      if (_breakfastController.text.isEmpty) {
        _breakfastController.text = previousInvoice['breakfast'] ?? '';
      }
      if (_AddOnController.text.isEmpty) {
        _AddOnController.text = previousInvoice['add_on'] ?? '';
      }
      if (_RemarkController.text.isEmpty) {
        _RemarkController.text = previousInvoice['remarks'] ?? '';
      }
      if (_dateInvoiceController.text.isEmpty) {
        _dateInvoiceController.text = previousInvoice['date_invoice'] ?? '';
      }
      if (checkInController.text.isEmpty) {
        checkInController.text = _formatDate(previousInvoice['check_in_date']);
      }
      if (checkOutController.text.isEmpty) {
        checkOutController.text =
            _formatDate(previousInvoice['check_out_date']);
      }
      if (_bankTransferController.text.isEmpty) {
        _bankTransferController.text =
            _formatDate(previousInvoice['bank_transfer']);
      }
      if (DatelineController.text.isEmpty) {
        DatelineController.text = _formatDate(previousInvoice['dateline']);
      }

      // Keep numeric fields editable
      if (_quantityRoomController.text.isEmpty) {
        _quantityRoomController.clear();
      }

      if (roomRateController.text.isEmpty) {
        roomRateController.clear();
      }
      // if (balanceDueController.text.isEmpty) {
      //   balanceDueController.clear();
      // }
      // if (amountController.text.isEmpty) {
      //   amountController.clear();
      // }
      // if (totalAmountController.text.isEmpty) {
      //   totalAmountController.clear();
      // }
      if (paymentController.text.isEmpty) {
        paymentController.clear();
      }
      // if (balanceController.text.isEmpty) {
      //   balanceController.clear();
      // }
      if (bookingNoController.text.isEmpty) {
        bookingNoController.clear();
      }
      if (surchargeController.text.isEmpty) {
        surchargeController.clear();
      }
    } else {
      print("❌ No previous invoice found. Using empty fields.");
    }

    double roomRate = double.tryParse(roomRateController.text) ?? 0.0;
    int quantityRoom = int.tryParse(_quantityRoomController.text) ?? 0;
    double surcharge = double.tryParse(surchargeController.text) ?? 0.0;
    double payment = double.tryParse(paymentController.text) ?? 0.0;
    double amount = roomRate * quantityRoom;
    double totalAmount = amount + surcharge;
    double balanceDue = payment - totalAmount;
    print("Amount: $amount");
    print("Total Amount: $totalAmount");
    print("Balance Due: $balanceDue");
    amountController.text = amount.toStringAsFixed(2);
    totalAmountController.text = totalAmount.toStringAsFixed(2);
    balanceDueController.text = balanceDue.toStringAsFixed(2);
    balanceController.text = balanceDue.toStringAsFixed(2);

    String status;
    if (!isManagement && payment == 0) {
      status = "Unpaid";
    } else if (!isManagement && balanceDue < 0) {
      status = "Pending";
    } else if (!isManagement && balanceDue >= 0) {
      status = "Paid";
    } else if (isManagement && (payment == 0 || balanceDue < 0)) {
      status = "Confirmed";
    } else {
      status = "Reviewed";
    }
    statusController.text = status;

    final file = await fillInvoiceTemplate(
      agentName1:
          _agentController.text.isNotEmpty ? _agentController.text : staffName,
      customerName: _fullNameController.text,
      invoiceNo: invoiceNumber,
      dateInvoice: _parseDate(_dateInvoiceController.text),
      checkInDate: _parseDate(checkInController.text),
      checkOutDate: _parseDate(checkOutController.text),
      bankTransfer: _parseDate(_bankTransferController.text),
      hotel: _hotelController.text,
      roomType: _roomTypeController.text,
      roomRate: formatNumber(double.tryParse(roomRateController.text)),
      breakfast: _breakfastController.text,
      quantityRoom: int.tryParse(_quantityRoomController.text) ?? 0,
      balanceDue: formatNumber(double.tryParse(balanceDueController.text)),
      amount: formatNumber(double.tryParse(amountController.text)),
      totalAmount: formatNumber(double.tryParse(totalAmountController.text)),
      payment: formatNumber(double.tryParse(paymentController.text)),
      balance: formatNumber(double.tryParse(balanceController.text)),
      bookingNo: bookingNoController.text.isNotEmpty
          ? int.tryParse(bookingNoController.text)
          : null,
      surcharge: surchargeController.text.isNotEmpty
          ? int.tryParse(surchargeController.text)
          : null,
      dateline: _parseDate(DatelineController.text),
      addOn: _AddOnController.text,
      remarks: _RemarkController.text,
      status: statusController.text,
      agentEmail: agentEmailController.text,
      role: RoleController.text,
    );

    print("✅ PDF generated: ${file.path}");
    print("✅ File exists? ${await file.exists()}");

    // if (!mounted) return;

    setState(() {
      _pdfFile = file;
      _isLoading.value = false;
    });
  }

  DateTime _parseDate(String date) {
    try {
      return DateFormat('dd/MM/yyyy').parse(date);
    } catch (e) {
      return DateTime.now(); // Default fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Invoice")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(
                _invoiceNoController,
                "Invoice Number for Existing Invoices",
                "Enter invoice no, A0001 for example",
                Icons.receipt,
                maxLength: 5,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                ], validator: (value) {
              if (!RegExp(r'^[a-zA-Z0-9]{5}$').hasMatch(value.trim())) {
                return "Please enter exactly 5 alphanumeric characters (0-9, A-Z).";
              }
              return null;
            }, onSubmitted: (value) async {
              if (value.trim().isNotEmpty) {
                isUsingAutoFetch = true;
                _invoiceNumberTypedManually = true;

                await fetchInvoiceDetails(value.trim());
              }
            }),

            // Guest Details Section
            _buildSectionHeader("Guest Details"),
            _buildTextField(_fullNameController, "Customer Name",
                "Enter customer's full name", Icons.person),
            // _buildDatePicker(context, _dateInvoiceController, "Invoice Date"),
            _buildTextField(_hotelController, "Hotel Name", "Enter Hotel Name",
                Icons.hotel),

            // Room Details Section
            _buildSectionHeader("Room Details"),
            _buildTextField(
                _roomTypeController, "Room Type", "Enter Room Type", Icons.bed),
            _buildDatePicker(context, checkInController, "Check-In Date"),
            _buildDatePicker(context, checkOutController, "Check-Out Date"),

            if (userRole == 'management') ...[
              // Payment Details Section
              _buildSectionHeader("Payment Details"),
              if (userRole == 'management') ...[
                _buildTextField(roomRateController, "Room Rate",
                    "Enter Room Rate (e.g., 250)", Icons.money,
                    isNumeric: true),
              ],
              _buildTextField(_quantityRoomController, "Quantity of Rooms",
                  "Enter the number of rooms", Icons.format_list_numbered,
                  isNumeric: true),
              _buildDropdown(
                "Breakfast Included?",
                ["Breakfast", "Yes", "No"],
                _breakfastController.text,
                (value) {
                  setState(() {
                    _breakfastController.text = value ?? "No";
                  });
                },
              ),
              _buildTextField(paymentController, "Payment",
                  "Enter payment amount", Icons.payment,
                  isNumeric: true),
              _buildTextField(surchargeController, "Surcharge",
                  "Enter surcharge values here", Icons.money,
                  isNumeric: true),
            ],

            // ✅ Agent Details Section
            _buildSectionHeader("Agent Details"),
            _buildTextField(_agentController, "Agent Name",
                "Enter agent's full name", Icons.person),
            _buildDatePicker(
                context, _bankTransferController, "Bank Transfer Date"),

            _buildDatePicker(context, DatelineController, "Dateline Date"),
            _buildTextField(_AddOnController, "Add-On",
                "Enter add-on, if applicable", Icons.format_list_bulleted_add),
            _buildTextField(_RemarkController, "Remarks", "Enter remarks here",
                Icons.format_list_bulleted_add),

            if (userRole == 'management') ...[
              // ✅ Condition now works
              _buildTextField(bookingNoController, "Booking No",
                  "Enter Booking Number", Icons.account_balance_wallet,
                  isNumeric: true),
            ],

            const SizedBox(height: 20),

            // **Show PDF Preview if Available**
            if (_pdfFile != null)
              Container(
                height: MediaQuery.of(context).size.height * 0.7,
                child: PDFView(
                  key: ValueKey(DateTime.now().millisecondsSinceEpoch),
                  filePath: _pdfFile!.path,
                  autoSpacing: true,
                  fitPolicy: FitPolicy.BOTH,
                  enableSwipe: true,
                  pageFling: true,
                  pageSnap: true,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final invoiceNumber = _invoiceNoController.text.trim();
          final isManagement = userRole == "management";
          bool isGeneratingInvoiceNumber = false;

          if (invoiceNumber.isEmpty) {
            if (isManagement) {
              // Management generates a new invoice number if empty
              isGeneratingInvoiceNumber = true;
              final newInvoiceNumber = await generateUniqueInvoiceNumber();
              print("📌 New invoice number generated: $newInvoiceNumber");
            } else {
              _showStatusDialog(context);
              return;
            }
          }

          // Only fetch details if the invoice number exists in Supabase
          if (invoiceNumber.isNotEmpty && !isGeneratingInvoiceNumber) {
            await fetchInvoiceDetails(invoiceNumber);
          }
          _uploadPDF(_invoiceNoController.text);
        },
        label: const Text("Upload"),
        icon: const Icon(Icons.cloud_upload),
      ),
    );
  }

  Widget _buildDatePicker(
      BuildContext context, TextEditingController controller, String label) {
    print("DatePicker value for $label: ${controller.text}");
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          hintText: "Select a date",
          prefixIcon: const Icon(Icons.calendar_today),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
        onTap: () async {
          DateTime? pickedDate = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (pickedDate != null) {
            controller.text = DateFormat('dd/MM/yyyy').format(pickedDate);
          }
        },
      ),
    );
  }

  Widget _buildAgentNameDisplay() {
    print(
        "Building Agent Name Display: $agentName"); // ✅ Check if it's updating
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Text("Agent Name:", style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            agentName ?? "Loading...",
            style: TextStyle(color: Colors.black87),
          ),
        ],
      ),
    );
  }

  // 🔹 Builds TextFields with Icons
  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, {
    bool isNumeric = false,
    void Function(String)? onSubmitted,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        inputFormatters: inputFormatters,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
          counterText: '',
        ),
        onChanged: (value) {
          switch (label) {
            case "Remarks":
              _hasUserEditedRemarks = true;
              print("_hasUserEditedRemarks: $_hasUserEditedRemarks");
              break;
            case "Add-On":
              _hasUserEditedAddOn = true;
              break;
            case "Breakfast Included?":
              _hasUserEditedBreakfast = true;
              break;
            case "Quantity of Rooms":
              _hasUserEditedQuantityRoom = true;
              break;
            case "Agent Email":
              _hasUserEditedAgentEmail = true;
              break;
          }

          if (label == "Invoice Number for Existing Invoices") {
            final trimmed = value.trim();
            final isValid = RegExp(r'^[a-zA-Z0-9]{5}$').hasMatch(trimmed);
            if (isValid && trimmed.toUpperCase() != _lastFetchedInvoiceNo) {
              isUsingAutoFetch = true;
              _invoiceNumberTypedManually = true;
              _lastFetchedInvoiceNo =
                  trimmed.toUpperCase(); // ✅ To avoid refetching same input
              fetchInvoiceDetails(trimmed);
            }
          }
        },
        onFieldSubmitted: (value) async {
          if (validator != null) {
            final error = validator(value);
            if (error != null) {
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("Invalid Input"),
                  content: Text(error),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("OK"),
                    ),
                  ],
                ),
              );
              return;
            }
          }
          if (onSubmitted != null) onSubmitted(value);
        },
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> options, String? value,
      Function(String?) onChanged) {
    String dropdownValue = value ?? "No";
    if (!options.contains(dropdownValue)) {
      dropdownValue = options.first;
    }

    print("Dropdown value for $label: $dropdownValue");
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: dropdownValue,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.fastfood),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
        items: options.map((option) {
          return DropdownMenuItem<String>(
            value: option,
            child: Text(option),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // 🔹 Builds Section Headers
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
      ),
    );
  }
}
