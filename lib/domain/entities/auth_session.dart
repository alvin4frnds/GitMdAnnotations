import 'git_identity.dart';

/// The authenticated GitHub session held in memory after OAuth Device Flow
/// or a PAT paste-in (IMPLEMENTATION.md §4.1). The token is the bearer used
/// for REST calls and the HTTPS password for git push/fetch.
class AuthSession {
  const AuthSession({required this.token, required this.identity});

  final String token;
  final GitIdentity identity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSession &&
          other.token == token &&
          other.identity == identity;

  @override
  int get hashCode => Object.hash(token, identity);

  @override
  String toString() => 'AuthSession(token: <redacted>, identity: $identity)';
}
