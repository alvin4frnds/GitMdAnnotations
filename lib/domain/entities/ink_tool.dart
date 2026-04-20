/// Stroke primitives from PRD §5.4 FR-1.14. Only [pen] has distinct behavior
/// in Milestone 1b T3 — all other tools degrade to pen (single freehand
/// stroke per interaction). T4/T5/T6 flesh out the remaining tools.
enum InkTool {
  pen,
  highlighter,
  line,
  arrow,
  rect,
  circle,
  eraser,
}
