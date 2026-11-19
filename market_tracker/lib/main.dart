import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'connectivity_service.dart';
import 'screens/database_helper.dart';
import 'screens/account_management_screen.dart';
import 'screens/app_session.dart';
import 'screens/company_sync_service.dart';
import 'screens/homescreen.dart';
import 'screens/login_screen.dart';
import 'screens/user_setup_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/subscription_screen.dart';

void main() {
  if (!Platform.isWindows) {
    throw UnsupportedError('Market Tracker supports Windows only.');
  }
  if (kReleaseMode) {
    final backendUri = Uri.tryParse(CompanySyncService.backendUrl);
    if (backendUri == null ||
        backendUri.scheme != 'https' ||
        backendUri.host.isEmpty ||
        backendUri.host == 'localhost') {
      throw StateError(
        'Release builds require an HTTPS BACKEND_URL supplied with --dart-define.',
      );
    }
  }

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
  late final ConnectivityService _connectivityService;

  @override
  void initState() {
    super.initState();
    _connectivityService = ConnectivityService()..start();
    // Run cleanup on startup
    db.deleteOldCustomers();
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    super.dispose();
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
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _navigationTimer = Timer(const Duration(seconds: 3), () {
      _continueFromSplash();
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  Future<void> _continueFromSplash() async {
    Widget nextScreen = const UserSetupScreen();
    try {
      final session = await CompanySyncService.restoreSession();
      if (session != null) {
        final snapshot = await CompanySyncService.downloadSnapshot();
        final userId = await DatabaseHelper.instance.importCompanySnapshot(
          snapshot.data,
          cloudRevision: snapshot.revision,
        );
        final username = session['username']?.toString() ?? '';
        if (session['role'] == 'worker') {
          AppSession.setWorker(userId, username);
          nextScreen = const HomeScreen();
        } else {
          AppSession.setOwner(userId, username);
          nextScreen = const AccountManagementScreen();
        }
      } else if ((await DatabaseHelper.instance.getUsers()).isNotEmpty) {
        nextScreen = const LoginScreen();
      }
    } catch (_) {
      if ((await DatabaseHelper.instance.getUsers()).isNotEmpty) {
        nextScreen = const LoginScreen();
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 253, 114, 1), // 🔹 Brand color
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/watermark.png',
              width: 220,
              height: 220,
              fit: BoxFit.contain,
            ),
          ],
        ),
      ),
    );
  }
}
