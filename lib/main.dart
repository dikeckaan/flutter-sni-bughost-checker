import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await DatabaseHelper.instance.initializeDatabase();
  }
  runApp(const SniCheckerApp());
}

class SniCheckerApp extends StatefulWidget {
  const SniCheckerApp({super.key});

  @override
  SniCheckerAppState createState() => SniCheckerAppState();
}

class SniCheckerAppState extends State<SniCheckerApp> {
  bool _isDarkTheme = true;

  @override
  void initState() {
    super.initState();
    _loadThemeSetting();
  }

  void _loadThemeSetting() async {
    if (kIsWeb) return;
    int? themeSetting = await DatabaseHelper.instance.getThemeSetting();
    if (themeSetting != null) {
      setState(() {
        _isDarkTheme = themeSetting == 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNI Checker',
      theme: _isDarkTheme ? ThemeData.dark() : ThemeData.light(),
      home: SniCheckerHomePage(toggleTheme: _toggleTheme),
    );
  }

  void _toggleTheme() {
    setState(() {
      _isDarkTheme = !_isDarkTheme;
      if (!kIsWeb) {
        DatabaseHelper.instance.insertThemeSetting(_isDarkTheme ? 1 : 0);
      }
    });
  }
}

class SniCheckerHomePage extends StatefulWidget {
  final VoidCallback toggleTheme;

  const SniCheckerHomePage({super.key, required this.toggleTheme});

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
  void initState() {
    super.initState();
    _loadPreviousHosts();
  }

  void _loadPreviousHosts() async {
    if (kIsWeb) return;
    String? previousHosts = await DatabaseHelper.instance.getPreviousHosts();
    if (previousHosts != null) {
      setState(() {
        _controller.text = previousHosts;
      });
    }
  }

  void _checkSniForHosts() async {
    if (_isChecking) {
      setState(() {
        _isChecking = false;
        _isLoading = false;
      });
      return;
    }

    if (!kIsWeb) {
      await DatabaseHelper.instance.insertHosts(_controller.text);
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
      String content = await File(result.files.single.path!).readAsString();
      setState(() {
        _controller.text = content;
      });
    }
  }

  void _clearAll() async {
    if (!kIsWeb) {
      await DatabaseHelper.instance.clearDatabase();
    }
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
          IconButton(
            icon: Icon(_isDarkTheme(context) ? Icons.dark_mode : Icons.light_mode),
            onPressed: widget.toggleTheme,
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

  bool _isDarkTheme(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<void> initializeDatabase() async {
    if (kIsWeb) return;
    _database = await _initDatabase();
  }

  Future<Database> _initDatabase() async {
    String path = p.join(await getDatabasesPath(), 'sni_checker.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE settings (id INTEGER PRIMARY KEY, theme INTEGER, hosts TEXT)'
        );
      },
    );
  }

  Future<void> insertHosts(String hosts) async {
    if (kIsWeb) return;
    Database db = await instance.database;
    await db.insert(
      'settings',
      {'id': 1, 'hosts': hosts},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getPreviousHosts() async {
    if (kIsWeb) return null;
    Database db = await instance.database;
    List<Map<String, dynamic>> result = await db.query('settings', where: 'id = ?', whereArgs: [1]);
    if (result.isNotEmpty) {
      return result.first['hosts'] as String?;
    }
    return null;
  }

  Future<int?> getThemeSetting() async {
    if (kIsWeb) return null;
    Database db = await instance.database;
    List<Map<String, dynamic>> result = await db.query('settings', columns: ['theme'], where: 'id = ?', whereArgs: [1]);
    if (result.isNotEmpty) {
      return result.first['theme'] as int?;
    }
    return null;
  }

  Future<void> insertThemeSetting(int theme) async {
    if (kIsWeb) return;
    Database db = await instance.database;
    await db.insert(
      'settings',
      {'id': 1, 'theme': theme},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearDatabase() async {
    if (kIsWeb) return;
    Database db = await instance.database;
    await db.delete('settings');
  }
}
