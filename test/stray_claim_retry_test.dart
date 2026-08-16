// A retry must never replay a captured optimistic-concurrency token.
//
// Yandex uses `version` for optimistic concurrency on a claim. The stray-claim
// panel captured it when the panel loaded. If the courier accepted in the
// meantime, Yandex bumped it — so «Попробовать ещё раз» replayed the stale
// version and failed identically, forever. And because the error branch never
// refreshed `_lastLive`, nothing in the panel could recover: the manager's only
// escape was leaving the screen, while an uncancellable ~1,774₸ courier drove
// to a customer who was not there.
//
// Same class as the infinite-retry that got 1.9.0 archived.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File(
    'lib/features/delivery/presentation/delivery_section.dart',
  ).readAsStringSync();

  // Only the stray-claim panel, not the whole file.
  final panel = src.substring(src.indexOf('class _PickupStrayClaimViewState'));

  group('the stray-claim panel must not dead-end on failure', () {
    test('the failed state offers a REFRESH, not a blind retry', () {
      expect(panel, contains('Обновить статус'),
          reason: 'after a failure the action must re-read server truth');
      expect(panel.contains('Попробовать ещё раз'), isFalse,
          reason: 'a retry that replays the captured version fails forever');
    });

    test('the failure path re-reads the claim from the server', () {
      expect(panel, contains('initByOrder(widget.orderId)'),
          reason: 'version and _lastLive must come from the server, not from '
              'the stale snapshot the panel loaded with');
    });

    test('cancel still sends the version, but only on the NON-failed path', () {
      // The happy path is unchanged: a first cancel uses the loaded version.
      expect(panel, contains('_confirmAndCancel(live.claimId, live.version)'));
      // …and it is guarded by `failed`, so it cannot be the retry action.
      final iFailed = panel.indexOf('? () => context');
      final iCancel = panel.indexOf('_confirmAndCancel(live.claimId');
      expect(iFailed, greaterThan(-1));
      expect(iFailed, lessThan(iCancel),
          reason: 'the failed branch must come first, or the stale-version '
              'cancel is still what a retry runs');
    });

    test('a cancel that SUCCEEDED but failed to re-read also recovers', () {
      // cancelFlow wraps cancel AND the follow-up refresh in one try, so a
      // successful cancel with a failed re-read lands in DeliveryError too.
      // Re-reading resolves it honestly: the claim returns terminal and the
      // panel hides itself.
      expect(panel, contains('Не удалось подтвердить отмену'),
          reason: 'must not claim the cancel definitely failed');
    });
  });

  group('a route-scoped cubit must not emit after close', () {
    final cubit = File(
      'lib/features/delivery/state/delivery_cubit.dart',
    ).readAsStringSync();

    test('every emit goes through the closed-guard helper', () {
      expect(cubit, contains('if (isClosed) return;'));
      // Exactly one bare `emit(` — the one inside _safeEmit itself.
      final bare = RegExp(r'(?<![_A-Za-z])emit\(').allMatches(cubit).length;
      expect(bare, 1,
          reason: 'found $bare bare emits; the one that gets forgotten is the '
              'one that fires after the panel is popped');
    });

    test('the helper actually exists and is used', () {
      expect(cubit, contains('void _safeEmit(DeliveryState state)'));
      expect(RegExp(r'_safeEmit\(').allMatches(cubit).length, greaterThan(10));
    });
  });
}
