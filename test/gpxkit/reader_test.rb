# frozen_string_literal: true

require_relative "../test_helper"
require "tempfile"

class ReaderTest < Minitest::Test
  def test_reads_gpx_1_1_and_1_0
    assert_nil Documents.read(Documents.gpx)
    assert_nil Documents.read(Documents.gpx(namespace: GpxKit::NAMESPACE_1_0, version: "1.0"))
  end

  def test_the_namespace_decides_when_the_version_disagrees
    assert_nil Documents.read(Documents.gpx(namespace: GpxKit::NAMESPACE_1_0, version: "1.1"))
  end

  def test_reads_a_gpx_root_without_a_namespace_by_its_version
    assert_nil Documents.read(Documents.gpx(namespace: nil, version: "1.1"))
    assert_nil Documents.read(Documents.gpx(namespace: nil, version: "1.0"))
  end

  def test_rejects_a_gpx_root_without_a_namespace_or_a_known_version
    [nil, "2.0"].each do |version|
      xml = version ? Documents.gpx(namespace: nil, version: version) : "<gpx creator='x'/>"
      error = assert_raises(GpxKit::UnsupportedFormatError) { Documents.read(xml) }
      assert_match(/no namespace/, error.message)
    end
  end

  def test_each_message_without_a_block_returns_an_enumerator
    enumerator = GpxKit::Reader.new(StringIO.new(Documents.gpx)).each_message

    assert_kind_of Enumerator, enumerator
    assert_equal %i[metadata document], enumerator.map(&:name)
  end

  def test_skips_whitespace_before_the_xml_declaration
    assert_nil Documents.read("   \r\n\t#{Documents.gpx}")
    assert_nil Documents.read("\xEF\xBB\xBF  #{Documents.gpx}")
  end

  def test_rejects_another_root_element
    error = assert_raises(GpxKit::UnsupportedFormatError) do
      Documents.read(%(<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"/>))
    end

    assert_match(/root element is TrainingCenterDatabase/, error.message)
    assert_equal 1, error.line
  end

  def test_rejects_a_gpx_root_in_another_namespace
    error = assert_raises(GpxKit::UnsupportedFormatError) do
      Documents.read(Documents.gpx(namespace: "http://www.topografix.com/GPX/2/0"))
    end

    assert_match(/namespace/, error.message)
  end

  def test_reads_paths_and_pathnames
    Tempfile.create(["ride", ".gpx"]) do |file|
      file.write(Documents.gpx)
      file.close

      assert_nil GpxKit::Reader.new(file.path).each_message { |*| nil }
      assert_nil GpxKit::Reader.new(Pathname.new(file.path)).each_message { |*| nil }
      assert_equal file.path, GpxKit::Reader.new(file.path).source_label
    end
  end

  def test_a_seekable_io_can_be_read_again_from_its_starting_position
    io = StringIO.new("junk#{Documents.gpx}")
    io.read(4)
    reader = GpxKit::Reader.new(io)

    2.times { assert_nil reader.each_message { |*| nil } }
    refute_predicate io, :closed?
  end

  def test_a_non_seekable_io_can_be_read_once
    reader, writer = IO.pipe
    writer.write(Documents.gpx)
    writer.close
    gpx = GpxKit::Reader.new(reader)
    gpx.each_message { |*| nil }

    assert_raises(GpxKit::Error) { gpx.each_message { |*| nil } }
  ensure
    reader&.close
  end

  def test_close_io_closes_the_callers_io
    io = StringIO.new(Documents.gpx)
    reader = GpxKit::Reader.new(io, close_io: true)
    reader.each_message { |*| nil }

    assert_predicate io, :closed?
    assert_raises(GpxKit::Error) { reader.each_message { |*| nil } }
  end

  def test_close_io_closes_even_after_an_error
    io = StringIO.new("<oops")

    assert_raises(GpxKit::Error) { GpxKit::Reader.new(io, close_io: true).each_message { |*| nil } }
    assert_predicate io, :closed?
  end

  def test_source_label
    error = assert_raises(GpxKit::InvalidFileError) { Documents.read(Documents.gpx("<a></b>"), source_label: "upload 7") }

    assert_equal "upload 7", error.source
  end

  def test_rejects_other_sources
    assert_raises(ArgumentError) { GpxKit::Reader.new(42) }
    assert_raises(ArgumentError) { GpxKit::Reader.new(StringIO.new(""), limits: :none) }
  end
end
