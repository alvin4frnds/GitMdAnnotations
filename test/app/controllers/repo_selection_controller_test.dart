import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdscribe/app/controllers/repo_selection_controller.dart';
import 'package:gitmdscribe/app/providers/spec_import_providers.dart';

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

RepoSelectionController _notifier(ProviderContainer c) =>
    c.read(repoSelectionControllerProvider.notifier);

void main() {
  group('RepoSelectionController', () {
    test('starts empty', () {
      final c = _container();
      expect(c.read(repoSelectionControllerProvider), isEmpty);
    });

    test('toggle adds then removes a relPath', () {
      final c = _container();
      final n = _notifier(c);

      n.toggle('a/one.md');
      expect(c.read(repoSelectionControllerProvider), {'a/one.md'});
      expect(n.isSelected('a/one.md'), isTrue);

      n.toggle('a/one.md');
      expect(c.read(repoSelectionControllerProvider), isEmpty);
      expect(n.isSelected('a/one.md'), isFalse);
    });

    test('selection persists across a simulated navigation (no clear)', () {
      final c = _container();
      final n = _notifier(c);
      n.toggle('a/one.md');
      n.toggle('b/two.pdf');
      // Nothing clears on navigation — the set is keyed by repo-relative
      // path and survives folder changes (OQ-1 default).
      expect(c.read(repoSelectionControllerProvider), {'a/one.md', 'b/two.pdf'});
    });

    test('selectAll unions the given relPaths with the current set', () {
      final c = _container();
      final n = _notifier(c);
      n.toggle('keep.md');
      n.selectAll(['a.md', 'b.md', 'keep.md']);
      expect(
        c.read(repoSelectionControllerProvider),
        {'keep.md', 'a.md', 'b.md'},
      );
    });

    test('deselectAll removes exactly the given relPaths (difference)', () {
      final c = _container();
      final n = _notifier(c);
      n.selectAll(['a.md', 'b.md', 'c.md']);
      n.deselectAll(['a.md', 'b.md']);
      expect(c.read(repoSelectionControllerProvider), {'c.md'});
    });

    test('clear empties the set', () {
      final c = _container();
      final n = _notifier(c);
      n.selectAll(['a.md', 'b.md']);
      n.clear();
      expect(c.read(repoSelectionControllerProvider), isEmpty);
    });

    test('the exposed set is not the same mutable instance across mutations',
        () {
      final c = _container();
      final n = _notifier(c);
      n.toggle('a.md');
      final first = c.read(repoSelectionControllerProvider);
      n.toggle('b.md');
      final second = c.read(repoSelectionControllerProvider);
      expect(identical(first, second), isFalse);
      // The first snapshot must not have been mutated in place.
      expect(first, {'a.md'});
    });
  });
}
