'use strict';
'require baseclass';

// getRandomValues is available on ordinary HTTP LuCI origins too.
function create() {
  var bytes = new Uint8Array(16);

  crypto.getRandomValues(bytes);

  return Array.from(bytes, function (value) {
    return value.toString(16).padStart(2, '0');
  }).join('');
}

return baseclass.extend({ create: create });
