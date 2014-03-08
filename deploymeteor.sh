#!/bin/bash

HOME_DIR=/home/ec2-user
NODEPROXY_DIR=$HOME_DIR/nodeproxy
PWD=`pwd`
SCRIPTPATH="$HOME/.deploymeteor"
APPS_DIR=$HOME_DIR/meteorapps
APP_NAME=${PWD##*/}

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
    cd $HOME_DIR
    echo "Installing prerequisites..."
    sudo yum install -q -y gcc gcc-c++ make git openssl-devel freetype-devel fontconfig-devel &> /dev/null

    #install node
    echo "Installing Node and NPM..."
    sudo yum install -q -y npm --enablerepo=epel &> /dev/null

    #install nvm
    echo "Installing or updating NVM..."
    sudo -H npm install -g nvm &> /dev/null
    
    #install forever
    echo "Installing or updating Forever..."
    sudo -H npm install -g forever &> /dev/null

    #install meteor
    echo "Installing or updating Meteor..."
    curl https://install.meteor.com | /bin/sh

    #install meteorite
    echo "Installing or updating Meteorite..."
    sudo -H npm install -g meteorite &> /dev/null

    #install http-proxy
    echo "Installing or updating http-proxy..."
    mkdir -p $NODEPROXY_DIR
    cd $NODEPROXY_DIR
    npm install http-proxy &> /dev/null

    #add nvm node versions to path
    if grep -q "./node_modules/.bin" <<< "$PATH" ; then
        echo "./node_modules/.bin found in PATH"
    else
        echo "./node_modules/.bin not found in PATH. Adding it to PATH."
        export PATH=./node_modules/.bin:$PATH
    fi
    if grep -q "./node_modules/.bin" ~/.bashrc ; then
        echo "./node_modules/.bin found in ~/.bashrc"
    else
        echo "./node_modules/.bin not found in ~/.bashrc. Adding it in ~/.bashrc."
        echo "export PATH=./node_modules/.bin:$PATH" >> ~/.bashrc
    fi
EOL
    # Copy nodeproxy.js from script directory to server
    # We don't need to start it until an environment has been deployed
    echo "Copying nodeproxy.js to the server..."
    scp $SSH_OPT $SCRIPTPATH/nodeproxy.js $SSH_HOST:$NODEPROXY_DIR &> /dev/null
    echo "Done!"
    exit 1
    ;;
logs)
    if [ -z "$2" ]; then
        echo
        echo "Usage: deploymeteor logs <environment> or deploymeteor logs all"
        exit 1;
    fi
    if [ $2 = "all" ]; then
        ssh -t $SSH_OPT $SSH_HOST <<EOL5
        for dir in \$(find "$APPS_DIR" -type d -maxdepth 3 -iname "logs")
        do
          echo
          echo
          echo "********* LOGS FOR \$dir *********"
          echo
          echo "*** Error Log ***"
          cat "\$dir/err.log"
          echo
          echo "*** Out Log ***"
          cat "\$dir/out.log"
          echo
          echo "*** Forever Log ***"
          cat "\$dir/forever.log"
          echo
          echo
        done
EOL5
    else
        LOG_DIR=$APPS_DIR/$APP_NAME/$2/logs
        ssh -t $SSH_OPT $SSH_HOST <<EOL2
        echo
        echo "*** Error Log ***"
        cat $LOG_DIR/err.log
        echo
        echo "*** Out Log ***"
        cat $LOG_DIR/out.log
        echo
        echo "*** Forever Log ***"
        cat $LOG_DIR/forever.log
        echo
EOL2
    fi
    exit 1
    ;;
clearlogs)
    if [ -z "$2" ]; then
        echo
        echo "Usage: deploymeteor clearlogs <environment> or deploymeteor clearlogs all"
        exit 1;
    fi
    if [ $2 = "all" ]; then
        ssh -t $SSH_OPT $SSH_HOST <<EOL6
        echo "Clearing all logs..."
        for dir in \$(find "$APPS_DIR" -type d -maxdepth 3 -iname "logs")
        do
          echo "Clearing logs in \$dir..."
          sudo rm "\$dir/err.log"
          sudo touch "\$dir/err.log"
          sudo rm "\$dir/out.log"
          sudo touch "\$dir/out.log"
          sudo rm "\$dir/forever.log"
          sudo touch "\$dir/forever.log"
        done
