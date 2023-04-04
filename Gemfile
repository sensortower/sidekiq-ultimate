# frozen_string_literal: true

source "https://rubygems.org"
ruby RUBY_VERSION

gem "rake"
gem "rspec"
gem "rubocop", :require => false
gem "rubocop-performance", :require => false
gem "rubocop-rake", :require => false
gem "rubocop-rspec", :require => false

group :development do
  gem "guard",         :require => false
  gem "guard-rspec",   :require => false
  gem "guard-rubocop", :require => false
  gem "pry",           :require => false
end

group :test do
  gem "codecov",    :require => false
  gem "simplecov",  :require => false
end

group :doc do
  gem "redcarpet"
  gem "yard"
end

gemspec
