import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/phase.dart';
import 'package:gitmdannotations_tablet/domain/fakes/fake_file_system.dart';
import 'package:gitmdannotations_tablet/domain/ports/file_system_port.dart';

/// Integration-style test: the in-memory [FakeFileSystem] feeds the existing
/// [Phase.resolve] (T2) to prove that a realistic `jobs/pending/spec-<id>/`
/// listing resolves to the correct [Phase] end-to-end in the domain layer.
void main() {
  group('FileSystemPort x Phase.resolve integration', () {
    const jobDir = '/repo/jobs/pending/spec-foo';

    Future<Phase> resolveFromListing(FakeFileSystem fs) async {
      final entries = await fs.listDir(jobDir);
      final names = entries.map((e) => e.name).toSet();
      return Phase.resolve(names);
    }

    test('full job folder including 05-approved resolves to Phase.approved',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('$jobDir/02-spec.md', '# spec')
        ..seedFile('$jobDir/03-review.md', '# review')
        ..seedFile('$jobDir/04-spec-v2.md', '# v2')
        ..seedFile('$jobDir/05-approved', '');

      expect(await resolveFromListing(fs), Phase.approved);
    });

    test('without 05-approved, 04-spec-v2.md resolves to Phase.revised',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('$jobDir/02-spec.md', '# spec')
        ..seedFile('$jobDir/03-review.md', '# review')
        ..seedFile('$jobDir/04-spec-v2.md', '# v2');

      expect(await resolveFromListing(fs), Phase.revised);
    });

    test('without any 04-spec-v*, 03-review.md resolves to Phase.review',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('$jobDir/02-spec.md', '# spec')
        ..seedFile('$jobDir/03-review.md', '# review');

      expect(await resolveFromListing(fs), Phase.review);
    });

    test('only 02-spec.md resolves to Phase.spec', () async {
      final fs = FakeFileSystem()..seedFile('$jobDir/02-spec.md', '# spec');

      expect(await resolveFromListing(fs), Phase.spec);
    });

    test('listing returns only immediate children (no nested fixtures leak)',
        () async {
      final fs = FakeFileSystem()
        ..seedFile('$jobDir/02-spec.md', '# spec')
        ..seedFile('$jobDir/attachments/img.png', 'fake-bytes');

      final entries = await fs.listDir(jobDir);
      final names = entries.map((e) => e.name).toSet();
      // `attachments` is reported as a directory child; its contents are not.
      expect(names, containsAll({'02-spec.md', 'attachments'}));
      expect(names.contains('img.png'), isFalse);

      // Resolve still works because only recognised phase files are consulted.
      expect(Phase.resolve(names), Phase.spec);
    });

    test('FsNotFound is raised when the job dir does not exist', () async {
      final fs = FakeFileSystem();
      await expectLater(
        fs.listDir(jobDir),
        throwsA(isA<FsNotFound>()),
      );
    });
  });
}
