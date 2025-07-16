import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show File, Platform, WebSocket;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'widgets/video_player_widget.dart';
import 'widgets/status_bar_widget.dart';

void main() {
  runApp(const MyApp());
}



class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  // Load previously used backend URLs from file
  Future<void> _loadUrls() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/kv_urls.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> urls = jsonDecode(content);
        setState(() {
          _previousUrls = urls.cast<String>();
          _loadingUrls = false;
          if (_previousUrls.isNotEmpty) {
            _urlController.text = _previousUrls.first;
          }
        });
      } else {
        setState(() {
          _previousUrls = [];
          _loadingUrls = false;
        });
      }
    } catch (e) {
      setState(() {
        _previousUrls = [];
        _loadingUrls = false;
      });
    }
  }

  // Save a backend URL to the file
  Future<void> _saveUrl(String url) async {
    if (!_previousUrls.contains(url)) {
      _previousUrls.insert(0, url);
      if (_previousUrls.length > 10) {
        _previousUrls = _previousUrls.sublist(0, 10);
      }
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/kv_urls.json');
      await file.writeAsString(jsonEncode(_previousUrls));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KV: Remote KVM',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: _backendUrl == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Enter Backend URL')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _loadingUrls
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _urlController,
                              decoration: const InputDecoration(
                                labelText: 'Backend URL',
                                hintText: 'e.g. http://localhost:3000',
                              ),
                              keyboardType: TextInputType.url,
                              onSubmitted: (value) => _submitUrl(),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _submitUrl,
                              child: const Text('Connect'),
                            ),
                            if (_previousUrls.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Text('Previously used URLs:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ListView.builder(
                                shrinkWrap: true,
                                itemCount: _previousUrls.length,
                                itemBuilder: (context, index) {
                                  final url = _previousUrls[index];
                                  return ListTile(
                                    title: Text(url),
                                    onTap: () {
                                      setState(() {
                                        _urlController.text = url;
                                      });
                                    },
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            )
          : Scaffold(
              appBar: AppBar(
                backgroundColor: Theme.of(context).colorScheme.inversePrimary,
                title: const Text('KV: Remote KVM'),
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: VideoPlayerWidget(
                      backendUrl: _backendUrl!,
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _submitUrl() async {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      await _saveUrl(url);
      setState(() {
        _backendUrl = url;
      });
    }
  }
  String? _backendUrl;
  final TextEditingController _urlController = TextEditingController();
  List<String> _previousUrls = [];
  bool _loadingUrls = true;

  @override
  void initState() {
    super.initState();
    _loadUrls();
  }


  @override
  void dispose() {
    // ...existing code...
    super.dispose();
  }
}

