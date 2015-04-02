var httpProxy = require('http-proxy'),
    http = require('http'),
    fs = require('fs');

var nodeProxyDir = __dirname;
var map = {};
fs.readdir(nodeProxyDir, function(err, files) {
    if (err) {
        console.log('Error: ' + err);
        return;
    }

    for (var i = 0, ln = files.length, file, data; i < ln; i++) {
        file = files[i];
        if (file.slice(-5) === '.json') {
            data = fs.readFileSync(nodeProxyDir + '/' + file, 'utf8');
            data = JSON.parse(data);
            for (var name in data) {
                map[name] = data[name];
            }
        }
    }
    
    //create proxy server
    var proxy = httpProxy.createProxyServer();

    proxy.on('error', function (error, req, res) {
        var json;
        console.log('proxy error', error);
        if (!res.headersSent) {
            res.writeHead(500, { 'content-type': 'application/json' });
        }

        json = { error: 'proxy_error', reason: error.message };
        res.end(JSON.stringify(json));
    });

    //start proxy server
    var server = http.createServer(function(req, res) {
        proxy.web(req, res, {
          target: 'http://' + map[req.headers.host]
        });
    });

    //
    // Listen to the `upgrade` event and proxy the
    // WebSocket requests as well.
    //
    server.on('upgrade', function (req, socket, head) {
      proxy.ws(req, socket, head, {
        target: 'ws://' + map[req.headers.host]
      });
    });

    server.listen(80);

    console.log('Node Proxy Server started with:', map);
    // Downgrade the process to run as the ec2-user group and user now that it's bound to privileged ports.
    process.setgid('ec2-user');
    process.setuid('ec2-user');
});
