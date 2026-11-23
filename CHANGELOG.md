# Changelog

## 0.1.0

First release: a read-only, streaming reader for GPX 1.1 and 1.0 files, with typed messages and fields, the common fitness extensions, enforced limits, refusal of DTDs, and an `Activity` view in the shape of `FitKit::Activity`. Requires Ruby 3.1 and Nokogiri 1.17.

Development, by milestone:

- M4: hardening. Reading 24-hour files is about a third faster (the time limit's clock now pauses once per message, and paths, names and types are cached per place in a message). Seeded fuzz tests of bytes, markup and values run with the suite. Exporter quirks are reproduced in tests; undeclared namespace prefixes no longer stop reading (decision 4), a DTD in a UTF-16 document is refused before parsing, and numbers beyond a Float are decoded without Ruby warnings.
- M3: `Activity` view in the shape of `FitKit::Activity`: sessions (one per `<trk>`, with segments), records, waypoints and routes. Record values come from the first valid source in the order of decision 2. Checked against FIT exports of the same activities.
- `copyright/year` is decoded as an `xsd:gYear` (an `Integer`) instead of unchecked text, with the new invalid reason `:not_a_year`. Accepting `+` and `-0` on non-negative integers is now documented.
- M2: messages and fields. The Reader yields a `Message` per metadata, waypoint, route, route point, track, track segment and track point, and a final `:document`, each with its `context`. Every leaf element and attribute is a `Field` with the text as written, a value typed from the GPX 1.1 or 1.0 schema, and `valid?`/`invalid_reason`. TrackPointExtension v1 and v2, PowerExtension v1, Cluetrust GPXDATA and a bare `power` are typed; other extensions are kept untyped.
- M1: safe streaming reader. `Reader` (paths, Pathnames and IO, `close_io:`, re-reading seekable IO), `Limits` (`max_bytes`, `max_elements`, `max_depth`, `max_text_bytes`, `max_seconds`), refusal of DTD internal subsets and DTD entities, `TruncatedFileError` for files cut off, `UnsupportedFormatError` for anything but GPX 1.1 or 1.0 (a root without a namespace is read by its version attribute), and skipping whitespace before the XML declaration. Yields no messages yet. Requires Nokogiri 1.17.
- M0: specification, gem skeleton and CI.
