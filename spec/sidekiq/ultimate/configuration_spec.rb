# frozen_string_literal: true

require "sidekiq/ultimate/configuration"

RSpec.describe Sidekiq::Ultimate::Configuration do
  describe "empty_queues_refresh_interval" do
    let(:instance) { Class.new(described_class).instance }

    it "defaults to 60 seconds" do
      expect(instance.empty_queues_refresh_interval).to eq(30)
    end

    it "raises an error if set to a non boolean value" do
      p = -> { 30 }
      expect { instance.empty_queues_refresh_interval = p }.
        to raise_error(ArgumentError, "Invalid 'empty_queues_refresh_interval' value: #{p}. Must be Numeric")
    end

    it "can be overridden" do
      instance.empty_queues_refresh_interval = 60
      expect(instance.empty_queues_refresh_interval).to eq(60)
    end
  end
end
