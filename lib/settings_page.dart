import 'package:flutter/material.dart';
import 'services/firebase_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_agent_page.dart';

class SettingsPage extends StatefulWidget {
  final Function(bool) onThemeChanged;

  const SettingsPage({Key? key, required this.onThemeChanged})
      : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notificationsEnabled = true;
  User? _currentUser;
  bool isDarkMode = false;
  bool isAuthorized = false;

  // List of allowed emails
  final List<String> allowedEmails = [
    "darkside260700@gmail.com",
    "norahazlin.isa@gmail.com",
    "manager@example.com"
  ];

  @override
  void initState() {
    super.initState();
    FirebaseNotificationService.initialize();
    _loadUserData();
    _loadThemePreference();
  }

  void _loadUserData() {
    User? user = FirebaseAuth.instance.currentUser;
    setState(() {
      _currentUser = user;
      isAuthorized = user != null && allowedEmails.contains(user.email);
    });
  }

  void _toggleNotifications(bool value) {
    setState(() {
      notificationsEnabled = value;
    });

    if (notificationsEnabled) {
      FirebaseNotificationService.initialize();
    }
  }

  void _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  void _toggleDarkMode(bool value) {
    widget.onThemeChanged(value);
    setState(() {
      isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (_currentUser != null) ...[
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: _currentUser!.photoURL != null
                        ? NetworkImage(_currentUser!.photoURL!)
                        : const AssetImage("assets/default_avatar.png")
                            as ImageProvider,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _currentUser!.displayName ?? "No Name",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(_currentUser!.email ?? "No Email",
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
          // SwitchListTile(
          //   title: const Text("Enable Notifications"),
          //   value: notificationsEnabled,
          //   onChanged: _toggleNotifications,
          // ),
          SwitchListTile(
            title: const Text("Enable Dark Mode"),
            value: isDarkMode,
            onChanged: _toggleDarkMode,
          ),
          if (isAuthorized)
            ListTile(
              title: const Text("Add New Agent"),
              trailing: const Icon(Icons.person_add),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AddAgentPage()),
                );
              },
            ),
        ],
      ),
    );
  }
}
