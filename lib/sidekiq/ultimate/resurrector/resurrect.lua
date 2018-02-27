local count = 0

while true do
  local val = redis.call("LPOP", KEYS[1])

  if val then
    count = count + 1
    redis.call("RPUSH", KEYS[2], val)
  else
    return count
  end
end
