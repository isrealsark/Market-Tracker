import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'login_screen.dart';
import 'homescreen.dart';
import 'app_session.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final db = DatabaseHelper.instance;
  late Future<List<Map<String, dynamic>>> workersFuture;

  @override
  void initState() {
    super.initState();
    workersFuture = db.getWorkers();
  }

  Future<bool> _verifyPin() async {
    final pinController = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final valid = await db.verifyPin(pinController.text.trim());
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext, valid);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    pinController.dispose();
    return verified == true;
  }

  Future<void> _openWorkerAccount(Map<String, dynamic> worker) async {
    final workerName = worker['name']?.toString() ?? '';
    if (workerName.isEmpty) return;

    AppSession.setWorker(AppSession.userId, workerName);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _deactivateWorker(Map<String, dynamic> worker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate worker?'),
        content: Text(
          'Remove ${worker['name']} from this company account? The company account will remain active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !(await _verifyPin())) return;

    await db.deactivateWorker(worker['id'] as int);
    if (!mounted) return;
    setState(() {
      workersFuture = db.getWorkers();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Worker deactivated')));
  }

  Future<void> _deactivateAccount() async {
    final pinController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This will remove the Company account and saved worker names from this device.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final valid = await db.verifyPin(pinController.text.trim());
              if (!dialogContext.mounted) return;
              if (valid) {
                Navigator.pop(dialogContext, true);
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    pinController.dispose();

    if (confirmed != true || !mounted) return;
    await db.deactivateAccount();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workers'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Login', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: workersFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load workers: ${snapshot.error}'),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          final workers = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Saved worker names',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (workers.isEmpty)
                const Text('No worker names saved.')
              else
                ...workers.asMap().entries.map(
                  (entry) => ListTile(
                    leading: CircleAvatar(child: Text('${entry.key + 1}')),
                    title: Text(entry.value['name']?.toString() ?? ''),
                    onTap: () => _openWorkerAccount(entry.value),
                    trailing: SizedBox(
                      width: 135,
                      child: TextButton.icon(
                        onPressed: () => _deactivateWorker(entry.value),
                        icon: const Icon(Icons.person_remove, size: 17),
                        label: const Text(
                          'Deactivate',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _deactivateAccount,
                      icon: const Icon(Icons.person_off, size: 16),
                      label: const Text(
                        'Deactivate Account',
                        style: TextStyle(fontSize: 13),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
