import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'firestore_sync_service_provider.dart';
import 'tracked_series_provider.dart';

/// Starts a pull/merge/push cycle whenever a Firebase account becomes active.
final firestoreSyncOnSignInProvider = Provider<void>((ref) {
  ref.listen(authStateProvider, (previous, next) {
    final user = next.valueOrNull;
    if (user == null || previous?.valueOrNull?.uid == user.uid) return;

    unawaited(() async {
      try {
        await ref.read(firestoreSyncServiceProvider).syncForUser(user.uid);
        ref.invalidate(trackedSeriesProvider);
      } catch (error) {
        debugPrint('ReadToon kitaplığı eşitlenemedi: $error');
      }
    }());
  });
});
