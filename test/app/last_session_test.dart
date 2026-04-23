import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/last_session.dart';
import 'package:gitmdscribe/domain/entities/repo_ref.dart';
import 'package:gitmdscribe/domain/fakes/fake_secure_storage.dart';
import 'package:gitmdscribe/domain/ports/secure_storage_port.dart';

const _repo = RepoRef(
  owner: 'octocat',
  name: 'hello-world',
  defaultBranch: 'main',
);

void main() {
  group('LastSessionRepoCodec', () {
    test('round-trips an ordinary RepoRef', () {
      final encoded = LastSessionRepoCodec.encode(_repo);
      expect(encoded, 'octocat|hello-world|main');
      expect(LastSessionRepoCodec.decode(encoded), _repo);
    });

    test('escapes literal | and % in fields so they do not split the blob',
        () {
      const tricky = RepoRef(
        owner: 'owner|with|pipes',
        name: 'name%25with%percent',
        defaultBranch: 'branch|',
      );
      final encoded = LastSessionRepoCodec.encode(tricky);
      // Every `%` escaped first, then every `|` — the count of raw
      // separator pipes stays at exactly 2.
      expect(encoded.split('|').length, 3);
      expect(LastSessionRepoCodec.decode(encoded), tricky);
    });

    test('decode returns null for blobs without three fields', () {
      expect(LastSessionRepoCodec.decode('too|few'), isNull);
      expect(LastSessionRepoCodec.decode('no-pipes-at-all'), isNull);
      expect(LastSessionRepoCodec.decode('a|b|c|d'), isNull);
    });

    test('decode returns null when any required field is empty', () {
      expect(LastSessionRepoCodec.decode('|name|main'), isNull);
      expect(LastSessionRepoCodec.decode('owner||main'), isNull);
      expect(LastSessionRepoCodec.decode('owner|name|'), isNull);
    });
  });

  group('loadLastSession / save / clear round-trip', () {
    // Stub validator that accepts any path — the actual filesystem check
    // is exercised in the 'workdir validation' group below.
    bool alwaysValid(String _) => true;

    test('missing keys → null', () async {
      final storage = FakeSecureStorage();
      expect(
        await loadLastSession(storage, validateWorkdir: alwaysValid),
        isNull,
      );
    });

    test('repo+workdir present, jobId absent → LastSession with null jobId',
        () async {
      final storage = FakeSecureStorage();
      await saveLastOpenedRepo(
        storage,
        repo: _repo,
        workdir: '/data/app/repos/octocat/hello-world',
      );

      final restored =
          await loadLastSession(storage, validateWorkdir: alwaysValid);
      expect(restored, isNotNull);
      expect(restored!.repo, _repo);
      expect(restored.workdir, '/data/app/repos/octocat/hello-world');
      expect(restored.jobId, isNull);
    });

    test('all three keys present → full LastSession', () async {
      final storage = FakeSecureStorage();
      await saveLastOpenedRepo(
        storage,
        repo: _repo,
        workdir: '/workdir',
      );
      await saveLastOpenedJobId(storage, 'spec-foo-123');

      final restored =
          await loadLastSession(storage, validateWorkdir: alwaysValid);
      expect(restored, isNotNull);
      expect(restored!.repo, _repo);
      expect(restored.workdir, '/workdir');
      expect(restored.jobId, 'spec-foo-123');
    });

    test('workdir present but repo absent → null (half-state rejected)',
        () async {
      final storage = FakeSecureStorage();
      await storage.writeString(SecureStorageKeys.lastOpenedWorkdir, '/wd');
      expect(
        await loadLastSession(storage, validateWorkdir: alwaysValid),
        isNull,
      );
    });

    test('repo present but workdir absent → null (half-state rejected)',
        () async {
      final storage = FakeSecureStorage();
      await storage.writeString(
        SecureStorageKeys.lastOpenedRepo,
        LastSessionRepoCodec.encode(_repo),
      );
      expect(
        await loadLastSession(storage, validateWorkdir: alwaysValid),
        isNull,
      );
    });

    test('corrupt repo blob → null (does not throw)', () async {
      final storage = FakeSecureStorage();
      await storage.writeString(
        SecureStorageKeys.lastOpenedRepo,
        'garbage-no-pipes',
      );
      await storage.writeString(SecureStorageKeys.lastOpenedWorkdir, '/wd');
      expect(
        await loadLastSession(storage, validateWorkdir: alwaysValid),
        isNull,
      );
    });

    test('saveLastOpenedJobId(null) deletes the key', () async {
      final storage = FakeSecureStorage();
      await saveLastOpenedJobId(storage, 'spec-foo-123');
      expect(
        await storage.readString(SecureStorageKeys.lastOpenedJobId),
        'spec-foo-123',
      );

      await saveLastOpenedJobId(storage, null);
      expect(
        await storage.containsKey(SecureStorageKeys.lastOpenedJobId),
        isFalse,
      );
    });

    test('clearLastSession removes all three keys', () async {
      final storage = FakeSecureStorage();
      await saveLastOpenedRepo(storage, repo: _repo, workdir: '/wd');
      await saveLastOpenedJobId(storage, 'spec-foo-123');

      await clearLastSession(storage);
      expect(
        await storage.containsKey(SecureStorageKeys.lastOpenedRepo),
        isFalse,
      );
      expect(
        await storage.containsKey(SecureStorageKeys.lastOpenedWorkdir),
        isFalse,
      );
      expect(
        await storage.containsKey(SecureStorageKeys.lastOpenedJobId),
        isFalse,
      );
    });

    test('clearLastSession is safe when keys are already absent', () async {
      final storage = FakeSecureStorage();
      await clearLastSession(storage); // should not throw
      expect(storage.snapshot, isEmpty);
    });
  });

  group('workdir validation (W5.3 recovery)', () {
    test('validator rejects workdir → returns null and clears stale keys',
        () async {
      final storage = FakeSecureStorage();
      await saveLastOpenedRepo(storage, repo: _repo, workdir: '/gone');
      await saveLastOpenedJobId(storage, 'spec-foo-123');

      final restored = await loadLastSession(
        storage,
        validateWorkdir: (_) => false,
      );

      expect(restored, isNull);
      // All three keys scrubbed so the next cold start doesn't loop on
      // the broken pointer.
      expect(storage.snapshot, isEmpty);
    });

    test('validator accepts workdir → restore succeeds as normal', () async {
      final storage = FakeSecureStorage();
      await saveLastOpenedRepo(storage, repo: _repo, workdir: '/wd');

      final restored = await loadLastSession(
        storage,
        validateWorkdir: (_) => true,
      );

      expect(restored, isNotNull);
      expect(restored!.workdir, '/wd');
    });

    test('validator receives the persisted workdir string', () async {
      final storage = FakeSecureStorage();
      await saveLastOpenedRepo(storage, repo: _repo, workdir: '/observed');
      String? seen;

      await loadLastSession(storage, validateWorkdir: (w) {
        seen = w;
        return true;
      });

      expect(seen, '/observed');
    });
  });

  group('ColdStartTracker', () {
    test('captures preload, first-frame, job-list-visible in order', () {
      final start = DateTime(2026, 4, 21, 10, 0, 0);
      final tracker = ColdStartTracker(start: start);
      expect(tracker.preload, isNull);
      expect(tracker.firstFrame, isNull);
      expect(tracker.jobListVisible, isNull);

      tracker.markPreload();
      tracker.markFirstFrame();
      tracker.markJobListVisible();

      expect(tracker.preload, isNotNull);
      expect(tracker.firstFrame, isNotNull);
      expect(tracker.jobListVisible, isNotNull);
      // All timestamps >= start (use !isBefore so an equal instant passes).
      expect(tracker.preload!.isBefore(start), isFalse);
      expect(tracker.firstFrame!.isBefore(start), isFalse);
      expect(tracker.jobListVisible!.isBefore(start), isFalse);
    });

    test('mark* is idempotent — only the first call is recorded', () async {
      final tracker = ColdStartTracker();
      tracker.markPreload();
      final first = tracker.preload;
      // Small gap so a second call would produce a different timestamp.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      tracker.markPreload();
      expect(tracker.preload, same(first));
    });
  });
}
