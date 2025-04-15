import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'main.dart';

final supabase = Supabase.instance.client;

class ViewInvoicePage extends StatefulWidget {
  final String pdfUrl;
  final String invoiceNumber;

  const ViewInvoicePage({
    required this.pdfUrl,
    required this.invoiceNumber,
    Key? key,
  }) : super(key: key);

  @override
  _ViewInvoicePageState createState() => _ViewInvoicePageState();
}

class _ViewInvoicePageState extends State<ViewInvoicePage> {
  String? localPdfPath;
  String? filePublicUrl;
  bool isDownloading = false;

  @override
  void initState() {
    super.initState();
    fetchInvoiceDetails();
    _setupNotifications();
    _downloadAndOpenPDF();
  }

  void _setupNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          OpenFilex.open(response.payload!);
        }
      },
    );
  }

  void _showErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: const Text("Error saving PDF. Please try again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showErrorPDFDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: const Text("Failed to fetch PDF requested. Please try again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> fetchInvoiceDetails() async {
    final response = await supabase
        .from('invoices')
        .select('pdf_url')
        .eq('invoice_no', widget.invoiceNumber); // Fetch all matching invoices

    if (response.isNotEmpty) {
      setState(() {
        filePublicUrl = response.last['pdf_url'];
      });
    } else {
      print("Invoice not found!");
    }
  }

  Future<void> _downloadAndOpenPDF() async {
    setState(() => isDownloading = true);

    try {
      String updatedUrl = widget.pdfUrl;
      var response = await http.get(Uri.parse(updatedUrl));

      if (response.statusCode == 200) {
        Directory tempDir = await getTemporaryDirectory();
        String filePath = '${tempDir.path}/invoice_${widget.invoiceNumber}.pdf';

        File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          localPdfPath = filePath;
          isDownloading = false;
        });
      } else {
        print(
            "Failed to fetch updated PDF. Status Code: ${response.statusCode}");
        _showErrorPDFDialog(context);
      }
    } catch (e) {
      print("Error fetching PDF: $e");
      _showErrorPDFDialog(context);
    }
  }

  Future<void> _savePDFLocally(String invoiceNo) async {
    if (localPdfPath == null) {
      _showSnackbar("PDF is still loading. Please wait.");
      return;
    }

    try {
      File flattenedFile = await flattenPdf(File(localPdfPath!));
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else if (Platform.isIOS) {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir != null) {
        String savePath = '${downloadsDir.path}/AMK$invoiceNo.pdf';
        await flattenedFile.copy(savePath);
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            content: Text(
              "Invoice has been saved as AMK$invoiceNo.pdf",
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
        _showNotification(
            "Invoice Downloaded", "Saved at: $savePath", savePath);
      }
    } catch (e) {
      _showErrorDialog(context);
    }
  }

  void _showNotification(String title, String body, String filePath) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'invoice_channel',
      'Invoice Notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      ticker: 'ticker',
      largeIcon: DrawableResourceAndroidBitmap(
          '@android:drawable/stat_sys_download_done'),
    );

    const DarwinNotificationDetails iosPlatformChannelSpecifics =
        DarwinNotificationDetails();
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iosPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: filePath,
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<File> flattenPdf(File originalPdfFile) async {
    final PdfDocument document =
        PdfDocument(inputBytes: await originalPdfFile.readAsBytes());
    document.form.flattenAllFields();
    final List<int> bytes = await document.save();
    final File flattenedFile = File("${originalPdfFile.path}_invoice.pdf");
    await flattenedFile.writeAsBytes(bytes);
    document.dispose();

    return flattenedFile;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Invoice PDF"),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              await fetchInvoiceDetails();

              if (filePublicUrl != null) {
                _savePDFLocally(widget.invoiceNumber);
              } else {
                print("No file URL available!");
              }
            },
          ),
        ],
      ),
      body: Center(
        child: isDownloading
            ? const CircularProgressIndicator()
            : localPdfPath != null
                ? PDFView(filePath: localPdfPath!)
                : const Text("Loading PDF..."),
      ),
    );
  }
}
