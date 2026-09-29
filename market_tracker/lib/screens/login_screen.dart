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
  final db = DatabaseHelper.instance;
  final usernameController = TextEditingController();
  final companyController = TextEditingController();
  final pinController = TextEditingController();
  String? error;

  Future<void> _login() async {
    final username = usernameController.text.trim();
    final company = companyController.text.trim();
    final pin = pinController.text.trim();

    // 🔑 Admin login check (requires PIN)
    if (username == "ISRAELSARK" &&
        company == "ADMIN" &&
        pin == "M4411d1971.") {
      AppSession.setOwner();
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

    // Normal login accepts either the account username or a worker name.
    final isValid = await db.verifyUser(username, company);
    if (isValid) {
      final accountId = await db.getUserIdForLogin(username, company);
      final isWorkerLogin = await db.isWorker(username, company);

      AppSession.userId = accountId;
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
        // Keep the previously stored status when the backend is unavailable.
      }

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
    } else {
      setState(() => error = "Invalid username or company");
    }
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
                              labelText: "Company Name",
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
                              labelText: "PIN (optional)",
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
                      onPressed: _login,
                      child: const Text("Unlock"),
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
                    "Back to setup",
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
