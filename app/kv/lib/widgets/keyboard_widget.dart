import 'package:flutter/material.dart';

class KeyboardWidget extends StatefulWidget {
  final void Function(String key, {List<String> modifiers}) onKeyPress;
  const KeyboardWidget({super.key, required this.onKeyPress});

  @override
  State<KeyboardWidget> createState() => _KeyboardWidgetState();
}

class _KeyboardWidgetState extends State<KeyboardWidget> {
  bool _shiftOn = false;
  bool _ctrlOn = false;
  bool _altOn = false;

  // 65% keyboard layout rows, all lowercase, no caps lock
  static const List<List<String>> _baseKeys = [
    ['esc', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 'backspace'],
    ['tab', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', 'enter'],
    ['shift', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/','up'],
    ['ctrl', 'win', 'alt', 'space', 'menu', 'left', 'down', 'right'],
  ];

  // Shifted values for number row and symbols
  static const Map<String, String> _shiftMap = {
    '1': '!', '2': '@', '3': '#', '4': '\$', '5': '%', '6': '^', '7': '&', '8': '*', '9': '(', '0': ')',
    '-': '_', '=': '+', '[': '{', ']': '}', '\\': '|', ';': ':', '\'': '"', ',': '<', '.': '>', '/': '?',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _baseKeys.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            final isSpace = key == 'space';
            final isShift = key == 'shift';
            final isCtrl = key == 'ctrl';
            final isAlt = key == 'alt';
            final isEnter = key == 'enter';
            final isBackspace = key == 'backspace';
            Widget child;
            if (key == 'left') {
              child = const Icon(Icons.arrow_back);
            } else if (key == 'right') {
              child = const Icon(Icons.arrow_forward);
            } else if (key == 'up') {
              child = const Icon(Icons.arrow_upward);
            } else if (key == 'down') {
              child = const Icon(Icons.arrow_downward);
            } else if (isShift) {
              child = const Icon(Icons.file_upload);
            } else if (isEnter) {
              child = const Icon(Icons.keyboard_return);
            } else if (isBackspace) {
              child = const Icon(Icons.backspace);
            } else {
              String display = key;
              if (_shiftOn) {
                if (key.length == 1 && RegExp(r'[a-z]').hasMatch(key)) {
                  display = key.toUpperCase();
                } else if (_shiftMap.containsKey(key)) {
                  display = _shiftMap[key]!;
                }
              }
              child = Text(
                display,
                style: const TextStyle(fontSize: 14),
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              );
            }
            // The spacebar should be as wide as the number of keys it visually replaces (here: 5 keys wide)
            Color? bgColor;
            if (isShift && _shiftOn) bgColor = Colors.blue;
            if (isCtrl && _ctrlOn) bgColor = Colors.blue;
            if (isAlt && _altOn) bgColor = Colors.blue;
            final button = SizedBox(
              width: isSpace ? 290 : 40, // 40 * 5 = 200
              height: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: bgColor,
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => _handleKey(key),
                child: child,
              ),
            );
            return Padding(
              padding: const EdgeInsets.all(1.0),
              child: button,
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  void _handleKey(String key) {
    final lower = key.toLowerCase();
    if (lower == 'ctrl' || lower == 'control') {
      setState(() {
        _ctrlOn = !_ctrlOn;
      });
    } else if (lower == 'alt') {
      setState(() {
        _altOn = !_altOn;
      });
    } else if (lower == 'shift') {
      setState(() {
        _shiftOn = !_shiftOn;
      });
    } else if (lower == 'win') {
      widget.onKeyPress('meta', modifiers: ['meta']);
    } else if (lower == 'menu') {
      widget.onKeyPress('contextmenu');
    } else if (lower == 'space') {
      widget.onKeyPress('space', modifiers: _getActiveModifiers());
    } else if (lower == 'tab') {
      widget.onKeyPress('tab', modifiers: _getActiveModifiers());
    } else if (lower == 'enter') {
      widget.onKeyPress('enter', modifiers: _getActiveModifiers());
    } else if (lower == 'backspace') {
      widget.onKeyPress('backspace', modifiers: _getActiveModifiers());
    } else if (lower == 'esc') {
      widget.onKeyPress('escape', modifiers: _getActiveModifiers());
    } else if (lower == 'left' || lower == 'right' || lower == 'up' || lower == 'down') {
      widget.onKeyPress(lower, modifiers: _getActiveModifiers());
    } else {
      String sendKey = key;
      if (_shiftOn) {
        if (key.length == 1 && RegExp(r'[a-z]').hasMatch(key)) {
          sendKey = key.toUpperCase();
        } else if (_shiftMap.containsKey(key)) {
          sendKey = _shiftMap[key]!;
        }
      }
      widget.onKeyPress(sendKey, modifiers: _getActiveModifiers());
    }
  }

  List<String> _getActiveModifiers() {
    final mods = <String>[];
    if (_ctrlOn) mods.add('control');
    if (_altOn) mods.add('alt');
    if (_shiftOn) mods.add('shift');
    return mods;
  }
}
