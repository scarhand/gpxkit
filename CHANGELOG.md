# Changelog

## Unreleased

- M2: messages and fields. The Reader yields a `Message` per metadata, waypoint, route, route point, track, track segment and track point, and a final `:document`, each with its `context`. Every leaf element and attribute is a `Field` with the text as written, a value typed from the GPX 1.1 or 1.0 schema, and `valid?`/`invalid_reason`. TrackPointExtension v1 and v2, PowerExtension v1, Cluetrust GPXDATA and a bare `power` are typed; other extensions are kept untyped.
- M1: safe streaming reader. `Reader` (paths, Pathnames and IO, `close_io:`, re-reading seekable IO), `Limits` (`max_bytes`, `max_elements`, `max_depth`, `max_text_bytes`, `max_seconds`), refusal of DTD internal subsets and DTD entities, `TruncatedFileError` for files cut off, `UnsupportedFormatError` for anything but GPX 1.1 or 1.0 (a root without a namespace is read by its version attribute), and skipping whitespace before the XML declaration. Yields no messages yet. Requires Nokogiri 1.17.
- M0: specification, gem skeleton and CI.
