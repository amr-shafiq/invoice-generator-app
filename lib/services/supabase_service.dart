import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<String?> uploadPDF(File pdfFile, String fileName) async {
    try {
      final response = await supabase.storage
          .from(
              'invoices') // Replace 'invoices' with your Supabase storage bucket name
          .upload(fileName, pdfFile);

      if (response.isEmpty) {
        print("Failed to upload PDF.");
        return null;
      }

      final String publicUrl =
          supabase.storage.from('invoices').getPublicUrl(fileName);
      print("PDF uploaded successfully: $publicUrl");
      return publicUrl;
    } catch (e) {
      print("Supabase upload error: $e");
      return null;
    }
  }

  Future<void> savePdfUrl(String pdfUrl) async {
    final supabase = Supabase.instance.client;

    try {
      await supabase.from('invoices').insert({
        'pdf_url': pdfUrl, // Adjust based on your Supabase column name
        'created_at': DateTime.now().toIso8601String(),
      });

      print("PDF URL saved to Supabase successfully.");
    } catch (error) {
      print("Error saving PDF URL: $error");
    }
  }

  Future<List<String>> listPDFs() async {
    try {
      final response = await supabase.storage.from('invoices').list();
      return response.map((file) => file.name).toList();
    } catch (e) {
      print("Error listing PDFs: $e");
      return [];
    }
  }

  Future<void> deletePDF(String fileName) async {
    try {
      await supabase.storage.from('invoices').remove([fileName]);
      print("PDF deleted: $fileName");
    } catch (e) {
      print("Error deleting PDF: $e");
    }
  }
}