EOL6
    else
        LOG_DIR=$APPS_DIR/$APP_NAME/$2/logs
        ssh -t $SSH_OPT $SSH_HOST <<EOL2
        echo "Clearing err.log..."
        sudo rm $LOG_DIR/err.log
        sudo touch $LOG_DIR/err.log
        echo "Clearing out.log..."
        sudo rm $LOG_DIR/out.log
        sudo touch $LOG_DIR/out.log
        echo "Clearing forever.log..."
        sudo rm $LOG_DIR/forever.log
        sudo touch $LOG_DIR/forever.log
EOL2
    fi
    exit 1
    ;;
restartproxy)
    echo "Restarting nodeproxy..."
    ssh -t $SSH_OPT $SSH_HOST <<EOL3
    sudo forever stop $NODEPROXY_DIR/nodeproxy.js &> /dev/null
    sudo forever start -l $NODEPROXY_DIR/logs/forever.log -o $NODEPROXY_DIR/logs/out.log -e $NODEPROXY_DIR/logs/err.log -a -s $NODEPROXY_DIR/nodeproxy.js
EOL3
    echo "Done!"
    exit 1
    ;;
restart)
    if [ -z "$2" ]; then
        echo
        echo "Usage: deploymeteor restart <environment> or deploymeteor restart all"
        exit 1;
    fi
    if [ $2 = "all" ]; then
        ssh -t $SSH_OPT $SSH_HOST <<EOL8
        echo "Restarting all app environments..."
        for file in \$(find "$APPS_DIR" -type f -maxdepth 3 -iname "restartapp")
        do
            \$file
        done
        echo "Restarting nodeproxy..."
        sudo forever stop $NODEPROXY_DIR/nodeproxy.js &> /dev/null
        sudo forever start -l $NODEPROXY_DIR/logs/forever.log -o $NODEPROXY_DIR/logs/out.log -e $NODEPROXY_DIR/logs/err.log -a -s $NODEPROXY_DIR/nodeproxy.js &> /dev/null
        echo "Done"
EOL8
    else
        ssh -t $SSH_OPT $SSH_HOST <<EOL4
        if [ -r "$APPS_DIR/$APP_NAME/$2/restartapp" ]; then
            $APPS_DIR/$APP_NAME/$2/restartapp
            echo "Done!"
        else
            echo "You must run deploymeteor $2 first!"
        fi
EOL4
    fi
    exit 1
    ;;
stop)
    if [ -z "$2" ]; then
        echo
        echo "Usage: deploymeteor stop <environment>"
        exit 1;
    fi
    ssh -t $SSH_OPT $SSH_HOST <<EOL7
    sudo forever stop $APPS_DIR/$APP_NAME/$2/www/main.js &> /dev/null
EOL7
    echo "Stopped the $2 environment of $APP_NAME"
    exit 1
    ;;
esac

####The rest is run only for setting up git deployment####
APP_DIR=$APPS_DIR/$APP_NAME/$1

#If this has been run before, grab variable defaults from stored config file
if [ -r "$SCRIPTPATH/.settings.$APP_NAME.$1" ]; then
source "$SCRIPTPATH/.settings.$APP_NAME.$1"
fi

