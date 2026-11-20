# frozen_string_literal: true

module GpxKit
  # Streams the messages of a GPX 1.1 or 1.0 document.
  #
  #   GpxKit::Reader.new("ride.gpx").each_message { |message| ... }
  #
  # source is a path, a Pathname or an IO-like object that responds to read.
  # Caller-owned IO is closed only with close_io: true. A seekable IO is read
  # from its position at construction on every pass; a non-seekable one can
  # be read once.
  #
  # limits: a GpxKit::Limits, or a Hash of its keywords. Limits::DEFAULT
  # unless given; Limits.none switches them off.
  #
  # Each message is yielded when its element closes, so a segment's points
  # come before the segment and a track's segments before the track; the
  # last message is :document. See Message and SPECIFICATION.md 6.2.
  class Reader
    attr_reader :source_label, :limits

    def initialize(source, close_io: false, source_label: nil, limits: Limits::DEFAULT)
      @close_io = close_io
      @limits = Limits.coerce(limits)
      @consumed = false
      @closed_by_reader = false

      # Pathname responds to read (it reads the whole file), so paths come first.
      if source.is_a?(String) || source.is_a?(Pathname)
        @path = source.to_s
        @source_label = source_label || @path
      elsif source.respond_to?(:read)
        @io = source
        @source_label = source_label || (source.respond_to?(:path) ? source.path : source.class.name)
        @initial_position = initial_position(source)
        raise ArgumentError, "close_io requires a closeable IO-like source" if @close_io && !source.respond_to?(:close)
      elsif source.respond_to?(:to_path)
        @path = source.to_path
        @source_label = source_label || @path
      else
        raise ArgumentError, "source must be a filesystem path or an IO-like object"
      end
    end

    def each_message(&block)
      return enum_for(__method__) unless block

      io, owned = open_io
      begin
        builder = MessageBuilder.new(&block)
        XML::Parser.new(io, limits: @limits, source_label: @source_label).each_event do |type, element|
          check_root(element) if type == :start && element.depth == 1
          builder.handle(type, element)
        end
      ensure
        @closed_by_reader = true if @close_io && @io.equal?(io)
        io.close if (owned || @close_io) && io.respond_to?(:close) && !(io.respond_to?(:closed?) && io.closed?)
      end
      nil
    end

    private

    # The namespace decides the version. A gpx root without a namespace is
    # read as the version its version attribute names (SPECIFICATION.md,
    # decision 3).
    def check_root(element)
      unsupported(element, "The root element is #{short(element.name)}, not gpx") unless element.name == "gpx"
      return if NAMESPACES.key?(element.namespace)

      unsupported(element, "gpx is not in the GPX 1.1 or 1.0 namespace") unless element.namespace.nil?
      version = element.attribute("version")&.value
      return if NAMESPACES.value?(version)

      unsupported(element, "gpx has no namespace and its version is not 1.1 or 1.0")
    end

    def unsupported(element, message)
      raise UnsupportedFormatError.new(message, source: @source_label, line: element.line, column: element.column)
    end

    def short(name)
      name.length > 64 ? "#{name[0, 64]}..." : name
    end

    def initial_position(io)
      return unless io.respond_to?(:pos) && io.respond_to?(:seek)

      io.pos
    rescue IOError, Errno::ESPIPE
      nil
    end

    def open_io
      return [File.open(@path, "rb"), true] if @path

      if @closed_by_reader || (@io.respond_to?(:closed?) && @io.closed?)
        raise Error.new("The IO source is closed", source: @source_label)
      end

      if @initial_position
        @io.seek(@initial_position)
      elsif @consumed
        raise Error.new("A non-seekable IO source can only be read once", source: @source_label)
      else
        @consumed = true
      end
      [@io, false]
    end
  end
end
