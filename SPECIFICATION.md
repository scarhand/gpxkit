# GpxKit — Project Specification

**Status:** Approved by the maintainer on 2026-11-20; all milestones done for 0.1.0 (2026-11-23)
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
- Never fill in, estimate, smooth or derive measurements the file does not contain. In particular, never compute distance, speed or durations from positions and timestamps; that belongs to the application, labelled as derived. A distance the file states (GPXDATA `distance`) is reported as stated.
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

A message is emitted when its element closes, so it carries everything inside it: a segment's points arrive before the segment, a track's segments before the track. Elements in the document's GPX namespace become messages only where the schema puts them:

| Message name | Element (where) | Fields include |
|---|---|---|
| `:metadata` | `metadata` (1.1, in `gpx`) | `name`, `desc`, `author_name`, `author_email_id`, `author_email_domain`, `author_link_href`, `copyright_author`, `copyright_year`, `link_href`, `link_text`, `link_type`, `time`, `keywords`, `bounds_minlat` ... |
| `:waypoint` | `wpt` (in `gpx`) | the point fields below |
| `:route_point` | `rtept` (in `rte`) | the point fields below |
| `:route` | `rte` (in `gpx`) | `name`, `cmt`, `desc`, `src`, `link_href`, `number`, `type` (1.1), `url`, `urlname` (1.0) |
| `:track_point` | `trkpt` (in `trkseg`) | the point fields below, and in 1.0 `course` and `speed` |
| `:track_segment` | `trkseg` (in `trk`) | none of its own |
| `:track` | `trk` (in `gpx`) | as `:route` |
| `:document` | `gpx` | `version`, `creator`; in 1.0 also the top-level `name`, `desc`, `author`, `email`, `url`, `urlname`, `time`, `keywords`, `bounds_*`; anything else directly in `gpx`, such as its `extensions`; always the last message |

Point fields (`wptType`): `lat`, `lon`, `ele`, `time`, `magvar`, `geoidheight`, `name`, `cmt`, `desc`, `src`, `link_href`, `link_text`, `link_type` (1.1), `url`, `urlname` (1.0), `sym`, `type`, `fix`, `sat`, `hdop`, `vdop`, `pdop`, `ageofdgpsdata`, `dgpsid`, plus the known extensions in 6.3.

Every leaf element and every attribute inside a message, outside the messages nested in it, is one of its fields. An element with only attributes (`<bounds .../>`) gives only its attribute fields, and an empty `extensions` is not a field.

Field names join the snake_case names of every element on the path, attributes included, and leave out the wrappers `extensions`, `Extensions` and `TrackPointExtension`: `link/@href` is `link_href`, `author/email/@id` is `author_email_id`, `extensions/TrackPointExtension/hr` is `hr`, `extensions/PowerInWatts` is `power_in_watts`. The path keeps every element, with local names only, since prefixes are chosen by each file. When names repeat (`hr` from TrackPointExtension and from GPXDATA), `fields_named` returns all of them, and the path or `namespace` tells them apart.

`context` places a message: its own index and its ancestors'. `metadata`, `waypoint`, `route` and `track` count across the document; `route_point` counts within its route, `track_segment` within its track and `track_point` within its segment.

```ruby
message.name                # :track_point
message.element_name        # "trkpt"
message.context             # { track: 0, track_segment: 1, track_point: 812 }
message.line, message.column
message.fields              # Array of Field, in document order (names can repeat)
message[:ele]               # typed value of the first field with that name
message["extensions/TrackPointExtension/hr"] # lookup by path
message.field(:hr)
message.fields_named(:hr)
message.attributes          # fields for the message element's own attributes
message.timestamp           # the time field
message.to_h
```

### 6.3 Fields

```ruby
field.name           # :hr
field.path           # "extensions/TrackPointExtension/hr"
field.namespace      # the TrackPointExtension v2 namespace URI
field.text           # " 142 ", exactly as written
field.raw_value      # "142": the text after the type's whitespace rule
field.value          # 142, typed; nil when invalid
field.type           # :decimal, :latitude, :date_time, :fix, :beats_per_minute, :string, :unknown, ...
field.known?
field.valid?
field.invalid_reason # nil, :empty, :not_a_number, :not_finite, :not_an_integer, :out_of_range,
                     # :not_a_date_time, :no_utc_offset, :not_in_enumeration, :not_a_year
field.line
```

