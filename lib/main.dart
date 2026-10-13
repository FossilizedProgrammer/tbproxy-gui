import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_window_close/flutter_window_close.dart';

import 'settings.dart';
import 'tbproxy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TbguiApp());
}

class TbguiApp extends StatelessWidget {
  const TbguiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'tbproxy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Settings _s = Settings();
  List<String> _countries = <String>[];
  final List<String> _log = <String>[];

  Process? _proc;
  String _state = 'idle'; // idle | connecting | connected | stopping | error
  String _detail = '';
  bool _root = false;
  bool _busy = false;
  bool _loaded = false;
  bool _stoppingByUser = false;
  String? _cli;

  Timer? _saveTimer;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _socksCtrl = TextEditingController();
  final _httpCtrl = TextEditingController();
  final _upSocksCtrl = TextEditingController();
  final _upHttpCtrl = TextEditingController();
  final _logScroll = ScrollController();

  // Widget keys — also used by TBGUI_DEBUG_RECTS=1 to dump geometry.
  final _emailKey = GlobalKey();
  final _passKey = GlobalKey();
  final _countryKey = GlobalKey();
  final _socksKey = GlobalKey();
  final _httpKey = GlobalKey();
  final _connectKey = GlobalKey();
  final _checkKey = GlobalKey();
  final _disconnectKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Closing the window must not drop the tunnel silently: disconnect
    // first (SIGTERM + wait, same as the Disconnect button), and only then
    // allow the window to close.
    FlutterWindowClose.setWindowShouldCloseHandler(() async {
      if (_running) {
        _add('Window closed while connected — disconnecting first ...');
        await _disconnect();
      }
      return true;
    });
    _boot();
  }

  /// Debug aid (TBGUI_DEBUG_RECTS=1): log where each control sits on screen.
  void _reportRects() {
    if (Platform.environment['TBGUI_DEBUG_RECTS'] != '1') return;
    final widgets = <String, GlobalKey>{
      'email': _emailKey,
      'pass': _passKey,
      'country': _countryKey,
      'socks': _socksKey,
      'http': _httpKey,
      'connect': _connectKey,
      'check': _checkKey,
      'disconnect': _disconnectKey,
    };
    for (final e in widgets.entries) {
      final rb = e.value.currentContext?.findRenderObject();
      if (rb is! RenderBox || !rb.hasSize) continue;
      final o = rb.localToGlobal(Offset.zero);
      _add('rect ${e.key} ${o.dx.round()},${o.dy.round()} '
          '${rb.size.width.round()}x${rb.size.height.round()}');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _proc?.kill(ProcessSignal.sigkill);
    for (final c in [
      _emailCtrl,
      _passCtrl,
      _socksCtrl,
      _httpCtrl,
      _upSocksCtrl,
      _upHttpCtrl,
      _logScroll,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- boot ---

  Future<void> _boot() async {
    _s = await Settings.load();
    _emailCtrl.text = _s.email;
    _passCtrl.text = _s.password;
    _socksCtrl.text = _s.socksPort;
    _httpCtrl.text = _s.httpPort;
    _upSocksCtrl.text = _s.upstreamSocks;
    _upHttpCtrl.text = _s.upstreamHttp;
    setState(() => _loaded = true);
    _add('settings loaded: '
        'email=${_s.email.isEmpty ? '(empty)' : _s.email}, '
        'password=${_s.password.isEmpty ? 'not saved' : 'saved'}, '
        'country=${_s.country}, '
        'config=${Settings.configPath()}');

    _root = await TbProxy.isRoot();
    final bin = TbProxy.findBinary();
    if (bin == null) {
      _add('error: tbproxy binary not found next to the app, in this folder '
          'or on PATH (set TBPROXY=/path/to/tbproxy)');
      setState(() {});
      return;
    }
    _cli = bin;
    _add('tbproxy: $bin');
    if (!_root) {
      _add('warning: not running as root — the tun device needs it. '
          'Relaunch as root: ${TbProxy.rootHint()}');
      // Visible, modal message — the log line alone is easy to miss.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRootDialog());
    }
    setState(() {});
    try {
      final list = await TbProxy.countries(bin);
      setState(() => _countries = list);
      _add('loaded ${list.length} server countries');
    } catch (e) {
      _add('error: could not load countries: $e');
    }
    setState(() {});
    _add('ready 🐻');
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportRects());
  }

  // ------------------------------------------------------------ utilities ---

  void _add(String line) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final entry = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $line';
    _log.add(entry);
    if (_log.length > 2000) _log.removeRange(0, _log.length - 2000);
    // Optional mirror for debugging: TBGUI_LOG_FILE=/tmp/tbgui.log
    final mirror = Platform.environment['TBGUI_LOG_FILE'];
    if (mirror != null && mirror.isNotEmpty) {
      try {
        File(mirror).writeAsStringSync('$entry\n', mode: FileMode.append);
      } catch (_) {
        // Never let the debug mirror break the UI.
      }
    }
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _setState(String state, [String detail = '']) {
    if (!mounted) return;
    setState(() {
      _state = state;
      _detail = detail;
    });
  }

  /// The tunnel device can only be created as root; without it openvpn dies
  /// with `TUNSETIFF ... Operation not permitted`. Tell the user once,
  /// visibly, instead of letting the connection fail halfway.
  Future<void> _showRootDialog() async {
    if (!mounted) return;
    final cmd = TbProxy.rootHint();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Root required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('tbproxy needs root to create the VPN tunnel device (tun). '
                'Without it the connection cannot be established.'),
            const SizedBox(height: 12),
            const Text('Relaunch as root with:'),
            const SizedBox(height: 6),
            SelectableText(
              cmd,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: cmd));
              Navigator.of(ctx).pop();
            },
            child: const Text('copy command'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      final err = await _s.save();
      if (err != null) _add('warning: $err');
    });
  }

  bool get _running => _proc != null;

  // ------------------------------------------------------------- actions ---

  Future<void> _connect() async {
    if (_running || _busy) return;
    if (!_root) {
      _add('error: not running as root — relaunch as root: '
          '${TbProxy.rootHint()}');
      await _showRootDialog();
      return;
    }
    if (_s.email.isEmpty || _s.password.isEmpty) {
      _add('Enter email + password first.');
      return;
    }
    if (_cli == null) {
      _add('error: tbproxy binary not found.');
      return;
    }
    await _s.save();
    _stoppingByUser = false;
    _setState('connecting', 'starting');
    _add('Connecting to ${_s.country} '
        '(socks :${_s.socksPort}, http :${_s.httpPort}) ...');
    _add('\$ $_cli ${TbProxy.connectArgs(_s).join(' ')}');

    try {
      final p = await Process.start(
        _cli!,
        TbProxy.connectArgs(_s),
        workingDirectory: File(_cli!).parent.path,
      );
      _proc = p;
      if (mounted) setState(() {});
      p.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      p.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);

      final code = await p.exitCode;
      _proc = null;
      if (!mounted) return;
      if (_stoppingByUser || code == 0) {
        _setState('idle', 'stopped');
        if (_stoppingByUser) _add('Disconnected.');
      } else {
        _setState('error', 'exit code $code');
        _add('error: tbproxy exited with code $code');
      }
      setState(() {});
    } catch (e) {
      _proc = null;
      _setState('error', '$e');
      _add('error: could not start tbproxy: $e');
    }
  }

  Future<void> _disconnect() async {
    final p = _proc;
    if (p == null) return;
    _stoppingByUser = true;
    _setState('stopping', 'shutting down');
    _add('Disconnecting ...');
    p.kill(ProcessSignal.sigterm);
    try {
      await p.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _add('warning: still alive after SIGTERM — sending SIGKILL');
      p.kill(ProcessSignal.sigkill);
      await p.exitCode.timeout(const Duration(seconds: 5));
    }
  }

  Future<void> _check() async {
    if (_running || _busy) return;
    if (_s.email.isEmpty || _s.password.isEmpty) {
      _add('Enter email + password first.');
      return;
    }
    if (_cli == null) {
      _add('error: tbproxy binary not found.');
      return;
    }
    await _s.save();
    setState(() => _busy = true);
    _add('Checking login ...');
    try {
      final r = await Process.run(
        _cli!,
        TbProxy.checkArgs(_s),
        workingDirectory: File(_cli!).parent.path,
      );
      final out = '${r.stdout}${r.stderr}'
          .split('\n')
          .where((l) => l.trim().isNotEmpty);
      for (final l in out) {
        _add(l);
      }
      switch (r.exitCode) {
        case 0:
          _add('CHECK OK ✅');
          break;
        case 1:
          _add('CHECK FAILED: wrong email or password');
          break;
        default:
          _add('CHECK FAILED (code ${r.exitCode})');
      }
    } catch (e) {
      _add('error: check failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onLine(String line) {
    final l = line.trimRight();
    if (l.isEmpty) return;
    if (l.contains('tunnel up, starting local proxy') ||
        l.contains('tunnel connected')) {
      _setState('connected', _s.country);
      _add('Connected ✅  $l');
      return;
    }
    _add(l);
  }

  // ----------------------------------------------------------------- ui ----

  Color _stateColor() => switch (_state) {
        'connected' => Colors.greenAccent,
        'connecting' || 'stopping' => Colors.amberAccent,
        'error' => Colors.redAccent,
        _ => const Color(0xFF94A3B8),
      };

  String get _stateLabel => _state == 'connected'
      ? 'connected'
      : (_detail.isEmpty ? _state : '$_state · $_detail');

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final items = <String>{..._countries, _s.country}.toList();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _header(),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: TextField(
                            key: _emailKey,
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'you@mail.com',
                            ),
                            onChanged: (v) {
                              _s.email = v.trim();
                              _scheduleSave();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: _passKey,
                            controller: _passCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                            onChanged: (v) {
                              _s.password = v;
                              _scheduleSave();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: _countryKey,
                        initialValue: _s.country,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Server country'),
                        items: [
                          for (final c in items)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _s.country = v);
                          _scheduleSave();
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            key: _socksKey,
                            controller: _socksCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'SOCKS5 port',
                              hintText: '1081',
                            ),
                            onChanged: (v) {
                              _s.socksPort = v.trim();
                              _scheduleSave();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: _httpKey,
                            controller: _httpCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'HTTP proxy port',
                              hintText: '8081',
                            ),
                            onChanged: (v) {
                              _s.httpPort = v.trim();
                              _scheduleSave();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        'Apps use: socks5://127.0.0.1:${_s.socksPort.isEmpty ? '1081' : _s.socksPort}'
                        ' · http://127.0.0.1:${_s.httpPort.isEmpty ? '8081' : _s.httpPort}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  key: _connectKey,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _running ? null : _connect,
                  child: Text(
                    _running ? 'Connected — running…' : 'Connect',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      key: _checkKey,
                      onPressed: (_running || _busy) ? null : _check,
                      child: const Text('Check login'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      key: _disconnectKey,
                      onPressed: _running ? _disconnect : null,
                      child: const Text('Disconnect'),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    children: [
                      _switchRow(
                        'System-wide',
                        'all traffic via VPN',
                        _s.systemwide,
                        (v) {
                          setState(() => _s.systemwide = v);
                          _scheduleSave();
                        },
                      ),
                      _switchRow(
                        'Share on LAN',
                        'bind 0.0.0.0 instead of 127.0.0.1',
                        _s.share,
                        (v) {
                          setState(() => _s.share = v);
                          _scheduleSave();
                        },
                      ),
                      _switchRow(
                        'Fast UDP',
                        'off = stable TCP (default)',
                        _s.fastUdp,
                        (v) {
                          setState(() => _s.fastUdp = v);
                          _scheduleSave();
                        },
                      ),
                      const Divider(height: 20),
                      Text(
                        'Advanced — upstreams for filtered networks',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _switchRow(
                        'Use upstream proxy',
                        'on = auto-detect a local proxy (or use the fields below); '
                            'off = always connect directly',
                        _s.useUpstream,
                        (v) {
                          setState(() => _s.useUpstream = v);
                          _scheduleSave();
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _upSocksCtrl,
                            enabled: _s.useUpstream,
                            decoration: const InputDecoration(
                              hintText: 'upstream SOCKS 127.0.0.1:1080',
                            ),
                            onChanged: (v) {
                              _s.upstreamSocks = v.trim();
                              _scheduleSave();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _upHttpCtrl,
                            enabled: _s.useUpstream,
                            decoration: const InputDecoration(
                              hintText: 'upstream HTTP 127.0.0.1:8080',
                            ),
                            onChanged: (v) {
                              _s.upstreamHttp = v.trim();
                              _scheduleSave();
                            },
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Text('Log',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white.withValues(alpha: 0.75))),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: _log.join('\n')));
                            _add('log copied to clipboard');
                          },
                          child: const Text('copy'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _log.clear()),
                          child: const Text('clear'),
                        ),
                      ]),
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView.builder(
                          controller: _logScroll,
                          itemCount: _log.length,
                          itemBuilder: (_, i) {
                            final line = _log[i];
                            final err = line.contains('error') ||
                                line.contains('FAILED');
                            return Text(
                              line,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.5,
                                fontFamily: 'monospace',
                                color: err
                                    ? Colors.redAccent
                                    : const Color(0xFFCBD5E1),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          const Text('🐻', style: TextStyle(fontSize: 34)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TunnelBear',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  'via tbproxy · proxy-only by default',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _stateColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_stateLabel,
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
              ],
            ),
          ),
        ],
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      );
}
