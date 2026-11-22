# frozen_string_literal: true

require_relative "../test_helper"

# Section 7: elements in an order the schema does not allow are read
# through, each typed where it is.
class ElementOrderTest < Minitest::Test
  TPX2 = GpxKit::Schema::TRACK_POINT_EXTENSION_V2

  def test_track_point_children_in_any_order
    xml = Documents.track_point(<<~XML)
      <extensions><t:TrackPointExtension xmlns:t="#{TPX2}"><t:cad>80</t:cad><t:hr>130</t:hr></t:TrackPointExtension></extensions>
      <sat>8</sat><time>2026-01-01T08:00:00Z</time><name>p</name><ele>4.5</ele>
    XML
    point = Documents.message(xml, :track_point)

    assert_equal [80, 130, 8, Time.utc(2026, 1, 1, 8), "p", 4.5], point.to_h.values_at(:cad, :hr, :sat, :time, :name, :ele)
    assert point.fields.all?(&:known?)
  end

  def test_track_fields_after_its_segments_and_metadata_after_tracks
    xml = Documents.gpx(<<~XML, declaration: true)
      <trk><trkseg><trkpt lat="1" lon="2"/></trkseg><number>3</number><name>Late</name></trk>
      <metadata><name>Last</name></metadata>
    XML
    messages = Documents.messages(xml).reject { |message| message.name == :metadata && message.fields.empty? }
    track = messages.find { |message| message.name == :track }

    assert_equal [3, "Late"], track.to_h.values_at(:number, :name)
    assert_equal "Last", messages.find { |message| message.name == :metadata && message[:name] }[:name]
  end
end
