# frozen_string_literal: true

module GpxKit
  # Convenience view of a GPX file, in the shape of FitKit::Activity.
  #
  #   activity = GpxKit::Activity.read("ride.gpx", limits: { max_seconds: 30 })
  #   activity.sessions.each { |session| puts session.name }
  #   activity.records.each { |record| puts record.timestamp }
  #
  # A session is one <trk>; its segments hold its points. GPX has no laps
  # and states no totals, so laps is always empty and totals are nil.
  # Values are reported as the file states them: nothing is computed from
  # positions or timestamps. The view does not assume an activity: a file
  # with only routes or waypoints has no sessions or records.
  #
  # When two sources could fill a record value (hr from TrackPointExtension
  # and from GPXDATA), the first valid one in the documented order wins
  # (SPECIFICATION.md, decision 2); every source stays on the raw message.
  class Activity
    SUMMARY = %i[
      sport sub_sport total_distance total_elapsed_time total_timer_time total_calories
      avg_speed max_speed avg_heart_rate max_heart_rate avg_cadence max_cadence
      avg_power max_power total_ascent total_descent num_laps
    ].freeze

    NO_LAPS = [].freeze

    attr_reader :messages, :sessions, :records, :waypoints, :routes, :document

    # options are passed to Reader.new, e.g. limits: { max_seconds: 30 }.
    def self.read(source, **options)
      new(Reader.new(source, **options).each_message.to_a)
    end

    def self.from_file(path, **options)
      read(path, **options)
    end

    def self.from_io(io, **options)
      read(io, **options)
    end

    def initialize(messages)
      @messages = messages.freeze
      points_by_segment = Hash.new { |hash, key| hash[key] = [] }
      segments_by_track = Hash.new { |hash, key| hash[key] = [] }
      points_by_route = Hash.new { |hash, key| hash[key] = [] }
      @sessions = []
      @records = []
      @waypoints = []
      @routes = []
      @metadata = nil
      @document = nil

      @messages.each do |message|
        context = message.context
        case message.name
        when :track_point
          record = Record.new(message)
          @records << record
          points_by_segment[context.values_at(:track, :track_segment)] << record
        when :track_segment
          segment = Segment.new(message, points_by_segment.delete(context.values_at(:track, :track_segment)) || [])
          segments_by_track[context[:track]] << segment
        when :track
          @sessions << Session.new(message, segments_by_track.delete(context[:track]) || [])
        when :route_point then points_by_route[context[:route]] << Record.new(message)
        when :route then @routes << Route.new(message, points_by_route.delete(context[:route]) || [])
        when :waypoint then @waypoints << Record.new(message)
        when :metadata then @metadata ||= message
        when :document then @document = message
        end
      end

      [@sessions, @records, @waypoints, @routes].each(&:freeze)
      freeze
    end

    def laps
      NO_LAPS
    end

    # The first session, or nil.
    def session
      @sessions.first
    end

    # The <metadata> message (GPX 1.1), or in GPX 1.0, which has none, the
    # :document message that holds the same fields.
    def metadata
      @metadata || (version == "1.0" ? @document : nil)
    end

    # gpx@creator.
    def creator
      @document&.[](:creator)
    end

    # The document's GPX version, "1.1" or "1.0" (the namespace decides).
    def version
      return unless @document

      NAMESPACES[@document.namespace] || @document[:version]
    end

    def start_time
      session&.start_time
    end

    def end_time
      @sessions.last&.end_time
    end

    SUMMARY.each do |name|
      define_method(name) { session&.public_send(name) }
    end

    # Base for the wrappers.
    class Wrapper
      attr_reader :raw_message

      def initialize(message)
        @raw_message = message
      end

      def [](key)
        @raw_message[key]
      end

      private

      # The value of the first valid field among sources, in order. A source
      # is [namespace, element name], where :gpx means the document's GPX
      # namespace (1.1, 1.0 or none). Only fields the schema puts there count.
      def first_valid(sources)
        sources.each do |namespace, name|
          @raw_message.fields.each do |field|
            next unless field.known? && field.valid? && leaf?(field.path, name)
            next unless namespace == :gpx ? gpx_namespace?(field.namespace) : field.namespace == namespace

            return field.value
          end
        end
        nil
      end

      def gpx(name)
        first_valid([[:gpx, name]])
      end

      def leaf?(path, name)
        path == name || path.end_with?("/#{name}")
      end

      def gpx_namespace?(namespace)
        namespace.nil? || NAMESPACES.key?(namespace)
      end
    end

    # One <trk>.
    class Session < Wrapper
      attr_reader :segments

      def initialize(message, segments)
        super(message)
        @segments = segments.freeze
        freeze
      end

      def name = gpx("name")
      def description = gpx("desc")
      def number = gpx("number")

      # The track's <type>, as written ("running", "9", ...). GPX 1.0 has no
      # type; one written there anyway is read as text.
      def sport
        field = @raw_message.fields.find { |candidate| candidate.path == "type" && gpx_namespace?(candidate.namespace) }
        field&.raw_value
      end

      def records
        @segments.flat_map(&:records)
      end

      # The first point with a valid time.
      def start_time
        @segments.each { |segment| segment.records.each { |record| return record.timestamp if record.timestamp } }
        nil
      end

      # The last point with a valid time.
      def end_time
        @segments.reverse_each { |segment| segment.records.reverse_each { |record| return record.timestamp if record.timestamp } }
        nil
      end

      def laps = NO_LAPS
      def num_laps = nil

      # Not stated by GPX.
      %i[sub_sport total_distance total_elapsed_time total_timer_time total_calories avg_speed max_speed
         avg_heart_rate max_heart_rate avg_cadence max_cadence avg_power max_power total_ascent total_descent].each do |name|
        define_method(name) { nil }
      end
    end

    # One <trkseg>.
    class Segment < Wrapper
      attr_reader :records

      def initialize(message, records)
        super(message)
        @records = records.freeze
        freeze
      end
    end

    # One <rte> with its points.
    class Route < Wrapper
      attr_reader :points

      def initialize(message, points)
        super(message)
        @points = points.freeze
        freeze
      end

      def name = gpx("name")
    end

    # One point: a track point, route point or waypoint.
    class Record < Wrapper
      TPX1 = Schema::TRACK_POINT_EXTENSION_V1
      TPX2 = Schema::TRACK_POINT_EXTENSION_V2
      POWER = Schema::POWER_EXTENSION_V1
      GPXDATA = Schema::GPXDATA

      # Where each value comes from, in order (decision 2).
      SOURCES = {
        heart_rate: [[TPX2, "hr"], [TPX1, "hr"], [GPXDATA, "hr"]],
        cadence: [[TPX2, "cad"], [TPX1, "cad"], [GPXDATA, "cadence"]],
        power: [[POWER, "PowerInWatts"], [:gpx, "power"]],
        temperature: [[TPX2, "atemp"], [TPX1, "atemp"], [GPXDATA, "temp"]],
        speed: [[:gpx, "speed"], [TPX2, "speed"]],
        course: [[:gpx, "course"], [TPX2, "course"]],
        distance: [[GPXDATA, "distance"]]
      }.freeze

      def initialize(message)
        super
        freeze
      end

      def timestamp = gpx("time")
      def latitude = gpx("@lat")
      def longitude = gpx("@lon")
      def altitude = gpx("ele")
      def name = gpx("name")

      SOURCES.each_key do |value|
        define_method(value) { first_valid(SOURCES[value]) }
      end

      # Not in GPX.
      def grade = nil
    end
  end
end
