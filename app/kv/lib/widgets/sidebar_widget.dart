import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

class SidebarWidget extends StatefulWidget {
  final bool isOpen;
  final Function(String) onSendText;
  final Function(String) onSendKey;
  final Function(List<String>, List<String>) onSendCombination;
  final Function(String) onSendMouseClick;
  final VoidCallback onToggle;
  final String backendUrl;

  const SidebarWidget({
    super.key,
    required this.isOpen,
    required this.onSendText,
    required this.onSendKey,
    required this.onSendCombination,
    required this.onSendMouseClick,
    required this.onToggle,
    required this.backendUrl,
  });

  @override
  State<SidebarWidget> createState() => SidebarWidgetState();
}

class SidebarWidgetState extends State<SidebarWidget> {
  final Map<String, ExpansionTileController> _sectionControllers = {
    'keyboard': ExpansionTileController(),
    'mouse': ExpansionTileController(),
    'usb': ExpansionTileController(),
    'network': ExpansionTileController(),
    'video': ExpansionTileController(), // New video section controller
  };

  List<String> _availableQualities = [];
  String? _selectedQuality;

  void expandSection(String sectionId) {
    _sectionControllers.forEach((key, controller) {
      if (key == sectionId) {
        if (!controller.isExpanded) {
          controller.expand();
        }
      } else {
        if (controller.isExpanded) {
          controller.collapse();
        }
      }
    });
  }
  final TextEditingController _textController = TextEditingController();
  List<String> _usbImages = [];
  String? _selectedUsbImage;
  bool _ecmEnabled = false;

  @override
  void initState() {
    super.initState();
    _fetchUsbImages();
    _fetchEcmStatus();
    _fetchVideoQualities();
  }

