# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class SecurityTest < Minitest::Test
  def test_refuses_a_dtd_internal_subset
    xml = %(<?xml version="1.0"?>\n<!DOCTYPE gpx [<!ENTITY e "x">]>\n) +
          Documents.gpx("<desc>&e;</desc>", declaration: false)

    assert_raises(GpxKit::UnsafeContentError) { Documents.read(xml) }
  end

  def test_refuses_entity_expansion
    entities = (1..9).map { |n| %(<!ENTITY e#{n} "#{"&e#{n - 1};" * 10}">) }.join
    xml = %(<!DOCTYPE t [<!ENTITY e0 "lol">#{entities}]>) + Documents.gpx("<desc>&e9;</desc>", declaration: false)

    assert_raises(GpxKit::UnsafeContentError) { Documents.read(xml) }
  end

  def test_never_reads_external_entities_or_dtds
    Dir.mktmpdir do |dir|
      secret = File.join(dir, "secret.txt")
      File.write(secret, "SECRET")
      dtd = File.join(dir, "evil.dtd")
      File.write(dtd, %(<!ENTITY e SYSTEM "file://#{secret}">))
      xml = %(<!DOCTYPE gpx SYSTEM "file://#{dtd}">) +
            Documents.gpx("<desc>&e;</desc>", declaration: false)
      texts = []

      assert_raises(GpxKit::Error) do
        GpxKit::XML::Parser.new(StringIO.new(xml), limits: GpxKit::Limits::DEFAULT, source_label: "t")
                           .each_event { |type, element| texts << element.text if type == :end }
      end
      refute texts.any? { |text| text.to_s.include?("SECRET") }
    end
  end

  def test_an_undeclared_entity_is_invalid
    assert_raises(GpxKit::Error) { Documents.read(Documents.gpx("<desc>&nbsp;</desc>")) }
  end

  def test_errors_do_not_contain_document_text
    error = assert_raises(GpxKit::Error) { Documents.read(Documents.gpx("<desc>private note & more</desc>")) }

    refute_includes error.message, "private note"
  end
end
