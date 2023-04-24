# frozen_string_literal: true

require "sidekiq/ultimate/configuration"

RSpec.describe Sidekiq::Ultimate::Configuration do
  describe "empty_queues_cache_refresh_interval_sec" do
    let(:instance) { Class.new(described_class).instance }

    it "defaults to 30 seconds" do
      expect(instance.empty_queues_cache_refresh_interval_sec).to eq(30)
    end

    it "raises an error if set to a non boolean value" do
      p = -> { 30 }
      expect { instance.empty_queues_cache_refresh_interval_sec = p }.
        to raise_error(ArgumentError, "Invalid 'empty_queues_cache_refresh_interval_sec' value: #{p}. Must be Numeric")
    end

    it "can be overridden" do
      instance.empty_queues_cache_refresh_interval_sec = 60
      expect(instance.empty_queues_cache_refresh_interval_sec).to eq(60)
    end
  end

  describe "throttled_fetch_timeout_sec" do
    let(:instance) { Class.new(described_class).instance }

    it "defaults to 15 seconds" do
      expect(instance.throttled_fetch_timeout_sec).to eq(15)
    end

    it "accepts a proc" do
      p = -> { 30 }
      instance.throttled_fetch_timeout_sec = p
      expect(instance.throttled_fetch_timeout_sec).to eq(30)
    end

    it "can be overridden" do
      instance.throttled_fetch_timeout_sec = 60
      expect(instance.throttled_fetch_timeout_sec).to eq(60)
    end
  end
end
