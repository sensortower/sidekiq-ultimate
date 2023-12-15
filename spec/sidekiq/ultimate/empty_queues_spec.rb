# frozen_string_literal: true

require "sidekiq/ultimate/empty_queues"
require "sidekiq"
require "sidekiq/component"

RSpec.describe Sidekiq::Ultimate::EmptyQueues do
  describe ".setup!" do
    let(:sidekiq_util)  do
      klass = Class.new do
        include Sidekiq::Component

        attr_writer :config
      end

      util_instance = klass.new
      util_instance.config = Sidekiq
      util_instance
    end

    it "subscribes to sidekiq startup and shutdown event to set up and shutdown queue refresh" do
      empty_queues_spy = instance_spy(described_class)
      allow(described_class).to receive(:instance).and_return(empty_queues_spy)

      described_class.setup!
      timer_task = Sidekiq::Ultimate::EmptyQueues::RefreshTimerTask::TASK_CLASS

      expect { sidekiq_util.fire_event(:startup) }.
        to change { ObjectSpace.each_object(timer_task).count(&:running?) }.from(0).to(1)

      sleep(1) # Wait for .refresh! to run

      expect { sidekiq_util.fire_event(:shutdown) }.
        to change { ObjectSpace.each_object(timer_task).count(&:running?) }.from(1).to(0)
      expect(empty_queues_spy).to have_received(:refresh!)
    end
  end

  describe "#refresh!", :redis => true do
    let(:instance) { Class.new(described_class).instance }

    before do
      allow(described_class).to receive(:instance).and_return(instance)
    end

    context "when local lock is free" do
      context "when global lock is free" do
        it "does not update the global cache if it was recently updated but updates the local cache" do
          instance.instance_variable_set(:@queues, %w[john])
          allow(Sidekiq::Ultimate::Configuration.instance).
            to receive(:empty_queues_cache_refresh_interval_sec).and_return(42)

          Sidekiq.redis do |r|
            r.set("ultimate:empty_queues_updater:last_run", r.time[0])

            r.sadd("ultimate:empty_queues", %w[john ringo])
            r.sadd("queues", %w[john ringo paul])
            r.lpush("queue:john", 1)

            expect { instance.refresh! }.
              to not_change { r.smembers("ultimate:empty_queues") }.
              and change(instance, :queues).
              from(%w[john]).
              to(match_array(%w[john ringo]))
          end
        end

        it "updates the global cache and local cache of empty queues" do
          instance.instance_variable_set(:@queues, %w[john])

          Sidekiq.redis do |r|
            r.sadd("ultimate:empty_queues", %w[john])
            r.sadd("queues", %w[john ringo paul])
            r.lpush("queue:john", 1)

            expect(instance.refresh!).to be_truthy

            expect(r.smembers("ultimate:empty_queues")).to match_array(%w[ringo paul])
            expect(instance.queues).to match_array(%w[ringo paul])
          end
        end

        it "updates the global cache and local cache if there are no empty queues" do
          instance.instance_variable_set(:@queues, %w[john])

          Sidekiq.redis do |r|
            r.sadd("ultimate:empty_queues", %w[john])
            r.sadd("queues", %w[john])
            r.lpush("queue:john", 1)

            expect(instance.refresh!).to be_truthy

            expect(r.smembers("ultimate:empty_queues")).to eq([])
            expect(instance.queues).to eq([])
          end
        end
      end

      context "when global lock is not free" do
        it "does not update the global cache but updates the local cache to match global cache" do
          instance.instance_variable_set(:@queues, %w[john])

          Sidekiq.redis do |r|
            Redlock::Client.new([r]).lock("ultimate:empty_queues_updater:lock", 30_000)

            r.sadd("ultimate:empty_queues", %w[john ringo])
            r.sadd("queues", %w[john ringo paul])
            r.lpush("queue:john", 1)

            expect(instance.refresh!).to be_truthy

            expect(r.smembers("ultimate:empty_queues")).to match_array(%w[john ringo])
            expect(instance.queues).to match_array(%w[john ringo])
          end
        end
      end
    end

    context "when local lock is not free" do
      before do
        local_lock = instance_double(Mutex, :try_lock => false)
        allow(instance).to receive(:local_lock).and_return(local_lock)
      end

      it "does not refresh the caches" do
        instance.instance_variable_set(:@queues, %w[john])

        Sidekiq.redis do |r|
          r.sadd("ultimate:empty_queues", %w[john])
          r.sadd("queues", %w[john ringo paul])
          r.lpush("queue:john", 1)

          expect { instance.refresh! }.
            to  not_change { r.smembers("ultimate:empty_queues") }.
            and not_change { instance.queues }
        end
      end
    end
  end
end
