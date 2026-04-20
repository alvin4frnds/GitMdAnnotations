import '../../domain/ports/id_generator_port.dart';

/// Production [IdGenerator] adapter. Mints per-session unique ids of the form
/// `stroke-group-<t36><counter>` where `t36` is the session start time in
/// microseconds-since-epoch rendered in base-36 and `counter` is a monotonic
/// per-instance counter. The exact scheme is cosmetic — any unique-per-session
/// id satisfies the domain invariant that `StrokeGroup.id` is non-empty and
/// unique within a session (see IMPLEMENTATION.md §3.4).
///
/// Tests pin a deterministic scheme via [FakeIdGenerator]; the only contract
/// this adapter enforces is the `stroke-group-` prefix and per-call
/// distinctness.
class SystemIdGenerator implements IdGenerator {
  SystemIdGenerator()
      : _seed = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  final String _seed;
  int _counter = 0;

  @override
  String next() {
    final id = 'stroke-group-$_seed-$_counter';
    _counter++;
    return id;
  }
}
