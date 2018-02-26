while true do
  local val = redis.call("LPOP", KEYS[1])

  if val then
    redis.call("RPUSH", KEYS[2], val)
  else
    return
  end
end
