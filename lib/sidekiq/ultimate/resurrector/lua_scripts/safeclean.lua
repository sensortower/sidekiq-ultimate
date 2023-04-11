local rip = true

for i, v in ipairs(KEYS) do
  if 2 <= i then
    if 0 == redis.call("LLEN", v) then
      redis.call("DEL", v)
    else
      rip = false
    end
  end
end

if rip then
  redis.call("HDEL", KEYS[1], ARGV[1])
  return 1
end

return nil
