# frozen_string_literal: true

module GpxKit
  # Turns the XML layer's element events into Messages (SPECIFICATION.md
  # 6.2). A message is emitted when its element closes; every leaf element
  # and attribute inside it, outside nested messages, becomes one of its
  # Fields. The gpx element itself is the :document message, emitted last.
  # One builder per pass.
  class MessageBuilder
    # Elements left out of field names: "extensions/TrackPointExtension/hr" is hr.
    WRAPPERS = %w[extensions Extensions TrackPointExtension].freeze

    # Child elements that start messages, by the parent message's kind.
    MESSAGES = {
      document: { "metadata" => :metadata, "wpt" => :waypoint, "rte" => :route, "trk" => :track },
      route: { "rtept" => :route_point },
      track: { "trkseg" => :track_segment },
      track_segment: { "trkpt" => :track_point }
    }.freeze

    # Indexes counted across the document; the others count within their parent.
    DOCUMENT_COUNTERS = %i[metadata waypoint route track].freeze

    CACHE_SIZE = 4096

    # path: the element's path inside its message ("" for the message
    # element), key: the same path in Schema terms, nil once a segment is
    # outside the known namespaces, name: the field name so far.
    Node = Struct.new(:kind, :element, :frame, :path, :key, :name)

    # A message being collected.
    class Frame
      attr_reader :kind, :element, :context, :fields, :table

      def initialize(kind, element, context, table)
        @kind = kind
        @element = element
        @context = context.freeze
        @table = table
        @fields = []
        @counters = Hash.new(0)
      end

      def next_index(kind)
        index = @counters[kind]
        @counters[kind] += 1
        index
      end

      def to_message
        Message.new(name: kind, element_name: element.name, namespace: element.namespace, context: context,
                    line: element.line, column: element.column, fields: fields)
      end
    end

    attr_reader :version

    def initialize(&emit)
      @emit = emit
      @nodes = []
      @counters = Hash.new(0)
      @joins = {}
    end

    def handle(type, element)
      type == :start ? start(element) : finish(element)
    end

    private

    def start(element)
      parent = @nodes.last
      return start_document(element) unless parent

      kind = parent.kind == :message && element.namespace == @namespace && MESSAGES.dig(parent.frame.kind, element.name)
      if kind
        @nodes << open_message(kind, element, parent.frame)
      else
        node = Node.new(:field, element, parent.frame, join(parent.path, element.name, "/"),
                        join_key(parent.key, segment(element)), field_name(parent.name, element.name))
        add_attributes(node)
        @nodes << node
      end
    end

    # The Reader has checked the root: the namespace decides the version, and
    # a root without one is read by its version attribute.
    def start_document(element)
      @namespace = element.namespace
      @version = NAMESPACES[@namespace] || element.attribute("version")&.value
      frame = Frame.new(:document, element, {}, Schema.table(@version, :document))
      node = Node.new(:message, element, frame, "", "", "")
      add_attributes(node)
      @nodes << node
    end

    def finish(element)
      node = @nodes.pop
      case node.kind
      when :message then @emit.call(node.frame.to_message)
      when :field then add_text(node, element) unless element.children?
      end
    end

    def open_message(kind, element, parent_frame)
      index = DOCUMENT_COUNTERS.include?(kind) ? next_document_index(kind) : parent_frame.next_index(kind)
      context = parent_frame.context.merge(kind => index)
      frame = Frame.new(kind, element, context, Schema.table(@version, kind))
      node = Node.new(:message, element, frame, "", "", "")
      add_attributes(node)
      node
    end

    def next_document_index(kind)
      index = @counters[kind]
      @counters[kind] += 1
      index
    end

    def add_attributes(node)
      node.element.attributes.each do |attribute|
        add_field(node.frame, path: join(node.path, "@#{attribute.name}", "/"),
                              key: join_key(node.key, attribute.namespace.nil? ? "@#{attribute.name}" : nil),
                              name: field_name(node.name, attribute.name), namespace: attribute.namespace,
                              text: attribute.value, line: node.element.line)
      end
    end

    # An empty wrapper is not a field, and neither is the missing text of an
    # element that only carries attributes (such as <bounds .../>).
    def add_text(node, element)
      return if WRAPPERS.include?(element.name) && element.text.strip.empty?
      return if element.text.empty? && !element.attributes.empty?

      add_field(node.frame, path: node.path, key: node.key, name: node.name.to_sym,
                            namespace: element.namespace, text: element.text, line: element.line)
    end

    def add_field(frame, path:, key:, name:, namespace:, text:, line:)
      spec = key && frame.table[key]
      frame.fields << Field.new(name: name.to_sym, path: path, namespace: namespace, text: text,
                                spec: spec || Types::UNKNOWN, line: line)
    end

    # The parent's name joined with this element's snake_case name, wrappers
    # left out: "link/@href" is link_href, "extensions/TrackPointExtension/hr" hr.
    def field_name(parent_name, name)
      return parent_name if WRAPPERS.include?(name)

      join(parent_name, Naming.snake_case(name), "_")
    end

    def join_key(key, segment)
      key && segment && join(key, segment, "/")
    end

    # Joined paths and names repeat on every point, so they are cached; the
    # cache is bounded because unknown names come from the file.
    def join(left, right, separator)
      return right if left.empty?

      by_right = @joins[[left, separator]] ||= {}
      cached = by_right[right]
      return cached if cached

      joined = "#{left}#{separator}#{right}".freeze
      by_right[right] = joined if @joins.size < CACHE_SIZE && by_right.size < CACHE_SIZE
      joined
    end

    # The schema key of an element, or nil for a namespace the schema does
    # not cover.
    def segment(element)
      return element.name if element.namespace == @namespace

      prefix = Schema::PREFIXES[element.namespace]
      prefix && join(prefix, element.name, ":")
    end
  end
end
