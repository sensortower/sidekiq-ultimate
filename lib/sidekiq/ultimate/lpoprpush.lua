local src = KEYS[1]
local dst = KEYS[2]
local val = redis.call("LPOP", src)

if val then
  redis.call("RPUSH", dst, val)
end

return val
