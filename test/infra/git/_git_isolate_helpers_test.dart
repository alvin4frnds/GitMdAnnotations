import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/ports/git_port.dart';
import 'package:gitmdannotations_tablet/infra/git/_git_isolate_helpers.dart';

/// Unit tests for the push-error classifier in `_git_isolate_helpers.dart`.
///
/// These tests exercise [classifyPushError] (pure string-based) and
/// [pushOutcomeFor] (pure dispatch) with the set of libgit2 / smart-http
/// error phrasings we expect to see in the wild. The live
/// [mapPushError] wrapper threads the two together plus a `git2.Remote`
/// parameter used only for the informational `remoteSha`; the glue
/// between the three is trivial and is not exercised here because
/// constructing a `git2.Remote` requires a loaded libgit2 FFI lib, which
/// is not available under `fvm flutter test` on the Windows host. The
/// integration suite at `integration_test/sync_conflict_test.dart`
/// exercises the live path end-to-end.
///
/// Why substring-based: `libgit2dart 1.2.2` exposes only `toString()` on
/// `LibGit2Error` — the `git_error.klass` field is held behind a private
/// `Pointer<git_error>`. See the doc-comment on [classifyPushError] for
/// the full rationale + the "harden against real messages" follow-up.
void main() {
  group('classifyPushError', () {
    group('non-fast-forward', () {
      // Each of these is a real phrasing observed from libgit2 (1.0–1.5) or
      // the smart-http server side-band. Order-sensitivity (ambiguous
      // messages that match multiple buckets) is verified in the
      // "precedence" group below.
      const nonFastForwardMessages = <String>[
        'cannot push non-fastforwardable reference',
        'cannot push non fastforwardable reference',
        'non-fast-forward update',
        'updates were rejected because a pushed branch tip is behind',
        'updates were rejected because the tip of your current branch is '
            'behind its remote counterpart',
        'failed to push some refs to https://github.com/owner/repo.git',
        ' ! [rejected]        main -> main (non-fast-forward)',
        // libgit2 1.5 native — caught end-to-end by
        // integration_test/sync_conflict_test.dart 2026-04-21:
        'cannot push because a reference that you are trying to update on '
            'the remote contains commits that are not present locally.',
      ];

      for (final raw in nonFastForwardMessages) {
        test('classifies "$raw"', () {
          expect(
            classifyPushError(Exception(raw)),
            PushErrorCategory.nonFastForward,
          );
        });
      }
    });

    group('auth', () {
      const authMessages = <String>[
        'request failed with status code: 401',
        'request failed with status code: 403',
        'unexpected http status code: 401',
        'too many redirects or authentication replays',
        'authentication required but no callback set to retrieve '
            'credentials',
        'remote: Invalid username or password.',
        'fatal: Authentication failed for '
            'https://github.com/owner/repo.git',
        'remote: Bad credentials',
        'Unauthorized',
      ];

      for (final raw in authMessages) {
        test('classifies "$raw"', () {
          expect(
            classifyPushError(Exception(raw)),
            PushErrorCategory.auth,
          );
        });
      }
    });

    group('network', () {
      const networkMessages = <String>[
        'failed to connect to github.com: Connection refused',
        'failed to resolve address for github.com',
        'failed to send request: connection reset',
        'unexpected disconnection from remote',
        'curl error: 28 (Operation timed out after 10000 ms)',
        'ssl error: certificate has expired',
        'TLS error: handshake failed',
        'operation timed out',
        'connection reset by peer',
        'connection refused',
        'Network is unreachable',
        'No route to host',
      ];

      for (final raw in networkMessages) {
        test('classifies "$raw"', () {
          expect(
            classifyPushError(Exception(raw)),
            PushErrorCategory.network,
          );
        });
      }
    });

    group('unknown / fallback', () {
      const unknownMessages = <String>[
        '',
        'something completely unrelated blew up',
        'integer overflow in packfile offset',
        'repository corrupted: missing pack index',
        'disk full',
      ];

      for (final raw in unknownMessages) {
        test('classifies "$raw" as unknown', () {
          expect(
            classifyPushError(Exception(raw)),
            PushErrorCategory.unknown,
          );
        });
      }

      test('accepts any Object, not just Exception (uses toString)', () {
        // Concrete libgit2 errors are `LibGit2Error` which is not an
        // `Exception` subclass; the helper only relies on `toString()`.
        expect(
          classifyPushError(const _FakeLibGit2Error('401 unauthorized')),
          PushErrorCategory.auth,
        );
        expect(
          classifyPushError(42),
          PushErrorCategory.unknown,
        );
      });
    });

    group('precedence (ambiguous messages)', () {
      test('non-fast-forward wins over auth when both phrasings appear', () {
        // The GitHub smart-http server has been observed to send a 403 and
        // a "non-fast-forward" side-band hint in the same body.
        expect(
          classifyPushError(
            Exception(
              'request failed with status code: 403 '
              '(non-fast-forward update)',
            ),
          ),
          PushErrorCategory.nonFastForward,
        );
      });

      test('auth wins over network when both phrasings appear', () {
        // A 401 response can still arrive over a dropped connection; we
        // want the user-actionable auth classification, not "retry the
        // network".
        expect(
          classifyPushError(
            Exception(
              'request failed with status code: 401 after connection reset',
            ),
          ),
          PushErrorCategory.auth,
        );
      });

      test('is case-insensitive', () {
        expect(
          classifyPushError(Exception('NON-FAST-FORWARD')),
          PushErrorCategory.nonFastForward,
        );
        expect(
          classifyPushError(Exception('UNAUTHORIZED')),
          PushErrorCategory.auth,
        );
      });
    });
  });

  group('pushOutcomeFor (pure category -> PushOutcome dispatch)', () {
    test('nonFastForward -> PushRejectedNonFastForward with both shas', () {
      expect(
        pushOutcomeFor(
          PushErrorCategory.nonFastForward,
          remoteSha: 'cafef00d',
          localSha: 'deadbeef',
        ),
        const PushRejectedNonFastForward(
          remoteSha: 'cafef00d',
          localSha: 'deadbeef',
        ),
      );
    });

    test('nonFastForward preserves empty remoteSha (the common case — we '
        "can't cheaply look up the remote tip without an extra fetch)", () {
      expect(
        pushOutcomeFor(
          PushErrorCategory.nonFastForward,
          remoteSha: '',
          localSha: 'deadbeef',
        ),
        const PushRejectedNonFastForward(
          remoteSha: '',
          localSha: 'deadbeef',
        ),
      );
    });

    test('auth -> const PushRejectedAuth (ignores shas)', () {
      final outcome = pushOutcomeFor(
        PushErrorCategory.auth,
        remoteSha: 'ignored',
        localSha: 'ignored',
      );
      expect(outcome, const PushRejectedAuth());
    });

    test('network -> null (caller rethrows per GitPort contract — '
        'transport-level failures must not be collapsed into a typed '
        'outcome)', () {
      expect(
        pushOutcomeFor(
          PushErrorCategory.network,
          remoteSha: '',
          localSha: 'deadbeef',
        ),
        isNull,
      );
    });

    test('unknown -> null (caller rethrows the original exception)', () {
      expect(
        pushOutcomeFor(
          PushErrorCategory.unknown,
          remoteSha: '',
          localSha: 'deadbeef',
        ),
        isNull,
      );
    });
  });
}

/// Stand-in for `LibGit2Error` — the real class has a private FFI pointer
/// ctor so we can't synthesise one without reaching into libgit2's
/// internals. This fake reproduces the only surface the classifier uses:
/// `toString()`.
class _FakeLibGit2Error {
  const _FakeLibGit2Error(this._message);
  final String _message;
  @override
  String toString() => _message;
}
