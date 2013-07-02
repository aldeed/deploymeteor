#!/bin/bash

NODE_VERSION=0.10.12
HOME_DIR=/home/ec2-user
NODEPROXY_DIR=$HOME_DIR/nodeproxy
PWD=`pwd`
SCRIPTPATH="$HOME/.deploymeteor"

if [ -z "$1" ]; then
	echo
	echo "Usage: deploymeteor <environment>"
	echo "For example, type deploymeteor staging to deploy to a staging environment. This environment will be created and initialized on the remote server and added as a remote repository for this git repository."
	echo
	echo "Before the first time you use deploymeteor with a new server, you should also run deploymeteor prepserver. This will install node, npm, meteor, forever, and meteorite on the server."
	exit 1
fi

#If this has been run before, grab variable defaults from stored config file
if [ -r "$PWD/.deploymeteor.config" ]; then
	source "$PWD/.deploymeteor.config"
fi

#prompt for info needed by both prepserver and environment deploy
echo
echo "Enter the hostname or IP address of the Amazon Linux EC2 server."
echo "Examples: 11.111.11.111 or ec2-11-111-11-111.us-west-2.compute.amazonaws.com"
if [ -z "$LAST_APP_HOST" ]; then
	echo "Default (press ENTER): No default"
else
	echo "Default (press ENTER): $LAST_APP_HOST"
fi
read -e -p "Host: " APP_HOST
APP_HOST=${APP_HOST:-$LAST_APP_HOST}
echo
echo "Enter the path to your EC2 .pem file on this machine."
if [ -z "$LAST_EC2_PEM_FILE" ]; then
	echo "Default (press ENTER): No default"
else
	echo "Default (press ENTER): $LAST_EC2_PEM_FILE"
fi
read -e -p "Key file: " EC2_PEM_FILE
EC2_PEM_FILE=${EC2_PEM_FILE:-$LAST_EC2_PEM_FILE}

#store answers to use as defaults the next time deploymeteor is run
cat > $PWD/.deploymeteor.config <<ENDCAT
LAST_APP_HOST=$APP_HOST
LAST_EC2_PEM_FILE=$EC2_PEM_FILE
ENDCAT

SSH_HOST="ec2-user@$APP_HOST"
SSH_OPT="-i $EC2_PEM_FILE"

case "$1" in
prepserver)
    echo
    echo "Preparing server..."
    ssh -t $SSH_OPT $SSH_HOST <<EOL
    sudo yum install gcc-c++ make
    sudo yum install openssl-devel
    sudo yum install git

    cd $HOME_DIR
    mkdir -p $NODEPROXY_DIR

    #Check if Node is installed and at the right version
    echo "Checking for Node version $NODE_VERSION"
    #if Node is installed
    if hash node 2>/dev/null; then
        #see if it needs to be upgraded
        if node --version | grep -q $NODE_VERSION; then
            #Upgrade Node
            sudo npm cache clean -f
            sudo npm install -g n
            sudo n stable
        fi
    else
        # Install Node
        git clone git://github.com/joyent/node.git
        cd node
        git checkout v$NODE_VERSION
        ./configure
        make
        sudo make install
        cd ..
    fi

    #install forever
    sudo -H npm install -g forever

    #install meteor
    curl https://install.meteor.com | /bin/sh

    #install meteorite
    sudo -H npm install -g meteorite

    #install node-proxy
    sudo -H npm install -g http-proxy
EOL
    # Copy nodeproxy.js from script directory to server
    # We don't need to start it until an environment has been deployed
    scp $SSH_OPT $SCRIPTPATH/nodeproxy.js $SSH_HOST:$NODEPROXY_DIR
    echo "Done!"
    exit 1
    ;;
esac

