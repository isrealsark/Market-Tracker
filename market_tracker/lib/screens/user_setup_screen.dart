import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'login_screen.dart';
import 'company_sync_service.dart';

class UserSetupScreen extends StatefulWidget {
  const UserSetupScreen({super.key});

  @override
  State<UserSetupScreen> createState() => _UserSetupScreenState();
}

class _UserSetupScreenState extends State<UserSetupScreen> {
  final db = DatabaseHelper.instance;
  final double formOpacity = 0.12;
  final double fieldOpacity = 0.08;
  final double borderOpacity = 0.25;
  final usernameController = TextEditingController();
  final companyController = TextEditingController();
  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  final workerController = TextEditingController();
  final List<String> workerNames = [];

  Future<void> _register() async {
    final username = usernameController.text.trim();
    final company = companyController.text.trim();
    final pin = pinController.text.trim();
    final confirm = confirmController.text.trim();
    final pendingWorker = workerController.text.trim();
    final workersToSave = List<String>.from(workerNames);

    if (pendingWorker.isNotEmpty &&
        !workersToSave.any(
          (worker) => worker.toLowerCase() == pendingWorker.toLowerCase(),
        )) {
      workersToSave.add(pendingWorker);
    }

    if (username.isEmpty || company.isEmpty) {
      _showMessage("Enter username and company name");
      return;
    }

    if (workersToSave.isEmpty) {
      _showMessage("Add at least one worker name");
      return;
    }

    if (pin.length != 4 || pin != confirm) {
      _showMessage("PIN must be 4 digits and match");
      return;
    }

    try {
      // 🔹 Check if user already exists
      final exists = await db.verifyUser(username, company);
      if (exists) {
        _showMessage("Account details already exist");
        return;
      }

      // 🔹 Save user and confirm success
      final id = await db.saveUser(username, company, pin);
      if (id > 0) {
        await db.saveWorkers(id, workersToSave);
        try {
          final synced = await CompanySyncService.registerCompany(
            companyName: company,
            username: username,
          );
          if (!synced) {
            _showMessage(
              "Account saved locally, but company sync is unavailable",
            );
          }
        } catch (_) {
          _showMessage(
            "Account saved locally, but company sync is unavailable",
          );
        }
        _showMessage("Account created successfully");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      } else {
        _showMessage("Failed to create account");
      }
    } catch (e) {
      print("Error saving user: $e");
      _showMessage("Error creating account");
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                    "Create my Account",
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
                            color: Colors.white.withOpacity(fieldOpacity),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                          ),
                          child: TextField(
                            controller: usernameController,
                            decoration: const InputDecoration(
                              labelText: "Username",
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
                            color: Colors.white.withOpacity(fieldOpacity),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(fieldOpacity),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: workerController,
                                  decoration: const InputDecoration(
                                    labelText: "Worker Name",
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 8,
                                    ),
                                  ),
                                  onSubmitted: (_) => _addWorker(),
                                ),
                              ),
                              IconButton(
                                tooltip: "Add worker",
                                onPressed: _addWorker,
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (workerNames.isNotEmpty)
                          ...workerNames.asMap().entries.map(
                            (entry) => Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text(entry.value),
                                trailing: IconButton(
                                  tooltip: "Remove worker",
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    setState(
                                      () => workerNames.removeAt(entry.key),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(fieldOpacity),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                          ),
                          child: TextField(
                            controller: pinController,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: const InputDecoration(
                              labelText: "4-digit PIN",
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
                            color: Colors.white.withOpacity(fieldOpacity),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                          ),
                          child: TextField(
                            controller: confirmController,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            decoration: const InputDecoration(
                              labelText: "Confirm PIN",
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
                      onPressed: _register,
                      child: const Text("Register"),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? "),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Login",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addWorker() {
    final name = workerController.text.trim();
    if (name.isEmpty) return;
    if (workerNames.any(
      (worker) => worker.toLowerCase() == name.toLowerCase(),
    )) {
      _showMessage("Worker name already added");
      return;
    }
    setState(() {
      workerNames.add(name);
      workerController.clear();
    });
  }
}
