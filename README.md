# deploymeteor

The deploymeteor script makes it as easy as possible to deploy one or more meteor apps to a standard Amazon EC2 server running the latest Amazon Linux AMI. It can be used to set up the server and to set up individual app environments on the server. Each app is hosted on a port that you specify, but the script also automatically sets up a node proxy server on port 80, which serves the correct app based on hostname.

## Install deploymeteor

To install deploymeteor on your workstation (Mac or Linux), run this command in your terminal:

```bash
$ sudo -H curl https://raw.github.com/aldeed/deploymeteor/master/install | sh
```

## Setting Up the Server

1. Launch a new Amazon Linux EC2 server and make note of its hostname. You can deploy multiple meteor apps/websites to this one server. Make sure to enable SSH (port 22) and HTTP (port 80). You might want to open additional ports or port ranges for connecting directly to your meteor apps.
2. SSH into the EC2 server and enter `sudo visudo`. Near the bottom, press I to switch to insert mode and insert a ! before `requiretty`. This is necessary for the deploymeteor script to work correctly. Press ESC and enter `:w!`. Now enter `:q` to quit.
3. On your workstation, open a Terminal session and enter `deploymeteor prepserver`. Answer the prompts. The host is the one you noted in step 1 and the key file is the one you downloaded while setting up the EC2 server.

You may now use this server to host one or more meteor apps. You never need to run `deploymeteor prepserver` for this server again, but you may do so whenever you want to ensure that the server is running the latest versions of node, meteor, etc.

## Set Up the App for Deployment to an Environment

Let's assume that you created a meteor app locally, and now you're ready to deploy it to your server.

```bash
$ cd /my/app/directory
$ deploymeteor <env>
```

Replace &lt;env&gt; with whatever you want to call the environment (for example, test, staging, or prod), and then answer all the prompts. This environment will be created and initialized on the remote server and added as a remote repository for this git repository.

You must have git installed locally before running this command, but you do not necessarily have to initialize a git repository in your app directory. If the current directory isn't already under git version control when you run deploymeteor, the script automatically initializes the git repo for you, adds all files, and does an initial commit.

## Deploying the App

After you have run `deploymeteor <env>` once, you don't need to run it again for that app environment unless any of the information you provided in the prompts changes, for example, if your database or e-mail URLs need to change for that environment.

It's now very easy to deploy the app:

```bash
$ git push <env> master
```

And when you make more changes to the local app files, simply commit your changes and run that same command again:

```bash
$ git commit -a -m "I updated my app"
$ git push <env> master
```

## Additional Options

There are several additional options that allow you to quickly perform actions for a certain app environment from your workstation.

### deploymeteor logs

Shows you the `out`, `error`, and `forever` logs for a certain app environment or for all app environments hosted on a single server at once.

```bash
$ cd /my/app/directory
$ deploymeteor logs <env>
```

Or

```bash
$ cd /any/app/directory
$ deploymeteor logs all
```

### deploymeteor clearlogs

Clears the `out`, `error`, and `forever` logs for a certain app environment or for all app environments hosted on a single server at once.

```bash
$ cd /my/app/directory
$ deploymeteor clearlogs <env>
```

Or

```bash
$ cd /any/app/directory
$ deploymeteor clearlogs all
```

### deploymeteor restart

Restarts (or starts) a certain app environment or all app environments hosted on a single server at once.

```bash
$ cd /my/app/directory
$ deploymeteor restart <env>
```

Or

```bash
$ cd /any/app/directory
$ deploymeteor restart all
```

Tip: If you need to reboot your EC2 instance for any reason, run `deploymeteor restart all` after it restarts and everything should be back to normal.

### deploymeteor restartproxy

Restarts (or starts) the nodeproxy app, which is what routes traffic to the correct app/port based on hostname. Generally speaking, there's no reason for you to run this.

### deploymeteor stop

Stops a certain app environment.

```bash
$ cd /my/app/directory
$ deploymeteor stop <env>
```

## What Exactly Does the Script Do?

### deploymeteor prepserver

Connects to the EC2 server using SSH and then:

1. Installs or upgrades Git to the latest version.
2. Installs or upgrades Node to the latest version.
3. Installs or upgrades Forever to the latest version.
4. Installs or upgrades Meteor to the latest version.
5. Installs or upgrades Meteorite to the latest version.
6. Installs or upgrades the node http-proxy package to the latest version.
7. Copies nodeproxy.js to the server.

### deploymeteor &lt;environment&gt;

1. Prompts you for the root URL for the environment, the port on which it should be hosted, the MongoDB URL, and the SMTP URL. These are the same environment variable values you would enter when launching Meteor as per their documentation.
2. Initializes git in the local directory if you haven't already done so.
3. Creates necessary directories on the EC2 server. Your apps are automatically stored in ~/meteorapps/[appname]/[environmentname].
4. Initializes a bare git repository on the EC2 server.
5. Creates a custom post-receive hook for this git repository on the EC2 server.
6. Creates a file on the EC2 server that maps your app's hostname to its port. This file is used by nodeproxy.js.
7. Starts or restarts the nodeproxy.js node app on the EC2 server, causing the new file to be read and parsed.
8. Sets up a new remote in your local git directory. This remote is named based on the environment name you specified.

### git push &lt;environment&gt; master

Whenever you push your changes to the new remote that was set up, the post-receive hook script automatically runs on the EC2 server. It does the following:

1. Copies the latest versions of all the app files to a secondary directory.
2. Runs `meteor bundle` to create the node bundle, and then immediately extracts the archive file.
3. Reinstalls `fibers` in the extracted bundle.
4. Copies the node app to another directory from which it will run.
5. Starts or restarts the app using Node and Forever. It is bound to the port you specified, but it is also accessible through port 80 based on using the hostname you provided (the root URL minus protocol).

## What About SSL?

If you want to secure an app environment using an SSL certificate, you can do it by using a load balancer:

1. When you are prompted for the root URL, make sure to enter a URL that begins with `https://`
2. Set up an Elastic Load Balancer (ELB) in Amazon EC2. In the ELB settings, choose to forward HTTPS (port 443) to HTTP (port 80). Provide your SSL certificate (single domain or wildcard).
3. If the app is hosted on a subdomain, then just create a CNAME record in your DNS settings, and point to the DNS address of the ELB. If the app is a root domain, you'll need to use an A record instead of CNAME, but you can only do that if you use Route53 DNS through Amazon, in which case you can use an A record ALIAS.

If you need to use multiple SSL certificates (because you're hosting multiple root domains or you don't have a wildcard certificate), then you'll need to set up one ELB per certificate. They can all forward to port 80 on the same EC2 instance, though. The AWS Console may or may not let you select an EC2 instance that already has a load balancer. If it does not, you can still do it, but you'll have to use the CLI or API.

## Thanks

Thanks to @julien-c for inspiration in [meteoric.sh](https://github.com/julien-c/meteoric.sh) and credit to [this post](http://toroid.org/ams/git-website-howto).

[![Support via Gittip](https://rawgithub.com/twolfson/gittip-badge/0.2.0/dist/gittip.png)](https://www.gittip.com/aldeed/)
