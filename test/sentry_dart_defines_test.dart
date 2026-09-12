// DART_DEFINES in Release.xcconfig must be encoded the way Flutter decodes it.
//
// Build 1.1.10+52 shipped with crash reporting silently dead. The value was
// ONE base64 blob of a comma-joined string, but Flutter splits on ',' FIRST
// and only then base64-decodes each item:
//
//   flutter_tools/lib/src/build_info.dart  decodeDartDefines()
//     value.split(',').map(base64.decoder.fuse(utf8.decoder).convert)
//
// So Dart received a single define — key SENTRY_DSN, value the whole rest of
// the string. `Dsn.parse()` does not throw on that (pathSegments is non-empty),
// so projectId became "4511363319922768,SENTRY_ENVIRONMENT=production" and
// every envelope was POSTed to a URL that does not exist. SENTRY_ENVIRONMENT
// was never defined. The app ran perfectly and reported nothing for six weeks.
//
// main.dart's release guard did not catch it: it checks the DSN is non-EMPTY,
// not that it is VALID. This file is the missing validity check, moved to a
// place that runs before a build instead of after one.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Exactly what flutter_tools does, so this test cannot disagree with the build.
List<String> _decodeDartDefines(String raw) => raw
    .split(',')
    .map(base64.decoder.fuse(utf8.decoder).convert)
    .toList();

String _rawDartDefines() {
  final file = File('ios/Flutter/Release.xcconfig');
  expect(file.existsSync(), isTrue,
      reason: 'Release.xcconfig missing — run this from the package root');
  final line = file.readAsLinesSync().firstWhere(
        (l) => l.startsWith('DART_DEFINES='),
        orElse: () => '',
      );
  expect(line, isNotEmpty,
      reason: 'Release.xcconfig has no DART_DEFINES — release archives would '
          'ship with no DSN at all');
  return line.substring('DART_DEFINES='.length).trim();
}

Map<String, String> _defines() {
  final out = <String, String>{};
  for (final d in _decodeDartDefines(_rawDartDefines())) {
    final i = d.indexOf('=');
    expect(i, greaterThan(0), reason: 'define is not KEY=VALUE: $d');
    out[d.substring(0, i)] = d.substring(i + 1);
  }
  return out;
}

void main() {
  test('the value is a comma-joined LIST, not one blob', () {
    // The exact regression. A single item means someone base64'd the whole
    // joined string again.
    final items = _rawDartDefines().split(',');
    expect(items.length, greaterThanOrEqualTo(2),
        reason: 'DART_DEFINES is a single item — base64 each KEY=VALUE pair '
            'separately and join with commas, or every define after the first '
            'is swallowed into the first one\'s value');
  });

  test('no define value contains a comma', () {
    // A comma inside a decoded value is the fingerprint of the bug: it means
    // a second pair got glued onto the first one's value.
    _defines().forEach((k, v) {
      expect(v.contains(','), isFalse,
          reason: '$k has a comma in its value — another pair is glued on: $v');
    });
  });

  test('SENTRY_DSN is a valid Sentry DSN', () {
    final dsn = _defines()['SENTRY_DSN'];
    expect(dsn, isNotNull, reason: 'no SENTRY_DSN baked into release archives');

    final uri = Uri.parse(dsn!);
    expect(uri.scheme, 'https');
    expect(uri.userInfo, isNotEmpty, reason: 'DSN carries no public key');
    expect(uri.pathSegments, isNotEmpty);

    // This is what Sentry uses as projectId, and what the broken value
    // poisoned. It must be digits and nothing else.
    final projectId = uri.pathSegments.last;
    expect(RegExp(r'^\d+$').hasMatch(projectId), isTrue,
        reason: 'projectId is not numeric — events will POST to a URL that '
            'does not exist and be dropped silently. Got: $projectId');
  });

  test('SENTRY_ENVIRONMENT survives as its own define', () {
    // It was absent entirely in the broken encoding, and only looked right
    // because main.dart happens to default to 'production'.
    expect(_defines()['SENTRY_ENVIRONMENT'], 'production');
  });

  test('SENTRY_RELEASE is NOT baked', () {
    // sentry_flutter derives it from package info. A hand-maintained tag went
    // stale at admin@1.0.0+18 while the app shipped 1.1.x, filing every crash
    // under an ancient build.
    expect(_defines().containsKey('SENTRY_RELEASE'), isFalse,
        reason: 'remove SENTRY_RELEASE — it goes stale on every version bump');
  });
}
