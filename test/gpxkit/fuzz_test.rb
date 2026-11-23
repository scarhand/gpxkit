# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/fuzzer"

# Whatever the input, reading either succeeds or raises a GpxKit::Error:
# never another exception. FUZZ_ITERATIONS and FUZZ_SEED run longer or
# different rounds; a failure names the seed and iteration to reproduce it.
class FuzzTest < Minitest::Test
  ITERATIONS = Integer(ENV.fetch("FUZZ_ITERATIONS", "300"))
  SEED = Integer(ENV.fetch("FUZZ_SEED", "20261123"))

  DOCUMENTS = [
    File.read(Documents.fixture("ride-1.1.gpx"), encoding: "UTF-8"),
    File.read(Documents.fixture("walk-1.0.gpx"), encoding: "UTF-8")
  ].freeze

  def test_mutated_documents_only_raise_gpxkit_errors
    fuzzer = Fuzzer.new(SEED)
    outcomes = Hash.new(0)
    limits = { max_bytes: 1_000_000, max_elements: 20_000, max_depth: 64, max_text_bytes: 100_000, max_seconds: 5 }

    ITERATIONS.times do |iteration|
      document = fuzzer.mutate(DOCUMENTS[iteration % DOCUMENTS.size])
      begin
        exercise(GpxKit::Activity.from_io(StringIO.new(document), limits: limits))
        outcomes[:read] += 1
      rescue GpxKit::Error => error
        outcomes[error.class] += 1
      rescue StandardError, SystemStackError => error
        flunk "FUZZ_SEED=#{SEED} iteration #{iteration}: #{error.class}: #{error.message}\n#{document.inspect[0, 2000]}"
      end
    end

    # Both outcomes occur, so the mutations neither always break nor never break the document.
    assert_operator outcomes[:read], :>, 0
    assert_operator outcomes.sum { |outcome, count| outcome == :read ? 0 : count }, :>, 0
    warn "fuzz outcomes: #{outcomes.transform_keys { |key| key.to_s.delete_prefix('GpxKit::') }}" if ENV["FUZZ_VERBOSE"]
  end

  def test_mutated_values_only_raise_gpxkit_errors
    fuzzer = Fuzzer.new(SEED)
    read = 0

    ITERATIONS.times do |iteration|
      document = fuzzer.mutate_values(DOCUMENTS[iteration % DOCUMENTS.size])
      begin
        exercise(GpxKit::Activity.from_io(StringIO.new(document)))
        read += 1
      rescue GpxKit::Error
        nil
      rescue StandardError, SystemStackError => error
        flunk "FUZZ_SEED=#{SEED} iteration #{iteration}: #{error.class}: #{error.message}\n#{document[0, 3000]}"
      end
    end

    # Values are fuzzed, not the markup, so nearly every document still reads.
    assert_operator read, :>, ITERATIONS / 2
  end

  private

  # Touches every value, so the wrappers run too.
  def exercise(activity)
    activity.messages.each { |message| message.fields.each { |field| [field.value, field.valid?, field.raw_value] } }
    (activity.records + activity.waypoints + activity.routes.flat_map(&:points)).each do |record|
      GpxKit::Activity::Record::SOURCES.each_key { |name| record.public_send(name) }
      [record.timestamp, record.latitude, record.longitude, record.altitude]
    end
    activity.sessions.each { |session| [session.sport, session.name, session.start_time, session.end_time] }
    GpxKit::Activity::SUMMARY.each { |name| activity.public_send(name) }
    [activity.version, activity.creator, activity.metadata, activity.start_time, activity.end_time]
  end
end
