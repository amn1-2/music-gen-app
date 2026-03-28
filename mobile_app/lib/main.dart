import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // for kReleaseMode
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Global base URL – switches automatically
const String baseUrl = kReleaseMode
    ? 'https://musicgen-backend-rm7c.onrender.com'
    : 'http://localhost:8000';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Music Generator',
      theme: ThemeData(primarySwatch: Colors.green),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const MainScreen(),
      },
    );
  }
}

// ---------- Auth Wrapper ----------
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final storage = const FlutterSecureStorage();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final token = await storage.read(key: 'token');
    if (token != null) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : const SizedBox(),
      ),
    );
  }
}

// ---------- Auth Service ----------
class AuthService {
  final storage = const FlutterSecureStorage();

  Future<bool> register(String username, String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );
    return response.statusCode == 200;
  }

  Future<bool> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': username, 'password': password},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await storage.write(key: 'token', value: data['access_token']);
      return true;
    }
    return false;
  }

  Future<void> logout() async => await storage.delete(key: 'token');
  Future<String?> getToken() async => await storage.read(key: 'token');

  Future<Map<String, String>> get authHeaders async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}

// ---------- Login Screen ----------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final success = await AuthService().login(
        _usernameController.text,
        _passwordController.text,
      );
      setState(() => _isLoading = false);
      if (success) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login failed. Check username/password.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text('Login'),
                    ),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/register'),
                child: const Text('Don\'t have an account? Register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Register Screen ----------
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  Future<void> _register() async {
    if (_formKey.currentState!.validate() &&
        _passwordController.text == _confirmController.text) {
      setState(() => _isLoading = true);
      final auth = AuthService();
      final success = await auth.register(
        _usernameController.text,
        _emailController.text,
        _passwordController.text,
      );
      setState(() => _isLoading = false);
      if (success) {
        final loginSuccess = await auth.login(
          _usernameController.text,
          _passwordController.text,
        );
        if (loginSuccess) {
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registration failed. Username/email may already exist.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _register,
                      child: const Text('Register'),
                    ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed('/login'),
                child: const Text('Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Main Screen (Tabs) ----------
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final auth = AuthService();
  final _libraryKey = GlobalKey<_MusicLibraryScreenState>();

  void _refreshLibrary() {
    _libraryKey.currentState?._loadTracks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎵 AI Music Generator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          MusicGeneratorScreen(onTrackGenerated: _refreshLibrary),
          MusicLibraryScreen(key: _libraryKey),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note),
            label: 'Generate',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'My Music',
          ),
        ],
      ),
    );
  }
}

// ---------- Generate Screen ----------
class MusicGeneratorScreen extends StatefulWidget {
  final VoidCallback? onTrackGenerated;
  const MusicGeneratorScreen({super.key, this.onTrackGenerated});

  @override
  State<MusicGeneratorScreen> createState() => _MusicGeneratorScreenState();
}