####The rest is run only for setting up git deployment####
APPS_DIR=$HOME_DIR/meteorapps
APP_NAME=${PWD##*/}

#Prompt for additional app-specific info that is needed
echo
echo "Enter the root URL for this website, as users will access it, including protocol."
echo "Examples: http://mysite.com or https://mysite.com"
echo "Default (press ENTER): http://$APP_HOST"
echo
read -e -p "Root URL: " ROOT_URL
ROOT_URL=${ROOT_URL:-http://$APP_HOST}
echo
echo "Enter the port on which to host this website."
echo "Examples: 8080 or 3001"
echo "Default (press ENTER): 80"
echo
read -e -p "Port: " PORT
PORT=${PORT:-80}
echo
echo "Enter the URL for the MongoDB database used by this app."
echo "Format: mongodb://<username>:<password>@<ip or hostname>:<port>/<dbname>"
read -e -p "MongoDB URL: " MONGO_URL
echo
echo
echo "Enter the SMTP URL for e-mail sending by this app."
echo "Format: smtp://<username>:<password>@<ip or hostname>:<port>"
read -e -p "E-mail URL: " MAIL_URL
echo

APP_DIR=$APPS_DIR/$APP_NAME/$1
GIT_APP_DIR=$APP_DIR/git
WWW_APP_DIR=$APP_DIR/www
TMP_APP_DIR=$APP_DIR/bundletmp
LOG_DIR=$APP_DIR/logs
BUNDLE_DIR=$APP_DIR/bundle
HOSTNAME=${ROOT_URL#https://}
HOSTNAME=${HOSTNAME#http://}

##on workstation, make sure git init has been run
if [ ! -d ".git" ]; then
	git init
	git add .
	git commit -a -m "Initial commit"
fi

echo
echo
echo "Setting up git deployment for the $1 environment of $APP_NAME"
ssh -t $SSH_OPT $SSH_HOST <<EOLENVSETUP
# Create necessary directories
mkdir -p $APP_DIR
rm -rf $GIT_APP_DIR
mkdir -p $GIT_APP_DIR/hooks
mkdir -p $WWW_APP_DIR
mkdir -p $LOG_DIR
mkdir -p $BUNDLE_DIR
# Init the bare git repo
cd $GIT_APP_DIR
git init --bare
# Create the post-receive hook file and set its permissions; we'll add its contents in a bit
touch hooks/post-receive
sudo chmod +x hooks/post-receive
# Create/update the JSON file for this environment used by nodeproxy.js
cd $NODEPROXY_DIR
cat > $APP_NAME.$1.json <<EOLJSONDOC
{"$HOSTNAME": "127.0.0.1:$PORT"}
EOLJSONDOC
# Start/restart nodeproxy.js using forever so that hostname/IP updates are seen
mkdir -p logs
sudo forever stop $NODEPROXY_DIR/nodeproxy.js
sudo forever start -l $NODEPROXY_DIR/logs/forever.log -o $NODEPROXY_DIR/logs/out.log -e $NODEPROXY_DIR/logs/err.log -a -s $NODEPROXY_DIR/nodeproxy.js
EOLENVSETUP
cat > tmp-post-receive <<ENDCAT
#!/bin/sh

# Clean up any directories that might exist already
if [ -d "$TMP_APP_DIR" ]; then
    rm -rf $TMP_APP_DIR
fi
if [ -d "$BUNDLE_DIR" ]; then
    rm -rf $BUNDLE_DIR
fi

# Create the temporary directory where all the project files should be copied when git pushed
mkdir -p $TMP_APP_DIR

# Copy all the project files to the temporary directory
cd $GIT_APP_DIR
GIT_WORK_TREE="$TMP_APP_DIR" git checkout -f

# Create the node bundle using the meteor/meteorite bundle command
cd $TMP_APP_DIR
sudo -H mrt bundle $APP_DIR/bundle.tgz

# Extract the bundle into the BUNDLE_DIR, and then delete the .tgz file
cd $APP_DIR
tar -zxvf bundle.tgz
rm bundle.tgz

# Reinstall fibers
# (http://stackoverflow.com/questions/13327088/meteor-bundle-fails-because-fibers-node-is-missing)
cd $BUNDLE_DIR/server
npm uninstall fibers
npm install fibers

# Copy the extracted and tweaked node application to the WWW_APP_DIR
cp -R $BUNDLE_DIR/* $WWW_APP_DIR

# Clean up any directories that we created
if [ -d "$TMP_APP_DIR" ]; then
    rm -rf $TMP_APP_DIR
fi
if [ -d "$BUNDLE_DIR" ]; then
    rm -rf $BUNDLE_DIR
fi

# Try to stop the node app using forever, in case it's already running
cd $WWW_APP_DIR
sudo forever stop $WWW_APP_DIR/main.js

# Start the node app using forever
sudo PORT=$PORT ROOT_URL=$ROOT_URL MONGO_URL=$MONGO_URL MAIL_URL=$MAIL_URL forever start -l $LOG_DIR/forever.log -o $LOG_DIR/out.log -e $LOG_DIR/err.log -a -s $WWW_APP_DIR/main.js
ENDCAT
scp $SSH_OPT tmp-post-receive $SSH_HOST:$GIT_APP_DIR/hooks/post-receive
rm tmp-post-receive
ssh-add $EC2_PEM_FILE
# Set up the environment remote
git remote rm $1
git remote add $1 ssh://$SSH_HOST$GIT_APP_DIR
# Do the initial git push
git push $1 master
echo
echo
echo
echo "Done! Now simply make and commit your changes and then redeploy as necessary with git push $1"
echo