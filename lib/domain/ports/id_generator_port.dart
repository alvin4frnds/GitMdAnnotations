/// Abstract id generator used by domain services that mint new domain
/// entity ids — e.g. [AnnotationSession] allocating a `StrokeGroup.id`.
///
/// Real implementation (UUID v4 or similar) lives in the infra layer;
/// tests use `FakeIdGenerator` for determinism.
abstract class IdGenerator {
  String next();
}
