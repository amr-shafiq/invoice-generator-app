import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

File? _pdfFile;
Timer? _debounce;
bool _isLoading = false;

class AddPDFPage extends StatefulWidget {
  @override
  _AddPDFPageState createState() => _AddPDFPageState();
}

class _AddPDFPageState extends State<AddPDFPage> {
  final SupabaseService _supabaseService = SupabaseService();
  final supabase = Supabase.instance.client;
  bool _hasPreviewed = false;
  String initialStatus = "Unpaid"; // Default status when uploading a PDF
  String? userRole;
  final AuthService _authService = AuthService();
  String? selectedBreakfast;
  // String? agentName;
  String agentName = "Loading...";
  double hideIfZero(double? value) {
    return (value ?? 0) == 0 ? 0 : value!;
  }

  void _onTextChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _updatePDFPreview(); // Call this without extra setState()
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    dateInvoiceController.text =
        DateFormat('dd/MM/yyyy').format(DateTime.now());

    List<TextEditingController> controllers = [
      fullNameController,
      invoiceNoController,
      dateInvoiceController,
      checkInController,
      checkOutController,
      hotelController,
      roomTypeController,
      // roomRateController,
      breakfastController,
      quantityRoomController,
      // balanceDueController,
      bankTransferController,
      // amountController,
      // totalAmountController,
      // paymentController,
      // balanceController,
      agentController,
      bookingNoController,
      DatelineController,
      AddOnController,
      RemarkController,
    ];

