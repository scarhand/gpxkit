# frozen_string_literal: true

module GpxKit
  # Field types per message and GPX version, written from TopoGrafix's GPX
  # 1.1 and 1.0 schemas and the extension schemas named below (type names in
  # comments). Extension schemas are not part of this repository.
  #
  # Keys are paths relative to the message element. A segment in the
  # document's GPX namespace is its local name; one in a known extension
  # namespace is the prefix below plus its local name ("tpx2:hr"); an
  # attribute is "@" plus its name. A path with a segment in any other
  # namespace never matches.
  module Schema
    T = Types

    TRACK_POINT_EXTENSION_V1 = "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
    TRACK_POINT_EXTENSION_V2 = "http://www.garmin.com/xmlschemas/TrackPointExtension/v2"
    POWER_EXTENSION_V1 = "http://www.garmin.com/xmlschemas/PowerExtension/v1"
    GPXDATA = "http://www.cluetrust.com/XML/GPXDATA/1/0"

    PREFIXES = {
      TRACK_POINT_EXTENSION_V1 => "tpx1",
      TRACK_POINT_EXTENSION_V2 => "tpx2",
      POWER_EXTENSION_V1 => "pwr",
      GPXDATA => "gpxdata"
    }.freeze

    NON_NEGATIVE_INTEGER = T.integer(:non_negative_integer, min: 0, max: nil)
    DGPS_STATION = T.integer(:dgps_station, min: 0, max: 1023, signed: true) # dgpsStationType
    FIX = T.enumeration(:fix, %w[none 2d 3d dgps pps], preserve: true) # fixType, based on xsd:string
    ANY_URI = T.token(:any_uri)

    # latitudeType, longitudeType and degreesType differ between versions:
    # 1.0 allows 180 and 360 themselves.
    LATITUDE = T.decimal(:latitude, min: -90.0, max: 90.0)
    LONGITUDE = {
      "1.1" => T.decimal(:longitude, min: -180.0, max_exclusive: 180.0),
      "1.0" => T.decimal(:longitude, min: -180.0, max: 180.0)
    }.freeze
    DEGREES = {
      "1.1" => T.decimal(:degrees, min: 0.0, max_exclusive: 360.0),
      "1.0" => T.decimal(:degrees, min: 0.0, max: 360.0)
    }.freeze

    def self.within(prefix, table)
      table.transform_keys { |key| "#{prefix}/#{key}" }
    end

    def self.link(prefix = "link")
      { "#{prefix}/@href" => ANY_URI, "#{prefix}/text" => T.string, "#{prefix}/type" => T.string }
    end

    def self.bounds(version)
      { "bounds/@minlat" => LATITUDE, "bounds/@minlon" => LONGITUDE[version],
        "bounds/@maxlat" => LATITUDE, "bounds/@maxlon" => LONGITUDE[version] }
    end

    # TrackPointExtension_t v1 (Garmin TrackPointExtensionv1.xsd).
    TRACK_POINT_EXTENSION_FIELDS_V1 = {
      "atemp" => T.double(:degrees_celsius),
      "wtemp" => T.double(:degrees_celsius),
      "depth" => T.double(:meters),
      "hr" => T.integer(:beats_per_minute, min: 1, max: 255),
      "cad" => T.integer(:revolutions_per_minute, min: 0, max: 254)
    }.freeze

    # TrackPointExtension_t v2 adds speed, course and bearing.
    TRACK_POINT_EXTENSION_FIELDS_V2 = TRACK_POINT_EXTENSION_FIELDS_V1.merge(
      "speed" => T.double(:meters_per_second),
      "course" => T.decimal(:degrees_true, min: 0.0, max: 360.0),
      "bearing" => T.decimal(:degrees_true, min: 0.0, max: 360.0)
    ).freeze

    # Extension elements of a point, as they appear inside it. In GPX 1.1 they
    # sit in <extensions>; GPX 1.0 has no <extensions> and allows them directly.
    POINT_EXTENSIONS = {
      **TRACK_POINT_EXTENSION_FIELDS_V1.to_h { |name, spec| ["tpx1:TrackPointExtension/tpx1:#{name}", spec] },
      **TRACK_POINT_EXTENSION_FIELDS_V2.to_h { |name, spec| ["tpx2:TrackPointExtension/tpx2:#{name}", spec] },
      "pwr:PowerInWatts" => T.integer(:unsigned_short, min: 0, max: 65_535), # PowerExtensionv1.xsd
      "gpxdata:hr" => NON_NEGATIVE_INTEGER, # gpxdata10.xsd
      "gpxdata:cadence" => NON_NEGATIVE_INTEGER,
      "gpxdata:temp" => T.decimal,
      "gpxdata:distance" => T.decimal,
      "gpxdata:distance/@sensor" => T.enumeration(:sensor_kind, %w[wheel pedometer])
    }.freeze

    # A bare <power> in <extensions>, as several exporters write it. No schema
    # defines it; it is read as a decimal number of watts.
    BARE_POWER = { "extensions/power" => T.decimal(:power) }.freeze

    def self.point_extensions(version)
      version == "1.1" ? within("extensions", POINT_EXTENSIONS).merge(BARE_POWER) : POINT_EXTENSIONS
    end

    # wptType (1.1); the waypoint, route point and track point elements (1.0).
    def self.point(version, track_point:)
      table = {
        "@lat" => LATITUDE,
        "@lon" => LONGITUDE[version],
        "ele" => T.decimal,
        "time" => T.date_time,
        "magvar" => DEGREES[version],
        "geoidheight" => T.decimal,
        "name" => T.string, "cmt" => T.string, "desc" => T.string, "src" => T.string,
        "sym" => T.string, "type" => T.string,
        "fix" => FIX,
        "sat" => NON_NEGATIVE_INTEGER,
        "hdop" => T.decimal, "vdop" => T.decimal, "pdop" => T.decimal, "ageofdgpsdata" => T.decimal,
        "dgpsid" => DGPS_STATION
      }
      if version == "1.1"
        table.merge!(link)
      else
        table.merge!("url" => ANY_URI, "urlname" => T.string)
        table.merge!("course" => DEGREES[version], "speed" => T.decimal) if track_point
      end
      table.merge(point_extensions(version)).freeze
    end

    # rteType and trkType (1.1); rte and trk (1.0, which has no type).
    def self.route_or_track(version)
      table = { "name" => T.string, "cmt" => T.string, "desc" => T.string, "src" => T.string, "number" => NON_NEGATIVE_INTEGER }
      version == "1.1" ? table.merge(link, "type" => T.string).freeze : table.merge("url" => ANY_URI, "urlname" => T.string).freeze
    end

    # metadataType, personType, copyrightType, boundsType (1.1).
    METADATA = {
      "name" => T.string, "desc" => T.string,
      "author/name" => T.string, "author/email/@id" => T.string, "author/email/@domain" => T.string,
      **link("author/link"),
      "copyright/@author" => T.string, "copyright/year" => T.g_year, "copyright/license" => ANY_URI,
      **link,
      "time" => T.date_time,
      "keywords" => T.string,
      **bounds("1.1")
    }.freeze

    # The gpx element: version and creator; in 1.0 also its own metadata.
    def self.document(version)
      table = { "@version" => T.string, "@creator" => T.string }
      return table.freeze if version == "1.1"

      table.merge(
        "name" => T.string, "desc" => T.string, "author" => T.string, "email" => T.string,
        "url" => ANY_URI, "urlname" => T.string, "time" => T.date_time, "keywords" => T.string, **bounds("1.0")
      ).freeze
    end

    EMPTY = {}.freeze

    TABLES = %w[1.1 1.0].to_h do |version|
      waypoint = point(version, track_point: false)
      [version, {
        document: document(version),
        metadata: version == "1.1" ? METADATA : EMPTY,
        waypoint: waypoint,
        route: route_or_track(version),
        route_point: waypoint,
        track: route_or_track(version),
        track_segment: EMPTY,
        track_point: point(version, track_point: true)
      }.freeze]
    end.freeze

    def self.table(version, kind)
      TABLES.fetch(version).fetch(kind, EMPTY)
    end
  end
end
