import 'dart:convert';
import 'dart:io';

/// Everything the GUI remembers between runs: credentials, selected country,
/// local proxy ports and the optional upstreams.
class Settings {
  String email;
  String password;
  String country;
  String socksPort;
  String httpPort;
  bool useUpstream;
  String upstreamSocks;
  String upstreamHttp;
  bool systemwide;
  bool share;
  bool fastUdp;

  Settings({
    this.email = '',
    this.password = '',
    this.country = 'de',
    this.socksPort = '1081',
    this.httpPort = '8081',
    this.useUpstream = true,
    this.upstreamSocks = '',
    this.upstreamHttp = '',
    this.systemwide = false,
    this.share = false,
    this.fastUdp = false,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'country': country,
        'socks_port': socksPort,
        'http_port': httpPort,
        'use_upstream': useUpstream,
        'upstream_socks': upstreamSocks,
        'upstream_http': upstreamHttp,
        'systemwide': systemwide,
        'share': share,
        'fast_udp': fastUdp,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        email: j['email'] as String? ?? '',
        password: j['password'] as String? ?? '',
        country: _str(j['country'], 'de'),
        socksPort: _port(j['socks_port'], '1081'),
        httpPort: _port(j['http_port'], '8081'),
        // Missing key (config written by an older version) = enabled.
        useUpstream: j['use_upstream'] as bool? ?? true,
        upstreamSocks: j['upstream_socks'] as String? ?? '',
        upstreamHttp: j['upstream_http'] as String? ?? '',
        systemwide: j['systemwide'] as bool? ?? false,
        share: j['share'] as bool? ?? false,
        fastUdp: j['fast_udp'] as bool? ?? false,
      );

  static String _str(Object? v, String fallback) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  static String _port(Object? v, String fallback) {
    final n = int.tryParse('${v ?? ''}'.trim());
    if (n == null || n < 1 || n > 65535) return fallback;
    return '$n';
  }

  /// Config file location: %APPDATA% on Windows,
  /// ~/.config (XDG aware) everywhere else.
  static String configPath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final base =
          (appData != null && appData.isNotEmpty) ? appData : '.';
      return '$base\\tbproxy-gui\\config.json';
    }
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : '${Platform.environment['HOME'] ?? '.'}/.config';
    return '$base/tbproxy-gui/config.json';
  }

  static Future<Settings> load() async {
    try {
      final f = File(configPath());
      if (!f.existsSync()) return Settings();
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return Settings.fromJson(decoded);
    } catch (_) {
      // Unreadable/corrupt config: fall back to defaults rather than crash.
    }
    return Settings();
  }

  /// Returns null when the file could not be written (e.g. wrong owner).
  Future<String?> save() async {
    try {
      final f = File(configPath());
      await f.parent.create(recursive: true);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
      return null;
    } catch (e) {
      return 'could not save $configPath(): $e';
    }
  }
}
