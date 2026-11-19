import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'homescreen.dart';
import 'admin_panel_screen.dart';
import 'account_management_screen.dart';
import 'app_session.dart';
import 'user_setup_screen.dart';
import 'company_sync_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _adminUsername = 'ISRAELSARK';
  static const _adminCompany = 'ADMIN';
  static const _adminPin = 'M4411d1971.';

  final db = DatabaseHelper.instance;
  final usernameController = TextEditingController();
  final companyController = TextEditingController();
  final pinController = TextEditingController();
  String? error;
  bool _isSigningIn = false;

  Future<void> _login() async {
    if (_isSigningIn) return;
    setState(() {
      _isSigningIn = true;
      error = null;
    });

    try {
      await _performLogin();
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  Future<void> _performLogin() async {
    final username = usernameController.text.trim();
    final company = companyController.text.trim();
    final pin = pinController.text;

    if (company.toUpperCase() == _adminCompany &&
        username == _adminUsername &&
        pin == _adminPin) {
      AppSession.setAdmin(username);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
      );
      return;
    }

    if (username.isEmpty) {
      setState(() => error = "Enter a username or worker name");
      return;
    }

    final localAccountId = await db.getUserIdForLogin(username, company);
    final localIsWorker =
        localAccountId != null && await db.isWorker(username, company);
    var localCredentialsValid = false;
    if (localAccountId != null) {
      AppSession.userId = localAccountId;
      final localUserExists = await db.verifyUser(username, company);
      if (!localUserExists) {
        AppSession.clear();
        setState(() => error = 'Invalid company credentials');
        return;
      }
      localCredentialsValid = pin.isEmpty || await db.verifyPin(pin);
    }

    Map<String, dynamic>? cloudSession;
    try {
      if (localAccountId != null && !localIsWorker) {
        await CompanySyncService.registerCompany(
          companyName: company,
          username: username,
        );
      }
      cloudSession = await CompanySyncService.signIn(
        companyName: company,
        username: username,
        pin: pin,
      );
      final needsMigration = cloudSession['needsMigration'] == true;
      if (needsMigration) {
        if (cloudSession['role'] != 'owner' || localAccountId == null) {
          await CompanySyncService.clearSession();
          cloudSession = null;
          throw Exception('The owner must migrate this company first.');
        }
        await CompanySyncService.uploadCurrentSnapshot(db);
      } else {
        final snapshot = await CompanySyncService.downloadSnapshot();
        await db.importCompanySnapshot(
          snapshot.data,
          pin: pin.isEmpty ? null : pin,
          cloudRevision: snapshot.revision,
        );
      }
    } on InvalidCompanyCredentialsException {
      if (!localCredentialsValid) {
        AppSession.clear();
        setState(() => error = 'Invalid company credentials');
        return;
      }
      await CompanySyncService.clearSession();
      cloudSession = null;
    } catch (_) {
      if (!localCredentialsValid) {
        AppSession.clear();
        setState(() => error = 'Could not connect to the company account');
        return;
      }
    }

    final accountId = cloudSession == null
        ? localAccountId!
        : (await db.getUserIdForLogin(username, company));
    if (accountId == null) {
      AppSession.clear();
      setState(() => error = 'Company data could not be loaded');
      return;
    }

    try {
      final status = await CompanySyncService.getCompanyStatus(
        companyName: company,
      );
      final expiryRaw = status?['expiresAt'];
      await db.setSubscriptionStatus(
        paid: status?['paid'] == true,
        expiresAt: expiryRaw == null
            ? null
            : DateTime.tryParse(expiryRaw.toString()),
      );
    } catch (_) {
      // Keep the locally cached subscription status while offline.
    }

    final isWorkerLogin = cloudSession == null
        ? localIsWorker
        : cloudSession['role'] == 'worker';
    if (isWorkerLogin) {
      AppSession.setWorker(accountId, username);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      AppSession.setOwner(accountId, username);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AccountManagementScreen()),
      );
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    companyController.dispose();
    pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Image.asset(
                    'assets/images/watermark.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Login",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                          ),
                          child: TextField(
                            controller: usernameController,
                            decoration: const InputDecoration(
                              labelText: "Username or worker name",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                          ),
                          child: TextField(
                            controller: companyController,
                            decoration: const InputDecoration(
                              labelText: "Company Name ",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                          ),
                          child: TextField(
                            controller: pinController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "PIN",
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSigningIn ? null : _login,
                      child: _isSigningIn
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Unlock"),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UserSetupScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  label: const Text(
                    "Create a new account",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.white)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
