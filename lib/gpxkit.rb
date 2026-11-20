# frozen_string_literal: true

require_relative "gpxkit/version"
require_relative "gpxkit/error"

# A read-only, streaming parser for GPX 1.1 and 1.0 files.
# See SPECIFICATION.md for the planned API; the reader arrives in milestone M1.
module GpxKit
  NAMESPACE_1_1 = "http://www.topografix.com/GPX/1/1"
  NAMESPACE_1_0 = "http://www.topografix.com/GPX/1/0"
end
