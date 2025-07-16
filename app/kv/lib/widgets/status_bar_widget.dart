import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StatusBarWidget extends StatefulWidget {
  final String backendUrl;
  final bool capsLockOn;
  final VoidCallback? onCapsLockToggle;
  final Function(String) onSectionTap; // New callback

  const StatusBarWidget({
    super.key,
    required this.backendUrl,
    required this.capsLockOn,
    this.onCapsLockToggle,
    required this.onSectionTap, // Make it required
  });

  @override
  State<StatusBarWidget> createState() => _StatusBarWidgetState();
}

class _StatusBarWidgetState extends State<StatusBarWidget> {
  Map<String, dynamic> _statusData = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchStatus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await http.get(Uri.parse(widget.backendUrl + '/api/status'));
      if (response.statusCode == 200) {
        setState(() {
          _statusData = jsonDecode(response.body);
        });
      } else {
        debugPrint('Failed to load status: \\${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = _statusData['video'] ?? {};
    final keyboard = _statusData['keyboard'] ?? {};
    final mouse = _statusData['mouse'] ?? {};
    final ecm = _statusData['ecm'] ?? {};

    Color enabledColor = Colors.green;
    Color disabledColor = Colors.red;
    Color neutralColor = Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Video indicator
            GestureDetector(
              onTap: () => widget.onSectionTap('video'),
              child: Row(
                children: [
                  Icon(Icons.videocam, color: video['actual_fps'] != null ? enabledColor : neutralColor, size: 20),
                  if (video['actual_fps'] != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${video['actual_fps']?.toStringAsFixed(2)} fps',
                      style: TextStyle(
                        color: enabledColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 18),
            // Keyboard indicator
            GestureDetector(
              onTap: () => widget.onSectionTap('keyboard'),
              child: Icon(Icons.keyboard,
                  color: keyboard['enabled'] == true ? enabledColor : disabledColor, size: 20),
            ),
            const SizedBox(width: 18),
            // Mouse indicator
            GestureDetector(
              onTap: () => widget.onSectionTap('mouse'),
              child: Icon(Icons.mouse,
                  color: mouse['enabled'] == true ? enabledColor : disabledColor, size: 20),
            ),
            const SizedBox(width: 18),
            // Network indicator (replaces ECM Up/Down)
            GestureDetector(
              onTap: () => widget.onSectionTap('network'),
              child: Icon(
                Icons.network_check,
                color: ecm['up'] == true ? enabledColor : disabledColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 18),
            // Storage indicator
            GestureDetector(
              onTap: () => widget.onSectionTap('usb'),
              child: Icon(Icons.usb,
                  color: _statusData['storage']?['attached'] == true ? enabledColor : disabledColor, size: 20),
            ),
            const SizedBox(width: 18),
            // Caps Lock indicator (reactive, clickable)
            GestureDetector(
              onTap: widget.onCapsLockToggle,
              child: AnimatedOpacity(
                opacity: widget.capsLockOn ? 1.0 : 0.2,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  margin: const EdgeInsets.only(left: 2.0, right: 2.0),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.capsLockOn ? Colors.amber : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.black26),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'A',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Caps',
                        style: TextStyle(
                          color: widget.capsLockOn ? Colors.amber[900] : Colors.grey,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