Types come from tables written from the schemas of the document's version, keyed by path and namespace. In GPX 1.1 extensions are typed inside `extensions`; in GPX 1.0, which has no `extensions` element, directly inside the point.

- Whitespace: `xsd:string`, and `fixType` (an enumeration based on `xsd:string`), keep the text as written; every other type collapses it.
- `xsd:decimal` → `Float`, with no exponent, `INF` or `NaN` (`:not_a_number`). Extension values typed `xsd:double` allow exponents. Callers that need exact decimals use `BigDecimal(field.raw_value)`.
- Integer types → `Integer`, range-checked: `nonNegativeInteger` (`sat`, `number`), `dgpsStationType` (0 to 1023). An optional `+`, and `-` before zero, are accepted, as XSD 1.0 and 1.1 both allow for `nonNegativeInteger` and XSD 1.1 for the unsigned types; `-1` is `:not_an_integer`.
- `xsd:dateTime` → `Time` in UTC when the text has `Z` or an offset; without one, `nil` and `:no_utc_offset` (decision 1). Same rules as tcxkit.
- `fixType` → `:none`, `:"2d"`, `:"3d"`, `:dgps`, `:pps`; matching is exact.
- `xsd:anyURI` → the collapsed `String`.
- `xsd:gYear` (`copyright/year`) → the year as an `Integer` (`2026`); a time zone, if written, stays in `raw_value`. Anything else, such as `26` or `2026-01`, is `:not_a_year`.
- Ranges are validity, not errors. GPX 1.1: `latitudeType` (-90 to 90), `longitudeType` (-180 up to, not including, 180), `degreesType` (0 up to, not including, 360). GPX 1.0 allows 180 and 360 themselves.
- Unknown elements and attributes: `known?` false, `type` `:unknown`, `value` is the text as written. That includes GPX elements of the other version (`course` in a 1.1 track point) and elements in the other version's namespace.

Known extensions:

| Namespace | Elements and types |
|---|---|
| TrackPointExtension v1 | `atemp`, `wtemp` (°C, double), `depth` (m, double), `hr` (1 to 255), `cad` (0 to 254) |
| TrackPointExtension v2 | v1's, plus `speed` (m/s, double), `course`, `bearing` (decimal, 0 to 360) |
| PowerExtension v1 | `PowerInWatts` (unsigned short) |
| Cluetrust GPXDATA 1.0 | `hr`, `cadence` (non-negative integers), `temp` (decimal), `distance` (decimal, with a `sensor` attribute: `wheel` or `pedometer`) |
| the document's GPX namespace (1.1) | `power` inside `extensions`, as several exporters write it; read as a decimal |

### 6.4 Activity view

The shared shape across fitkit, tcxkit and gpxkit, applied to what GPX can state:

```ruby
activity = GpxKit::Activity.read("ride.gpx", limits: { max_seconds: 30 })
# also Activity.from_file(path) and Activity.from_io(io); options go to Reader.new

activity.sessions   # one per <trk>
activity.laps       # always empty: GPX has no laps
activity.records    # every track point, in file order
activity.waypoints  # waypoints, as records
activity.routes     # routes, each with its points as records
activity.metadata   # the 1.1 :metadata message, or in 1.0 the :document message
activity.document   # the :document message
activity.version    # "1.1" or "1.0"
activity.creator    # gpx@creator
activity.messages
activity.session

# Summary methods read the first session, as in fitkit:
activity.sport      # the first track's <type>, as written; nil if absent
activity.start_time # the first track's first valid point time
activity.end_time   # the last track's last valid point time
activity.total_distance, activity.total_timer_time, ... # nil: GPX states no totals

session = activity.session
session.name, session.description, session.number
session.sport       # <type>, as written ("running", "9", "treadmill_running", ...)
session.segments    # each with its records
session.records

record = activity.records.first
record.timestamp    # Time (UTC)
record.latitude, record.longitude
record.altitude     # ele, m
record.name
record.heart_rate   # bpm
record.cadence      # rpm
record.power        # W
record.temperature  # °C
record.speed        # m/s
record.course       # degrees
record.distance     # GPXDATA distance, m, as stated; nil without it
record.raw_message
```

