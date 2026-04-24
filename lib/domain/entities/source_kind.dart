/// The kind of source being reviewed or browsed: a markdown spec file
/// (`02-spec.md` / `04-spec-v*.md`), a PDF attachment, or a standalone SVG
/// diagram. SVG is non-annotatable — the reader is view-only and the commit
/// planner refuses any strokes with an SVG source (spec-002).
///
/// See IMPLEMENTATION.md §2.6 and §4.3. This enum is used by both [Job] and
/// [SpecFile] so it lives in its own file (the task spec describes it as
/// "nested" for brevity only; one file per type is the project rule).
enum SourceKind { markdown, pdf, svg }
