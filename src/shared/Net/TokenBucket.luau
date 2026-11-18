--!strict
-- Token-bucket rate limiter (TECH_SPEC §7). Pure: the caller passes the clock, so tests are exact.
-- A bucket holds up to `burst` tokens and refills at `perSecond`; each call costs one token.

local TokenBucket = {}

export type Bucket = { tokens: number, capacity: number, perSecond: number, t: number }

function TokenBucket.new(perSecond: number, burst: number, now: number): Bucket
	assert(perSecond > 0 and burst >= 1, "rate must be positive and burst at least 1")
	return { tokens = burst, capacity = burst, perSecond = perSecond, t = now }
end

function TokenBucket.take(bucket: Bucket, now: number, cost: number?): boolean
	local price = cost or 1
	local elapsed = math.max(0, now - bucket.t) -- a clock that goes backwards refills nothing
	bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.perSecond)
	bucket.t = math.max(bucket.t, now)
	if bucket.tokens >= price then
		bucket.tokens -= price
		return true
	end
	return false
end

return TokenBucket
