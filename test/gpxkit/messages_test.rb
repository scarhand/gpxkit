# frozen_string_literal: true

require_relative "../test_helper"

class MessagesTest < Minitest::Test
  def messages(name = "ride-1.1.gpx")
    @messages ||= {}
    @messages[name] ||= GpxKit::Reader.new(Documents.fixture(name)).each_message.to_a
  end

  def named(kind, file = "ride-1.1.gpx")
    messages(file).select { |message| message.name == kind }
  end

  def test_messages_arrive_when_their_element_closes
    assert_equal %i[metadata waypoint route_point route_point route track_point track_point track_segment
                    track_point track_segment track document], messages.map(&:name)
  end

  def test_context_places_each_message
    assert_equal [{ track: 0, track_segment: 0, track_point: 0 }, { track: 0, track_segment: 0, track_point: 1 },
                  { track: 0, track_segment: 1, track_point: 0 }], named(:track_point).map(&:context)
    assert_equal [{ route: 0, route_point: 0 }, { route: 0, route_point: 1 }], named(:route_point).map(&:context)
    assert_equal [{ track: 0, track_segment: 0 }, { track: 0, track_segment: 1 }], named(:track_segment).map(&:context)
    assert_equal [{ metadata: 0 }, { waypoint: 0 }, { route: 0 }, { track: 0 }, {}],
                 %i[metadata waypoint route track document].map { |kind| named(kind).first.context }
  end

  def test_track_point_fields
    point = named(:track_point).first

    assert_equal [12.3456789, -45.6789012, 10.4], point.to_h.values_at(:lat, :lon, :ele)
    assert_equal Time.utc(2026, 3, 14, 9), point.timestamp
    assert_equal [:"3d", 9, 0.9], point.to_h.values_at(:fix, :sat, :hdop)
  end

  def test_track_point_extension_v2_and_power_extension
    point = named(:track_point).first

    assert_equal [18.5, 120, 88, 7.5, 90.5], point.to_h.values_at(:atemp, :hr, :cad, :speed, :course)
    assert_equal 250, point[:power_in_watts]
    assert_equal "extensions/TrackPointExtension/hr", point.field(:hr).path
    assert_equal GpxKit::Schema::TRACK_POINT_EXTENSION_V2, point.field(:hr).namespace
    assert_equal GpxKit::Schema::POWER_EXTENSION_V1, point.field(:power_in_watts).namespace
  end

  def test_track_point_extension_v1_gpxdata_and_bare_power
    point = named(:track_point)[1]
    hr = point.fields_named(:hr)

    assert_equal [121, 122], hr.map(&:value)
    assert_equal [GpxKit::Schema::TRACK_POINT_EXTENSION_V1, GpxKit::Schema::GPXDATA], hr.map(&:namespace)
    assert_equal [87, 18.0, 7.6, :wheel], point.to_h.values_at(:cadence, :temp, :distance, :distance_sensor)
    assert_in_delta 255.0, point[:power]
    assert_equal Time.utc(2026, 3, 14, 9, 0, Rational(3, 2)), point.timestamp
  end

  def test_invalid_values_are_kept_with_a_reason
    point = named(:track_point).last

    assert_equal [:not_a_number, :no_utc_offset, :not_in_enumeration, :out_of_range],
                 %i[ele time fix hr].map { |name| point.field(name).invalid_reason }
    assert_equal ["1e3", "2026-03-14T09:10:00", " 3d", "0"], %i[ele time fix hr].map { |name| point.field(name).raw_value }
  end

  def test_unknown_extensions_are_kept
    field = named(:track_point).first.field(:mystery)

    refute_predicate field, :known?
    assert_equal ["42", "urn:example:unknown"], [field.value, field.namespace]
    assert_equal "root extension", named(:document).first[:note]
  end

  def test_metadata
    metadata = named(:metadata).first

    assert_equal ["Synthetic ride", "Example Rider", "rider", "example.org", "https://example.org/rider", "Profile"],
                 metadata.to_h.values_at(:name, :author_name, :author_email_id, :author_email_domain,
                                         :author_link_href, :author_link_text)
    assert_equal ["Example Rider", "2026", "https://example.org/ride/1", "text/html"],
                 metadata.to_h.values_at(:copyright_author, :copyright_year, :link_href, :link_type)
    assert_equal Time.utc(2026, 3, 14, 9), metadata.timestamp
    assert_equal [12.3, -45.7, 12.4, -45.6], metadata.to_h.values_at(:bounds_minlat, :bounds_minlon, :bounds_maxlat, :bounds_maxlon)
    assert metadata.fields.all?(&:known?)
  end

  def test_waypoints_routes_and_tracks
    assert_equal ["Café", "Flag", 15.0], named(:waypoint).first.to_h.values_at(:name, :sym, :ele)
    assert_equal %w[Start Turn], named(:route_point).map { |point| point[:name] }
    assert_equal "Planned loop", named(:route).first[:name]
    assert_equal ["Morning ride", "cycling"], named(:track).first.to_h.values_at(:name, :type)
  end

  def test_document
    document = named(:document).first

    assert_equal ["1.1", "Example Exporter"], document.to_h.values_at(:version, :creator)
    assert_equal "gpx", document.element_name
  end

  def test_gpx_1_0
    point = named(:track_point, "walk-1.0.gpx").first
    document = named(:document, "walk-1.0.gpx").first

    assert_equal [180.0, 360.0, 1.4], point.to_h.values_at(:lon, :course, :speed)
    assert point.fields.all?(&:valid?)
    assert_equal 95, point[:hr]
    assert_equal "TrackPointExtension/hr", point.field(:hr).path
    assert_equal ["1.0", "Synthetic walk", "Example Walker", "walker@example.org", "https://example.org/walk"],
                 document.to_h.values_at(:version, :name, :author, :email, :url)
    assert_equal [Time.utc(2026, 4, 1, 6), 180.0], document.to_h.values_at(:time, :bounds_maxlon)
    assert_equal 1, named(:track, "walk-1.0.gpx").first[:number]
  end

  def test_elements_with_only_attributes_give_only_attribute_fields
    names = named(:metadata).first.fields.map(&:name)

    refute_includes names, :bounds
    refute_includes names, :author_email
  end
end
