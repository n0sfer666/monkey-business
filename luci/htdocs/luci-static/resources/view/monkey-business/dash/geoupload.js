'use strict';
'require baseclass';
'require request';
'require rpc';

function send(which, file) {
  var data = new FormData();

  data.append('sessionid', rpc.getSessionID());
  data.append('filename', '/tmp/mb-upload-' + which + '.dat');
  data.append('filedata', file);

  return request.post(L.env.cgi_base + '/cgi-upload', data).then(function (res) {
    if (!res.ok) throw new Error(res.statusText || _('Upload failed'));
    var reply = null;

    try {
      reply = res.json();
    } catch (_) {}
    if (reply && reply.failure) throw new Error(reply.message || _('Upload failed'));
  });
}

return baseclass.extend({
  pick: function (which, onFile) {
    var input = E('input', {
      type: 'file',
      class: 'mb-geo-file',
      accept: '.dat',
      tabindex: '-1',
      'aria-hidden': 'true',
    });

    input.addEventListener('change', function () {
      var file = input.files && input.files[0];

      input.value = '';
      if (file)
        onFile(function () {
          return send(which, file);
        });
    });

    return input;
  },
});
