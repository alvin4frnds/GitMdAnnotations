import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/domain/ports/git_port.dart';
import 'package:gitmdscribe/infra/git/git_adapter.dart';

/// Shell unit test for [GitAdapter]. Heavy libgit2 round-trips belong in
/// `integration_test/infra/git/git_adapter_test.dart` — this file only
/// proves the public shape at the Dart VM level:
///
/// - default ctor constructs without throwing (no isolate spawned yet —
///   spawning is lazy on first request),
/// - it implements the [GitPort] interface,
/// - [GitAdapter.dispose] completes cleanly on a fresh, never-used adapter.
void main() {
  group('GitAdapter (shell)', () {
    test('default ctor constructs and implements GitPort', () {
      final adapter = GitAdapter();
      expect(adapter, isA<GitPort>());
    });

    test('dispose on an unused adapter completes without error', () async {
      final adapter = GitAdapter();
      await adapter.dispose();
    });

    test('accepts an optional credentialsLoader seam', () {
      final adapter = GitAdapter(credentialsLoader: () async => 'token-abc');
      expect(adapter, isA<GitPort>());
    });
  });
}