  @override
  void didUpdateWidget(SidebarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _fetchUsbImages();
      _fetchEcmStatus();
      _fetchVideoQualities();
    }
  }

  Future<void> _fetchVideoQualities() async {
    try {
      final response = await http.get(Uri.parse('${widget.backendUrl}/api/status'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _availableQualities = List<String>.from(data['video']?['qualities'] ?? []);
          _selectedQuality = data['video']?['selected_quality'];
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _setVideoQuality(String quality) async {
    try {
      await http.post(
        Uri.parse('${widget.backendUrl}/api/video/quality'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'quality': quality}),
      );
      _fetchVideoQualities();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _fetchUsbImages() async {
    try {
      final response = await http.get(Uri.parse('${widget.backendUrl}/api/storage/images'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _usbImages = List<String>.from(data['images']);
          _selectedUsbImage = data['selected'];
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _fetchEcmStatus() async {
    try {
      final response = await http.get(Uri.parse('${widget.backendUrl}/api/status'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _ecmEnabled = data['ecm']?['enabled'] ?? false;
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _selectUsbImage(String? imageName) async {
    try {
      await http.post(
        Uri.parse('${widget.backendUrl}/api/storage/select'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': imageName}),
      );
      _fetchUsbImages();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _uploadUsbImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      var request = http.MultipartRequest('POST', Uri.parse('${widget.backendUrl}/api/storage/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', result.files.single.path!));
      await request.send();
      _fetchUsbImages();
    }
  }

  Future<void> _setEthernet(bool enable) async {
    try {
      await http.post(Uri.parse('${widget.backendUrl}/api/ethernet/${enable ? 'enable' : 'disable'}'));
      _fetchEcmStatus();
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    double sidebarWidth;
    if (widget.isOpen) {
      if (isLandscape) {
        sidebarWidth = screenWidth * 0.5;
      } else {
        sidebarWidth = screenWidth * 0.9;
      }
    } else {
      sidebarWidth = 48;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: sidebarWidth,
      color: Colors.grey.shade200,
      child: Row(
        children: [
          if (widget.isOpen)
            Expanded(
              child: _buildSidebarContent(),
            ),
          IconButton(
            icon: Icon(widget.isOpen ? Icons.chevron_right : Icons.chevron_left),
            onPressed: widget.onToggle,
            tooltip: widget.isOpen ? 'Close sidebar' : 'Open sidebar',
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarContent() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children: [
        _buildKeyboardSection(),
        const Divider(),
        _buildMouseButtonSection(),
        const Divider(),
        _buildUsbDriveSection(),
        const Divider(),
        _buildNetworkSection(),
        const Divider(),
        _buildVideoSection(), // New video section
      ],
    );
  }

 Widget _buildKeyboardSection() {
    return ExpansionTile(
      controller: _sectionControllers['keyboard'],
      title: const Text('Keyboard'),
      initiallyExpanded: false,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(hintText: 'Type text to send...'),
                onSubmitted: (value) {
                  widget.onSendText(value);
                  _textController.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                widget.onSendText(_textController.text);
                _textController.clear();
              },
            ),
          ],
        ),
        Divider(),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: {
            'Enter': 'enter',
            'Tab': 'tab',
            'Esc': 'escape',
            'Backspace': 'backspace',
            'Delete': 'delete',
            'Space': 'space',
          }.entries.map((entry) {
            return ElevatedButton(
              onPressed: () => widget.onSendKey(entry.value),
              child: Text(entry.key),
            );
          }).toList(),
        ),
        Divider(),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: {
            'Ctrl+C': [['ctrl'], ['c']],
            'Ctrl+V': [['ctrl'], ['v']],
            'Ctrl+X': [['ctrl'], ['x']],
            'Ctrl+Z': [['ctrl'], ['z']],
            'Ctrl+A': [['ctrl'], ['a']],
            'Alt+Tab': [['alt'], ['tab']],
          }.entries.map((entry) {
            return ElevatedButton(
              onPressed: () => widget.onSendCombination(entry.value[0], entry.value[1]),
              child: Text(entry.key),
            );
          }).toList(),
        ),
      ],
    );
  } 

  Widget _buildMouseButtonSection() {
    return ExpansionTile(
      controller: _sectionControllers['mouse'],
      title: const Text('Mouse Buttons'),
      initiallyExpanded: false,
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: {
            'L Click': 'left',
            'R Click': 'right',
            'M Click': 'middle',
          }.entries.map((entry) {
            return ElevatedButton(
              onPressed: () => widget.onSendMouseClick(entry.value),
              child: Text(entry.key),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildUsbDriveSection() {
    return ExpansionTile(
      controller: _sectionControllers['usb'],
      title: const Text('Virtual USB Drive'),
      initiallyExpanded: false,
      children: [
        ..._usbImages.map((image) => ListTile(
              title: Text(image),
              trailing: _selectedUsbImage == image
                  ? const Icon(Icons.eject, color: Colors.green)
                  : const Icon(Icons.play_arrow),
              onTap: () => _selectUsbImage(_selectedUsbImage == image ? null : image),
            )),
        ElevatedButton.icon(
          onPressed: _uploadUsbImage,
          icon: const Icon(Icons.upload_file),
          label: const Text('Upload Image'),
        ),
      ],
    );
  }

  Widget _buildNetworkSection() {
    return ExpansionTile(
      controller: _sectionControllers['network'],
      title: const Text('Network (ECM)'),
      initiallyExpanded: false,
      children: [
        SwitchListTile(
          title: const Text('Enable Ethernet'),
          value: _ecmEnabled,
          onChanged: (value) => _setEthernet(value),
        ),
      ],
    );
  }

  Widget _buildVideoSection() {
    return ExpansionTile(
      controller: _sectionControllers['video'],
      title: const Text('Video'),
      initiallyExpanded: false,
      children: [
        ListTile(
          title: const Text('Resolution'),
          trailing: DropdownButton<String>(
            value: _selectedQuality,
            onChanged: (String? newValue) {
              if (newValue != null) {
                _setVideoQuality(newValue);
              }
            },
            items: _availableQualities.map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoControlsSection() {
    return const ExpansionTile(
      title: Text('Video Controls'),
      initiallyExpanded: true,
      children: [
        ListTile(title: Text('Fullscreen: F11 or Ctrl+F')),
        ListTile(title: Text('Screenshot: Ctrl+S or Alt+S')),
        ListTile(title: Text('Input Capture: Click on video')),
        ListTile(title: Text('Release Input: ESC key')),
      ],
    );
  }
}
