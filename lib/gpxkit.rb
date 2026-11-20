# frozen_string_literal: true

require "pathname"

require_relative "gpxkit/version"
require_relative "gpxkit/error"
require_relative "gpxkit/limits"
require_relative "gpxkit/xml/clock"
require_relative "gpxkit/xml/element"
require_relative "gpxkit/xml/source"
require_relative "gpxkit/xml/parser"
require_relative "gpxkit/types"
require_relative "gpxkit/schema"
require_relative "gpxkit/field"
require_relative "gpxkit/message"
require_relative "gpxkit/message_builder"
require_relative "gpxkit/reader"

# A read-only, streaming parser for GPX 1.1 and 1.0 files.
# See SPECIFICATION.md for the API and what each milestone delivers.
module GpxKit
  NAMESPACE_1_1 = "http://www.topografix.com/GPX/1/1"
  NAMESPACE_1_0 = "http://www.topografix.com/GPX/1/0"
  NAMESPACES = { NAMESPACE_1_1 => "1.1", NAMESPACE_1_0 => "1.0" }.freeze
end
