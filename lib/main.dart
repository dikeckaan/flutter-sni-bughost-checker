import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  runApp(const SniCheckerApp());
}

class SniCheckerApp extends StatelessWidget {
  const SniCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNI Checker',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const SniCheckerHomePage(),
    );
  }
}

class SniCheckerHomePage extends StatefulWidget {
  const SniCheckerHomePage({super.key});

  @override
  SniCheckerHomePageState createState() => SniCheckerHomePageState();
}

class SniCheckerHomePageState extends State<SniCheckerHomePage> {
  final TextEditingController _parallelChecksController = TextEditingController(text: '5');
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _timeoutController = TextEditingController(text: '5');
  final List<String> _hosts = [];
  final List<String> _successHosts = [];
  int _successCount = 0;
  int _failCount = 0;
  bool _isLoading = false;
  bool _isChecking = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SNI Checker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  controller: _controller,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Enter hosts (one per line)',
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _timeoutController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Timeout (s)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _parallelChecksController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Parallel',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _pickFile,
                      child: const Text('Load from File'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _clearAll,
                  child: const Text('Clear All'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _checkSniForHosts,
                  child: Text(_isLoading ? 'Stop Checking' : 'Check SNI'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: TextEditingController(text: _hosts.join('\n')),
                  maxLines: 10,
                  readOnly: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Hosts Log',
                  ),
                ),
                const SizedBox(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Success: $_successCount'),
                    Text('Fail: $_failCount'),
                    const SizedBox(height: 10),
                    const Text('Successful Hosts:', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextField(
                      controller: TextEditingController(text: _successHosts.join('\n')),
                      maxLines: 5,
                      readOnly: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _copyToClipboard,
                      child: const Text('Copy to Clipboard'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _checkSniForHosts() async {
    if (_isChecking) {
      setState(() {
        _isChecking = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isChecking = true;
      _successHosts.clear();
      _successCount = 0;
      _failCount = 0;
      _hosts.clear();
    });

    List<String> hosts = _controller.text.split('\n');
    int timeout = int.tryParse(_timeoutController.text) ?? 10;
    int parallelChecks = int.tryParse(_parallelChecksController.text) ?? 3;

    List<Future<void>> futures = [];
    for (String host in hosts) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!_isChecking) break;

      host = host.trim();
      if (host.isNotEmpty) {
        futures.add(_checkSni(host, timeout).then((result) {
          if (!_isChecking) return;
          setState(() {
            if (result) {
              _successHosts.add(host);
              _successCount++;
            } else {
              _failCount++;
            }
            _hosts.add('$host - ${result ? "Success" : "Fail"}');
          });
        }));

        if (futures.length >= parallelChecks) {
          await Future.wait(futures);
          futures.clear();
        }
      }
    }

    await Future.wait(futures);

    setState(() {
      _isLoading = false;
      _isChecking = false;
    });
  }

  Future<bool> _checkSni(String hostname, int timeout) async {
    try {
      final url = Uri.https(hostname, '');
      final response = await http.get(url).timeout(Duration(seconds: timeout));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (result != null) {
      String content = String.fromCharCodes(result.files.single.bytes!);
      setState(() {
        _controller.text = content;
      });
    }
  }

  void _clearAll() {
    setState(() {
      _controller.clear();
      _hosts.clear();
      _successHosts.clear();
      _successCount = 0;
      _failCount = 0;
    });
  }

  void _copyToClipboard() {
    if (_successHosts.isNotEmpty) {
      String content = _successHosts.join('\n');
      Clipboard.setData(ClipboardData(text: content));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Success hosts copied to clipboard')),
      );
    }
  }
}
