import 'dart:io';

import 'settings.dart';

/// Everything the GUI needs to know about the `tbproxy` command line tool.
class TbProxy {
  /// Names searched in every ancestor directory (exe dir, CWD) until the
  /// binary is found: the repo checkout, the app bundle, then $PATH.
  static const _names = <String>[
    'tbproxy',
    'tbproxy.exe',
    'dist/tbproxy-linux-amd64',
    'dist/tbproxy-linux-arm64',
  ];

  /// Returns the path of the tbproxy binary, or null when it is not found.
  static String? findBinary() {
    final env = Platform.environment['TBPROXY'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) return env;

    final roots = <String>{
      File(Platform.resolvedExecutable).parent.path,
      Directory.current.path,
    };
    for (final start in roots) {
      var dir = start;
      for (var i = 0; i < 10; i++) {
        for (final name in _names) {
          final p = '$dir/$name';
          if (File(p).existsSync()) return p;
        }
        final parent = Directory(dir).parent.path;
        if (parent == dir) break;
        dir = parent;
      }
    }

    // Last resort: whatever `PATH` has (no window helper — try running it).
    for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
      if (dir.isEmpty) continue;
      for (final name in _names.take(2)) {
        final p = '$dir/$name';
        if (File(p).existsSync()) return p;
      }
    }
    return null;
  }

  /// Codes printed by `tbproxy -list-countries`.
  static Future<List<String>> countries(String bin) async {
    final r = await Process.run(bin, ['-list-countries']);
    if (r.exitCode != 0) {
      throw Exception(
          '-list-countries failed (exit ${r.exitCode}): ${_err(r.stderr)}');
    }
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// True when the process may create the tun device.
  static Future<bool> isRoot() async {
    try {
      final r = await Process.run('id', ['-u']);
      return (r.stdout as String).trim() == '0';
    } catch (_) {
      return false;
    }
  }

  /// `tbproxy` arguments for the Connect button.
  static List<String> connectArgs(Settings s) => _base(s);

  /// `tbproxy` arguments for the Check-login button (no tun device).
  static List<String> checkArgs(Settings s) => [
        ..._base(s),
        '-check',
        '-check-timeout',
        '60s',
      ];

  static List<String> _base(Settings s) => [
        '-user',
        s.email,
        '-pass',
        s.password,
        '-country',
        s.country,
        '-proto',
        s.fastUdp ? 'udp' : 'tcp',
        '-socks',
        '127.0.0.1:${s.socksPort}',
        '-http',
        '127.0.0.1:${s.httpPort}',
        if (s.systemwide) '-system',
        if (s.share) '-share',
        if (s.useUpstream) ...[
          if (s.upstreamSocks.isNotEmpty) ...['-upstream-socks', s.upstreamSocks],
          if (s.upstreamHttp.isNotEmpty) ...['-upstream-http', s.upstreamHttp],
        ] else ...[
          // Upstream switched off entirely: say so explicitly, otherwise the
          // CLI picks up a local proxy on 1080/8080 on its own.
          '-upstream',
          'off',
        ],
      ];

  static String _err(Object? e) => (e ?? '').toString().trim();
}
