# frozen_string_literal: true

# Times reading a synthetic 24-hour track: a point every second, with
# position, elevation, time, Garmin TrackPointExtension v2 heart rate,
# cadence and speed, and PowerExtension power. The values are made up.
#
#   bundle exec ruby -Ilib bench/read_24h.rb [path]
#
# The file is written to path (default: tmp/24h.gpx) unless it exists.
# Prints the best of three CPU times for streaming the messages and for
# building the Activity view.
require "fileutils"
require "gpxkit"

path = ARGV[0] || File.expand_path("../tmp/24h.gpx", __dir__)
unless File.exist?(path)
  FileUtils.mkdir_p(File.dirname(path))
  start = Time.utc(2026, 1, 1)
  File.open(path, "w") do |file|
    file << %(<?xml version="1.0" encoding="UTF-8"?>\n<gpx xmlns="#{GpxKit::NAMESPACE_1_1}" version="1.1" creator="bench" ) +
            %(xmlns:gpxtpx="#{GpxKit::Schema::TRACK_POINT_EXTENSION_V2}" xmlns:pwr="#{GpxKit::Schema::POWER_EXTENSION_V1}">) +
            %(<trk><name>Synthetic</name><trkseg>\n)
    86_400.times do |i|
      file << %(<trkpt lat="#{10 + (i * 1e-6)}" lon="#{20 + (i * 1e-6)}"><ele>12.5</ele><time>#{(start + i).strftime('%FT%TZ')}</time>) +
              %(<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr><gpxtpx:cad>85</gpxtpx:cad><gpxtpx:speed>2.5</gpxtpx:speed>) +
              %(</gpxtpx:TrackPointExtension><pwr:PowerInWatts>250</pwr:PowerInWatts></extensions></trkpt>\n)
    end
    file << "</trkseg></trk></gpx>\n"
  end
end

cpu = -> { Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) }
best = lambda do |label, &block|
  times = Array.new(3) do
    GC.start
    started = cpu.call
    block.call
    cpu.call - started
  end
  puts format("%-10s %6.2f s CPU", label, times.min)
end

puts format("%s: %.1f MB, Ruby %s, Nokogiri %s (libxml2 %s)", path, File.size(path) / 1e6, RUBY_VERSION,
            Nokogiri::VERSION, Nokogiri::VERSION_INFO.dig("libxml", "loaded"))
best.call("messages") { GpxKit::Reader.new(path).each_message { |*| nil } }
best.call("activity") { GpxKit::Activity.read(path) }
