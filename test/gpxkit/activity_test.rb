# frozen_string_literal: true

require_relative "../test_helper"

class ActivityTest < Minitest::Test
  TPX1 = GpxKit::Schema::TRACK_POINT_EXTENSION_V1
  TPX2 = GpxKit::Schema::TRACK_POINT_EXTENSION_V2

  def ride = @ride ||= GpxKit::Activity.read(Documents.fixture("ride-1.1.gpx"))
  def walk = @walk ||= GpxKit::Activity.read(Documents.fixture("walk-1.0.gpx"))

  def read(xml)
    GpxKit::Activity.from_io(StringIO.new(xml))
  end

  def record(children, **options)
    read(Documents.track_point(children, **options)).records.first
  end

  def test_reads_paths_io_and_options
    assert_equal 3, GpxKit::Activity.from_file(Documents.fixture("ride-1.1.gpx")).records.size
    assert_raises(GpxKit::LimitExceededError) do
      GpxKit::Activity.read(Documents.fixture("ride-1.1.gpx"), limits: { max_depth: 3 })
    end
  end

  def test_sessions_segments_and_records
    assert_equal 1, ride.sessions.size
    assert_equal [2, 1], ride.session.segments.map { |segment| segment.records.size }
    assert_equal 3, ride.records.size
    assert_equal ride.records, ride.session.records
    assert_empty ride.laps
    assert_empty ride.session.laps
    assert_predicate ride, :frozen?
    assert_predicate ride.records, :frozen?
  end

  def test_session_values
    session = ride.session

    assert_equal ["Morning ride", "cycling", nil], [session.name, session.sport, session.number]
    assert_equal "cycling", ride.sport
    assert_equal Time.utc(2026, 3, 14, 9), ride.start_time
    # The last point's time has no UTC offset, so the last valid time is the second point's.
    assert_equal Time.utc(2026, 3, 14, 9, 0, Rational(3, 2)), ride.end_time
  end

  def test_document_values
    assert_equal ["1.1", "Example Exporter", "Synthetic ride"], [ride.version, ride.creator, ride.metadata[:name]]
    assert_equal ["1.0", "Example Logger", "Synthetic walk"], [walk.version, walk.creator, walk.metadata[:name]]
    assert_equal :document, walk.metadata.name
  end

  def test_gpx_states_no_totals
    (GpxKit::Activity::SUMMARY - %i[sport]).each do |name|
      assert_nil ride.public_send(name), name
    end
  end

  def test_waypoints_and_routes
    assert_equal ["Café", 15.0, 12.35], ride.waypoints.first.then { |point| [point.name, point.altitude, point.latitude] }
    assert_equal ["Planned loop"], ride.routes.map(&:name)
    assert_equal %w[Start Turn], ride.routes.first.points.map(&:name)
    refute_includes ride.records, ride.waypoints.first
  end

  def test_record_values_from_track_point_extension_v2_and_power_extension
    record = ride.records.first

    assert_equal [Time.utc(2026, 3, 14, 9), 12.3456789, -45.6789012, 10.4],
                 [record.timestamp, record.latitude, record.longitude, record.altitude]
    assert_equal [120, 88, 250, 18.5, 7.5, 90.5, nil],
                 [record.heart_rate, record.cadence, record.power, record.temperature, record.speed, record.course, record.distance]
    assert_equal :track_point, record.raw_message.name
  end

  def test_record_values_from_track_point_extension_v1_gpxdata_and_bare_power
    record = ride.records[1]

    assert_equal [121, 87, 255.0, 18.0, 7.6], [record.heart_rate, record.cadence, record.power, record.temperature, record.distance]
    assert_equal [121, 122], record.raw_message.fields_named(:hr).map(&:value)
  end

  def test_invalid_values_are_nil
    record = ride.records.last

    assert_equal [nil, nil, nil], [record.timestamp, record.altitude, record.heart_rate]
  end

  def test_an_invalid_first_source_falls_through_to_the_next
    xml = %(<extensions><t:TrackPointExtension xmlns:t="#{TPX2}"><t:hr>0</t:hr></t:TrackPointExtension>
      <g:hr xmlns:g="#{GpxKit::Schema::GPXDATA}">130</g:hr></extensions>)

    assert_equal 130, record(xml).heart_rate
  end

  def test_source_order
    v1 = %(<v1:TrackPointExtension xmlns:v1="#{TPX1}"><v1:hr>110</v1:hr><v1:cad>70</v1:cad></v1:TrackPointExtension>)
    v2 = %(<v2:TrackPointExtension xmlns:v2="#{TPX2}"><v2:hr>120</v2:hr><v2:cad>80</v2:cad><v2:speed>3.5</v2:speed></v2:TrackPointExtension>)
    power = %(<p:PowerInWatts xmlns:p="#{GpxKit::Schema::POWER_EXTENSION_V1}">200</p:PowerInWatts><power>300</power>)

    assert_equal [120, 80, 200], record("<extensions>#{v1}#{power}#{v2}</extensions>").then { |r| [r.heart_rate, r.cadence, r.power] }
    assert_equal [110, 300.0], record("<extensions>#{v1}<power>300</power></extensions>").then { |r| [r.heart_rate, r.power] }
    assert_equal 3.5, record("<extensions>#{v2}</extensions>").speed
  end

  def test_gpx_1_0_speed_and_course_come_before_extensions
    record = walk.records.first

    assert_equal [1.4, 360.0, 95, 180.0], [record.speed, record.course, record.heart_rate, record.longitude]
  end

  def test_unknown_namespaces_are_not_used
    xml = %(<extensions><TrackPointExtension xmlns="urn:other"><hr>150</hr></TrackPointExtension></extensions>)

    assert_nil record(xml).heart_rate
  end

  def test_a_document_without_a_namespace
    record = record("<ele>5</ele><time>2026-01-01T08:00:00Z</time>", namespace: nil, version: "1.1")

    assert_equal [5.0, Time.utc(2026, 1, 1, 8), 1.5], [record.altitude, record.timestamp, record.latitude]
  end

  def test_a_file_with_only_waypoints
    activity = read(Documents.gpx(%(<wpt lat="1" lon="2"><name>Home</name></wpt>)))

    assert_empty activity.sessions
    assert_empty activity.records
    assert_equal ["Home"], activity.waypoints.map(&:name)
    assert_nil activity.sport
    assert_nil activity.start_time
  end

  def test_several_tracks
    xml = Documents.gpx(%(<trk><type>running</type><trkseg><trkpt lat="1" lon="2"><time>2026-01-01T08:00:00Z</time></trkpt></trkseg></trk>
      <trk><type>cycling</type><trkseg><trkpt lat="1" lon="2"><time>2026-01-01T09:00:00Z</time></trkpt></trkseg></trk>))
    activity = read(xml)

    assert_equal %w[running cycling], activity.sessions.map(&:sport)
    assert_equal [Time.utc(2026, 1, 1, 8), Time.utc(2026, 1, 1, 9)], [activity.start_time, activity.end_time]
    assert_equal 2, activity.records.size
  end
end