    for (var controller in controllers) {
      controller.addListener(() {
        if (mounted) {
          _updatePDFPreview();
        }
      });
    }
  }

  @override
  void dispose() {
    List<TextEditingController> controllers = [
      fullNameController,
      invoiceNoController,
      dateInvoiceController,
      hotelController,
      roomTypeController,
      checkInController,
      checkOutController,
      // roomRateController,
      breakfastController,
      quantityRoomController,
      // balanceDueController,
      // amountController,
      agentController,
      // totalAmountController,
      // paymentController,
      // balanceController,
      bankTransferController,
      bookingNoController,
      DatelineController,
      AddOnController,
      RemarkController,
    ];

    for (var controller in controllers) {
      controller.dispose();
    }

    super.dispose();
  }

  // Controllers for user inputs
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController invoiceNoController = TextEditingController();
  final TextEditingController dateInvoiceController = TextEditingController();
  final TextEditingController hotelController = TextEditingController();
  final TextEditingController roomTypeController = TextEditingController();
  final TextEditingController checkInController = TextEditingController();
  final TextEditingController checkOutController = TextEditingController();
  final TextEditingController bankTransferController = TextEditingController();
  final TextEditingController paxController = TextEditingController();
  // final TextEditingController roomRateController = TextEditingController();
  final TextEditingController breakfastController = TextEditingController();
  final TextEditingController quantityRoomController = TextEditingController();
  // final TextEditingController balanceDueController = TextEditingController();
  // final TextEditingController amountController = TextEditingController();
  final TextEditingController agentController = TextEditingController();
  // final TextEditingController totalAmountController = TextEditingController();
  // final TextEditingController paymentController = TextEditingController();
  // final TextEditingController balanceController = TextEditingController();
  final TextEditingController bookingNoController = TextEditingController();
  final TextEditingController DatelineController = TextEditingController();
  final TextEditingController AddOnController = TextEditingController();
  final TextEditingController RemarkController = TextEditingController();

  File? _pdfFile; // Store the latest generated PDF

  Future<String?> fetchAgentNameFromFirestore(String email) async {
    var querySnapshot = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: email)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      return querySnapshot.docs.first.data()["agent_name"];
    }
    return null;
  }

  Future<void> _fetchUserRole() async {
    String? email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;

    Map<String, String>? roleData = await _authService.checkUserRole(email);
    if (roleData != null) {
      setState(() {
        userRole = roleData["role"]; // Update state with user role
      });
    }
  }

  void _showErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: const Text("Failed to upload PDF: $e"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
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

  Future<File> fillInvoiceTemplate({
    required String customerName,
    required String invoiceNo,
    required DateTime dateInvoice,
    required String hotel,
    required String roomType,
    required DateTime checkInDate,
    required DateTime checkOutDate,
    required DateTime bankTransfer,
    // required double roomRate,
    required String breakfast,
    required int quantityRoom,
    // required double balanceDue,
    // required double amount,
    required String agentName,
    // required double totalAmount,
    // required double payment,
    // required double balance,
    required String? bookingNo,
    required DateTime dateline,
    required String addOn,
    required String remarks,
  }) async {
    final ByteData data =
        await rootBundle.load("assets/INVB3758_word_fillable_agent.pdf");
    final List<int> bytes = data.buffer.asUint8List();
    sf.PdfDocument document = sf.PdfDocument(inputBytes: bytes);

    final sf.PdfForm form = document.form;
    form.setDefaultAppearance(false);

    // Format dates properly
    String formattedInvoiceDate = DateFormat('dd/MM/yyyy').format(dateInvoice);
    String formattedBankTransfer =
        DateFormat('dd/MM/yyyy').format(bankTransfer);
    String formattedCheckInDate = DateFormat('d MMMM yyyy').format(checkInDate);
    String formattedCheckOutDate =
        DateFormat('d MMMM yyyy').format(checkOutDate);
    String formattedDateline = DateFormat('d MMMM yyyy').format(dateline);

    final Map<String, dynamic> fields = {
      "CUSTOMER_NAME": customerName,
      "INVOICE_NO": invoiceNo,
      "DATE": formattedInvoiceDate,
      "BANK_TRANSFER": formattedBankTransfer,
      "HOTEL_NAME": hotel,
      "ROOM_TYPE": roomType,
      "CHECK_IN": formattedCheckInDate,
      "CHECK_OUT": formattedCheckOutDate,
      // "ROOM_RATE": roomRate,
      "BREAKFAST_OR_NO": breakfast,
      "QUANTITY": quantityRoom.toString(),
      // "BALANCE_DUE": balanceDue.toString(),
      // "AMOUNT": amount.toString(),
      "AGENT_NAME": agentName,
      // "TOTAL": totalAmount.toString(),
      // "PAYMENT": payment.toString(),
      // "BALANCE": balance.toString(),
      "BOOKING_NO": bookingNo ?? "Pending Verification",
      // "DATELINE": formattedDateline,
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
    _pdfFile = File("${output.path}/AMK$invoiceNo.pdf");
    await _pdfFile!.writeAsBytes(updatedBytes);

    return _pdfFile!;
  }

  Future<String> generateUniqueInvoiceNumber() async {
    final response = await supabase.from('invoices').select('invoice_no');
    // .eq('agent_name', agentName); // Filter by agent_name

    if (response.isEmpty) {
      return "00001"; // Start fresh if no invoice exists for this agent
    }

    // Extract only valid "ZZZZZ" format invoices
    List<String> validInvoices = response
        .map<String>((row) => row['invoice_no'] as String)
        .where((no) => _isFiveCharFormat(no))
        .toList();

    if (validInvoices.isEmpty) {
      return "00001";
    }

    // Sort invoices in descending order and pick the latest one
    validInvoices.sort((a, b) => b.compareTo(a));
    String latestInvoice = validInvoices.first;

    return _incrementFiveCharInvoice(latestInvoice);
  }

  bool _isFiveCharFormat(String invoiceNo) {
    return RegExp(r'^[\dA-Z]{5}$').hasMatch(invoiceNo);
  }

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
        charCodes[i] = charCode + 1;
        return String.fromCharCodes(charCodes);
      }
    }

    return String.fromCharCodes(charCodes);
  }

  DateTime parseDate(String? dateString) {
    if (dateString == null || dateString.trim().isEmpty) return DateTime.now();
    try {
      return DateFormat("yyyy-MM-dd").parse(dateString);
    } catch (e) {
      print("Error parsing date to DateTime: $e");
      return DateTime.now();
    }
  }

  String? formatDate(String dateString) {
    if (dateString.trim().isEmpty) return null;
    try {
      DateFormat inputFormat = DateFormat("dd/MM/yyyy"); // Selected format
      DateFormat outputFormat = DateFormat("yyyy-MM-dd"); // PostgreSQL format
      DateTime parsedDate = inputFormat.parse(dateString);
      return outputFormat.format(parsedDate);
    } catch (e) {
      print("Error parsing date: $e");
      return null;
    }
  }

  Future<void> _downloadPDF() async {
    String invoiceNumber = await generateUniqueInvoiceNumber();
    if (_pdfFile == null || !await _pdfFile!.exists()) {
      print("Error: _pdfFile is null or does not exist!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No PDF available to download!")),
      );
      return;
    }

    // Request permissions for Android 10+ (Scoped Storage)
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
      Uint8List bytes = await _pdfFile!.readAsBytes();

      File savedFile = File(outputPath);
      await savedFile.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(
            "Invoice saved successfully at $outputPath",
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.blueGrey
              : Colors.lightBlue[50],
          leading: Icon(
            Icons.check_circle,
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
      _showErrorDialog(context);
    }
  }

  bool _validateFields() {
    List<TextEditingController> requiredFields = [
      fullNameController,
      hotelController,
      roomTypeController,
      checkInController,
      checkOutController,
      breakfastController,
      quantityRoomController,
    ];

    for (var controller in requiredFields) {
      if (controller.text.trim().isEmpty) {
        return false;
      }
    }

    return true;
  }

  Future<String> getAgentNameFromFirestore(String userEmail) async {
    try {
      CollectionReference usersRef =
          FirebaseFirestore.instance.collection('users');
      QuerySnapshot querySnapshot =
          await usersRef.where('email', isEqualTo: userEmail).get();

      if (querySnapshot.docs.isNotEmpty) {
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

  Future<void> _uploadPDF() async {
    await supabase.auth.refreshSession();
    AuthService authService = AuthService();
    String? userEmail = supabase.auth.currentUser?.email;
    if (userEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User not logged in")),
      );
      return;
    }
    String agentName = await getAgentNameFromFirestore(userEmail);
    Map<String, String>? userInfo = await authService.checkUserRole(userEmail);
    String userRole = userInfo?["role"] ?? "unknown";
    String invoiceNumber = invoiceNoController.text.trim().isNotEmpty
        ? invoiceNoController.text.trim()
        : await generateUniqueInvoiceNumber();

    File originalPdfFile = await fillInvoiceTemplate(
      customerName: fullNameController.text,
      invoiceNo: invoiceNumber,
      dateInvoice: parseDate(formatDate(dateInvoiceController.text)),
      checkInDate: parseDate(formatDate(checkInController.text)),
      checkOutDate: parseDate(formatDate(checkOutController.text)),
      bankTransfer: parseDate(formatDate(bankTransferController.text)),
      hotel: hotelController.text,
      roomType: roomTypeController.text,
      breakfast: breakfastController.text,
      quantityRoom: int.tryParse(quantityRoomController.text) ?? 0,
      agentName: agentName,
      bookingNo:
          bookingNoController.text.isNotEmpty ? bookingNoController.text : null,
      dateline: parseDate(formatDate(DatelineController.text)),
      addOn: AddOnController.text,
      remarks: RemarkController.text,
    );

    if (!_validateFields()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please fill in all required fields before uploading."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final fileName = "AMK$invoiceNumber.pdf";
    try {
      await supabase.storage.from('invoices').upload(fileName, originalPdfFile);

      final filePublicUrl =
          supabase.storage.from('invoices').getPublicUrl(fileName);

      await supabase.from('invoices').insert({
        'pdf_url': filePublicUrl,
        'agent_name': agentName,
        'agent_email': userEmail,
        'user_id': supabase.auth.currentUser?.id,
        'customer_name': fullNameController.text,
        'invoice_no': invoiceNumber,
        'date_invoice': formatDate(dateInvoiceController.text),
        'hotel': hotelController.text,
        'room_type': roomTypeController.text,
        'check_in': formatDate(checkInController.text),
        'check_out': formatDate(checkOutController.text),
        'breakfast': breakfastController.text,
        'quantity_room': quantityRoomController.text.isNotEmpty
            ? int.tryParse(quantityRoomController.text)
            : null,
        'status': initialStatus,
        'date': DateTime.now().toIso8601String(),
        'transfer_date': formatDate(bankTransferController.text),
        'booking_no': bookingNoController.text.isNotEmpty
            ? bookingNoController.text
            : null,
        'dateline': formatDate(DatelineController.text),
        'add_on': AddOnController.text,
        'remarks': RemarkController.text,
        'role': userRole,
      });

      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text(
            "Invoice has been uploaded successfully",
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.blueGrey
              : Colors.lightBlue[50],
          leading: Icon(
            Icons.check_circle,
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
      Future.delayed(Duration(seconds: 3), () {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      });

      if (invoiceNoController.text.trim().isEmpty) {
        invoiceNoController.clear();
      }
    } catch (e) {
      print("Error uploading file: $e");
      _showErrorDialog(context);
    }
  }

  Future<void> _updatePDFPreview() async {
    await supabase.auth.refreshSession();
    String invoiceNumber = await generateUniqueInvoiceNumber();
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _pdfFile = null;
    });

    String userEmail = supabase.auth.currentUser?.email ?? "unknown";
    String agentName =
        await fetchAgentNameFromFirestore(userEmail) ?? "Unknown Agent";

    final file = await fillInvoiceTemplate(
      agentName: agentName,
      customerName: fullNameController.text,
      invoiceNo: invoiceNumber,
      dateInvoice: _parseDate(dateInvoiceController.text),
      checkInDate: _parseDate(checkInController.text),
      checkOutDate: _parseDate(checkOutController.text),
      bankTransfer: _parseDate(bankTransferController.text),
      hotel: hotelController.text,
      roomType: roomTypeController.text,
      // roomRate: hideIfZero(double.tryParse(roomRateController.text)),
      breakfast: breakfastController.text,
      quantityRoom: int.tryParse(quantityRoomController.text) ?? 0,
      // balanceDue: double.tryParse(balanceDueController.text) ?? 0,
      // amount: double.tryParse(amountController.text) ?? 0,
      // totalAmount: double.tryParse(totalAmountController.text) ?? 0,
      // payment: double.tryParse(paymentController.text) ?? 0,
      // balance: double.tryParse(balanceController.text) ?? 0,
      bookingNo:
          bookingNoController.text.isNotEmpty ? bookingNoController.text : null,
      dateline: _parseDate(DatelineController.text),
      addOn: AddOnController.text,
      remarks: RemarkController.text,
    );

    setState(() {
      _pdfFile = file;
      _isLoading = false;
    });
  }

// Helper function to handle empty date cases
  DateTime _parseDate(String date) {
    try {
      return DateFormat('dd/MM/yyyy').parse(date);
    } catch (e) {
      return DateTime.now();
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
            // Guest Details Section
            _buildSectionHeader("Guest Details"),
            _buildTextField(fullNameController, "Customer Name",
                "Enter customer's full name", Icons.person),
            // _buildDatePicker(context, dateInvoiceController, "Invoice Date"),
            _buildTextField(
                hotelController, "Hotel Name", "Enter Hotel Name", Icons.hotel),

            // Room Details Section
            _buildSectionHeader("Room Details"),
            _buildTextField(
                roomTypeController, "Room Type", "Enter Room Type", Icons.bed),
            _buildDatePicker(context, checkInController, "Check-In Date"),
            _buildDatePicker(context, checkOutController, "Check-Out Date"),
            // if (userRole == 'management') ...[
            //   _buildTextField(roomRateController, "Room Rate",
            //       "Enter Room Rate (e.g., 250)", Icons.money,
            //       isNumeric: true),
            // ],
            _buildDropdown(
                "Breakfast Included?", ["Yes", "No"], selectedBreakfast,
                (value) {
              setState(() {
                selectedBreakfast = value;
                breakfastController.text = value ?? "";
              });
            }),
            _buildTextField(quantityRoomController, "Quantity of Rooms",
                "Enter the number of rooms", Icons.format_list_numbered,
                isNumeric: true),

            // if (userRole == 'management') ...[
            //   // ✅ Payment Details Section
            //   _buildSectionHeader("Payment Details"),
            //   _buildTextField(balanceDueController, "Balance Due",
            //       "Enter balance due amount", Icons.account_balance_wallet,
            //       isNumeric: true),
            //   _buildTextField(
            //     amountController,
            //     "Amount",
            //     "Enter invoice amount",
            //     Icons.attach_money,
            //     isNumeric: true,
            //   ),

            //   // Add missing totalAmountController
            //   _buildTextField(totalAmountController, "Total Amount",
            //       "Enter total amount", Icons.summarize,
            //       isNumeric: true),
            //   // Add missing paymentController
            //   _buildTextField(paymentController, "Payment",
            //       "Enter payment amount", Icons.payment,
            //       isNumeric: true),

            //   _buildTextField(balanceController, "Balance", "Enter balance due",
            //       Icons.payment,
            //       isNumeric: true),
            // ],

            // Agent Details Section
            _buildSectionHeader("Agent Details"),
            if (userRole == 'management') ...[
              _buildAgentNameDisplay(),
            ],
            // _buildDatePicker(
            //     context, bankTransferController, "Bank Transfer Date"),

            // _buildDatePicker(context, DatelineController, "Dateline Date"),
            _buildTextField(AddOnController, "Add-On",
                "Enter add-on, if applicable", Icons.format_list_bulleted_add),
            _buildTextField(RemarkController, "Remarks", "Enter remarks here",
                Icons.format_list_bulleted_add),

            if (userRole == 'management') ...[
              _buildTextField(bookingNoController, "Booking No",
                  "Enter Booking Number", Icons.account_balance_wallet,
                  isNumeric: true),
            ],

            const SizedBox(height: 20),

            // Preview & Upload Buttons
            // ElevatedButton(
            //   onPressed: () async {
            //     await _updatePDFPreview(); // TODO: Implement PDF Preview Logic
            //   },
            //   child: const Text("Preview PDF"),
            // ),

            // Show PDF Preview if Available
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
        onPressed: _uploadPDF,
        label: const Text("Upload"),
        icon: const Icon(Icons.cloud_upload),
      ),
    );
  }

  Widget _buildDatePicker(
      BuildContext context, TextEditingController controller, String label) {
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
    print("Building Agent Name Display: $agentName");
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Agent Name:", style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            agentName ?? "Loading...",
            style: TextStyle(color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      String hint, IconData icon,
      {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> options, String? value,
      Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: value,
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
