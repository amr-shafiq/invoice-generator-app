import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class FirebaseNotificationService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Request permission for notifications
    await _firebaseMessaging.requestPermission();

    const AndroidInitializationSettings androidInitSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidInitSettings);

    await _flutterLocalNotificationsPlugin.initialize(initSettings);

    // Foreground push notification handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showNotification(
          title: message.notification!.title ?? "New Invoice",
          body: message.notification!.body ?? "An invoice has been updated.",
        );
      }
    });

    // Background notification handler
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("User tapped on notification: ${message.notification?.title}");
      // Handle navigation if needed
    });

    // 🔥 Listen for Firestore updates (Real-time updates)
    listenForInvoiceUpdates();
  }

  static void listenForInvoiceUpdates() {
    FirebaseFirestore.instance
        .collection("invoices")
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _showNotification(
            title: "New Invoice Added",
            body: "Invoice ${change.doc.id} has been submitted.",
          );
        } else if (change.type == DocumentChangeType.modified) {
          _showNotification(
            title: "Invoice Updated",
            body: "Invoice ${change.doc.id} has been updated.",
          );
        }
      }
    });
  }

  static Future<void> _showNotification(
      {required String title, required String body}) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'invoice_updates',
      'Invoice Updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      largeIcon: DrawableResourceAndroidBitmap(
          '@android:drawable/stat_sys_download_done'),
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _flutterLocalNotificationsPlugin.show(
        0, title, body, platformDetails);
  }
}
