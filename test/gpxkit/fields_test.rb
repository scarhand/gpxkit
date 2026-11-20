# frozen_string_literal: true

require_relative "../test_helper"

class FieldsTest < Minitest::Test
  TPX2 = GpxKit::Schema::TRACK_POINT_EXTENSION_V2

  def point(children = "", **options)
    Documents.message(Documents.track_point(children, **options), :track_point)
  end

  def test_decimals_have_no_exponent
    assert_equal 12.5, point("<ele> 12.5 </ele>")[:ele]
    assert_equal :not_a_number, point("<ele>1.25e1</ele>").field(:ele).invalid_reason
    assert_equal :not_a_number, point("<ele>INF</ele>").field(:ele).invalid_reason
  end

  def test_doubles_in_extensions_allow_exponents
    xml = %(<extensions><t:TrackPointExtension xmlns:t="#{TPX2}"><t:speed>7.5e0</t:speed></t:TrackPointExtension></extensions>)

    assert_equal 7.5, point(xml)[:speed]
  end

  def test_gpx_1_1_coordinate_ranges
    assert_equal [90.0, -180.0], point(attributes: %(lat="90" lon="-180")).to_h.values_at(:lat, :lon)
    assert_equal :out_of_range, point(attributes: %(lat="90.5" lon="0")).field(:lat).invalid_reason
    assert_equal :out_of_range, point(attributes: %(lat="0" lon="180")).field(:lon).invalid_reason
    assert_equal :out_of_range, point("<magvar>360</magvar>").field(:magvar).invalid_reason
  end

  def test_gpx_1_0_allows_180_and_360
    one_oh = { namespace: GpxKit::NAMESPACE_1_0, version: "1.0" }

    assert_equal 180.0, point(attributes: %(lat="0" lon="180"), **one_oh)[:lon]
    assert_equal 360.0, point("<course>360</course>", **one_oh)[:course]
    assert_equal :out_of_range, point("<course>360.1</course>", **one_oh).field(:course).invalid_reason
  end

  def test_course_and_speed_are_gpx_1_0_only
    refute_predicate point("<course>10</course>").field(:course), :known?
  end

  def test_fix_keeps_whitespace_as_xsd_string
    assert_equal :dgps, point("<fix>dgps</fix>")[:fix]
    assert_equal :not_in_enumeration, point("<fix>3d </fix>").field(:fix).invalid_reason
    assert_equal :not_in_enumeration, point("<fix>3D</fix>").field(:fix).invalid_reason
  end

  def test_integers
    assert_equal 1023, point("<dgpsid>1023</dgpsid>")[:dgpsid]
    assert_equal :out_of_range, point("<dgpsid>-1</dgpsid>").field(:dgpsid).invalid_reason
    assert_equal 12_345_678_901, point("<sat>12345678901</sat>")[:sat]
    assert_equal :not_an_integer, point("<sat>-1</sat>").field(:sat).invalid_reason
  end

  def test_heart_rate_and_cadence_ranges
    extension = ->(body) { %(<extensions><t:TrackPointExtension xmlns:t="#{TPX2}">#{body}</t:TrackPointExtension></extensions>) }

    assert_equal [255, 254], point(extension.call("<t:hr>255</t:hr><t:cad>254</t:cad>")).to_h.values_at(:hr, :cad)
    assert_equal :out_of_range, point(extension.call("<t:hr>0</t:hr>")).field(:hr).invalid_reason
    assert_equal :out_of_range, point(extension.call("<t:cad>255</t:cad>")).field(:cad).invalid_reason
  end

  def test_extensions_count_only_in_their_namespace
    other = point(%(<extensions><TrackPointExtension xmlns="urn:other"><hr>120</hr></TrackPointExtension></extensions>))

    refute_predicate other.field(:hr), :known?
    assert_equal "120", other[:hr]
  end

  def test_extension_prefixes_do_not_matter
    xml = %(<extensions><abc:PowerInWatts xmlns:abc="#{GpxKit::Schema::POWER_EXTENSION_V1}">99</abc:PowerInWatts></extensions>)

    assert_equal 99, point(xml)[:power_in_watts]
  end

  def test_a_document_without_a_namespace
    xml = Documents.track_point(%(<ele>5</ele><extensions><power>200</power></extensions>), namespace: nil, version: "1.1")
    point = Documents.message(xml, :track_point)

    assert_equal [1.5, 5.0, 200.0], point.to_h.values_at(:lat, :ele, :power)
    assert point.fields.all?(&:known?)
    assert_nil point.namespace
  end

  def test_gpx_elements_from_the_other_version_are_unknown
    xml = Documents.track_point(%(<ele xmlns="#{GpxKit::NAMESPACE_1_0}">5</ele>))

    refute_predicate Documents.message(xml, :track_point).field(:ele), :known?
  end

  def test_unknown_elements_in_the_gpx_namespace_are_kept
    field = point("<heading>12</heading>").field(:heading)

    refute_predicate field, :known?
    assert_equal "12", field.value
  end

  def test_message_elements_only_count_where_the_schema_puts_them
    xml = Documents.gpx(%(<trk><trkpt lat="1" lon="2"/><trkseg><trkpt lat="1" lon="2"/></trkseg></trk><trkpt lat="3" lon="4"/>))
    messages = Documents.messages(xml)

    assert_equal %i[track_point track_segment track document], messages.map(&:name)
    assert_equal ["1", "3"], [messages[2]["trkpt/@lat"], messages[3]["trkpt/@lat"]]
  end
end
