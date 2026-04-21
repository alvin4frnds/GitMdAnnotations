@Tags(['platform'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:libgit2dart/libgit2dart.dart' as git2;

/// End-to-end regression test for the "libgit2dart has no Android plugin"
/// finding in `docs/Issues.md`. Proves:
///   1. `libgit2.so` is bundled under the APK's `lib/<abi>/` jniLibs dir
///      (the forked libgit2dart plugin packaged it).
///   2. The Android dynamic linker resolves the bare SONAME `libgit2.so`.
///   3. `dart:ffi` `DynamicLibrary.open` hands a valid handle back to the
///      patched `lib/src/util.dart::loadLibrary` on Android.
///   4. A trivial FFI round-trip (`git_libgit2_init` +
///      `git_libgit2_version`) succeeds.
///
/// If this suite fails on the emulator, the most likely causes — in order:
///   - Fork's `android/src/main/jniLibs/<abi>/libgit2.so` is missing or
///     built for the wrong ABI.
///   - Fork's `pubspec.yaml` does not declare `android: ffiPlugin: true`.
///   - Fork's `lib/src/util.dart` still throws `Unsupported platform.` on
///     Android (the `Platform.isAndroid` short-circuit regressed).
///
/// Invocation: `fvm flutter test integration_test/libgit2_android_load_test.dart -d emulator-5554`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('libgit2 loads and reports a version', () {
    final version = git2.Libgit2.version;
    expect(version, matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason: 'git_libgit2_version returned "$version"');
    expect(version, equals('1.5.0'));
  });

  test('libgit2 reports its compiled-in features', () {
    final features = git2.Libgit2.features;
    // Our Android build was configured with -DUSE_SSH=OFF -DUSE_HTTPS=OFF
    // -DREGEX_BACKEND=builtin, so expected features are just the core
    // THREADS flag. This assertion documents the build config and will
    // surface a change if the .so is swapped.
    expect(features, contains(git2.GitFeature.threads));
    expect(features, isNot(contains(git2.GitFeature.https)));
    expect(features, isNot(contains(git2.GitFeature.ssh)));
  });
}
