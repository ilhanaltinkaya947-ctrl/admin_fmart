import 'dart:io';

import 'package:admin_fmart/core/api/api_client.dart';
import 'package:admin_fmart/core/storage/token_storage.dart';
import 'package:admin_fmart/features/banners/data/banners_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the multipart encoding of the banner window fields.
///
/// This exists because the first version of this feature was SILENTLY DEAD
/// CODE. It signalled "clear this date" with an empty string; FastAPI coerces
/// an empty form value to None for Optional[str], so "" was indistinguishable
/// from "field not sent" and the clear never happened — PATCH returned 200
/// with the old date intact.
///
/// A DB-layer test missed it because it called the parsing helper directly and
/// the helper was correct. The BINDING was wrong. These assertions sit on the
/// client side of that boundary: they read what the repository hands to Dio,
/// so a regression back to "" fails here instead of in production.
void main() {
  late List<FormData> sent;

  /// Build a repository whose transport captures the outgoing FormData and
  /// returns a canned banner. Never touches the network.
  BannersRepository buildRepo() {
    sent = [];
    final api = ApiClient(
      baseUrl: 'http://localhost',
      tokenStorage: TokenStorage(),
      onUnauthorized: () {},
    );
    // Insert BEFORE the auth interceptor so we intercept the request first
    // and resolve it, meaning TokenStorage is never consulted (it would need
    // secure storage, which is unavailable in a unit test).
    api.dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = options.data;
          if (data is FormData) sent.add(data);
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: <String, dynamic>{
              'id': 1,
              'image_url': 'https://example.invalid/x.jpg',
              'sort_order': 0,
              'active': true,
              'starts_at': null,
              'ends_at': null,
              'created_at': '2026-06-15T12:00:00Z',
              'updated_at': '2026-06-15T12:00:00Z',
            },
          ));
        },
      ),
    );
    return BannersRepository(api: api);
  }

  /// Read a text field back out of a captured multipart body.
  String? fieldOf(FormData form, String key) {
    for (final f in form.fields) {
      if (f.key == key) return f.value;
    }
    return null;
  }

  List<String> keysOf(FormData form) => form.fields.map((f) => f.key).toList();

  File tmpFile() {
    final f = File('${Directory.systemTemp.path}/banner_repo_test.jpg');
    f.writeAsBytesSync(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    return f;
  }

  group('update — clearing a date', () {
    test('clearStartsAt sends the literal token "null", not ""', () async {
      await buildRepo().update(id: 1, clearStartsAt: true);
      final v = fieldOf(sent.single, 'starts_at');
      expect(v, 'null',
          reason: 'an empty string is indistinguishable from an omitted field '
              'once FastAPI binds it, so the clear silently does nothing');
      expect(v, isNot(''));
    });

    test('clearEndsAt sends the literal token "null"', () async {
      await buildRepo().update(id: 1, clearEndsAt: true);
      expect(fieldOf(sent.single, 'ends_at'), 'null');
    });

    test('setting a date sends ISO-8601 in UTC', () async {
      await buildRepo().update(id: 1, startsAt: DateTime.utc(2030, 1, 1));
      final v = fieldOf(sent.single, 'starts_at');
      expect(v, isNotNull);
      expect(v, isNot('null'));
      expect(v, '2030-01-01T00:00:00.000Z');
      expect(v!.endsWith('Z'), isTrue, reason: 'must be UTC');
    });

    test('omitting a date sends NO key at all (leave alone)', () async {
      await buildRepo().update(id: 1);
      expect(keysOf(sent.single), isNot(contains('starts_at')));
      expect(keysOf(sent.single), isNot(contains('ends_at')));
    });

    test('clear wins over a simultaneously-supplied date', () async {
      await buildRepo().update(
        id: 1,
        startsAt: DateTime.utc(2030, 1, 1),
        clearStartsAt: true,
      );
      expect(fieldOf(sent.single, 'starts_at'), 'null');
    });

    test('clearing one date does not disturb the other', () async {
      await buildRepo().update(
        id: 1,
        clearEndsAt: true,
        startsAt: DateTime.utc(2030, 1, 1),
      );
      expect(fieldOf(sent.single, 'starts_at'), '2030-01-01T00:00:00.000Z');
      expect(fieldOf(sent.single, 'ends_at'), 'null');
    });
  });

  group('create — ordering', () {
    test('omits sort_order when null so the backend appends', () async {
      await buildRepo().create(imageFile: tmpFile(), sortOrder: null);
      expect(keysOf(sent.single), isNot(contains('sort_order')),
          reason: 'sending 0 here is what used to shove every new banner to '
              'the front of the carousel');
    });

    test('sends an explicit sort_order when the operator pinned one', () async {
      await buildRepo().create(imageFile: tmpFile(), sortOrder: 7);
      expect(fieldOf(sent.single, 'sort_order'), '7');
    });

    test('create sends an empty window when none was chosen', () async {
      await buildRepo().create(imageFile: tmpFile());
      // On CREATE, empty is treated as absent by the backend -> no window,
      // which is correct: a brand-new banner has no dates yet.
      expect(fieldOf(sent.single, 'starts_at'), '');
      expect(fieldOf(sent.single, 'ends_at'), '');
    });

    test('create with a window sends ISO-8601 for both', () async {
      await buildRepo().create(
        imageFile: tmpFile(),
        startsAt: DateTime.utc(2030, 1, 1),
        endsAt: DateTime.utc(2030, 2, 1),
      );
      expect(fieldOf(sent.single, 'starts_at'), '2030-01-01T00:00:00.000Z');
      expect(fieldOf(sent.single, 'ends_at'), '2030-02-01T00:00:00.000Z');
    });

    test('active is always sent on create', () async {
      await buildRepo().create(imageFile: tmpFile(), active: false);
      expect(fieldOf(sent.single, 'active'), 'false');
    });
  });
}
