# frozen_string_literal: true

require_relative "../test_helper"

class MalformedInputTest < Minitest::Test
  def test_an_empty_file_is_invalid
    ["", "   \n"].each do |xml|
      assert_raises(GpxKit::InvalidFileError) { Documents.read(xml) }
    end
  end

  def test_files_cut_off_anywhere_are_truncated
    xml = Documents.gpx(<<~XML)
      <trk>
        <name>Café – easy</name>
        <trkseg>
          <trkpt lat="52.0" lon="5.0"><ele>1.5</ele><time>2026-01-01T08:00:00Z</time></trkpt>
        </trkseg>
      </trk>
    XML
    closing = xml.index("</gpx>")

    (1...closing).each do |length|
      cut = xml.byteslice(0, length)
      next unless cut.valid_encoding?

      error = assert_raises(GpxKit::Error, "cut at #{length}") { Documents.read(cut) }
      assert_kind_of GpxKit::TruncatedFileError, error, "cut at #{length}: #{error.class} #{error.message}"
    end
  end

  def test_a_single_line_file_cut_anywhere_is_truncated
    xml = Documents.gpx(%(<trk><name>x</name><trkseg><trkpt lat="52.0" lon="5.0"><time>2026-01-01T08:00:00Z</time></trkpt></trkseg></trk>))
                   .delete("\n")

    (1...xml.index("</gpx>")).each do |length|
      error = assert_raises(GpxKit::Error) { Documents.read(xml.byteslice(0, length)) }
      assert_kind_of GpxKit::TruncatedFileError, error, "cut at #{length}: #{error.message}"
    end
  end

  def test_malformed_single_line_files_are_invalid
    [
      Documents.gpx("<a>x & y</a>").delete("\n"),
      Documents.gpx("<a>x</a><b x='1' x='2'/>").delete("\n"),
      Documents.gpx("<a>x<</a>").delete("\n")
    ].each do |xml|
      assert_raises(GpxKit::InvalidFileError, xml) { Documents.read(xml) }
    end
  end

  def test_large_files_cut_off_or_malformed
    notes = (1..5000).map { |n| "<desc>note #{n}</desc>\n" }.join
    xml = Documents.gpx(notes)

    assert_raises(GpxKit::TruncatedFileError) { Documents.read(xml.byteslice(0, (xml.bytesize * 0.6).to_i)) }
    assert_raises(GpxKit::InvalidFileError) { Documents.read(xml.sub("note 2500<", "note 2500 & <")) }
  end

  def test_a_file_cut_inside_the_closing_root_tag_is_truncated
    xml = Documents.gpx

    assert_raises(GpxKit::TruncatedFileError) { Documents.read(xml.byteslice(0, xml.rindex(">"))) }
  end

  def test_malformed_xml_is_invalid_with_its_position
    {
      Documents.gpx("<a><b>x</b></c>") => /mismatch/,
      Documents.gpx("<a>x & y</a>") => /./,
      Documents.gpx("<a></b>") => /mismatch/,
      "#{Documents.gpx}<extra/>" => /Extra content/
    }.each do |xml, message|
      error = assert_raises(GpxKit::InvalidFileError, xml) { Documents.read(xml) }
      assert_match message, error.message
      refute_nil error.line
    end
  end

  def test_binary_input_such_as_a_fit_file_is_invalid
    fit = [14, 0x20, 0x8D, 0x52, 0, 0, 0, 0].pack("C4VC0") + ".FIT".b + "\x00\x00\x01\x02\xFF".b

    assert_raises(GpxKit::InvalidFileError) { Documents.read(fit) }
  end

  def test_a_byte_limit_hit_is_not_reported_as_truncation
    error = assert_raises(GpxKit::LimitExceededError) do
      Documents.read(Documents.gpx("<desc>#{'x' * 10_000}</desc>"), limits: { max_bytes: 1000 })
    end

    assert_equal :max_bytes, error.limit
  end
end
