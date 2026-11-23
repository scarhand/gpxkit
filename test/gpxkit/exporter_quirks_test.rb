# frozen_string_literal: true

require_relative "../test_helper"

# Quirks seen in files from real exporters, reproduced synthetically.
class ExporterQuirksTest < Minitest::Test
  TPX1 = GpxKit::Schema::TRACK_POINT_EXTENSION_V1

  def gpx(point: "", name: "Café ride", declaration: %(<?xml version="1.0" encoding="UTF-8"?>), root: nil)
    root ||= %(<gpx xmlns="#{GpxKit::NAMESPACE_1_1}" version="1.1" creator="test">)
    %(#{declaration}\n#{root}\n<trk><name>#{name}</name><type>running</type><trkseg>\n) +
      %(<trkpt lat="52.0" lon="5.0"><ele>2.5</ele><time>2026-01-01T08:00:00Z</time>#{point}</trkpt>\n</trkseg></trk>\n</gpx>\n)
  end

  def read(bytes)
    GpxKit::Activity.from_io(StringIO.new(bytes))
  end

  def test_an_undeclared_extension_prefix_is_read_without_a_namespace
    activity = read(gpx(point: "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>"))
    field = activity.records.first.raw_message.field(:hr)

    assert_equal ["140", nil], [field.value, field.namespace]
    refute_predicate field, :known?
    assert_nil activity.records.first.heart_rate
    assert_equal 2.5, activity.records.first.altitude
  end

  def test_other_errors_after_a_namespace_error_are_still_invalid
    xml = gpx(point: "<extensions><gpxtpx:hr>140</gpxtpx:hr><a c='1' c='2'/></extensions>")

    assert_match(/redefined/, assert_raises(GpxKit::InvalidFileError) { read(xml) }.message)
  end

  def test_a_root_without_a_namespace_and_with_extensions
    root = %(<gpx version="1.1" creator="test" xmlns:gpxtpx="#{TPX1}">)
    record = read(gpx(root: root, point: "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>")).records.first

    assert_equal [140, 2.5, 52.0], [record.heart_rate, record.altitude, record.latitude]
  end

  def test_utf_16_documents
    declaration = %(<?xml version="1.0" encoding="UTF-16"?>)
    {
      "little-endian with a byte order mark" => "\xFF\xFE".b + gpx(declaration: declaration).encode("UTF-16LE").b,
      "big-endian with a byte order mark" => "\xFE\xFF".b + gpx(declaration: declaration).encode("UTF-16BE").b,
      "little-endian without one" => gpx(declaration: declaration).encode("UTF-16LE").b
    }.each do |label, bytes|
      activity = read(bytes)
      assert_equal ["Café ride", 2.5], [activity.session.name, activity.records.first.altitude], label
    end
  end

  def test_a_dtd_in_a_utf_16_document_is_refused
    xml = %(<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE gpx [<!ENTITY e "y">]>) + gpx(declaration: "", name: "&e;")

    assert_raises(GpxKit::UnsafeContentError) { read("\xFF\xFE".b + xml.encode("UTF-16LE").b) }
  end

  def test_inputs_that_hand_over_a_few_bytes_at_a_time
    utf16 = %(<?xml version="1.0" encoding="UTF-16"?>)
    {
      "UTF-8" => gpx,
      "UTF-8 with a byte order mark" => "\xEF\xBB\xBF".b + gpx.b,
      "UTF-16 little-endian with a byte order mark" => "\xFF\xFE".b + gpx(declaration: utf16).encode("UTF-16LE").b,
      "UTF-16 big-endian with a byte order mark" => "\xFE\xFF".b + gpx(declaration: utf16).encode("UTF-16BE").b,
      "UTF-16 little-endian without one" => gpx(declaration: utf16).encode("UTF-16LE").b,
      "UTF-16 big-endian without one" => gpx(declaration: utf16).encode("UTF-16BE").b
    }.each do |label, bytes|
      expected = GpxKit::Reader.new(StringIO.new(bytes)).each_message.map(&:to_h)
      [1, 2, 3, 5].each do |size|
        actual = GpxKit::Reader.new(Documents::ShortReads.new(bytes, size)).each_message.map(&:to_h)
        assert_equal expected, actual, "#{label}, #{size}-byte reads"
      end
    end
  end

  def test_a_dtd_after_a_byte_order_mark_is_refused_from_short_reads
    dtd = %(<!DOCTYPE x [<!ENTITY e "y">]>)
    {
      "UTF-8" => "\xEF\xBB\xBF".b + (dtd + gpx.sub(/\A<\?xml[^>]*>/, "")).b,
      "UTF-16" => "\xFF\xFE".b + (dtd + gpx.sub(/\A<\?xml[^>]*>/, "")).encode("UTF-16LE").b
    }.each do |label, bytes|
      [1, 2, 3].each do |size|
        assert_raises(GpxKit::UnsafeContentError, "#{label}, #{size}-byte reads") do
          GpxKit::Reader.new(Documents::ShortReads.new(bytes, size)).each_message { |*| nil }
        end
      end
    end
  end

  def test_single_byte_encodings_declared_in_the_xml_declaration
    latin1 = gpx(declaration: %(<?xml version="1.0" encoding="ISO-8859-1"?>)).encode("ISO-8859-1").b
    windows = gpx(declaration: %(<?xml version="1.0" encoding="windows-1252"?>), name: "€5 ride").encode("Windows-1252").b

    assert_equal "Café ride", read(latin1).session.name
    assert_equal "€5 ride", read(windows).session.name
  end

  def test_latin_1_bytes_in_a_utf_8_document_are_invalid
    bytes = gpx.b.sub("Caf\xC3\xA9".b, "Caf\xE9".b)

    assert_match(/encoding/i, assert_raises(GpxKit::InvalidFileError) { read(bytes) }.message)
  end

  def test_crlf_line_endings
    activity = read(gpx(name: "line one\nline two").gsub("\n", "\r\n"))

    assert_equal "line one\nline two", activity.session.name
    assert_equal 2.5, activity.records.first.altitude
  end

  def test_whitespace_and_a_byte_order_mark_before_the_declaration
    assert_equal "running", read("\xEF\xBB\xBF \r\n#{gpx}").sport
  end

  def test_near_miss_values_are_invalid_not_guessed
    {
      "2026-01-01T08:00:00+0000" => :not_a_date_time,
      "2026-01-01T08:00:00z" => :not_a_date_time,
      "2026-01-01T08:00:00" => :no_utc_offset
    }.each do |text, reason|
      record = read(gpx.sub("2026-01-01T08:00:00Z", text)).records.first
      assert_nil record.timestamp, text
      assert_equal reason, record.raw_message.field(:time).invalid_reason, text
    end
    assert_equal :not_a_number, read(gpx.sub("<ele>2.5</ele>", "<ele>2,5</ele>")).records.first.raw_message.field(:ele).invalid_reason
  end
end
