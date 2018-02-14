# frozen_string_literal: true

require "bundler/gem_tasks"

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new

require "rubocop/rake_task"
RuboCop::RakeTask.new

if ENV["CI"]
  task :default => :spec
else
  task :default => %i[rubocop spec]
end
