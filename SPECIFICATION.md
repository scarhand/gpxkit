# GpxKit — Project Specification

**Status:** Approved by the maintainer on 2026-11-20
**Project type:** Read-only Ruby library for GPS Exchange Format (GPX) files
**Gem name:** `gpxkit` (free on RubyGems on 2026-11-20)
**Ruby namespace / require path:** `GpxKit` / `require "gpxkit"`
**Ruby support:** 3.1 and newer
**Licence:** MIT

Sister projects: [`fitkit`](https://github.com/scarhand/fitkit) (FIT) and [`tcxkit`](https://github.com/scarhand/tcxkit) (TCX). The three gems expose the same shape of API (section 6.4) so an application can handle all three formats the same way.

## 1. Purpose

Build a reliable, read-only parser for GPX 1.1 and GPX 1.0 files (`.gpx`).

GPX describes tracks, routes and waypoints, not workouts. Sport, heart rate, cadence and power appear only through extensions, and laps not at all. The library therefore exposes:

1. A low-level streaming `Reader` that yields one `Message` per meaningful GPX element (track point, segment, track, waypoint, route, ...), keeping every value exactly as written in the file, including elements and extensions the library does not recognise.
2. An optional `Activity` view in the same shape as `FitKit::Activity` and `TcxKit::Activity`, built from the tracks, which reports only what the file states.

The library must not create, modify, rewrite or repair GPX files.

## 2. Goals

- Parse GPX 1.1 and GPX 1.0 documents according to TopoGrafix's published schemas.
- Decode the common fitness extensions (section 6.3) and keep all others.
- Stream: memory use must not grow with the number of points unless the caller keeps them.
- Treat every file as untrusted input: no network access, no external entities, no DTD-defined entities, and enforced limits on size, depth, element count and time.
- Keep the text exactly as it appears in the file next to every typed value.
- Never fill in, estimate, smooth or derive measurements the file does not contain. In particular, never compute distance, speed or durations from positions and timestamps; that belongs to the application, labelled as derived.
- Raise useful, explicit exceptions with line and column numbers.
- One runtime dependency: Nokogiri 1.17 or later, used through its SAX interface.

## 3. Non-goals

- Writing, editing or repairing GPX files.
- XSD validation at runtime (section 7).
- Geometry: distance, bearing, simplification, bounds calculation.
- Mapping, charting, analysis, unit preferences.

## 4. Reference material

- GPX 1.1: `http://www.topografix.com/GPX/1/1`, schema and documentation at https://www.topografix.com/GPX/1/1/gpx.xsd and https://www.topografix.com/gpx/1/1/
- GPX 1.0: `http://www.topografix.com/GPX/1/0`, schema at https://www.topografix.com/GPX/1/0/gpx.xsd
- Garmin TrackPointExtension v1 and v2: `http://www.garmin.com/xmlschemas/TrackPointExtension/v1` and `/v2`
- Garmin PowerExtension v1: `http://www.garmin.com/xmlschemas/PowerExtension/v1`
- Cluetrust GPXDATA 1.0: `http://www.cluetrust.com/XML/GPXDATA/1/0`

TopoGrafix describes GPX as an open standard with no fees or licensing. Garmin publishes its extension schemas without stating a licence, so **do not copy any extension schema into this repository**. Implement from reading them and cite type names in comments and tests.

Every element, type and range this gem relies on must be checked against the published schemas, not taken from memory or inferred from sample files.

## 5. Architecture

Three layers, each usable on its own, as in tcxkit.

### 5.1 XML layer

- Nokogiri `XML::SAX::Parser#parse_io` over the source IO, wrapped so bytes read are counted (for `max_bytes`) as they are read.
- Keeps an element stack (namespace URI, local name, attributes, line, column) and collects text.
- Rejects unsafe or malformed input (section 7, section 8).

### 5.2 GPX layer

- Recognises the root `gpx` in the 1.1 or 1.0 namespace (and without a namespace, see section 7); anything else raises `UnsupportedFormatError`.
- Decides which elements become messages (section 6.2) and which are fields.
- Types each field from the schema of its version and from known extension namespaces.
- Assigns each message its context: which track, segment, route or waypoint it belongs to.

### 5.3 Activity layer

- Collects track points into sessions (tracks) and segments (section 6.4).
- Keeps every underlying `Message` reachable.

## 6. Public API

### 6.1 Reader

```ruby
reader = GpxKit::Reader.new("ride.gpx")

reader.each_message do |message|
  puts message[:ele] if message.name == :track_point
end
```

Same contract as `FitKit::Reader` and `TcxKit::Reader`:

- `Reader.new(source, close_io: false, source_label: nil, limits: Limits::DEFAULT)`. `source` is a path, a `Pathname` or an IO-like object that responds to `read`. A `Pathname` is read as a path even though it responds to `read`.
- `each_message` streams, and returns an Enumerator without a block.
- Seekable sources can be iterated again; a non-seekable IO can be read once, and a second iteration raises `Error`.
- Caller-owned IO is closed only with `close_io: true`.
- Time spent in the caller's block does not count towards `max_seconds`.

### 6.2 Messages

A message is emitted when its element closes, so it carries everything inside it: a segment's points arrive before the segment, a track's segments before the track.

| Message name | Element | Fields include |
|---|---|---|
| `:metadata` | `metadata` (1.1) | `name`, `desc`, `author_name`, `link_href`, `time`, `keywords`, bounds attributes |
| `:waypoint` | `wpt` | every `wptType` field (below) |
| `:route_point` | `rtept` | every `wptType` field |
| `:route` | `rte` | `name`, `cmt`, `desc`, `src`, `link_href`, `number`, `type` |
| `:track_point` | `trkpt` | every `wptType` field, plus known extensions |
| `:track_segment` | `trkseg` | none of its own |
| `:track` | `trk` | `name`, `cmt`, `desc`, `src`, `link_href`, `number`, `type` |
| `:document` | `gpx` | `version`, `creator`; in GPX 1.0 also the top-level `name`, `desc`, `author`, `email`, `url`, `time`, `keywords`, `bounds` |

`wptType` fields: `lat`, `lon` (attributes), `ele`, `time`, `magvar`, `geoidheight`, `name`, `cmt`, `desc`, `src`, `link_href`, `link_text`, `link_type`, `sym`, `type`, `fix`, `sat`, `hdop`, `vdop`, `pdop`, `ageofdgpsdata`, `dgpsid`, and in GPX 1.0 also `course`, `speed`, `url`, `urlname`.

Field names are the element's local name in snake_case, exactly as GPX names them (`ele`, not `elevation`; `hr`, not `heart_rate`). Nested elements join their names (`link/@href` becomes `link_href`); wrappers such as `extensions` and `TrackPointExtension` are dropped from the name but kept in the path. The Activity view (6.4) gives the friendlier names.

```ruby
message.name                # :track_point
message.context             # { track: 0, track_segment: 1, track_point: 812 }
message.line
message.fields              # Array of Field, in document order (names can repeat)
message[:ele]               # typed value of the first field with that name
message["extensions/gpxtpx:TrackPointExtension/gpxtpx:hr"] # lookup by path
message.field(:hr)
message.fields_named(:link_href)
message.attributes
message.to_h
```

### 6.3 Fields

```ruby
field.name           # :hr
field.path           # "extensions/TrackPointExtension/hr"
field.namespace      # the TrackPointExtension v2 namespace URI
field.raw_value      # "142", exactly as written (whitespace collapsed per its XSD type)
field.value          # 142, typed; nil when invalid
field.type           # :decimal, :date_time, :non_negative_integer, :string, ...
field.known?
field.valid?
field.invalid_reason # nil, :not_a_number, :out_of_range, :no_utc_offset, :not_in_enumeration, ...
field.line
```

Typing:

- `xsd:decimal` and `xsd:double` → `Float`. Callers that need exact decimals use `BigDecimal(field.raw_value)`.
- Integer types → `Integer`, range-checked.
- `xsd:dateTime` → `Time` in UTC when the text has `Z` or an offset. Without an offset the value is `nil` and `invalid_reason` is `:no_utc_offset` (decision 1, section 13).
- `fixType` → `:none`, `:"2d"`, `:"3d"`, `:dgps`, `:pps`.
- Schema ranges as validity, not errors: `latitudeType` (-90..90), `longitudeType` (-180 to under 180), `degreesType` (0 to under 360), `dgpsStationType` (0..1023), checked against the published schema.
- Unknown elements: `known?` false, `type` `:string`, `value` is the text.

Known extensions, decoded with types:

| Namespace | Elements |
|---|---|
| TrackPointExtension v1 | `atemp`, `wtemp`, `depth`, `hr`, `cad` |
| TrackPointExtension v2 | v1's, plus `speed`, `course`, `bearing` |
| PowerExtension v1 | `PowerInWatts` |
| Cluetrust GPXDATA 1.0 | `hr`, `cadence`, `temp` |
| none / GPX namespace | `power` inside `extensions`, as written by several exporters |

### 6.4 Activity view

The shared shape across fitkit, tcxkit and gpxkit, applied to what GPX can state:

```ruby
activity = GpxKit::Activity.read("ride.gpx", limits: { max_seconds: 30 })

activity.sessions   # one per <trk>
activity.laps       # always empty: GPX has no laps
activity.records    # every track point, in file order
activity.messages
activity.session
activity.waypoints  # :waypoint messages
activity.routes     # routes with their points
activity.metadata   # 1.1 metadata, or the 1.0 top-level fields
activity.creator    # gpx@creator

activity.sport            # first track's <type> text, as written; nil if absent
activity.start_time       # first track's first valid point time
activity.end_time         # last track's last valid point time
activity.total_distance   # nil: GPX does not state it
activity.total_timer_time # nil

session = activity.session
session.name
session.sport          # <type>, as written ("running", "9", ...)
session.segments       # each with its records
session.records

record = activity.records.first
record.timestamp       # Time (UTC)
record.latitude
record.longitude
record.altitude        # ele, m
record.heart_rate      # hr (TrackPointExtension or GPXDATA)
record.cadence         # cad or cadence
record.power           # PowerInWatts or power
record.temperature     # atemp or temp, °C
record.speed           # TrackPointExtension v2 speed, or GPX 1.0 speed, m/s
record.course          # degrees
record.distance        # nil: GPX does not state it
record.raw_message
```

Method names match `FitKit::Activity` wherever the meaning matches. A method whose value GPX cannot state returns `nil` instead of computing one. When two sources could fill a record value (for example `hr` in both TrackPointExtension and GPXDATA), the order is documented and tested, and both remain on the raw message.

The `Activity` view does not assume the file is an activity: a GPX with only routes or waypoints reads fine, with no sessions or records.

## 7. Leniency and strictness

Strict (raise):

- Not well-formed XML, or a root element other than `gpx`.
- A DTD internal subset, or any entity reference other than the five predefined XML entities and character references (section 8).
- Input cut off before the root element closes (`TruncatedFileError`). As in tcxkit, a file counts as cut off when libxml2's error is on the last line with at most part of one token (no `<` or `>`) after it, and the input starts with `<`. Anything else that is not well-formed is `InvalidFileError`.
- Any limit crossed.

Lenient (keep reading, record it on the field or message):

- Values that do not fit their type or range (`valid?` false).
- Unknown elements, attributes and extension namespaces; GPX 1.0 foreign elements anywhere.
- Elements in an order the schema does not allow, or missing elements: the field is simply absent.
- A `version` attribute that disagrees with the namespace: the namespace decides; `version` is kept as a field.

Known real-world quirks:

- A `gpx` root without any namespace. Read it as the version its `version` attribute names, with `document.namespace_missing?` true (decision 3, section 13).
- Whitespace before the XML declaration. Skipped, as in tcxkit.
- A UTF-8 byte order mark is accepted as XML allows.

## 8. Security

Identical to tcxkit:

- Never access the network or the filesystem beyond the source.
- Raise `UnsafeContentError` on a DTD internal subset (`<!DOCTYPE x [ ... ]>`) before the XML parser sees it, and on any reference to a DTD-declared entity. A document type declaration without an internal subset is allowed; its external DTD is never loaded.
- Enforce `Limits` while reading: `max_bytes` (64 MB), `max_elements` (5,000,000), `max_depth` (64), `max_text_bytes` (1 MB: the text of one element without child elements, one attribute value, or the prolog), `max_seconds` (none, and the caller's block is not counted). `nil` switches a limit off; `Limits.none` switches all off.
- Never include file content in exception messages beyond element names and positions.

## 9. Errors

```
GpxKit::Error                 base; source, line, column
├── InvalidFileError          not well-formed XML
├── UnsupportedFormatError    not a GPX 1.0 or 1.1 document
├── TruncatedFileError        ended before the root element closed
├── UnsafeContentError        DTD-declared entity
└── LimitExceededError        `limit` names the bound crossed
```

## 10. Testing

- Minitest, no other development dependencies beyond rake.
- Fixtures are synthetic, with made-up positions and values. Never commit real tracks. Document every fixture in `test/fixtures/README.md`.
- Cover both GPX versions; each message, field, type and range; each known extension, including two extensions stating the same value; unknown elements; every error and limit; hostile inputs (entity expansion, deep nesting, huge text, truncated files, binary garbage, a TCX file passed by mistake); and IO ownership and re-iteration.
- Assert decoded values, not merely that parsing succeeds.

## 11. Compatibility and packaging

- Ruby 3.1+, CI on 3.1, 3.2, 3.3, 3.4 and 4.0.
- Runtime dependency: `nokogiri ~> 1.17` (1.17 added the SAX `reference` callback).
- Semantic versioning. Publish to RubyGems only after the maintainer approves a release.

## 12. Milestones

- **M0 — Foundation** (this PR): specification, gem skeleton, CI.
- **M1 — Safe streaming reader:** XML layer, `Limits`, errors, root and version detection, section 7, security tests.
- **M2 — Messages and fields:** the message table in 6.2, schema typing for both versions, known extensions, unknown preservation.
- **M3 — Activity view:** section 6.4.
- **M4 — Hardening and release:** quirks from real exporters (reproduced synthetically), a benchmark on a 24-hour track, README examples verified, first release on approval.

## 13. Decisions (approved 2026-11-20)

1. **Times without a UTC offset.** Decided: `value` nil, `invalid_reason` `:no_utc_offset`, raw text kept. Same as tcxkit.
2. **Which source wins for a record value** when two extensions state it. Decided: TrackPointExtension v2, then v1, then PowerExtension, then GPXDATA, then bare `power`; GPX 1.0 `speed`/`course` before extensions.
3. **A `gpx` root without a namespace.** Decided: accept it, as in section 7.
