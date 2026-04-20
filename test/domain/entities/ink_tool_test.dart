import 'package:flutter_test/flutter_test.dart';
import 'package:gitmdannotations_tablet/domain/entities/ink_tool.dart';

/// [InkTool] is the set of stroke primitives from PRD §5.4 FR-1.14. In
/// Milestone 1b T3 only `pen` has distinct behavior — the other values
/// compile and the enum surface is stable so T4/T5/T6 can build on it.
void main() {
  test('InkTool enumerates exactly the seven PRD primitives', () {
    expect(InkTool.values, <InkTool>[
      InkTool.pen,
      InkTool.highlighter,
      InkTool.line,
      InkTool.arrow,
      InkTool.rect,
      InkTool.circle,
      InkTool.eraser,
    ]);
  });
}
