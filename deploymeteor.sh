#!/bin/bash

LATEST_NODE_VERSION=0.10.13
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
    echo "Installing prerequisites..."
    sudo yum install -q -y gcc gcc-c++ make git openssl-devel freetype-devel fontconfig-devel &> /dev/null

    #Check if Node is installed and at the latest version
    echo "Checking for Node..."
    #if Node is installed
    if hash node 2>/dev/null; then
        # Upgrade Node
        echo "Upgrading Node..."
        sudo npm cache clean -f &> /dev/null
        sudo npm update -g n &> /dev/null
        sudo n stable &> /dev/null
    else
        # Install Node
        echo "Installing Node..."
        cd $HOME_DIR
        git clone git://github.com/joyent/node.git &> /dev/null
        cd node
        git checkout v$LATEST_NODE_VERSION &> /dev/null
        ./configure &> /dev/null
        make &> /dev/null
        sudo make install &> /dev/null
        cd ..
    fi

    #install forever
    echo "Installing or updating Forever..."
    sudo -H npm update -g forever &> /dev/null

    #install meteor
    echo "Installing or updating Meteor..."
    curl https://install.meteor.com | /bin/sh

    #install meteorite
    echo "Installing or updating Meteorite..."
    sudo -H npm update -g meteorite &> /dev/null

    #install http-proxy
    echo "Installing or updating http-proxy..."
    mkdir -p $NODEPROXY_DIR/certs
    cd $NODEPROXY_DIR
    npm update http-proxy &> /dev/null

    #install PhantomJS
    echo "Installing PhantomJS..."
    cd $HOME_DIR
    git clone git://github.com/ariya/phantomjs.git &> /dev/null
    cd phantomjs
    git checkout 1.9 &> /dev/null
    ./build.sh &> /dev/null
EOL
    # Copy nodeproxy.js from script directory to server
    # We don't need to start it until an environment has been deployed
    echo "Copying nodeproxy.js to the server..."
    scp $SSH_OPT $SCRIPTPATH/nodeproxy.js $SSH_HOST:$NODEPROXY_DIR &> /dev/null
    echo "Done!"
    exit 1
    ;;
esac