class _MusicGeneratorScreenState extends State<MusicGeneratorScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _titleController = TextEditingController(
    text: 'My Track',
  );
  final TextEditingController _promptController = TextEditingController(
    text: 'upbeat electronic dance track with synth melody',
  );
  final TextEditingController _durationController = TextEditingController(
    text: '30',
  );
  String _selectedModel = 'medium';

  bool _isLoading = false;
  String _statusMessage = '';
  double _progress = 0.0;
  String? _jobId;
  Timer? _pollTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _titleController.dispose();
    _promptController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _generateMusic() async {
    final title = _titleController.text.trim();
    final prompt = _promptController.text.trim();
    final duration = int.tryParse(_durationController.text.trim());
    if (title.isEmpty || prompt.isEmpty || duration == null || duration < 5) {
      _showSnackBar('Please fill all fields correctly (duration ≥5)');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Starting generation...';
      _progress = 0.0;
      _jobId = null;
    });

    try {
      final auth = AuthService();
      final headers = await auth.authHeaders;
      final response = await http.post(
        Uri.parse('$baseUrl/generate'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'prompt': prompt,
          'duration': duration,
          'model_size': _selectedModel,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to start generation: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      _jobId = data['job_id'];

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        await _checkStatus();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _checkStatus() async {
    if (_jobId == null) return;

    try {
      final auth = AuthService();
      final headers = await auth.authHeaders;
      final response = await http.get(
        Uri.parse('$baseUrl/status/$_jobId'),
        headers: headers,
      );
      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          _pollTimer?.cancel();
          setState(() {
            _isLoading = false;
            _statusMessage = 'Job not found.';
          });
        }
        return;
      }

      final data = jsonDecode(response.body);
      final status = data['status'] as String;
      final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;

      setState(() {
        _statusMessage = _getStatusMessage(status);
        _progress = progress;
      });

      if (status == 'completed') {
        _pollTimer?.cancel();
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ Done!';
        });
        widget.onTrackGenerated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Track saved! Check My Music.')),
        );
      } else if (status == 'failed') {
        _pollTimer?.cancel();
        setState(() {
          _isLoading = false;
          _statusMessage = '❌ Failed: ${data['error']}';
        });
      }
    } catch (e) {
      _pollTimer?.cancel();
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error checking status: $e';
      });
    }
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'loading_model':
        return '⏳ Downloading model (first run only)...';
      case 'generating':
        return '🎵 Generating music...';
      case 'saving':
        return '💾 Saving file...';
      default:
        return 'Status: $status';
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
            enabled: !_isLoading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Describe your music'),
            enabled: !_isLoading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Duration (seconds)'),
            enabled: !_isLoading,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            items: const [
              DropdownMenuItem(value: 'small', child: Text('Small (fast)')),
              DropdownMenuItem(
                value: 'medium',
                child: Text('Medium (balanced)'),
              ),
              DropdownMenuItem(
                value: 'large',
                child: Text('Large (best quality)'),
              ),
            ],
            onChanged: _isLoading
                ? null
                : (value) => setState(() => _selectedModel = value!),
            decoration: const InputDecoration(labelText: 'Model size'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _generateMusic,
            child: const Text('Generate Music'),
          ),
          const SizedBox(height: 24),
          if (_statusMessage.isNotEmpty) ...[
            Text(_statusMessage, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
          ],
          if (_progress > 0 && _progress < 100) ...[
            LinearProgressIndicator(value: _progress / 100),
            const SizedBox(height: 4),
            Text('${_progress.toStringAsFixed(2)}%'),
          ],
        ],
      ),
    );
  }
}

// ---------- Track Model ----------
class Track {
  final int id;
  final String jobId;
  final String title;
  final String fileName;
  final DateTime createdAt;
  final int duration;

  Track({
    required this.id,
    required this.jobId,
    required this.title,
    required this.fileName,
    required this.createdAt,
    required this.duration,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] ?? 0,
      jobId: json['job_id'] ?? '',
      title: json['title'] ?? 'Untitled',
      fileName: json['filename']?.toString().split('/').last ?? '',
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      duration: json['duration'] ?? 0,
    );
  }
}

