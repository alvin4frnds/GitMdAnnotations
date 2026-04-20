/// The `(name, email)` pair sourced from GitHub's `GET /user` endpoint and
/// used to sign commits authored by the tablet.
///
/// See IMPLEMENTATION.md §2.6 and §3.6.
class GitIdentity {
  const GitIdentity({required this.name, required this.email});

  final String name;
  final String email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitIdentity && other.name == name && other.email == email;

  @override
  int get hashCode => Object.hash(name, email);

  @override
  String toString() => 'GitIdentity(name: $name, email: $email)';
}
