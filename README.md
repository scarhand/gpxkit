# GpxKit

A read-only, streaming Ruby parser for GPX 1.1 and GPX 1.0 (`.gpx`) files.

**Status: 0.1.0, the first release.** All four milestones of [`SPECIFICATION.md`](SPECIFICATION.md) are done. The API may still change before 1.0.

## Installation

```ruby
# Gemfile
gem "gpxkit"
```

Requires Ruby 3.1 or newer and Nokogiri 1.17 or newer (the only runtime dependency).

## Usage

```ruby
require "gpxkit"

activity = GpxKit::Activity.read("ride.gpx", limits: { max_seconds: 30 })
puts "#{activity.sport}: #{activity.start_time} to #{activity.end_time}"

activity.records.each do |record|
  puts [record.timestamp, record.latitude, record.longitude, record.altitude, record.heart_rate, record.power].inspect
end
```

The low-level reader yields one message per element:

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

GpxKit is a sister project of [fitkit](https://github.com/scarhand/fitkit) (FIT) and [tcxkit](https://github.com/scarhand/tcxkit) (TCX), and shares their API shape: the same reader contract and limits, matching error classes, and an `Activity` view with fitkit's method names.

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

The suite includes seeded fuzz tests. Longer or different rounds:

```sh
FUZZ_ITERATIONS=50000 FUZZ_SEED=7 bundle exec ruby -Ilib -Itest test/gpxkit/fuzz_test.rb
```

Test fixtures must be synthetic. Never commit real tracks: they contain locations, times and health data.

## Performance

Reading streams, so memory stays flat however long the file is (the `Activity` view keeps every message, by design). A one-hour activity reads in well under a second. A synthetic 24-hour file with a point every second (26 MB) takes about 9 s of CPU time on a laptop; set `limits: { max_seconds: ... }` for untrusted files. To time it yourself:

```sh
bundle exec ruby -Ilib bench/read_24h.rb
```

## Releasing

Releases are published by the maintainer: bump `lib/gpxkit/version.rb`, move the changelog's notes under the new version, then `bundle exec rake release`, which builds the gem, tags the commit and pushes the gem to RubyGems.

## Licence

MIT, see [`LICENSE`](LICENSE). Extension schemas by third parties are not part of this repository.
