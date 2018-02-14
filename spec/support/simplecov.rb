# frozen_string_literal: true

require "simplecov"

SimpleCov.formatter =
  if ENV["CI"]
    require "codecov"
    SimpleCov::Formatter::Codecov
  else
    SimpleCov::Formatter::HTMLFormatter
  end

SimpleCov.start do
  add_filter "/spec/"
  minimum_coverage 90
end
