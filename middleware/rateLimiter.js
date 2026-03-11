// Custom Rate Limiter Middleware
// Keeps app offline (no deps like express-rate-limit). 
// Limits: 7 requests per IP per minute across all services/routes.
// Uses in-memory Map (resets auto); production would use Redis/DB but simple here.

const rateLimitStore = new Map();  // IP -> {count, resetTime}
const { verifyToken } = require('../utils/jwt');

const rateLimiter = (req, res, next) => {
  // Admin JWT bypass: skip rate limiting entirely for valid admin tokens
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const payload = verifyToken(authHeader.split(' ')[1]);
    if (payload && payload.role === 'admin') return next();
  }

  // Improved IP extraction for consistency (handles IPv6 localhost, proxies; ensures single key per local/test IP)
  // Debug: log to terminal for verification (remove in prod)
  let ip = req.ip || req.connection?.remoteAddress || req.socket?.remoteAddress || 'unknown';
  if (ip.includes('::ffff:')) ip = ip.split('::ffff:')[1];  // normalize IPv4-mapped
  if (ip === '::1' || ip === '127.0.0.1::1') ip = '127.0.0.1';  // treat localhost IPv6 as IPv4
  console.log(`RateLimiter: IP=${ip}, count before=${rateLimitStore.get(ip)?.count || 0}`);  // TEMP DEBUG

  const now = Date.now();
  const windowMs = 60 * 1000;  // 1 min
  const max = 7;  // max reqs

  if (!rateLimitStore.has(ip)) {
    rateLimitStore.set(ip, { count: 0, resetTime: now + windowMs });
  }

  const record = rateLimitStore.get(ip);

  // Reset if window passed
  if (now > record.resetTime) {
    record.count = 0;
    record.resetTime = now + windowMs;
  }

  record.count += 1;
  console.log(`RateLimiter: IP=${ip}, count after=${record.count}`);  // TEMP DEBUG

  if (record.count > max) {
    console.log(`RateLimiter: BLOCKED IP=${ip}`);
    return res.status(429).json({
      error: 'Rate limit exceeded. Max 7 requests per minute per IP. Applies to all services (users/theaters/etc).'
    });
  }

  // Cleanup old entries periodically (concise)
  if (Math.random() < 0.01) {  // ~1% chance
    for (let [key, val] of rateLimitStore) {
      if (now > val.resetTime) rateLimitStore.delete(key);
    }
  }

  next();
};

module.exports = rateLimiter;