# frozen_string_literal: true

require "sidekiq/ultimate/queue_name"
require "sidekiq/component"

RSpec.describe Sidekiq::Ultimate::QueueName do
  let(:process_identity) do
    Object.new.tap { |o| o.extend Sidekiq::Component }.identity
  end

  it "can be used in arrays manipulations" do
    x = %w[h a r d].map { |name| described_class.new name }
    y = %w[c o r e].map { |name| described_class.new name }

    expect(x - y).to eq(%w[h a d].map { |name| described_class.new name })
  end

  describe ".new" do
    it "works supports anything that responds to #to_s" do
      expect(described_class.new(double(:to_s => "foobar"))). # rubocop:disable RSpec/VerifiedDoubles
        to have_attributes({
          :normalized => "foobar",
          :pending    => "queue:foobar",
          :inproc     => "inproc:#{process_identity}:foobar"
        })
    end

    it "allows to override identity" do
      expect(described_class.new(:foobar, :identity => :xxx)).
        to have_attributes({
          :normalized => "foobar",
          :pending    => "queue:foobar",
          :inproc     => "inproc:xxx:foobar"
        })
    end
  end

  describe ".[]" do
    it "works with normalized name" do
      expect(described_class["foobar"]).
        to be_a(described_class).
        and have_attributes({
          :normalized => "foobar",
          :pending    => "queue:foobar",
          :inproc     => "inproc:#{process_identity}:foobar"
        })
    end

    it "works with expanded name" do
      expect(described_class["queue:foobar"]).
        to be_a(described_class).
        and have_attributes({
          :normalized => "foobar",
          :pending    => "queue:foobar",
          :inproc     => "inproc:#{process_identity}:foobar"
        })
    end

    it "works with namespaced expanded name" do
      expect(described_class["xxx:queue:foobar"]).
        to be_a(described_class).
        and have_attributes({
          :normalized => "foobar",
          :pending    => "queue:foobar",
          :inproc     => "inproc:#{process_identity}:foobar"
        })
    end

    it "allows to pass custom identity" do
      expect(described_class["xxx:queue:foobar", :identity => :wtf]).
        to be_a(described_class).
        and have_attributes({
          :normalized => "foobar",
          :pending    => "queue:foobar",
          :inproc     => "inproc:wtf:foobar"
        })
    end
  end

  describe "#normalized" do
    subject { described_class.new("foobar").normalized }

    it { is_expected.to be_frozen.and eq("foobar") }
  end

  describe "#pending" do
    subject { described_class.new("foobar").pending }

    it { is_expected.to be_frozen.and eq("queue:foobar") }
  end

  describe "#inproc" do
    subject { described_class.new("foobar").inproc }

    it { is_expected.to be_frozen.and eq("inproc:#{process_identity}:foobar") }
  end

  describe "#hash" do
    subject { described_class.new("foobar").hash }

    it { is_expected.to be_an(Integer).and eq("foobar".hash) }
  end

  describe "#to_s" do
    subject { described_class.new("foobar").to_s }

    it { is_expected.to be_a(String).and eq("foobar") }
  end

  describe "#inspect" do
    subject { described_class.new("foobar").inspect }

    it { is_expected.to eq(%(#{described_class}["foobar"])) }
  end

  describe "#==" do
    subject { described_class.new("foobar") == other }

    context "with same normalized name" do
      let(:other) { described_class.new("foobar") }

      it { is_expected.to be true }
    end

    context "with different normalized name" do
      let(:other) { described_class.new("deadbeef") }

      it { is_expected.to be false }
    end

    context "with non QueueName instance" do
      let(:other) { "deadbeef" }

      it { is_expected.to be false }
    end
  end

  describe "#eql?" do
    subject { described_class.new("foobar").eql? other }

    context "with same normalized name" do
      let(:other) { described_class.new("foobar") }

      it { is_expected.to be true }
    end

    context "with different normalized name" do
      let(:other) { described_class.new("deadbeef") }

      it { is_expected.to be false }
    end

    context "with non QueueName instance" do
      let(:other) { "deadbeef" }

      it { is_expected.to be false }
    end
  end
end