// ---------- My Music Screen ----------
class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({super.key});

  @override
  State<MusicLibraryScreen> createState() => _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends State<MusicLibraryScreen> {
  List<Track> _tracks = [];
  bool _isLoading = true;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadTracks() async {
    setState(() => _isLoading = true);
    try {
      final auth = AuthService();
      final headers = await auth.authHeaders;
      final response = await http.get(
        Uri.parse('$baseUrl/my-tracks'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        setState(() {
          _tracks = jsonList.map((json) => Track.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        print('Load tracks failed: ${response.statusCode}');
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load tracks: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading tracks: $e');
    }
  }

  Future<void> _deleteTrack(Track track) async {
    print('Delete pressed for job: ${track.jobId}');
    try {
      final auth = AuthService();
      final headers = await auth.authHeaders;
      final response = await http.delete(
        Uri.parse('$baseUrl/tracks/${track.jobId}'),
        headers: headers,
      );
      print('Delete response: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200) {
        print('Reloading tracks...');
        await _loadTracks();
        print('After reload, tracks count: ${_tracks.length}');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${track.title} deleted')));
      } else {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Delete error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _shareTrack(Track track) async {
    try {
      final auth = AuthService();
      final headers = await auth.authHeaders;
      final downloadUrl = '$baseUrl/download/${track.jobId}';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing file for sharing...')),
      );

      final response = await http.get(Uri.parse(downloadUrl), headers: headers);
      if (response.statusCode != 200) throw Exception('Download failed');

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${track.fileName}');
      await tempFile.writeAsBytes(response.bodyBytes);

      if (!await tempFile.exists()) throw Exception('File not saved');

      await Share.shareXFiles([
        XFile(tempFile.path),
      ], text: 'Check out my AI generated track: ${track.title}');

      tempFile.delete();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _playTrack(Track track) async {
    try {
      final auth = AuthService();
      final headers = await auth.authHeaders;
      final downloadUrl = '$baseUrl/download/${track.jobId}';
      final response = await http.get(Uri.parse(downloadUrl), headers: headers);
      if (response.statusCode != 200) throw Exception('Download failed');

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${track.fileName}');
      await tempFile.writeAsBytes(response.bodyBytes);
      if (!await tempFile.exists()) throw Exception('File not saved');

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _AudioPlayerSheet(
          audioPlayer: _audioPlayer,
          filePath: tempFile.path,
          trackTitle: track.title,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Playback failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
          ? const Center(child: Text('No tracks yet. Generate some music!'))
          : RefreshIndicator(
              onRefresh: _loadTracks,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _tracks.length,
                itemBuilder: (context, index) {
                  final track = _tracks[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.audiotrack,
                        color: Colors.green,
                      ),
                      title: Text(track.title),
                      subtitle: Text(
                        '${_formatDate(track.createdAt)} • ${track.duration}s',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.play_arrow,
                              color: Colors.blue,
                            ),
                            onPressed: () => _playTrack(track),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share, color: Colors.grey),
                            onPressed: () => _shareTrack(track),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteTrack(track),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
}

// ---------- Audio Player Bottom Sheet ----------
class _AudioPlayerSheet extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final String filePath;
  final String trackTitle;

  const _AudioPlayerSheet({
    required this.audioPlayer,
    required this.filePath,
    required this.trackTitle,
  });

  @override
  State<_AudioPlayerSheet> createState() => _AudioPlayerSheetState();
}

class _AudioPlayerSheetState extends State<_AudioPlayerSheet> {
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await widget.audioPlayer.setSourceDeviceFile(widget.filePath);
    _positionSubscription = widget.audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _position = Duration(
            milliseconds: p.inMilliseconds.clamp(0, _duration.inMilliseconds),
          );
        });
      }
    });
    _durationSubscription = widget.audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playerStateSubscription = widget.audioPlayer.onPlayerStateChanged.listen((
      state,
    ) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    await widget.audioPlayer.resume();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    widget.audioPlayer.stop();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final twoDigits = (int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final double sliderValue = _position.inMilliseconds.toDouble().clamp(
      0,
      _duration.inMilliseconds.toDouble(),
    );
    final double maxValue = _duration.inMilliseconds.toDouble().clamp(
      0,
      double.infinity,
    );

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.trackTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Slider(
            value: sliderValue,
            max: maxValue > 0 ? maxValue : 1.0,
            onChanged: (value) {
              widget.audioPlayer.seek(Duration(milliseconds: value.toInt()));
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position)),
                Text(_formatDuration(_duration)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 48,
                ),
                onPressed: () async {
                  if (_isPlaying) {
                    await widget.audioPlayer.pause();
                  } else {
                    await widget.audioPlayer.resume();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