#Defaults
DEFAULT_ROOT_URL=${DEFAULT_ROOT_URL:-http://$APP_HOST}
DEFAULT_PORT=${DEFAULT_PORT:-8000}
DEFAULT_NODE_VERSION=${DEFAULT_NODE_VERSION:-v0.10.26}

#Prompt for additional app-specific info that is needed
echo
echo "Enter the version of NodeJS that you want to use."
echo "Example: v0.10.26"
echo "Default (press ENTER): $DEFAULT_NODE_VERSION"
echo
read -e -p "NodeJS Version: " NODE_VERSION
NODE_VERSION=${NODE_VERSION:-$DEFAULT_NODE_VERSION}
echo
echo "Enter the root URL for this website, as users should access it, including protocol."
echo "Examples: http://mysite.com or https://mysite.com"
echo "Default (press ENTER): $DEFAULT_ROOT_URL"
echo
read -e -p "Root URL: " ROOT_URL
ROOT_URL=${ROOT_URL:-$DEFAULT_ROOT_URL}
echo
echo "Enter the port on which to host this website. Do not enter 80 because a proxy server is automatically launched on that port."
echo "Examples: 8080 or 3001"
echo "Default (press ENTER): $DEFAULT_PORT"
echo
read -e -p "Port: " PORT
PORT=${PORT:-$DEFAULT_PORT}
echo
echo "Enter the URL for the MongoDB database used by this app."
echo "Format: mongodb://<username>:<password>@<ip or hostname>:<port>/<dbname>"
echo "Default (press ENTER): $DEFAULT_MONGO_URL"
read -e -p "MongoDB URL: " MONGO_URL
MONGO_URL=${MONGO_URL:-$DEFAULT_MONGO_URL}
echo
echo
echo "Enter the SMTP URL for e-mail sending by this app."
echo "Format: smtp://<username>:<password>@<ip or hostname>:<port>"
echo "Default (press ENTER): $DEFAULT_MAIL_URL"
read -e -p "E-mail URL: " MAIL_URL
MAIL_URL=${MAIL_URL:-$DEFAULT_MAIL_URL}
echo
echo
echo "Enter the local path to a settings JSON file for this app environment."
echo "Format: /path/to/settings.json"
echo "Default (press ENTER): $DEFAULT_SETTINGS_FILE"
read -e -p "Settings file path: " SETTINGS_FILE
SETTINGS_FILE=${SETTINGS_FILE:-$DEFAULT_SETTINGS_FILE}
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

if [ -z "$SETTINGS_FILE" ]; then
    SETTINGS_SETTER=""
else
    SETTINGS_SETTER=" METEOR_SETTINGS=\$(cat $APP_DIR/settings.json)"
fi

#store answers to use as defaults the next time deploymeteor is run
if [ -r "$SCRIPTPATH/.settings.$APP_NAME.$1" ]; then
    cat > $SCRIPTPATH/.settings.$APP_NAME.$1 <<ENDCAT1
    DEFAULT_ROOT_URL=$ROOT_URL
    DEFAULT_PORT=$PORT
    DEFAULT_MONGO_URL=$MONGO_URL
    DEFAULT_MAIL_URL=$MAIL_URL
    DEFAULT_SETTINGS_FILE=$SETTINGS_FILE
    DEFAULT_NODE_VERSION=$NODE_VERSION
ENDCAT1
else
    echo
    echo "Save these settings in the current user account on this machine?"
    echo "Everything, including passwords, will be stored in plain text, but"
    echo "the file is only readable by $(whoami). Enter YES to save them."
    read -e -p "Save settings? " SHOULD_SAVE
    echo
    if [ $SHOULD_SAVE = "YES" ] || [ $SHOULD_SAVE = "yes" ]; then
        cat > $SCRIPTPATH/.settings.$APP_NAME.$1 <<ENDCAT2
        DEFAULT_ROOT_URL=$ROOT_URL
        DEFAULT_PORT=$PORT
        DEFAULT_MONGO_URL=$MONGO_URL
        DEFAULT_MAIL_URL=$MAIL_URL
        DEFAULT_SETTINGS_FILE=$SETTINGS_FILE
        DEFAULT_NODE_VERSION=$NODE_VERSION
ENDCAT2
        chmod 600 $SCRIPTPATH/.settings.$APP_NAME.$1
    fi
fi

##set up variables
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

cd $TMP_APP_DIR

# Create the node bundle using the meteor/meteorite bundle command
echo "Creating node bundle on the EC2 server..."
# remove local directory if present to avoid potential permission issues
if [ -d "$TMP_APP_DIR/.meteor/local" ]; then
    sudo rm -r .meteor/local
fi
# bundle
(unset GIT_DIR; mrt update --repoPort=80)
# Why unset? https://github.com/oortcloud/meteorite/pull/165
meteor bundle bundle.tgz

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
if [ -d "$BUNDLE_DIR/programs/server" ]; then
    cd $BUNDLE_DIR/programs/server
    sudo rm -rf node_modules/fibers
    npm uninstall fibers &> /dev/null
    npm install fibers &> /dev/null
fi

if [ -d "$BUNDLE_DIR/server" ]; then
    cd $BUNDLE_DIR/server
    sudo rm -rf node_modules/fibers
    npm uninstall fibers &> /dev/null
    npm install fibers &> /dev/null
fi

# Copy the extracted and tweaked node application to the WWW_APP_DIR
cp -R $BUNDLE_DIR/* $WWW_APP_DIR

# Clean up any directories that we created
if [ -d "$TMP_APP_DIR" ]; then
    sudo rm -rf $TMP_APP_DIR
fi

cd $WWW_APP_DIR

# Use NVM to install and use correct version of node
echo "Installing and using correct NodeJS version..."
nvm install $NODE_VERSION &> /dev/null
nvm use $NODE_VERSION &> /dev/null
sudo ln -sf ~/.nvm/$NODE_VERSION/bin/node /usr/bin/node &> /dev/null
sudo ln -sf ~/.nvm/$NODE_VERSION/bin/node /usr/local/bin/node &> /dev/null

# Try to stop the node app using forever, in case it's already running
echo "Starting or restarting the $1 environment of $APP_NAME on the EC2 server..."
sudo forever stop $WWW_APP_DIR/main.js &> /dev/null

# Start the node app using forever
export PORT=$PORT ROOT_URL=$ROOT_URL${MONGO_URL_SETTER}${MAIL_URL_SETTER}${SETTINGS_SETTER}
sudo -E forever start -l $LOG_DIR/forever.log -o $LOG_DIR/out.log -e $LOG_DIR/err.log -a -s $WWW_APP_DIR/main.js &> /dev/null
ENDCAT
# Secure copy the post-receive script we just created, and then delete it
scp $SSH_OPT tmp-post-receive $SSH_HOST:$GIT_APP_DIR/hooks/post-receive &> /dev/null
rm tmp-post-receive &> /dev/null

echo "Creating the restart script and sending it to the EC2 server..."
touch tmp-restartapp
chmod
cat > tmp-restartapp <<ENDCAT5
#!/bin/sh

# Use NVM to install and use correct version of node
echo "Installing and using correct NodeJS version..."
nvm install $NODE_VERSION &> /dev/null
nvm use $NODE_VERSION &> /dev/null
sudo ln -sf ~/.nvm/$NODE_VERSION/bin/node /usr/bin/node &> /dev/null
sudo ln -sf ~/.nvm/$NODE_VERSION/bin/node /usr/local/bin/node &> /dev/null

# Try to stop the node app using forever, in case it's already running
echo "Starting or restarting this app environment on the EC2 server..."
cd $WWW_APP_DIR
sudo forever stop $WWW_APP_DIR/main.js &> /dev/null

# Start the node app using forever
export PORT=$PORT ROOT_URL=$ROOT_URL${MONGO_URL_SETTER}${MAIL_URL_SETTER}${SETTINGS_SETTER}
sudo -E forever start -l $LOG_DIR/forever.log -o $LOG_DIR/out.log -e $LOG_DIR/err.log -a -s $WWW_APP_DIR/main.js &> /dev/null
ENDCAT5
# Secure copy the restartapp script we just created
scp $SSH_OPT tmp-restartapp $SSH_HOST:$APP_DIR/restartapp &> /dev/null
# Then make it executable
ssh -t $SSH_OPT $SSH_HOST <<ENDCAT6
chmod 700 $APP_DIR/restartapp &> /dev/null
ENDCAT6
# Then delete the local file
rm tmp-restartapp &> /dev/null

# Secure copy the settings file
if [ -r "$SETTINGS_FILE" ]; then
    echo "Copying environment settings to the EC2 server..."
    scp $SSH_OPT $SETTINGS_FILE $SSH_HOST:$APP_DIR/settings.json &> /dev/null
fi

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