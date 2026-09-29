import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/database_helper.dart';
import 'screens/subscription_screen.dart';
import 'screens/user_setup_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  // Set the database factory to FFI (for desktop)
  databaseFactory = databaseFactoryFfi;
  runApp(const MarketTrackerApp());
}

class MarketTrackerApp extends StatefulWidget {
  const MarketTrackerApp({super.key});

  @override
  State<MarketTrackerApp> createState() => _MarketTrackerAppState();
}

class _MarketTrackerAppState extends State<MarketTrackerApp> {
  final db = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    // Run cleanup on startup
    db.deleteOldCustomers();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Market Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Skip badge call during debug if asset missing.
    // Navigate to UserSetupScreen after 3 seconds
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UserSetupScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange, // 🔹 Brand color
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/watermark.png',
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
          ],
        ),
      ),
    );
  }
}
