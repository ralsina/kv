import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'dart:io' show WebSocket;
import 'dart:convert';
import 'status_bar_widget.dart';
import 'sidebar_widget.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String backendUrl;
  const VideoPlayerWidget({super.key, required this.backendUrl});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  void _sendWsMessage(dynamic msg) {
    if (_ws == null) return;
    final encoded = jsonEncode(msg);
    _ws.add(encoded);
  }
  bool _sidebarOpen = false;
  bool _capsLockOn = false;
  dynamic _ws;
  bool _pointerCaptured = false;
  Offset? _lastPointerPosition;
  int _pressedButtons = 0;
  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _focusNode.requestFocus();
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
      final wsUrl = widget.backendUrl.replaceFirst(RegExp(r'^http'), 'ws') + '/ws/input';
      _ws = await WebSocket.connect(wsUrl);
    } catch (e) {}
  }

  bool get _wsOpen {
    if (_ws == null) return false;
    return _ws.readyState == WebSocket.open;
  }
  final FocusNode _focusNode = FocusNode();

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

  List<String> _getPressedButtonNames() {
    final names = <String>[];
    if (_pressedButtons & 1 != 0) names.add('left');
    if (_pressedButtons & 2 != 0) names.add('right');
    if (_pressedButtons & 4 != 0) names.add('middle');
    return names;
  }

  @override
  void dispose() {
    if (_ws != null) {
      try {
        _ws.close();
      } catch (_) {}
    }
    _focusNode.dispose();
  }

  final GlobalKey _videoKey = GlobalKey();
  final GlobalKey<SidebarWidgetState> _sidebarKey = GlobalKey<SidebarWidgetState>();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.basic,
                  onHover: (PointerHoverEvent event) {
                    final renderBox = _videoKey.currentContext?.findRenderObject() as RenderBox?;
                    if (renderBox != null) {
                      final localPosition = renderBox.globalToLocal(event.position);
                      final width = renderBox.size.width;
                      final height = renderBox.size.height;
                      if (localPosition.dx >= 0 && localPosition.dy >= 0 &&
                          localPosition.dx <= width && localPosition.dy <= height) {
                        int absX = ((localPosition.dx / width) * 32767).clamp(0, 32767).round();
                        int absY = ((localPosition.dy / height) * 32767).clamp(0, 32767).round();
                        if (_wsOpen) {
                          final msg = <String, dynamic>{
                            'type': 'mouse_absolute',
                            'x': absX,
                            'y': absY,
                          };
                          _sendWsMessage(msg);
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
                        onPointerMove: (event) {
                          final renderBox = _videoKey.currentContext?.findRenderObject() as RenderBox?;
                          if (renderBox != null) {
                            final localPosition = renderBox.globalToLocal(event.position);
                            final width = renderBox.size.width;
                            final height = renderBox.size.height;
                            if (localPosition.dx >= 0 && localPosition.dy >= 0 &&
                                localPosition.dx <= width && localPosition.dy <= height) {
                              int absX = ((localPosition.dx / width) * 32767).clamp(0, 32767).round();
                              int absY = ((localPosition.dy / height) * 32767).clamp(0, 32767).round();
                              if (_wsOpen) {
                                final msg = <String, dynamic>{
                                  'type': 'mouse_absolute',
                                  'x': absX,
                                  'y': absY,
                                  'buttons': _getPressedButtonNames(),
                                };
                                _sendWsMessage(msg);
                              }
                            }
                          }
                          _lastPointerPosition = event.position;
                        },
                        onPointerDown: (event) {
                          _captureMouse();
                          _focusNode.requestFocus();
                          setState(() {
                            _lastPointerPosition = event.position;
                            _pressedButtons = event.buttons;
                          });
                          if (_wsOpen) {
                            String? buttonName = _getMouseButtonName(event.buttons);
                            if (buttonName != null) {
                              final msg = <String, dynamic>{
                                'type': 'mouse_press',
                                'button': buttonName,
                              };
                              _sendWsMessage(msg);
                            }
                          }
                        },
                        onPointerUp: (event) {
                          if (_wsOpen) {
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
                              _sendWsMessage(msg);
                            }
                          }
                          _pressedButtons = event.buttons;
                        },
                        child: KeyboardListener(
                          focusNode: _focusNode,
                          autofocus: true,
                          onKeyEvent: (KeyEvent event) {
                            if (_sidebarOpen) return;
                            if (event is KeyDownEvent || event is KeyRepeatEvent) {
                              if (event.logicalKey == LogicalKeyboardKey.capsLock && event is KeyDownEvent) {
                                setState(() {
                                  _capsLockOn = !_capsLockOn;
                                });
                                return;
                              }
                              final List<String> modifiers = [];
                              if (HardwareKeyboard.instance.isControlPressed) modifiers.add('ctrl');
                              if (HardwareKeyboard.instance.isShiftPressed) modifiers.add('shift');
                              if (HardwareKeyboard.instance.isAltPressed) modifiers.add('alt');
                              bool isMeta = false;
                              if (HardwareKeyboard.instance.isMetaPressed) {
                                isMeta = true;
                              } else {
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
                              if (HardwareKeyboard.instance.isControlPressed && HardwareKeyboard.instance.isAltPressed && HardwareKeyboard.instance.isShiftPressed) {
                                _releaseMouse();
                                setState(() {});
                                return;
                              }
                              String key = event.logicalKey.keyLabel.isNotEmpty
                                  ? event.logicalKey.keyLabel
                                  : event.logicalKey.debugName ?? event.runtimeType.toString();
                              key = key.toLowerCase();
                              if (key == ' ') {
                                key = 'space';
                              }
                              const arrowMap = {
                                'arrow left': 'left',
                                'arrow right': 'right',
                                'arrow up': 'up',
                                'arrow down': 'down',
                              };
                              if (arrowMap.containsKey(key)) {
                                key = arrowMap[key]!;
                              }
                              bool isCapsLockOn = _capsLockOn;
                              bool isShift = modifiers.contains('shift');
                              if (key.length == 1 && key.codeUnitAt(0) >= 97 && key.codeUnitAt(0) <= 122) {
                                if (isCapsLockOn != isShift) {
                                  key = key.toUpperCase();
                                }
                              }
                              const modifierKeys = [
                                'shift', 'ctrl', 'control', 'alt', 'meta', 'super', 'windows', 'command', 'option'
                              ];
                              if (!modifierKeys.contains(key)) {
                                setState(() {});
                                if (_wsOpen) {
                                  final msg = <String, dynamic>{
                                    'type': 'key_combination',
                                    'keys': [key],
                                    'modifiers': modifiers,
                                  };
                                  _sendWsMessage(msg);
                                }
                              }
                            }
                          },
                          child: Mjpeg(
                            key: _videoKey,
                            stream: widget.backendUrl + '/video.mjpg',
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
                backendUrl: widget.backendUrl,
                capsLockOn: _capsLockOn,
                onCapsLockToggle: () {
                  setState(() {
                    _capsLockOn = !_capsLockOn;
                  });
                },
                onSectionTap: (sectionId) {
                  setState(() {
                    _sidebarOpen = true;
                  });
                  _sidebarKey.currentState?.expandSection(sectionId);
                },
              ),
            ],
          ),
        ),
        SidebarWidget(
          key: _sidebarKey,
          isOpen: _sidebarOpen,
          backendUrl: widget.backendUrl,
          onSendText: (text) => _sendWsMessage({'type': 'text', 'text': text}),
          onSendKey: (key) => _sendWsMessage({'type': 'key_press', 'key': key}),
          onSendCombination: (modifiers, keys) => _sendWsMessage({'type': 'key_combination', 'modifiers': modifiers, 'keys': keys}),
          onSendMouseClick: (button) => _sendWsMessage({'type': 'mouse_click', 'button': button}),
          onToggle: () {
            setState(() {
              _sidebarOpen = !_sidebarOpen;
            });
          },
        ),
      ],
    );
  }
}