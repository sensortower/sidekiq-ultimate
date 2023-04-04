# frozen_string_literal: true

require "sidekiq/ultimate/resurrector"

RSpec.describe Sidekiq::Ultimate::Resurrector::Lock do
  describe ".acquire", :redis => true do
    context "when there is no other lock" do
      it "yields" do
        expect { |b| described_class.acquire(&b) }.to yield_control
      end

      it "saves last run time to redis" do
        described_class.acquire {} # rubocop:disable Lint/EmptyBlock

        last_run = Sidekiq.redis { |redis| redis.get("ultimate:resurrector:last_run") }.to_i
        expect(last_run).to be_within(10).of(Time.now.to_i)
      end
    end

    context "when it was already executed in the last 60 seconds" do
      it "does not yield" do
        Sidekiq.redis { |redis| redis.set("ultimate:resurrector:last_run", Time.now.to_i) }

        expect { |b| described_class.acquire(&b) }.not_to yield_control
      end
    end

    context "when it was executed more than 60 seconds" do
      before do
        Sidekiq.redis { |redis| redis.set("ultimate:resurrector:last_run", Time.now.to_i - 62) }
      end

      it "yields" do
        expect { |b| described_class.acquire(&b) }.to yield_control
      end

      it "saves last run time to redis" do
        described_class.acquire {} # rubocop:disable Lint/EmptyBlock

        last_run = Sidekiq.redis { |redis| redis.get("ultimate:resurrector:last_run") }.to_i
        expect(last_run).to be_within(10).of(Time.now.to_i)
      end
    end
  end
end
