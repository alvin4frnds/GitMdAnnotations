import 'dart:io';

import 'package:flutter/services.dart';
import 'package:libgit2dart/libgit2dart.dart' as git2;
import 'package:path_provider/path_provider.dart';

/// Materializes the bundled Mozilla CA trust store onto disk (once per
/// cold start) and hands the path to libgit2 via
/// [git2.Libgit2.setSSLCertLocations].
///
/// Required because our forked libgit2 is linked against mbedTLS 2.28,
/// which on Android ships no CA bundle of its own. Without this, every
/// HTTPS clone/fetch/push against `github.com` fails with "the
/// certificate is not correctly signed by the trusted CA" — surfaced by
/// the RepoPicker during `cloneOrOpen` for private repos (and public
/// ones, since libgit2 always verifies).
///
/// Idempotent: re-running within the same process is a no-op;
/// cross-process the file is rewritten (cheap — ~220 KB).
Future<void> installBundledTrustStore() async {
  // Cache dir is appropriate — the file is reproducible from the asset,
  // and we don't want it surviving an app-data wipe without also
  // carrying the asset-bundle version that produced it.
  final cache = await getApplicationCacheDirectory();
  final pemPath = '${cache.path}/cacert.pem';
  final pem = File(pemPath);
  if (!await pem.exists()) {
    final bytes = await rootBundle.load('assets/ca/cacert.pem');
    await pem.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }
  git2.Libgit2.setSSLCertLocations(file: pemPath);
}
