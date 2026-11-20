# GpxKit

A read-only, streaming Ruby parser for GPX 1.1 and GPX 1.0 (`.gpx`) files.

**Status: milestone M1 of 4.** The reader reads a whole document safely (limits, DTD refusal, truncation detection) and checks it is GPX 1.1 or 1.0, but yields no messages yet; they arrive in M2. The full API is in [`SPECIFICATION.md`](SPECIFICATION.md).

```ruby
require "gpxkit"

begin
  GpxKit::Reader.new("ride.gpx", limits: { max_seconds: 30 }).each_message { |message| }
rescue GpxKit::TruncatedFileError, GpxKit::InvalidFileError, GpxKit::UnsupportedFormatError,
       GpxKit::UnsafeContentError, GpxKit::LimitExceededError => error
  warn "#{error.class}: #{error.message}" # includes the line and column
end
```

GpxKit is a sister project of [fitkit](https://github.com/scarhand/fitkit) (FIT) and [tcxkit](https://github.com/scarhand/tcxkit) (TCX), and shares their API shape. Planned for M2 and M3:

```ruby
require "gpxkit"

# Low level: one message per track point, segment, track, waypoint, route, ...
GpxKit::Reader.new("ride.gpx").each_message do |message|
  puts message[:ele] if message.name == :track_point
end

# Activity view: tracks as sessions, track points as records
activity = GpxKit::Activity.read("ride.gpx")
activity.records.each { |record| puts [record.timestamp, record.latitude, record.longitude, record.heart_rate].inspect }
```

Common fitness extensions (Garmin TrackPointExtension v1/v2, PowerExtension, Cluetrust GPXDATA) will be decoded; others kept as written.

## Principles

- Read-only: never writes or repairs files.
- Untrusted input: no network access, no DTD entities, enforced limits on size, depth and time.
- Values exactly as written next to typed values; unknown elements and extensions kept.
- Nothing filled in, estimated or derived: no distances or speeds computed from positions.

## Development

```sh
bundle install
bundle exec rake test
```

Requires Ruby 3.1 or newer. The only runtime dependency is Nokogiri.

Test fixtures must be synthetic. Never commit real tracks: they contain locations, times and health data.

## Licence

MIT, see [`LICENSE`](LICENSE). Extension schemas by third parties are not part of this repository.
