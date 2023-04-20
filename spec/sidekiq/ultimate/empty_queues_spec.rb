# frozen_string_literal: true

require "sidekiq/ultimate/empty_queues"
require "sidekiq/util"

RSpec.describe Sidekiq::Ultimate::EmptyQueues do
  describe ".setup!" do
    let(:sidekiq_util) { Object.new.tap { |o| o.extend Sidekiq::Util } }

    it "subscribes to sidekiq startup and shutdown event to set up and shutdown queue refresh" do
      instance_spy = instance_spy(described_class)
      allow(described_class).to receive(:instance).and_return(instance_spy)

      described_class.setup!

      expect { sidekiq_util.fire_event(:startup) }.
        to change { ObjectSpace.each_object(Concurrent::TimerTask).count(&:running?) }.from(0).to(1)

      sleep(1) # Wait for .refresh! to run

      expect { sidekiq_util.fire_event(:shutdown) }.
        to change { ObjectSpace.each_object(Concurrent::TimerTask).count(&:running?) }.from(1).to(0)
      expect(instance_spy).to have_received(:refresh!)
    end
  end

  describe "#refresh!", :redis => true do
    let(:instance) { Class.new(described_class).instance }

    before do
      allow(described_class).to receive(:instance).and_return(instance)
    end

    context "when local lock is free" do
      context "when global lock is free" do
        it "does not update the global list if it was recently updated but updates the local list" do
          instance.instance_variable_set(:@queues, %w[john])
          allow(Sidekiq::Ultimate::Configuration.instance).to receive(:empty_queues_refresh_interval).and_return(42)

          Sidekiq.redis do |r|
            r.set("ultimate:empty_queues_updater:last_run", r.time[0])

            r.sadd("ultimate:empty_queues", %w[john ringo])
            r.sadd("queues", %w[john ringo turtle3])
            r.lpush("john", 1)

            expect { instance.refresh! }.
              to not_change { r.smembers("ultimate:empty_queues") }.
              and change(instance, :queues).
              from(%w[john]).
              to(match_array(%w[john ringo]))
          end
        end

        it "updates the global list and local list of empty queues" do
          instance.instance_variable_set(:@queues, %w[john])

          Sidekiq.redis do |r|
            r.sadd("ultimate:empty_queues", %w[john])
            r.sadd("queues", %w[john ringo turtle3])
            r.lpush("john", 1)

            expect { instance.refresh! }.
              to change { r.smembers("ultimate:empty_queues") }.
              from(%w[john]).
              to(match_array(%w[ringo turtle3])).
              and change(instance, :queues).
              from(%w[john]).
              to(match_array(%w[ringo turtle3]))
          end
        end
      end

      context "when global lock is not free" do
        it "does not update the global list but updates the local list to match global list" do
          instance.instance_variable_set(:@queues, %w[john])

          Sidekiq.redis do |r|
            Redlock::Client.new([r]).lock("ultimate:empty_queues_updater:lock", 30_000)

            r.sadd("ultimate:empty_queues", %w[john ringo])
            r.sadd("queues", %w[john ringo paul])
            r.lpush("john", 1)

            expect { instance.refresh! }.
              to not_change { r.smembers("ultimate:empty_queues") }.
              and change(instance, :queues).
              from(%w[john]).
              to(match_array(%w[john ringo]))
          end
        end
      end
    end

    context "when local lock is not free" do
      before do
        local_lock = instance_double(Mutex, :try_lock => false)
        allow(instance).to receive(:local_lock).and_return(local_lock)
      end

      it "does not refresh the lists" do
        instance.instance_variable_set(:@queues, %w[john])

        Sidekiq.redis do |r|
          r.sadd("ultimate:empty_queues", %w[john])
          r.sadd("queues", %w[john ringo paul])
          r.lpush("john", 1)

          expect { instance.refresh! }.
            to  not_change { r.smembers("ultimate:empty_queues") }.
            and not_change { instance.queues }
        end
      end
    end
  end
end
