import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddAgentPage extends StatefulWidget {
  @override
  _AddAgentPageState createState() => _AddAgentPageState();
}

class _AddAgentPageState extends State<AddAgentPage> {
  final TextEditingController manualEmailController = TextEditingController();
  final TextEditingController manualNameController = TextEditingController();
  final List<String> allowedEmails = [
    "darkside260700@gmail.com",
    "manager@example.com"
  ];
  String _statusMessage = ''; // To show status messages
  Map<String, dynamic>? _profileData; // To hold profile data
  String? _currentUserEmail;
  List<Map<String, String>> pendingUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchCurrentUser();
  }

  /// ✅ Fetch the current logged-in user
  void _fetchCurrentUser() {
    User? user = FirebaseAuth.instance.currentUser; // 🔹 Fixed here
    if (user != null) {
      setState(() {
        _currentUserEmail = user.email;
      });
      if (allowedEmails.contains(user.email)) {
        _fetchPendingUsers();
      }
    }
  }

  /// Show a confirmation dialog before approving an agent
  Future<bool> _showConfirmationDialog(
      {required String title, required String content}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false), // Cancel
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true), // Confirm
                child: const Text("Approve"),
              ),
            ],
          ),
        ) ??
        false; // Default to false if dialog is dismissed
  }

  /// Show a success dialog after approval
  void _showSuccessDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Close
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  /// Show an error dialog if approval fails
  void _showErrorDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: Colors.red)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Close
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  /// ✅ Fetch unauthorized users (role: "unknown", status: "pending")
  Future<void> _fetchPendingUsers() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'unknown')
        .where('status', isEqualTo: 'pending')
        .get();

    print("📢 Debug: Retrieved Docs Count: ${snapshot.docs.length}");

    for (var doc in snapshot.docs) {
      print("📌 Found: ${doc.data()}"); // Debugging each document
    }

    setState(() {
      pendingUsers = snapshot.docs.map((doc) {
        return {
          'email': doc['email'] as String? ?? 'No Email',
          'agent_name': doc['agent_name'] as String? ?? 'Unknown',
        };
      }).toList();
    });

    print("✅ Updated Pending Users: $pendingUsers");
  }

  /// ✅ Manually Approve User
  Future<void> _manualApproveUser(String email, String name) async {
    bool confirm = await _showConfirmationDialog(
      title: "Manual Approval",
      content: "Are you sure you want to approve $email as an agent?",
    );

    if (!confirm) return;

    try {
      // Use a default name since we can't fetch displayName directly without a sign-in process
      String displayName = name;

      // Check if this user exists in Firestore
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Update if user already exists
        String docId = snapshot.docs.first.id;
        await FirebaseFirestore.instance.collection('users').doc(docId).update({
          'role': 'agent',
          'status': 'approved',
          'name': displayName, // Store the default display name in Firestore
        });
      } else {
        // Create a new user entry with displayName
        await FirebaseFirestore.instance.collection('users').add({
          'email': email,
          'role': 'agent',
          'status': 'approved',
          'agent_name':
              displayName, // Store the default display name in Firestore
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      _showSuccessDialog(
          "Agent Approved", "$email has been approved manually.");
      manualEmailController.clear();
      _fetchPendingUsers();
    } catch (e) {
      _showErrorDialog(
          "Error", "An error occurred while processing the approval: $e");
    }
  }

  /// ✅ Approve user as an "Agent"
  Future<void> _approveUser(String email) async {
    // Show confirmation dialog before approving
    bool confirm = await _showConfirmationDialog(
      title: "Approve Agent?",
      content: "Are you sure you want to approve $email as an agent?",
    );

    if (!confirm) return; // Exit if user cancels

    // 🔹 Find the document with the matching email
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    if (snapshot.docs.isNotEmpty) {
      String docId = snapshot.docs.first.id; // Get the correct Firestore doc ID

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'role': 'agent',
        'status': 'approved',
      });

      // Show success dialog after approval
      _showSuccessDialog(
          "Agent Approved", "The agent $email has been approved successfully.");

      // Refresh list after approval
      _fetchPendingUsers();
    } else {
      _showErrorDialog("Approval Failed", "No user found with email: $email");
    }
  }

  /// ✅ Reject user and delete their data from Firestore
  Future<void> _rejectUser(String email) async {
    // Show confirmation dialog before rejecting
    bool confirm = await _showConfirmationDialog(
      title: "Reject Agent?",
      content:
          "Are you sure you want to reject and delete $email from records?",
    );

    if (!confirm) return; // Exit if user cancels

    // 🔹 Find the document with the matching email
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    if (snapshot.docs.isNotEmpty) {
      String docId = snapshot.docs.first.id; // Get Firestore doc ID

      // Delete the document from Firestore
      await FirebaseFirestore.instance.collection('users').doc(docId).delete();

      // Show success dialog after deletion
      _showSuccessDialog(
          "Agent Rejected", "The agent $email has been removed.");

      // Refresh list after deletion
      _fetchPendingUsers();
    } else {
      _showErrorDialog("Rejection Failed", "No user found with email: $email");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserEmail == null ||
        !allowedEmails.contains(_currentUserEmail)) {
      return Scaffold(
        appBar: AppBar(title: const Text("Add Agent")),
        body: const Center(
          child: Text(
            "❌ Access Denied.\nOnly admins can approve agents.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Approve New Agents")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            /// 🔹 Firebase Pending Approvals
            ExpansionTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text(
                "🕓 Pending Approvals from Firebase",
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
              children: [
                pendingUsers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text("✅ No pending approvals."),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pendingUsers.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final user = pendingUsers[index];
                          return ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(user['agent_name'] ?? 'Unnamed'),
                            subtitle: Text(user['email'] ?? 'No email'),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.green),
                                  onPressed: () => _approveUser(user['email']!),
                                  tooltip: 'Approve',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel,
                                      color: Colors.red),
                                  onPressed: () => _rejectUser(user['email']!),
                                  tooltip: 'Reject',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),

            const SizedBox(height: 20),

            /// 🔹 Manual Agent Entry
            ExpansionTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text(
                "Manually Add Agent",
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
              initiallyExpanded: true, // keep this open by default
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: manualEmailController,
                        decoration: const InputDecoration(
                          labelText: 'Agent Email',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: manualNameController,
                        decoration: const InputDecoration(
                          labelText: 'Agent Name',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text("Approve Manually"),
                          onPressed: () {
                            String email = manualEmailController.text.trim();
                            String name = manualNameController.text.trim();
                            if (email.isNotEmpty && name.isNotEmpty) {
                              _manualApproveUser(email, name);
                            } else {
                              _showErrorDialog(
                                "Input Error",
                                "Please provide both email and name.",
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
