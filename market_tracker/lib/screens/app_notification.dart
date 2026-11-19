import 'dart:async';

import 'package:flutter/material.dart';

class AppNotification {
  static Timer? _dismissTimer;
  static OverlayEntry? _currentEntry;

  static void show(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _dismissTimer?.cancel();
    if (_currentEntry?.mounted ?? false) _currentEntry!.remove();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopNotification(
        message: message,
        onDismiss: () {
          if (entry.mounted) entry.remove();
          if (identical(_currentEntry, entry)) _currentEntry = null;
          _dismissTimer?.cancel();
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
      if (identical(_currentEntry, entry)) _currentEntry = null;
    });
  }
}

class _TopNotification extends StatelessWidget {
  const _TopNotification({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: Colors.white,
                  elevation: 8,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.orange.shade400),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.notifications_outlined,
                            color: Colors.deepOrange.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Color(0xFF342A20),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss notification',
                          onPressed: onDismiss,
                          icon: const Icon(Icons.close),
                          color: Colors.deepOrange,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
