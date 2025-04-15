import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:provider/provider.dart';

class AuthService with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final supabase.SupabaseClient _supabase =
      supabase.Supabase.instance.client; // ✅ Supabase instance

  AuthService() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      signOut(); // Auto sign-out when app is closed
    }
  }

  /// ✅ Sign in with Google and authenticate with Supabase
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null; // User canceled sign-in

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null) {
        print("❌ Google ID Token is null");
        return null; // Prevent passing a null value
      }

      // 🔹 Authenticate with Firebase using Google credentials
      final firebase_auth.AuthCredential credential =
          firebase_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken, // ✅ Ensure it's non-null
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      // 🔹 Authenticate with Supabase using Google ID Token
      final response = await _supabase.auth.signInWithIdToken(
        provider: supabase.OAuthProvider.google,
        idToken: googleAuth.idToken!, // ✅ Use the non-null ID token
      );

      if (response.user == null) {
        print("❌ Supabase Authentication Failed");
        return null;
      }

      print("✅ Signed into Supabase as: ${response.user!.id}");
      return userCredential;
    } catch (e) {
      print("Google Sign-In Error: $e");
      return null;
    }
  }

  Future<void> addAgent(String email) async {
    try {
      // 🔹 Check if user already exists in Firestore
      var userDoc = await _firestore.collection('users').doc(email).get();

      if (userDoc.exists) {
        throw Exception("User already exists!");
      }

      // 🔹 Add new agent with role = 'agent'
      await _firestore.collection('users').doc(email).set({
        'email': email,
        'role': 'agent',
        'createdAt': FieldValue.serverTimestamp(),
      });

      print("✅ Agent added successfully!");
    } catch (e) {
      print("❌ Error adding agent: $e");
      throw e;
    }
  }

  /// ✅ Fetch user role from Firestore & Supabase
  Future<Map<String, String>?> checkUserRole(String email) async {
    try {
      // 🔹 Check Firestore
      QuerySnapshot querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var userDoc = querySnapshot.docs.first;
        String role = userDoc['role'];
        String status = userDoc['status'];
        return {"role": role, "status": status};
      }

      // 🔹 Check Supabase
      final response = await _supabase
          .from('users')
          .select('role, status')
          .eq('email', email)
          .maybeSingle();

      if (response != null) {
        return {
          "role": response['role'] ?? 'unknown',
          "status": response['status'] ?? 'pending'
        };
      }
    } catch (e) {
      print("Error fetching user role: $e");
    }

    return null;
  }

  /// ✅ Handles authentication and role checking
  Future<String> handleSignIn() async {
    UserCredential? userCredential = await signInWithGoogle();
    if (userCredential == null) {
      return "cancelled";
    }

    String email = userCredential.user!.email!;
    String displayName = userCredential.user!.displayName ?? "Unknown";

    // 🔹 Fetch role & status from Firestore & Supabase
    Map<String, String>? userInfo = await checkUserRole(email);

    if (userInfo != null) {
      String role = userInfo["role"]!;
      String status = userInfo["status"]!;

      if (status == "approved") return role;
      return "pending";
    }

    // 🔹 If user is new, register them in Firestore & Supabase
    try {
      await _firestore.collection('users').add({
        "email": email,
        "agent_name": displayName,
        "role": "unknown",
        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
      });

      await _supabase.from('users').insert({
        "email": email,
        "agent_name": displayName,
        "role": "unknown",
        "status": "pending",
        "createdAt": DateTime.now().toIso8601String(),
      });

      print("🆕 New user registered: $email");
    } catch (e) {
      print("❌ Firestore/Supabase Write Error: $e");
    }

    return "unauthorized";
  }

  /// Sign out from Google, Firebase, and Supabase
  Future<void> signOut() async {
    await GoogleSignIn().disconnect();
    await GoogleSignIn().signOut();
    // await _auth.signOut();
    // await _supabase.auth.signOut();
  }
}
