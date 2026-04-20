import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers/annotation_providers.dart';
import 'app/providers/auth_providers.dart';
import 'app/providers/pdf_providers.dart';
import 'app/providers/spec_providers.dart';
import 'app/providers/sync_providers.dart';
import 'domain/ports/secure_storage_port.dart';
import 'infra/auth/github_oauth_adapter.dart';
import 'infra/clock/system_clock.dart';
import 'infra/fs/fs_adapter.dart';
import 'infra/git/git_adapter.dart';
import 'infra/id/system_id_generator.dart';
import 'infra/pdf/pdfx_adapter.dart';
import 'infra/storage/keystore_adapter.dart';

/// BLOCKER: real OAuth client id is still `OVERRIDE_ME`. The real GitHub
/// OAuth App isn't registered yet; this const lives here as a single
/// anchor so the follow-up patch is a one-line change. Do NOT try to sign
/// in until this is replaced.
const String _prodClientId = 'OVERRIDE_ME';

/// Builds the composition root. Binds every port listed in §2.1's layer
/// diagram to its production adapter. The returned scope wraps [child].
///
/// Test code doesn't call this — tests build their own [ProviderContainer]
/// or [ProviderScope] with per-test overrides.
ProviderScope buildAppScope({required Widget child}) {
  final storage = KeystoreAdapter();
  final fs = FsAdapter();
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      authPortProvider.overrideWithValue(
        GithubOAuthAdapter(clientId: _prodClientId, storage: storage),
      ),
      fileSystemProvider.overrideWithValue(fs),
      clockProvider.overrideWithValue(SystemClock()),
      idGeneratorProvider.overrideWithValue(SystemIdGenerator()),
      pdfRasterPortProvider.overrideWithValue(PdfxAdapter()),
      gitPortProvider.overrideWith((ref) {
        // Capture `ref` so the credentials loader stays lazy; resolving
        // storage at provider-define time would require a container which
        // Riverpod doesn't expose during factory construction. This closure
        // is invoked per remote op (clone/fetch/push), so reading the
        // token via `ref.read` each call picks up the latest session.
        return GitAdapter(
          credentialsLoader: () async =>
              ref.read(secureStorageProvider).readString(
                    SecureStorageKeys.authToken,
                  ),
        );
      }),
      // RepoPicker (M1c) sets currentWorkdirProvider + currentRepoProvider.
    ],
    child: child,
  );
}
