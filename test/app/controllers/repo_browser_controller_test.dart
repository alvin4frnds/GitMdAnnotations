import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/repo_browser_controller.dart';
import 'package:gitmdscribe/app/providers/spec_import_providers.dart';
import 'package:gitmdscribe/app/providers/spec_providers.dart';
import 'package:gitmdscribe/domain/fakes/fake_file_system.dart';

ProviderContainer _buildContainer(FakeFileSystem fs, {String? workdir}) {
  final container = ProviderContainer(overrides: [
    fileSystemProvider.overrideWithValue(fs),
    if (workdir != null) currentWorkdirProvider.overrideWith((_) => workdir),
  ]);
  addTearDown(container.dispose);
  return container;
}

FakeFileSystem _seededFs() {
  return FakeFileSystem()
    ..seedFile('/repo/README.md', 'root')
    ..seedFile('/repo/docs/one.md', '1')
    ..seedFile('/repo/docs/two.md', '2')
    ..seedFile('/repo/docs/image.png', 'png-bytes')
    ..seedFile('/repo/.git/HEAD', 'ref')
    ..seedFile('/repo/.gitmdscribe-backups/foo/bar.md', 'backup')
    ..seedFile('/repo/jobs/pending/spec-foo/02-spec.md', 'existing spec');
}

void main() {
  group('RepoBrowserController.build()', () {
    test('returns RepoBrowserUnavailable when no workdir', () async {
      final container = _buildContainer(_seededFs());
      final state =
          await container.read(repoBrowserControllerProvider.future);
      expect(state, isA<RepoBrowserUnavailable>());
    });

    test('lists only .md files + visible dirs at the repo root', () async {
      final container = _buildContainer(_seededFs(), workdir: '/repo');
      final state =
          await container.read(repoBrowserControllerProvider.future);

      final names = state.entries.map((e) => e.name).toList();
      // Hidden: .git, .gitmdscribe-backups. The `jobs` folder itself is
      // visible, but `jobs/pending` is hidden (verified in a deeper test).
      expect(names, contains('docs'));
      expect(names, contains('README.md'));
      expect(names, contains('jobs'));
      expect(names, isNot(contains('.git')));
      expect(names, isNot(contains('.gitmdscribe-backups')));

      // Directories sort before files.
      final firstFileIdx =
          state.entries.indexWhere((e) => !e.isDirectory);
      final firstDirIdx = state.entries.indexWhere((e) => e.isDirectory);
      expect(firstDirIdx, lessThan(firstFileIdx));
    });

    test('filters non-markdown files out of the listing', () async {
      final container = _buildContainer(_seededFs(), workdir: '/repo');
      await container.read(repoBrowserControllerProvider.future);
      await container
          .read(repoBrowserControllerProvider.notifier)
          .enter('docs');
      final state =
          await container.read(repoBrowserControllerProvider.future);

      final names = state.entries.map((e) => e.name).toList();
      expect(names, containsAll(['one.md', 'two.md']));
      expect(names, isNot(contains('image.png')));
    });

    test('hides jobs/pending subtree', () async {
      final container = _buildContainer(_seededFs(), workdir: '/repo');
      await container.read(repoBrowserControllerProvider.future);
      await container
          .read(repoBrowserControllerProvider.notifier)
          .enter('jobs');
      final state =
          await container.read(repoBrowserControllerProvider.future);

      final names = state.entries.map((e) => e.name).toList();
      expect(names, isNot(contains('pending')));
    });
  });

  group('navigation', () {
    test('enter / up walk the tree; up is a no-op at root', () async {
      final container = _buildContainer(_seededFs(), workdir: '/repo');
      await container.read(repoBrowserControllerProvider.future);

      final notifier =
          container.read(repoBrowserControllerProvider.notifier);

      await notifier.enter('docs');
      var state = await container.read(repoBrowserControllerProvider.future);
      expect(state.currentRelPath, 'docs');
      expect(state.isAtRoot, isFalse);

      await notifier.up();
      state = await container.read(repoBrowserControllerProvider.future);
      expect(state.currentRelPath, '');
      expect(state.isAtRoot, isTrue);

      // Another up at root stays at root.
      await notifier.up();
      state = await container.read(repoBrowserControllerProvider.future);
      expect(state.currentRelPath, '');
    });
  });
}
