import 'package:flutter/material.dart';
import 'database_helper.dart';

Future<bool> requirePin(BuildContext context, DatabaseHelper db) async {
  final pinController = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Enter PIN"),
      content: TextField(
        controller: pinController,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: const InputDecoration(labelText: "PIN"),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () async {
            final isValid = await db.verifyPin(pinController.text);
            if (isValid) {
              Navigator.pop(context, true);
            } else {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Incorrect PIN")));
            }
          },
          child: const Text("Confirm"),
        ),
      ],
    ),
  );

  return result ?? false;
}
