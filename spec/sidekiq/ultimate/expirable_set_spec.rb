# frozen_string_literal: true

require "sidekiq/ultimate/expirable_set"

RSpec.describe Sidekiq::Ultimate::ExpirableSet do
  subject(:list) { described_class.new }

  it { is_expected.to be_an Enumerable }
  it { is_expected.to respond_to :to_ary }

  describe "#each" do
    before do
      5.times do |i|
        expect(Concurrent).
          to receive(:monotonic_time).
          and_return(i.to_f)

        list.add(i + 1, :ttl => 3)
      end
    end

    context "without block given" do
      subject(:enum) { list.each }

      it { is_expected.to be_an Enumerator }

      it "enumerates over non-expired keys only" do
        expect(Concurrent).
          to receive(:monotonic_time).
          and_return(5.0)

        expect { |b| enum.each(&b) }.
          to yield_successive_args(3, 4, 5)
      end
    end

    it "enumerates over non-expired keys only" do
      expect(Concurrent).
        to receive(:monotonic_time).
        and_return(5.0)

      expect { |b| list.each(&b) }.
        to yield_successive_args(3, 4, 5)
    end
  end

  describe "#add" do
    it "allows to use different TTLs" do
      list.add(:a, :ttl => 50)
      list.add(:b, :ttl => 10)
      list.add(:c, :ttl => 30)

      expect(Concurrent).
        to receive(:monotonic_time).
        and_wrap_original(&->(m, *) { m.call + 25 })

      expect(list.to_a).to match_array(%i[a c])
    end

    it "does not overrides previo expiry if it's longer than new one" do
      list.add(:foo, :ttl => 50)
      list.add(:foo, :ttl => 10)

      expect(Concurrent).
        to receive(:monotonic_time).
        and_wrap_original(&->(m, *) { m.call + 25 })

      expect(list.to_a).to eq([:foo])
    end
  end
end
