// Compatibility for cached clients. Only write-authorized availability_start starts jobs.
function deprecated() { return { api_version: 2, error: 'deprecated', replacement: 'availability_start' }; }
function serversPing(ctx) { return deprecated(); }
function subscriptionPing(ctx, args) { return deprecated(); }
function serverPing(ctx, args) { return deprecated(); }
export { serversPing, subscriptionPing, serverPing };
