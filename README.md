# GpxKit

A read-only, streaming Ruby parser for GPX 1.1 and GPX 1.0 (`.gpx`) files.

**Status: milestone M2 of 4.** The reader streams typed messages for every track point, segment, track, waypoint, route and the metadata of a GPX 1.1 or 1.0 document, including the common fitness extensions. The `Activity` view arrives in M3. The full API is in [`SPECIFICATION.md`](SPECIFICATION.md).

```ruby
require "gpxkit"

GpxKit::Reader.new("ride.gpx", limits: { max_seconds: 30 }).each_message do |message|
  next unless message.name == :track_point

  puts [message.timestamp, message[:lat], message[:lon], message[:ele], message[:hr], message[:power_in_watts]].inspect
end
```

Every value is a `Field` with the text as written, a typed value, and a reason when the value does not fit the schema:

```ruby
field = message.field(:ele)
field.text            # "1e3"
field.value           # nil
field.invalid_reason  # :not_a_number (xsd:decimal has no exponent)
```

Errors carry the line and column:

```ruby
rescue GpxKit::TruncatedFileError, GpxKit::InvalidFileError, GpxKit::UnsupportedFormatError,
       GpxKit::UnsafeContentError, GpxKit::LimitExceededError => error
```

GpxKit is a sister project of [fitkit](https://github.com/scarhand/fitkit) (FIT) and [tcxkit](https://github.com/scarhand/tcxkit) (TCX), and shares their API shape. The activity view is planned for M3:

```ruby
require "gpxkit"

# Activity view: tracks as sessions, track points as records
activity = GpxKit::Activity.read("ride.gpx")
activity.records.each { |record| puts [record.timestamp, record.latitude, record.longitude, record.heart_rate].inspect }
```

Common fitness extensions (Garmin TrackPointExtension v1/v2, PowerExtension, Cluetrust GPXDATA) are decoded; others are kept as written.

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
