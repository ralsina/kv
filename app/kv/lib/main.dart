import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';

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
      // print('WebSocket connection error: $e');
    }
  }
  String _lastKey = '';
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


  @override
  Widget build(BuildContext context) {
    final isMobile = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: isMobile
              ? Stack(
                  children: [
                    Mjpeg(
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
                                _lastKey = value.characters.last;
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
                  cursor: _pointerCaptured ? SystemMouseCursors.none : SystemMouseCursors.basic,
                  onHover: (PointerHoverEvent event) {
                    if (_pointerCaptured) {
                      final dx = event.position.dx - (_lastPointerPosition?.dx ?? event.position.dx);
                      final dy = event.position.dy - (_lastPointerPosition?.dy ?? event.position.dy);
                      // Only send if there is movement
                      if ((dx != 0 || dy != 0)) {
                        if (_ws != null && _ws!.readyState == WebSocket.open) {
                          final msg = <String, dynamic>{
                            'type': 'mouse_move',
                            'x': dx.round(),
                            'y': dy.round(),
                            'buttons': [],
                          };
                          _ws!.add(jsonEncode(msg));
                        }
                      }
                      setState(() {
                        _lastPointerPosition = event.position;
                      });
                    }
                  },
                  child: Stack(
                    children: [
                      Mjpeg(
                        stream: widget.url,
                        isLive: true,
                        error: (context, error, stack) => const Center(child: Text('Stream error')),
                        loading: (context) => const Center(child: CircularProgressIndicator()),
                        fit: BoxFit.contain,
                      ),
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
                            if (event is KeyDownEvent) {
                              final List<String> modifiers = [];
                              if (HardwareKeyboard.instance.isControlPressed) modifiers.add('Ctrl');
                              if (HardwareKeyboard.instance.isShiftPressed) modifiers.add('Shift');
                              if (HardwareKeyboard.instance.isAltPressed) modifiers.add('Alt');
                              if (HardwareKeyboard.instance.isMetaPressed) modifiers.add('Meta');

                              // Check for Ctrl+Alt+Shift combination to release mouse
                              if (HardwareKeyboard.instance.isControlPressed && HardwareKeyboard.instance.isAltPressed && HardwareKeyboard.instance.isShiftPressed) {
                                _releaseMouse();
                                setState(() {
                                  _lastKey = 'Ctrl+Alt+Shift (Released Mouse)';
                                });
                                return; // Do not process as a regular key event
                              }

                              String key = event.logicalKey.keyLabel.isNotEmpty
                                  ? event.logicalKey.keyLabel
                                  : event.logicalKey.debugName ?? event.runtimeType.toString();
                              // If key is a single letter and shift is not pressed, make it lowercase
                              if (key.length == 1 && !HardwareKeyboard.instance.isShiftPressed) {
                                key = key.toLowerCase();
                              }
                              // Always send 'backspace' as lowercase
                              if (key.toLowerCase() == 'backspace') {
                                key = 'backspace';
                              }
                              setState(() {
                                _lastKey = [...modifiers, key].join('+');
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
                          },
                          child: Container(), // Empty container to ensure Listener gets events
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Last key: $_lastKey', style: const TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}
