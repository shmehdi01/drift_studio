## 0.1.0

Initial release.

- Object explorer with fuzzy search over table names and column names, live row counts and database info (SQLite version, schema version, size, journal mode).
- Data grid with pinned header and row numbers, lazy 2D rendering, resizable columns, click-to-sort, global search, a column filter builder (13 operators), paging and page-size control.
- Row inspector with pretty-printed JSON, hex dump for blobs, timestamp hints, copy as JSON / INSERT, and foreign-key navigation.
- Optional in-place editing and row deletion (primary-key targeted) when `allowWrites` is enabled.
- Structure view: columns, constraints, indexes, foreign keys, triggers and DDL.
- SQL console with syntax highlighting, schema- and alias-aware autocomplete, keyboard shortcuts, multi-statement scripts, read-only guard, write confirmation, history, saved queries, built-in templates and app-provided presets.
- Export results as CSV, JSON, Markdown or INSERT statements.
- Works with any SQLite binding through `StudioDataSource`.
- `initialTable` opens the studio on a specific table.
