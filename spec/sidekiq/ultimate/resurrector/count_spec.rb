# frozen_string_literal: true

require "sidekiq/ultimate/resurrector/count"

RSpec.describe Sidekiq::Ultimate::Resurrector::Count do
  describe ".read", :redis => true do
    let(:job_id) { "2647c4fe13acc692326bd4c2" }

    it "returns the count of times the job was resurrected" do
      Sidekiq.redis { |r| r.set("ultimate:resurrector:counter:jid:#{job_id}", 1) }

      expect(described_class.read(:job_id => job_id)).to eq(1)
    end
  end
end
