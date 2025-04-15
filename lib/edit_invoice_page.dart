import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'view_invoice_page.dart';

class EditInvoicePage extends StatefulWidget {
  final String documentId;
  final String? pdfUrl;
  final Map<String, dynamic> invoice;

  const EditInvoicePage({
    Key? key,
    required this.documentId,
    required this.pdfUrl,
    required this.invoice,
  }) : super(key: key);

  @override
  _EditInvoicePageState createState() => _EditInvoicePageState();
}

class _EditInvoicePageState extends State<EditInvoicePage> {
  final supabase = Supabase.instance.client;
  final SupabaseService _supabaseService = SupabaseService();
  late Map<String, dynamic> invoice;
  TextEditingController agentNameController = TextEditingController();
  TextEditingController statusController = TextEditingController();
  String pdfUrl = "";
  String lastUpdatedDate = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    invoice = widget.invoice;
    _fetchInvoiceDetails();
  }

  Future<void> _fetchInvoiceDetails() async {
    try {
      final response = await supabase
          .from('invoices')
          .select()
          .eq('id', widget.documentId)
          .single();

      setState(() {
        agentNameController.text = response['agent_name'];
        statusController.text = response['status'];
        pdfUrl = response['pdf_url'] ?? "";
        lastUpdatedDate = response['date'] ?? "";
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching invoice: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    try {
      await supabase.from('invoices').update({
        'agent_name': agentNameController.text,
        'status': statusController.text,
        'pdf_url': pdfUrl.isNotEmpty ? pdfUrl : null,
        'date': DateTime.now().toIso8601String(),
      }).eq('id', widget.documentId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invoice updated successfully")),
      );
      Navigator.pop(context);
    } catch (e) {
      print("Error updating invoice: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to update invoice")),
      );
    }
  }

  Future<void> _replacePDF() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);

    if (result != null) {
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;

      try {
        if (pdfUrl.isNotEmpty) {
          await supabase.storage
              .from('invoices')
              .remove([pdfUrl.split('/').last]);
        }

        // Upload new PDF
        final uploadedFilePath =
            await supabase.storage.from('invoices').upload(fileName, file);

        if (uploadedFilePath == null) {
          print("Upload failed: No file path returned");
        } else {
          // Get public URL of new file
          final filePublicUrl =
              supabase.storage.from('invoices').getPublicUrl(fileName);

          // Update state and database
          setState(() {
            pdfUrl = filePublicUrl;
          });

          await supabase.from('invoices').update({
            'pdf_url': filePublicUrl,
          }).eq('id', widget.documentId);
        }
      } catch (e) {
        print("Error replacing file: $e");
      }
    }
  }

  Future<void> _removePdf() async {
    if (pdfUrl.isNotEmpty) {
      try {
        await supabase.storage
            .from('invoices')
            .remove([pdfUrl.split('/').last]);

        await supabase.from('invoices').update({
          'pdf_url': null,
        }).eq('id', widget.documentId);
        setState(() {
          pdfUrl = "";
        });
      } catch (e) {
        print("Error removing PDF: $e");
      }
    }
  }

  void _viewPdf(String pdfUrl) {
    if (pdfUrl.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ViewInvoicePage(
            pdfUrl: pdfUrl,
            invoiceNumber:
                invoice['invoice_no'] ?? 'Unknown', // ✅ Now this works!
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Invoice")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: agentNameController,
                    decoration: const InputDecoration(labelText: "Agent Name"),
                  ),
                  TextField(
                    controller: statusController,
                    decoration: const InputDecoration(labelText: "Status"),
                  ),
                  const SizedBox(height: 20),
                  if (pdfUrl.isNotEmpty) ...[
                    Text("Current PDF:"),
                    ListTile(
                      title: Text(pdfUrl.split('/').last),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.visibility,
                                color: Colors.blue),
                            onPressed: () =>
                                _viewPdf(pdfUrl ?? ''), // ✅ Pass invoice
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: _removePdf,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  NeumorphicButton(
                    onPressed: _replacePDF,
                    style: NeumorphicStyle(
                      color: Colors.red,
                      depth: 4,
                      intensity: 0.8,
                    ),
                    child: Text(pdfUrl.isEmpty ? "Upload PDF" : "Replace PDF"),
                  ),
                  const SizedBox(height: 20),
                  NeumorphicButton(
                    onPressed: _saveChanges,
                    style: NeumorphicStyle(
                      color: const Color.fromARGB(255, 76, 129, 176),
                      depth: 4,
                      intensity: 0.8,
                    ),
                    child: const Text("Save Changes"),
                  ),
                ],
              ),
            ),
    );
  }
}