####The rest is run only for setting up git deployment####
APPS_DIR=$HOME_DIR/meteorapps
APP_NAME=${PWD##*/}

#Prompt for additional app-specific info that is needed
echo
echo "Enter the root URL for this website, as users should access it, including protocol."
echo "Examples: http://mysite.com or https://mysite.com"
echo "Default (press ENTER): http://$APP_HOST"
echo
read -e -p "Root URL: " ROOT_URL
ROOT_URL=${ROOT_URL:-http://$APP_HOST}
echo
echo "Enter the port on which to host this website. Do not enter 80 because a proxy server is automatically launched on that port."
echo "Examples: 8080 or 3001"
echo "Default (press ENTER): 8000"
echo
read -e -p "Port: " PORT
PORT=${PORT:-8000}
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

##support there being no mongo or mail url
if [ -z "$MONGO_URL" ]; then
    MONGO_URL_SETTER=""
else
    MONGO_URL_SETTER=" MONGO_URL=$MONGO_URL"
fi

if [ -z "$MAIL_URL" ]; then
    MAIL_URL_SETTER=""
else
    MAIL_URL_SETTER=" MAIL_URL=$MAIL_URL"
fi

##set up variables
APP_DIR=$APPS_DIR/$APP_NAME/$1
GIT_APP_DIR=$APP_DIR/git
WWW_APP_DIR=$APP_DIR/www
TMP_APP_DIR=$APP_DIR/bundletmp
LOG_DIR=$APP_DIR/logs
BUNDLE_DIR=$TMP_APP_DIR/bundle
HOSTNAME=${ROOT_URL#https://}
HOSTNAME=${HOSTNAME#http://}

##on workstation, make sure git init has been run
echo
echo
if [ ! -d ".git" ]; then
    echo "Initializing local git repository and committing all files..."
	git init &> /dev/null
	git add . &> /dev/null
	git commit -a -m "Initial commit" &> /dev/null
fi
echo "Setting up git deployment for the $1 environment of $APP_NAME"
ssh -t $SSH_OPT $SSH_HOST <<EOLENVSETUP
# Create necessary directories
echo "Creating directories..."
mkdir -p $APP_DIR
rm -rf $GIT_APP_DIR &> /dev/null
mkdir -p $GIT_APP_DIR/hooks
mkdir -p $WWW_APP_DIR
mkdir -p $LOG_DIR
mkdir -p $BUNDLE_DIR
# Init the bare git repo
echo "Setting up the bare git repository on the EC2 server..."
cd $GIT_APP_DIR
git init --bare &> /dev/null
# Create the post-receive hook file and set its permissions; we'll add its contents in a bit
touch hooks/post-receive
sudo chmod +x hooks/post-receive
# Create/update the JSON file for this environment used by nodeproxy.js
echo "Updating hostname mapping for nodeproxy..."
cd $NODEPROXY_DIR
cat > $APP_NAME.$1.json <<EOLJSONDOC
{"$HOSTNAME": "127.0.0.1:$PORT"}
EOLJSONDOC
# Start/restart nodeproxy.js using forever so that hostname/IP updates are seen
echo "Starting or restarting nodeproxy..."
mkdir -p logs
sudo forever stop $NODEPROXY_DIR/nodeproxy.js &> /dev/null
sudo forever start -l $NODEPROXY_DIR/logs/forever.log -o $NODEPROXY_DIR/logs/out.log -e $NODEPROXY_DIR/logs/err.log -a -s $NODEPROXY_DIR/nodeproxy.js
EOLENVSETUP
echo "Creating the post-receive script and sending it to the EC2 server..."
cat > tmp-post-receive <<ENDCAT
#!/bin/sh

# Clean up any directories that might exist already
if [ -d "$TMP_APP_DIR" ]; then
    sudo rm -rf $TMP_APP_DIR
fi

# Create the temporary directory where all the project files should be copied when git pushed
mkdir -p $TMP_APP_DIR

# Copy all the project files to the temporary directory
echo "Copying updated project files on the EC2 server..."
cd $GIT_APP_DIR
GIT_WORK_TREE="$TMP_APP_DIR" git checkout -f &> /dev/null

# Create the node bundle using the meteor/meteorite bundle command
echo "Creating node bundle on the EC2 server..."
cd $TMP_APP_DIR
# remove local directory if present to avoid potential permission issues
if [ -d "$TMP_APP_DIR/.meteor/local" ]; then
    sudo rm -r .meteor/local
fi
# bundle
mrt bundle bundle.tgz

# Extract the bundle into the BUNDLE_DIR, and then delete the .tgz file
echo "Extracting node bundle on the EC2 server..."
tar -zxvf bundle.tgz &> /dev/null
sudo rm -f bundle.tgz &> /dev/null

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Meteor bundle command failed!"
    sudo rm -rf $TMP_APP_DIR
    exit 1
fi

# Reinstall fibers
# (http://stackoverflow.com/questions/13327088/meteor-bundle-fails-because-fibers-node-is-missing)
echo "Reinstalling fibers in the node bundle on the EC2 server..."
cd $BUNDLE_DIR/server
npm uninstall fibers &> /dev/null
npm install fibers &> /dev/null

# Copy the extracted and tweaked node application to the WWW_APP_DIR
cp -R $BUNDLE_DIR/* $WWW_APP_DIR

# Clean up any directories that we created
if [ -d "$TMP_APP_DIR" ]; then
    sudo rm -rf $TMP_APP_DIR
fi

# Try to stop the node app using forever, in case it's already running
echo "Starting or restarting this app environment on the EC2 server..."
cd $WWW_APP_DIR
sudo forever stop $WWW_APP_DIR/main.js &> /dev/null

# Start the node app using forever
sudo PORT=$PORT ROOT_URL=$ROOT_URL${MONGO_URL_SETTER}${MAIL_URL_SETTER} forever start -l $LOG_DIR/forever.log -o $LOG_DIR/out.log -e $LOG_DIR/err.log -a -s $WWW_APP_DIR/main.js &> /dev/null
ENDCAT
# Secure copy the post-receive script we just created, and then delete it
scp $SSH_OPT tmp-post-receive $SSH_HOST:$GIT_APP_DIR/hooks/post-receive &> /dev/null
rm tmp-post-receive &> /dev/null
echo "Defining this environment as a local git remote..."
# Make sure SSH knows about the EC2 key file for pushing
ssh-add $EC2_PEM_FILE &> /dev/null
# Set up the environment remote
git remote rm $1 &> /dev/null
git remote add $1 ssh://$SSH_HOST$GIT_APP_DIR
echo
echo "Done! Enter the following command now and whenever you have committed changes you want to deploy to the $1 environment:"
echo "   git push $1 master"
echo