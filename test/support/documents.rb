# frozen_string_literal: true

require "stringio"

# Builders for synthetic test documents. Values are made up.
module Documents
  module_function

  def gpx(body = "<metadata/>", declaration: true, namespace: GpxKit::NAMESPACE_1_1, version: "1.1")
    xml = +""
    xml << %(<?xml version="1.0" encoding="UTF-8"?>\n) if declaration
    xmlns = namespace ? %( xmlns="#{namespace}") : ""
    xml << %(<gpx#{xmlns} version="#{version}" creator="test">\n#{body}\n</gpx>\n)
    xml
  end

  # Events from the XML layer, as [type, name, depth, text] rows.
  def events(xml, limits: GpxKit::Limits::DEFAULT)
    rows = []
    parser = GpxKit::XML::Parser.new(StringIO.new(xml), limits: GpxKit::Limits.coerce(limits), source_label: "test")
    parser.each_event { |type, element| rows << [type, element.name, element.depth, type == :end ? element.text : nil] }
    rows
  end

  def read(xml, **options)
    GpxKit::Reader.new(StringIO.new(xml), **options).each_message { |_message| nil }
  end

  def messages(xml, **options)
    GpxKit::Reader.new(StringIO.new(xml), **options).each_message.to_a
  end

  # The first message with that name.
  def message(xml, name)
    messages(xml).find { |message| message.name == name }
  end

  def fixture(name)
    File.expand_path("../fixtures/#{name}", __dir__)
  end

  # A document with one track point holding the given children.
  def track_point(children, attributes: %(lat="1.5" lon="2.5"), **options)
    gpx(%(<trk><trkseg><trkpt #{attributes}>#{children}</trkpt></trkseg></trk>), **options)
  end
end
