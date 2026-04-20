import '../../domain/entities/git_identity.dart';

/// Internal codec for [GitIdentity] persisted in [SecureStoragePort]. Format:
/// `"<name>|<email>"` where any literal `|` in either field is percent-
/// encoded as `%7C` (and any literal `%` as `%25`) so the first un-escaped
/// pipe unambiguously separates the two fields.
///
/// Kept internal to `lib/app/controllers/` — callers should go through
/// [AuthController] rather than touching storage directly.
class AuthIdentityCodec {
  const AuthIdentityCodec._();

  static String encode(GitIdentity id) =>
      '${_escape(id.name)}|${_escape(id.email)}';

  /// Returns `null` for blobs that don't match the `name|email` shape.
  static GitIdentity? decode(String blob) {
    final pipe = blob.indexOf('|');
    if (pipe < 0) return null;
    return GitIdentity(
      name: _unescape(blob.substring(0, pipe)),
      email: _unescape(blob.substring(pipe + 1)),
    );
  }

  static String _escape(String s) =>
      s.replaceAll('%', '%25').replaceAll('|', '%7C');
  static String _unescape(String s) =>
      s.replaceAll('%7C', '|').replaceAll('%25', '%');
}