Method names match `FitKit::Activity` wherever the meaning matches. A method whose value GPX cannot state returns `nil` instead of computing one. The view does not assume the file is an activity: a GPX with only routes or waypoints reads fine, with no sessions or records.

Record values come from the first valid source, in this order (decision 2); every source stays on the raw message, and an invalid value (a heart rate of 0) falls through to the next source:

| Value | Sources, in order |
|---|---|
| `heart_rate` | TrackPointExtension v2 `hr`, v1 `hr`, GPXDATA `hr` |
| `cadence` | TrackPointExtension v2 `cad`, v1 `cad`, GPXDATA `cadence` |
| `power` | PowerExtension `PowerInWatts`, then a bare `power` (a decimal, so a `Float`) |
| `temperature` | TrackPointExtension v2 `atemp`, v1 `atemp`, GPXDATA `temp` |
| `speed`, `course` | GPX 1.0 `speed`/`course`, then TrackPointExtension v2 |
| `distance` | GPXDATA `distance` |

Garmin's GPX export of an activity without GPS, such as a treadmill run, has an empty track: no points, and so no heart rate either.

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

Known real-world quirks, each reproduced in `test/gpxkit/exporter_quirks_test.rb`:

- A `gpx` root without any namespace. Read it as the version its `version` attribute names; the `:document` message's `namespace` is then `nil` (decision 3, section 13).
- Whitespace before the XML declaration. Skipped, as in tcxkit. A UTF-8 byte order mark is accepted as XML allows.
- A namespace prefix used without being declared (`<gpxtpx:hr>` with no `xmlns:gpxtpx`), or bound to an empty namespace: libxml2 reports these and reads on, and so does the reader. The element has no namespace, so its values are kept as untyped fields; the gem does not guess which namespace was meant (decision 4). Any other error still makes the file invalid.
- UTF-16 documents (with or without a byte order mark) and single-byte encodings named in the XML declaration (`ISO-8859-1`, `windows-1252`) are read; values come out as UTF-8. The DTD check decodes the start of a UTF-16 document, so a DTD is refused there too.
- Bytes that do not match the declared encoding (Latin-1 bytes in a UTF-8 document) make the file invalid.
- Carriage returns: XML turns `\r\n` into `\n` in text.
- Near-miss values stay invalid, with their text kept: `+0000` or a lowercase `z` in a time, a decimal comma in `ele`.

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

- **M0 — Foundation** (done): specification, gem skeleton, CI.
- **M1 — Safe streaming reader** (done): XML layer, `Limits`, errors, root and version detection, section 7, security tests.
- **M2 — Messages and fields** (done): the message table in 6.2, schema typing for both versions, known extensions, unknown preservation.
- **M3 — Activity view** (done): section 6.4.
- **M4 — Hardening and release** (done; release on approval): quirks from real exporters (reproduced synthetically), a benchmark on a 24-hour track, README examples verified, first release on approval. Also seeded fuzz tests of bytes, markup and values, and reading without Ruby warnings.

## 13. Decisions (approved 2026-11-20)

1. **Times without a UTC offset.** Decided: `value` nil, `invalid_reason` `:no_utc_offset`, raw text kept. Same as tcxkit.
2. **Which source wins for a record value** when two extensions state it. Decided: TrackPointExtension v2, then v1, then PowerExtension, then GPXDATA, then bare `power`; GPX 1.0 `speed`/`course` before extensions.
3. **A `gpx` root without a namespace.** Decided: accept it, as in section 7.
4. **Namespace errors** (2026-11-23). Decided: an undeclared or empty namespace prefix does not stop reading; the elements involved have no namespace, so their values are untyped fields. The same as tcxkit's decision 6. Pending the maintainer's review in the M4 pull request.
