local resurrected_jobs = 0

while true do
  local job_data = redis.call("LPOP", KEYS[1])

  if job_data then
    redis.call("RPUSH", KEYS[2], job_data)

    resurrected_jobs = resurrected_jobs + 1

    local _, jid_position = string.find(job_data, "\"jid\"")
    jid_position = jid_position + 3

    local jid = job_data:sub(jid_position, jid_position + 23)
    local jid_key =  KEYS[3] .. ':counter:jid:' .. jid

    redis.call("INCR", jid_key)
    redis.call("EXPIRE", jid_key, 86400)
  else
    return resurrected_jobs
  end
end
