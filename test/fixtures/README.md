# Test fixtures

Every fixture is synthetic: written by hand for these tests, with made-up places, times and measurements. None comes from a real activity or device. Never add real tracks: they contain locations, times and health data.

| File | Covers |
|---|---|
| `ride-1.1.gpx` | GPX 1.1 with metadata (author, copyright, links, bounds), a waypoint, a route, and a track with two segments. Track points use TrackPointExtension v2 and v1, PowerExtension v1, Cluetrust GPXDATA (`hr`, `cadence`, `temp`, `distance`), a bare `power`, an unknown extension namespace, and invalid values (`1e3` elevation, a time without offset, `" 3d"` fix, heart rate 0). |
| `walk-1.0.gpx` | GPX 1.0 with top-level metadata, a longitude of exactly 180, a track point with `course` and `speed`, and an extension directly in the point. |
