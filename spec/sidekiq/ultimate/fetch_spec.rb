# frozen_string_literal: true

require "sidekiq/component"
require "sidekiq/ultimate/fetch"

RSpec.describe Sidekiq::Ultimate::Fetch do
  describe ".retrieve_work" do
    describe "throttling" do
      let(:fetch) { described_class.new(:queues => %w[default]) }
      let(:work)  { instance_spy(Sidekiq::Ultimate::UnitOfWork) }

      before do
        allow(fetch).to receive(:retrieve).and_return(work)
      end

      it "requeues throttled work" do
        allow(work).to receive(:throttled?).and_return(true)

        expect(fetch.retrieve_work).to be_nil

        expect(work).to have_received(:requeue_throttled)
      end

      it "returns work if it's not throttled" do
        allow(work).to receive(:throttled?).and_return(false)

        expect(fetch.retrieve_work).to eq work
      end
    end

    describe "fetching", :redis => true do
      let(:queues) { %w[n r m] }
      let(:fetch) { described_class.new(:queues => queues) }
      let(:sidekiq_util) { Object.new.tap { |o| o.extend Sidekiq::Component } }

      before do
        Sidekiq.redis do |r|
          r.rpush("queue:n", "turtle1")
          r.rpush("queue:r", "turtle2")
          r.rpush("queue:m", "turtle3")
        end

        stub_const("Sidekiq::Ultimate::Fetch::TIMEOUT", 0)
      end

      it "returns work from the queue and puts it into inproc list" do
        works = Array.new(3) { fetch.retrieve_work }

        expect(works).to contain_exactly(
          have_attributes(:queue => "queue:n", :job => "turtle1"),
          have_attributes(:queue => "queue:r", :job => "turtle2"),
          have_attributes(:queue => "queue:m", :job => "turtle3")
        )

        Sidekiq.redis do |r|
          expect(r.lrange("inproc:#{sidekiq_util.identity}:n", 0, -1)).to eq(["turtle1"])
          expect(r.lrange("inproc:#{sidekiq_util.identity}:r", 0, -1)).to eq(["turtle2"])
          expect(r.lrange("inproc:#{sidekiq_util.identity}:m", 0, -1)).to eq(["turtle3"])
        end
      end

      context "when the queue was exhausted after throttling" do
        it "does not fetch from that queue" do
          allow(Sidekiq::Throttled).to receive(:throttled?).with("turtle1").and_return(true)
          allow(Sidekiq::Throttled).to receive(:throttled?).with("turtle2").and_return(false)
          allow(Sidekiq::Throttled).to receive(:throttled?).with("turtle3").and_return(false)

          allow(queues).to receive(:shuffle).and_return(queues) # Make specs stable

          works = Array.new(3) { fetch.retrieve_work }

          expect(works).to contain_exactly(
            nil,
            have_attributes(:queue => "queue:r", :job => "turtle2"),
            have_attributes(:queue => "queue:m", :job => "turtle3")
          )

          Sidekiq.redis do |r|
            expect(r.lrange("inproc:#{sidekiq_util.identity}:r", 0, -1)).to eq(["turtle2"])
            expect(r.lrange("inproc:#{sidekiq_util.identity}:m", 0, -1)).to eq(["turtle3"])
          end
        end
      end

      context "when the queue was empty recently" do
        let(:empty_queues_instance) { instance_double(Sidekiq::Ultimate::EmptyQueues) }

        it "does not fetch from that queue" do
          allow(Sidekiq::Ultimate::EmptyQueues).to receive(:instance).and_return(empty_queues_instance)
          allow(empty_queues_instance).to receive(:queues).and_return(%w[n r])

          works = Array.new(3) { fetch.retrieve_work }

          expect(works).to contain_exactly(nil, nil, have_attributes(:queue => "queue:m", :job => "turtle3"))

          Sidekiq.redis do |r|
            expect(r.lrange("inproc:#{sidekiq_util.identity}:m", 0, -1)).to eq(["turtle3"])
          end
        end
      end

      context "when queue is paused" do
        it "does not fetch from that queue" do
          Sidekiq.redis do |r|
            r.sadd("throttled:X:paused_queues", %w[n m])
          end

          works = Array.new(3) { fetch.retrieve_work }

          expect(works).to contain_exactly(nil, have_attributes(:queue => "queue:r", :job => "turtle2"), nil)

          Sidekiq.redis do |r|
            expect(r.lrange("inproc:#{sidekiq_util.identity}:r", 0, -1)).to eq(["turtle2"])
          end
        end
      end
    end
  end
end
