# deploymeteor

The deploymeteor script makes it as easy as possible to deploy a meteor app to a standard Amazon EC2 server running the latest Amazon Linux AMI.

## Install deploymeteor

To install deploymeteor on your workstation (Mac or Linux), run this command in your terminal:

```bash
$ sudo -H curl https://raw.github.com/aldeed/deploymeteor/master/install | sh
```

## Setting Up the Server

1. Launch a new EC2 server and make note of its hostname. You can deploy multiple meteor apps/websites to this one server. Make sure to enable SSH (port 22) and HTTP (port 80). You might want to open additional ports or port ranges for connecting directly to your meteor apps.
2. SSH into the EC2 server and enter `sudo visudo`. Near the bottom, press I to switch to insert mode and insert a ! before `requiretty`. This is necessary for the script to work correctly. Press ESC and enter `:w!`. Now enter `:q` to quit.
3. On your workstation, run `deploymeteor prepserver`. Answer the prompts. The host is the one you noted in step 1 and the key file is the one you downloaded while setting up the EC2 server.

You may now use this server to host one or more meteor apps.

## Deploy an App the First Time

Let's assume that you created a meteor app locally, and now you're ready to deploy it to your server.

```bash
$ cd /my/app/directory
$ deploymeteor <env>
```

Replace <env> with whatever you want to call the environment, and answer all the prompts. This environment will be created and initialized on the remote server and added as a remote repository for this git repository.

If the current directory isn't already under git version control when you run deploymeteor, the script initializes the git repo for you, adds all files, and does an initial commit.

## Subsequent Updates

You only need to run deploymeteor once per project environment. You should run it again if any of the information in the prompts changes, for example, if your database or e-mail URLs need to change.

After that first run, simply push to the correct remote env to deploy the current branch:

```bash
$ git push <env>
```

Where <env> is the same thing you entered when initially running deploymeteor. The initial `git push` is done for you during the deploymeteor script, so you don't need to do it again until you've made and committed more changes.

## How it Works

deploymeteor sets up a git post-receive hook script on the remote repository. Every time you push to that environment, the script runs, causing the files to be updated and the app restarted, using forever to keep it running, well, forever.

## Thanks

Thanks to @julien-c for [https://github.com/julien-c/meteoric.sh meteoric.sh] and credit to [http://toroid.org/ams/git-website-howto this post].