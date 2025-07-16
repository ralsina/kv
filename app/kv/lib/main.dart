import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KV: Remote KVM',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'KV: Remote KVM'),
    );
  }
}

// ...existing code...
class MyHomePage extends StatelessWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: VideoPlayerWidget(
              url: 'http://rocky2:3000/video.mjpg',
            ),
          );
        },
      ),
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  const VideoPlayerWidget({super.key, required this.url});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  bool _sidebarOpen = false;
  // Tracks caps lock state manually for UI and key event logic.
  bool _capsLockOn = false;
  WebSocket? _ws;
  bool _pointerCaptured = false;
  Offset? _lastPointerPosition;
  int _pressedButtons = 0; // New variable to store pressed buttons
  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _focusNode.requestFocus(); // Request focus when the widget initializes
  }

  void _captureMouse() {
    if (!_pointerCaptured) {
      setState(() {
        _pointerCaptured = true;
      });
    }
  }

  void _releaseMouse() {
    if (_pointerCaptured) {
      setState(() {
        _pointerCaptured = false;
      });
    }
  }

  Future<void> _connectWebSocket() async {
    try {
      _ws = await WebSocket.connect('ws://rocky2:3000/ws/input');
      // Optionally handle incoming messages here
    } catch (e) {
      // Optionally handle connection errors
      // debugPrint('WebSocket connection error: $e');
    }
  }
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _controller = TextEditingController();

  String? _getMouseButtonName(int buttons) {
    if (buttons == 1) {
      return 'left';
    } else if (buttons == 2) {
      return 'right';
    } else if (buttons == 4) {
      return 'middle';
    }
    return null;
  }

  @override
  void dispose() {
    _ws?.close();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }


  // Add a GlobalKey for the video widget
  final GlobalKey _videoKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isMobile = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    return Row(
      children: [
        // Sidebar
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _sidebarOpen ? 220 : 36,
          color: Colors.grey.shade200,
          child: Column(
            children: [
              IconButton(
                icon: Icon(_sidebarOpen ? Icons.chevron_left : Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _sidebarOpen = !_sidebarOpen;
                  });
                },
                tooltip: _sidebarOpen ? 'Close sidebar' : 'Open sidebar',
              ),
              if (_sidebarOpen)
                Expanded(
                  child: ListView(
                    children: const [
                      // Placeholder for future controls
                      ListTile(
                        leading: Icon(Icons.settings),
                        title: Text('Controls coming soon'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Main content
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: isMobile
                    ? Stack(
                        children: [
                          Mjpeg(
                            key: _videoKey,
                            stream: widget.url,
                            isLive: true,
                            error: (context, error, stack) => const Center(child: Text('Stream error')),
                            loading: (context) => const Center(child: CircularProgressIndicator()),
                            fit: BoxFit.contain,
                          ),
                          // Hidden TextField to capture input
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Opacity(
                              opacity: 0.01,
                              child: TextField(
                                controller: _controller,
                                autofocus: true,
                                onChanged: (value) {
                                  if (value.isNotEmpty) {
                                    setState(() {
                                      // _lastKey = value.characters.last; // Removed as _lastKey is no longer used
                                    });
                                    _controller.clear();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      )
                    : MouseRegion(
                        cursor: SystemMouseCursors.basic,
                        onHover: (PointerHoverEvent event) {
                          // Only send mouse_absolute if hovering over the video
                          final renderBox = _videoKey.currentContext?.findRenderObject() as RenderBox?;
                          if (renderBox != null) {
                            final localPosition = renderBox.globalToLocal(event.position);
                            final width = renderBox.size.width;
                            final height = renderBox.size.height;
                            if (localPosition.dx >= 0 && localPosition.dy >= 0 &&
                                localPosition.dx <= width && localPosition.dy <= height) {
                              // Normalize to 0..32767 as expected by backend
                              int absX = ((localPosition.dx / width) * 32767).clamp(0, 32767).round();
                              int absY = ((localPosition.dy / height) * 32767).clamp(0, 32767).round();
                              if (_ws != null && _ws!.readyState == WebSocket.open) {
                                final msg = <String, dynamic>{
                                  'type': 'mouse_absolute',
                                  'x': absX,
                                  'y': absY,
                                };
                                _ws!.add(jsonEncode(msg));
                              }
                            }
                          }
                          setState(() {
                            _lastPointerPosition = event.position;
                          });
                        },
                        child: Stack(
                          children: [
                            Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (event) {
                                _captureMouse();
                                _focusNode.requestFocus();
                                setState(() {
                                  _lastPointerPosition = event.position;
                                  _pressedButtons = event.buttons; // Store pressed buttons
                                });
                                if (_ws != null && _ws!.readyState == WebSocket.open) {
                                  String? buttonName = _getMouseButtonName(event.buttons);
                                  if (buttonName != null) {
                                    final msg = <String, dynamic>{
                                      'type': 'mouse_press',
                                      'button': buttonName,
                                    };
                                    _ws!.add(jsonEncode(msg));
                                  }
                                }
                              },
                              onPointerUp: (event) {
                                if (_ws != null && _ws!.readyState == WebSocket.open) {
                                  // Determine which button was released by comparing current and previous button states
                                  String? releasedButtonName;
                                  if ((_pressedButtons & 1) != 0 && (event.buttons & 1) == 0) {
                                    releasedButtonName = 'left';
                                  } else if ((_pressedButtons & 2) != 0 && (event.buttons & 2) == 0) {
                                    releasedButtonName = 'right';
                                  } else if ((_pressedButtons & 4) != 0 && (event.buttons & 4) == 0) {
                                    releasedButtonName = 'middle';
                                  }

                                  if (releasedButtonName != null) {
                                    final msg = <String, dynamic>{
                                      'type': 'mouse_release',
                                      'button': releasedButtonName,
                                    };
                                    _ws!.add(jsonEncode(msg));
                                  }
                                }
                                _pressedButtons = event.buttons; // Update pressed buttons after release
                              },
                              child: KeyboardListener(
                                focusNode: _focusNode,
                                autofocus: true,
                                onKeyEvent: (KeyEvent event) {
                                  if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                    // Track caps lock state manually
                                    if (event.logicalKey == LogicalKeyboardKey.capsLock && event is KeyDownEvent) {
                                      setState(() {
                                        _capsLockOn = !_capsLockOn;
                                      });
                                      // Don't send a key event for caps lock itself
                                      return;
                                    }
                                    final List<String> modifiers = [];
                                    if (HardwareKeyboard.instance.isControlPressed) modifiers.add('ctrl');
                                    if (HardwareKeyboard.instance.isShiftPressed) modifiers.add('shift');
                                    if (HardwareKeyboard.instance.isAltPressed) modifiers.add('alt');

                                    // Detect Super/Meta/Windows/Command key as 'meta' modifier
                                    // Check both HardwareKeyboard and the event's pressed keys
                                    bool isMeta = false;
                                    if (HardwareKeyboard.instance.isMetaPressed) {
                                      isMeta = true;
                                    } else {
                                      // Check if any of the known meta/super keys are pressed
                                      final metaKeys = [
                                        LogicalKeyboardKey.meta,
                                        LogicalKeyboardKey.metaLeft,
                                        LogicalKeyboardKey.metaRight,
                                        LogicalKeyboardKey.superKey,
                                      ];
                                      for (final k in metaKeys) {
                                        if (HardwareKeyboard.instance.logicalKeysPressed.contains(k)) {
                                          isMeta = true;
                                          break;
                                        }
                                      }
                                    }
                                    if (isMeta) modifiers.add('meta');

                                    // Check for Ctrl+Alt+Shift combination to release mouse
                                    if (HardwareKeyboard.instance.isControlPressed && HardwareKeyboard.instance.isAltPressed && HardwareKeyboard.instance.isShiftPressed) {
                                      _releaseMouse();
                                      setState(() {
                                        // _lastKey = 'Ctrl+Alt+Shift (Released Mouse)'; // Removed as _lastKey is no longer used
                                      });
                                      return; // Do not process as a regular key event
                                    }


                                    String key = event.logicalKey.keyLabel.isNotEmpty
                                        ? event.logicalKey.keyLabel
                                        : event.logicalKey.debugName ?? event.runtimeType.toString();
                                    key = key.toLowerCase();

                                    // Map cursor keys to short names
                                    const arrowMap = {
                                      'arrow left': 'left',
                                      'arrow right': 'right',
                                      'arrow up': 'up',
                                      'arrow down': 'down',
                                    };
                                    if (arrowMap.containsKey(key)) {
                                      key = arrowMap[key]!;
                                    }

                                    // Account for caps lock: if caps lock is on and key is a single letter, send uppercase (unless shift is also pressed)
                                    bool isCapsLockOn = _capsLockOn;
                                    bool isShift = modifiers.contains('shift');
                                    if (key.length == 1 && key.codeUnitAt(0) >= 97 && key.codeUnitAt(0) <= 122) { // a-z
                                      if (isCapsLockOn != isShift) {
                                        key = key.toUpperCase();
                                      }
                                    }

                                    // List of modifier key labels (all lowercase)
                                    const modifierKeys = [
                                      'shift', 'ctrl', 'control', 'alt', 'meta', 'super', 'windows', 'command', 'option'
                                    ];

                                    // Only send if the key is not a modifier
                                    if (!modifierKeys.contains(key)) {
                                      setState(() {
                                        // _lastKey = [...modifiers, key].join('+'); // Removed as _lastKey is no longer used
                                      });
                                      // Send to websocket
                                      if (_ws != null && _ws!.readyState == WebSocket.open) {
                                        final msg = <String, dynamic>{
                                          'type': 'key_combination',
                                          'keys': [key],
                                          'modifiers': modifiers,
                                        };
                                        _ws!.add(jsonEncode(msg));
                                      }
                                    }
                                  }
                                },
                                child: Mjpeg(
                                  key: _videoKey,
                                  stream: widget.url,
                                  isLive: true,
                                  error: (context, error, stack) => const Center(child: Text('Stream error')),
                                  loading: (context) => const Center(child: CircularProgressIndicator()),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              StatusBarWidget(
                capsLockOn: _capsLockOn,
                onCapsLockToggle: () {
                  setState(() {
                    _capsLockOn = !_capsLockOn;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class StatusBarWidget extends StatefulWidget {
  final bool capsLockOn;
  final VoidCallback? onCapsLockToggle;
  const StatusBarWidget({super.key, required this.capsLockOn, this.onCapsLockToggle});

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
      final response = await http.get(Uri.parse('http://rocky2:3000/api/status'));
      if (response.statusCode == 200) {
        setState(() {
          _statusData = jsonDecode(response.body);
        });
      } else {
        debugPrint('Failed to load status: ${response.statusCode}');
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Video indicator
          Row(
            children: [
              Icon(Icons.videocam, color: video['actual_fps'] != null ? enabledColor : neutralColor, size: 20),
              const SizedBox(width: 4),
              Text(
                video['resolution'] != null && video['actual_fps'] != null
                    ? '${video['resolution']} @ ${video['actual_fps']?.toStringAsFixed(2)} fps'
                    : 'No Video',
                style: TextStyle(
                  color: video['actual_fps'] != null ? enabledColor : neutralColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (video['fps'] != null) ...[
                const SizedBox(width: 2),
                Text('(${video['fps']} target)', style: TextStyle(color: neutralColor, fontSize: 12)),
              ]
            ],
          ),
          const SizedBox(width: 18),
          // Keyboard indicator
          Icon(Icons.keyboard,
              color: keyboard['enabled'] == true ? enabledColor : disabledColor, size: 20),
          const SizedBox(width: 18),
          // Mouse indicator
          Icon(Icons.mouse,
              color: mouse['enabled'] == true ? enabledColor : disabledColor, size: 20),
          const SizedBox(width: 18),
          // ECM indicator
          Row(
            children: [
              Icon(Icons.usb,
                  color: ecm['up'] == true ? enabledColor : disabledColor, size: 20),
              const SizedBox(width: 4),
              Text(
                ecm['up'] == true ? 'ECM Up' : 'ECM Down',
                style: TextStyle(
                  color: ecm['up'] == true ? enabledColor : disabledColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
    );
  }
}
