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

    # What a node in the element stack is: a message element (with its Frame)
    # or a field element (with its Shape).
    Node = Struct.new(:kind, :element, :frame, :shape)

    # Where an element or attribute sits inside a message: its path, schema
    # key (nil once a segment is outside the known namespaces), field name
    # (the joined names so far, as a String, and as the Symbol fields use)
    # and type. Every point has the same few shapes, so they are made once
    # per message type and reused; a builder makes at most SHAPE_LIMIT,
    # because unknown names come from the file.
    class Shape
      attr_reader :path, :key, :joined_name, :name, :spec

      def initialize(path:, key:, joined_name:, spec:)
        @path = path
        @key = key
        @joined_name = joined_name
        @name = joined_name.to_sym
        @spec = spec
        @children = {}
        @attributes = {}
      end

      def child(namespace, name) = @children[namespace]&.[](name)
      def attribute(namespace, name) = @attributes[namespace]&.[](name)
      def add_child(namespace, name, shape) = (@children[namespace] ||= {})[name] = shape
      def add_attribute(namespace, name, shape) = (@attributes[namespace] ||= {})[name] = shape
    end

    SHAPE_LIMIT = 10_000

    # A message being collected.
    class Frame
      attr_reader :kind, :element, :context, :fields, :table, :shape

      def initialize(kind, element, context, table, shape)
        @kind = kind
        @element = element
        @context = context.freeze
        @table = table
        @shape = shape
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
      @roots = {}.compare_by_identity
      @shapes = 0
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
        frame = parent.frame
        node = Node.new(:field, element, frame, child_shape(parent.shape, element, frame.table))
        add_attributes(node)
        @nodes << node
      end
    end

    # The Reader has checked the root: the namespace decides the version, and
    # a root without one is read by its version attribute.
    def start_document(element)
      @namespace = element.namespace
      @version = NAMESPACES[@namespace] || element.attribute("version")&.value
      frame = new_frame(:document, element, {}, Schema.table(@version, :document))
      node = Node.new(:message, element, frame, frame.shape)
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
      frame = new_frame(kind, element, context, Schema.table(@version, kind))
      node = Node.new(:message, element, frame, frame.shape)
      add_attributes(node)
      node
    end

    def new_frame(kind, element, context, table)
      root = @roots[table] ||= Shape.new(path: "", key: "", joined_name: "", spec: nil)
      Frame.new(kind, element, context, table, root)
    end

    def next_document_index(kind)
      index = @counters[kind]
      @counters[kind] += 1
      index
    end

    def child_shape(parent, element, table)
      cached = parent.child(element.namespace, element.name)
      return cached if cached

      key = join_key(parent.key, segment(element))
      shape = Shape.new(path: join(parent.path, element.name, "/"), key: key,
                        joined_name: field_name(parent.joined_name, element.name),
                        spec: (key && table[key]) || Types::UNKNOWN)
      parent.add_child(element.namespace, element.name, shape) if remember?
      shape
    end

    def attribute_shape(parent, attribute, table)
      cached = parent.attribute(attribute.namespace, attribute.name)
      return cached if cached

      key = join_key(parent.key, attribute.namespace.nil? ? "@#{attribute.name}" : nil)
      shape = Shape.new(path: join(parent.path, "@#{attribute.name}", "/"), key: key,
                        joined_name: field_name(parent.joined_name, attribute.name),
                        spec: (key && table[key]) || Types::UNKNOWN)
      parent.add_attribute(attribute.namespace, attribute.name, shape) if remember?
      shape
    end

    def remember?
      (@shapes += 1) <= SHAPE_LIMIT
    end

    def add_attributes(node)
      node.element.attributes.each do |attribute|
        shape = attribute_shape(node.shape, attribute, node.frame.table)
        node.frame.fields << Field.new(name: shape.name, path: shape.path, namespace: attribute.namespace,
                                       text: attribute.value, spec: shape.spec, line: node.element.line)
      end
    end

    # An empty wrapper is not a field, and neither is the missing text of an
    # element that only carries attributes (such as <bounds .../>).
    def add_text(node, element)
      return if WRAPPERS.include?(element.name) && element.text.strip.empty?
      return if element.text.empty? && !element.attributes.empty?

      shape = node.shape
      node.frame.fields << Field.new(name: shape.name, path: shape.path, namespace: element.namespace,
                                     text: element.text, spec: shape.spec, line: element.line)
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

    def join(left, right, separator)
      left.empty? ? right.dup.freeze : "#{left}#{separator}#{right}".freeze
    end

    # The schema key of an element, or nil for a namespace the schema does
    # not cover.
    def segment(element)
      return element.name if element.namespace == @namespace

      prefix = Schema::PREFIXES[element.namespace]
      prefix && "#{prefix}:#{element.name}"
    end
  end
end
