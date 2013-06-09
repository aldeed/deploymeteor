# deploymeteor

The deploymeteor script makes it as easy as possible to deploy a meteor app to a standard Amazon EC2 server running the latest Amazon Linux AMI.

## Install deploymeteor

Just run command in your terminal on Mac/Linux:

```bash
$ sudo -H curl https://raw.github.com/aldeed/deploymeteor/master/install | sh
```

## Prerequisites

1. Launch a new EC2 server and make note of its hostname. You can deploy multiple meteor apps/websites to this one server.
2. Before deploying each app, make sure that the app's directory is under git version control:

```bash
$ cd /my/app/directory
$ git init
```

## Deploy an App the First Time

Assuming the app directory is under git version control and you've committed all your changes, just run one command and answer the prompts:

```bash
$ cd /my/app/directory
$ deploymeteor <env>
```

Replace <env> with whatever you want to call the environment. This environment will be created and initialized on the remote server and added as a remote repository for this git repository.

## Thanks

Thanks to the creators of meteoric.sh and http://toroid.org/ams/git-website-howto.