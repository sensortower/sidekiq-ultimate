# Sidekiq::Ultimate

Sidekiq ultimate experience.

---

**WARNING**

This ia an alpha/preview software. Lots of changes will be made and eventually
it will overtake [sidekiq-throttled][] and will become truly ultimate sidekiq
extension one will need. :D

---


## Installation

Add this line to your application's Gemfile:

```ruby
gem "sidekiq-ultimate", ">= 0.0.1.alpha"
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-ultimate


## Usage

Add somewhere in your app's bootstrap (e.g. `config/initializers/sidekiq.rb` if
you are using Rails):

``` ruby
require "sidekiq/ultimate"
Sidekiq::Ultimate.setup!
```

## Configuration

### Resurrection event handler

An event handler can be called when a job is resurrected.

```ruby
Sidekiq::Ultimate.setup! do |config|
  config.on_resurrection = ->(queue_name, jobs_count) do
    puts "Resurrected #{jobs_count} jobs from #{queue_name}"
  end
end
```

### Resurrection counter

A resurrection counter can be enabled to count how many times a job was resurrected. If `enable_resurrection_counter` setting is enabled, on each resurrection event, a counter is increased. Counter value is stored in redis and has expiration time 24 hours. 

For example this can be used in the `ServerMiddleware` later on to early return resurrected jobs based on the counter value.

`enable_resurrection_counter` can be either a `Proc` or a constant. 

Having a `Proc` is useful if you want to enable or disable resurrection counter in run time. It will be called on each 
resurrection event to decide whether to increase the counter or not.

```ruby
Sidekiq::Ultimate.setup! do |config|
  config.enable_resurrection_counter = -> do
    DynamicSettings.get("enable_resurrection_counter")
  end
end

Sidekiq::Ultimate.setup! do |config|
  config.enable_resurrection_counter = true
end
```

#### Read the value

Resurrection counter value can be read using `Sidekiq::Ultimate::Resurrector::Count.read` method.

```ruby
Sidekiq::Ultimate::Resurrector::Count.read(:job_id => "2647c4fe13acc692326bd4c2")
=> 1
```

### Empty Queues Cache Refresh Interval

```ruby
Sidekiq::Ultimate.setup! do |config|
  config.empty_queues_cache_refresh_interval_sec = 42
end
```

Specifies how often the cache of empty queues should be refreshed.
In a nutshell, this sets the maximum possible delay between when a job was pushed to previously empty queue and earliest the moment when that new job could be picked up.

**Note:** every sidekiq process maintains its own local cache of empty queues.
Setting this interval to a low value will increase the number of Redis calls needed to check for empty queues, increasing the total load on Redis.

This setting helps manage the tradeoff between performance penalties and latency needed for reliable fetch.
Under the hood, Sidekiq's default fetch occurs with [a single Redis `BRPOP` call](https://redis.io/commands/brpop/) which is passes list of all queues to pluck work from.
In contrast, [reliable fetch uses `LPOPRPUSH`](https://redis.io/commands/rpoplpush/) (or the equivalent `LMOVE` in later Redis versions) to place in progress work into a WIP queue.
However, `LPOPRPUSH` can only check one source queue to pop from at once, and [no multi-key alternative is available](https://github.com/redis/redis/issues/1785), so multiple Redis calls are needed to pluck work if an empty queue is checked.
In order to avoid performance penalties for repeated calls to empty queues, Sidekiq Ultimate therefore maintains a list of recently know empty queues which it will avoid polling for work.

Therefore:
- If your Sidekiq architecture has *a low number of total queues*, the worst case penalty for polling empty queues will be bounded, and it is reasonable to **set a shorter refresh period**.
- If your Sidekiq architecture has a *high number of total queues*, the worst case penalty for polling empty queues is large, and it is recommended to **set a longer refresh period**.
- When adjusting this setting:
    - Check that work is consumed appropriately quickly from high priority queues after they bottom out (after increasing the refresh interval)
    - Check that backlog work does not accumulate in low priority queues (after decreasing the refresh interval)


---

**NOTICE**

Throttling is brought by [sidekiq-throttled][] and it's automatically set up
by the command above - don't run `Sidekiq::Throttled.setup!` yourself.

Thus look up it's README for throttling configuration details.

---


## Supported Ruby Versions

This library aims to support and is tested against the following Ruby and Redis client versions:

* Ruby
  * 2.7.x

* [redis-rb](https://github.com/redis/redis-rb)
  * 4.x

* [redis-namespace](https://github.com/resque/redis-namespace)
  * 1.6


If something doesn't work on one of these versions, it's a bug.

This library may inadvertently work (or seem to work) on other Ruby versions,
however support will only be provided for the versions listed above.

If you would like this library to support another Ruby version or
implementation, you may volunteer to be a maintainer. Being a maintainer
entails making sure all tests run and pass on that implementation. When
something breaks on your implementation, you will be responsible for providing
patches in a timely fashion. If critical issues for a particular implementation
exist at the time of a major release, support for that Ruby version may be
dropped.


## Development

After checking out the repo, run `bundle install` to install dependencies.
Then, run `bundle exec rake spec` to run the tests with ruby-rb client.

To install this gem onto your local machine, run `bundle exec rake install`.
To release a new version, update the version number in `version.rb`, and then
run `bundle exec rake release`, which will create a git tag for the version,
push git commits and tags, and push the `.gem` file to [rubygems.org][].


## Contributing

* Fork sidekiq-ultimate on GitHub
* Make your changes
* Ensure all tests pass (`bundle exec rake`)
* Send a pull request
* If we like them we'll merge them
* If we've accepted a patch, feel free to ask for commit access!


## Copyright

Copyright (c) 2018-23 SensorTower Inc.<br>
See [LICENSE.md][] for further details.


[rubygems.org]: https://rubygems.org
[LICENSE.md]: https://github.com/sensortower/sidekiq-ultimate/blob/master/LICENSE.txt
[sidekiq-throttled]: https://github.com/ixti/sidekiq-throttled
