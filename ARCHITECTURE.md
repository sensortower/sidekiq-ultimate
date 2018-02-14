# Decisions and Assumptions (AKA Architecture)

This is a very proof of concept version of the architecture for reliable fetch
strategy. IMplementation will be based on reliable queue pattern described in
redis documentation. In short fetch will look like this:

``` ruby
COOLDOWN = 2
IDENTITY = Object.new.tap { |o| o.extend Sidekiq::Util }.identity

def retrieve
  Sidekiq.redis do
    queue_names.each do |name|
      pending = "queue:#{name}"
      inproc  = "inproc:#{IDENTITY}:#{name}"
      job = redis.rpoplpush(pending, inproc)
      return job if job
    end
  end

  sleep COOLDOWN
end
```

The above means that we will have inproc queue per queue and sidekiq server
process. Naturally we will need a process that will monitor "orphan" queues.
We will run such on each Sidekiq server in a `Concurrent::TimerTask` thread.
We can easily check which sidekiq processes are currently alive with:

``` ruby
redis.exists(process_identity)
```

Sidekiq keeps it's own set of all known processes and clears it out upon first
web view, so we need our own way to track all ever-running sidekiq process
identities. So we can subscribe to `startup` event like so:

``` ruby
Sidekiq.on :startup do
  Sidekiq.redis do |redis|
    redis.sadd("ultimate:identities", IDENTITY)
  end
end
```

So now our casualties monitor can get all known identities and check which of
them are still alive:

``` ruby
casualties = []

Sidekiq.redis do |redis|
  identities = redis.smembers("ultimate:identities")
  heartbeats = redis.pipelined do
    identities.each { |key| redis.exists(key) }
  end

  heartbeats.each_with_index do |exists, idx|
    casualties << identities[idx] unless exists
  end
end
```

I want to put lost but found jobs back to the queue. But I want them to appear
at the head of the pending queue so that thwey will be retried. So, I want some
sort of LPOPRPUSH command, which does not exist, so we will use LUA script for
that to guarantee atomic execution:

``` lua
local src = KEYS[1]
local dst = KEYS[2]
local val = redis.call("LPOP", src)

if val then
  redis.call("RPUSH", dst, val)
end

return val
```

So now our casualties monitor can start resurrecting them:

``` ruby
def resurrect
  Sidekiq.redis do |redis|
    casualties.each do |identity|
      queue_names.each do |name|
        src = "inproc:#{identity}:#{name}"
        dst = "queue:#{name}"
        loop while redis.eval(LPOPRPUSH, :keys => [src, dst])
        redis.del(src)
      end
    end
  end
end
```

All good, but here's the problem: dead process could have differnet set of
queues it was serving. So, instead of relying on `Sidekiq.options` we can
save queues in the hash in redis, so our startup event will look like this:

``` ruby
Sidekiq.on :startup do
  Sidekiq.redis do |redis|
    queues = JSON.dump(Sidekiq.options[:queues].uniq)
    redis.hmset("ultimate:identities", IDENTITY, queues)
  end
end
```

Now, to get casualties we will use `HKEYS` instead of `SMEMBERS`. But they have
same complexity.

In addition to the above we will be using redis-based locks to guarantee only
one sidekiq process is handling resurrection at a time.
