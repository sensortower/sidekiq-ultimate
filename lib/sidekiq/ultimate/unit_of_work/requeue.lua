if 1 == redis.call("LREM", KEYS[2], -1, ARGV[2]) then
  redis.call(ARGV[1], KEYS[1], ARGV[2])
  return 1
end

return 0

