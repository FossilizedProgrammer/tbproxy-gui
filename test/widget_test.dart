import 'package:flutter_test/flutter_test.dart';

import 'package:tbgui/settings.dart';
import 'package:tbgui/tbproxy.dart';

void main() {
  test('settings survive a JSON round-trip', () {
    final s = Settings(
      email: 'me@mail.com',
      password: 's3cret',
      country: 'uk',
      socksPort: '1085',
      httpPort: '8085',
      upstreamSocks: '127.0.0.1:1090',
      upstreamHttp: '',
      useUpstream: false,
      systemwide: true,
      share: true,
    );
    final back = Settings.fromJson(s.toJson());
    expect(back.email, 'me@mail.com');
    expect(back.password, 's3cret');
    expect(back.country, 'uk');
    expect(back.socksPort, '1085');
    expect(back.httpPort, '8085');
    expect(back.upstreamSocks, '127.0.0.1:1090');
    expect(back.useUpstream, isFalse);
    expect(back.systemwide, isTrue);
    expect(back.share, isTrue);
  });

  test('bad or missing values fall back to defaults', () {
    final s = Settings.fromJson(const {});
    expect(s.country, 'de');
    expect(s.socksPort, '1081');
    expect(s.httpPort, '8081');
    expect(s.email, '');
    expect(s.systemwide, isFalse);
    // An old config without the key keeps the previous behaviour: upstream on.
    expect(s.useUpstream, isTrue);

    final bad = Settings.fromJson(const {'socks_port': 'banana', 'http_port': '99999'});
    expect(bad.socksPort, '1081');
    expect(bad.httpPort, '8081');
  });

  test('connect command carries credentials, country and ports', () {
    final args = TbProxy.connectArgs(Settings(
      email: 'a@b.c',
      password: 'pw',
      country: 'us-west',
      socksPort: '1111',
      httpPort: '2222',
    ));
    expect(args, containsAllInOrder(['-user', 'a@b.c']));
    expect(args, containsAllInOrder(['-pass', 'pw']));
    expect(args, containsAllInOrder(['-country', 'us-west']));
    expect(args, containsAllInOrder(['-socks', '127.0.0.1:1111']));
    expect(args, containsAllInOrder(['-http', '127.0.0.1:2222']));
    expect(args, isNot(contains('-system')));
    expect(args, isNot(contains('-share')));
  });

  test('optional flags are only added when enabled', () {
    final s = Settings(
      email: 'a@b.c',
      password: 'pw',
      country: 'de',
      systemwide: true,
      share: true,
      upstreamSocks: '127.0.0.1:1080',
      upstreamHttp: '127.0.0.1:8080',
    );
    final args = TbProxy.connectArgs(s);
    expect(args, contains('-system'));
    expect(args, contains('-share'));
    expect(args, containsAllInOrder(['-upstream-socks', '127.0.0.1:1080']));
    expect(args, containsAllInOrder(['-upstream-http', '127.0.0.1:8080']));

    // -check mode must not touch the tun device.
    final check = TbProxy.checkArgs(s);
    expect(check, contains('-check'));
    expect(check.indexOf('-check'), lessThan(check.length));
  });

  test('upstream switch off means -upstream off and no upstream addresses', () {
    final off = TbProxy.connectArgs(Settings(
      email: 'a@b.c',
      password: 'pw',
      country: 'de',
      useUpstream: false,
      // Filled in but switched off — they must not be sent.
      upstreamSocks: '127.0.0.1:1080',
      upstreamHttp: '127.0.0.1:8080',
    ));
    expect(off, containsAllInOrder(['-upstream', 'off']));
    expect(off, isNot(contains('-upstream-socks')));
    expect(off, isNot(contains('-upstream-http')));

    // -check honours the switch too.
    final offCheck = TbProxy.checkArgs(Settings(useUpstream: false));
    expect(offCheck, containsAllInOrder(['-upstream', 'off']));

    // Switched on (default): nothing extra is passed, the CLI auto-detects.
    final on = TbProxy.connectArgs(Settings(email: 'a@b.c', password: 'pw'));
    expect(on, isNot(contains('-upstream')));
    expect(on, isNot(contains('off')));
  });

  test('tbproxy binary is discoverable from the repo checkout', () {
    expect(TbProxy.findBinary(), isNotNull);
  });
}
