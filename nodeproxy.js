var http = require('http-proxy');
var fs = require('fs');

var options = {
    hostnameOnly: true,
    router: {}
};

fs.readDir(__dirname, function(err, files) {
    if (err) {
        console.log('Error: ' + err);
        return;
    }

    for (var i = 0, ln = files.length, file, data; i < ln; i++) {
        file = files[i];
        if (file.slice(-5) === '.json') {
            data = fs.readFileSync(file, 'utf8');
            data = JSON.parse(data);
            for (var name in data) {
                options["router"][name] = data[name];
            }
        }
    }

    http.createServer(options).listen(80, function() {
        console.log('Node Proxy Server started');
        // Downgrade the process to run as the ec2-user group and user now that's it bound to privileged ports.
        process.setgid('ec2-user');
        process.setuid('ec2-user');
    });
});