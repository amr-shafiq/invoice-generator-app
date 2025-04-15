import 'package:cloud_firestore/cloud_firestore.dart';

class Invoice {
  String id;
  String agentName;
  String status;
  double amount;

  Invoice(
      {required this.id,
      required this.agentName,
      required this.status,
      required this.amount});

  // Convert Firestore document to Dart object
  factory Invoice.fromMap(Map<String, dynamic> data, String documentId) {
    return Invoice(
      id: documentId,
      agentName: data['agentName'] ?? '',
      status: data['status'] ?? 'Pending',
      amount: (data['amount'] ?? 0.0).toDouble(),
    );
  }

  // Convert Dart object to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'agentName': agentName,
      'status': status,
      'amount': amount,
    };
  }
}
