redis.call(ARGV[1], KEYS[1], ARGV[2])
redis.call("LREM", KEYS[2], -1, ARGV[2])
