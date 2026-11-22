# frozen_string_literal: true

require_relative "../test_helper"

class RestrictedFieldsTest < Minitest::Test
  def copyright_year(text)
    xml = Documents.gpx(%(<metadata><copyright author="A"><year>#{text}</year></copyright></metadata>))
    Documents.message(xml, :metadata).field(:copyright_year)
  end

  def test_copyright_year_is_an_xsd_g_year
    assert_equal 2026, copyright_year("2026").value
    assert_equal 2026, copyright_year(" 2026Z ").value
    assert_equal "2026+01:00", copyright_year("2026+01:00").raw_value
    assert_equal 12_026, copyright_year("12026").value
    assert_equal :g_year, copyright_year("2026").type
  end

  def test_copyright_years_that_are_not_g_years
    ["26", "2026-01", "MMXXVI", "2026+15:00"].each do |text|
      field = copyright_year(text)
      assert_nil field.value, text
      assert_equal :not_a_year, field.invalid_reason, text
    end
  end

  # XSD 1.1 allows "+" on nonNegativeInteger (as XSD 1.0 already did), and
  # "-" before zero.
  def test_non_negative_integers_accept_signs
    point = ->(sat) { Documents.message(Documents.track_point("<sat>#{sat}</sat>"), :track_point).field(:sat) }

    assert_equal [7, 0], [point.call("+7").value, point.call("-0").value]
    assert_equal :not_an_integer, point.call("-7").invalid_reason
  end
end
