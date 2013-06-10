#!/bin/bash

if [ -z "$1" ]; then
	echo
	echo "Usage: deploymeteor <environment>"
	echo "For example, type deploymeteor staging to deploy to a staging environment. This environment will be created and initialized on the remote server and added as a remote repository for this git repository."
	echo
	echo "Before the first time you use deploymeteor with a new server, you should also run deploymeteor prepserver. This will install node, npm, meteor, forever, and meteorite on the server."
	exit 1
fi

HOME_DIR=/home/ec2-user

PREP="
sudo yum install gcc-c++ make;
sudo yum install openssl-devel;
sudo yum install git;
cd $HOME_DIR;
git clone git://github.com/joyent/node.git;
cd node;
git checkout v0.10.10;
./configure;
make;
sudo make install;
cd ..;
sudo -H npm install -g forever;
curl https://install.meteor.com | /bin/sh;
sudo -H npm install -g meteorite;
"

#Eventually should make prepserver upgrade them if they're already installed
#This is how you upgrade node:
#sudo npm cache clean -f
#sudo npm install -g n
#sudo n stable

#If this has been run before, grab variable defaults from stored config file
PWD=`pwd`
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

cat > $PWD/.deploymeteor.config <<ENDCAT
LAST_APP_HOST=$APP_HOST
LAST_EC2_PEM_FILE=$EC2_PEM_FILE
ENDCAT

SSH_HOST="ec2-user@$APP_HOST"
SSH_OPT="-i $EC2_PEM_FILE"

case "$1" in
prepserver)
	echo
	echo "Preparing server…"
	ssh -t $SSH_OPT $SSH_HOST $PREP
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

GIT_APP_DIR=$APPS_DIR/$APP_NAME/git
WWW_APP_DIR=$APPS_DIR/$APP_NAME/www
LOG_DIR=$APPS_DIR/$APP_NAME/logs
BUNDLE_DIR=$APPS_DIR/$APP_NAME/bundle
ROOT_URL=http://$APP_HOST

ENVSETUP="
mkdir -p $APPS_DIR/$APP_NAME;
rm -rf $GIT_APP_DIR;
mkdir -p $GIT_APP_DIR/hooks;
mkdir -p $WWW_APP_DIR;
mkdir -p $LOG_DIR;
mkdir -p $BUNDLE_DIR;
cd $GIT_APP_DIR;
git init --bare;
touch hooks/post-receive;
sudo chmod +x hooks/post-receive;
"

##on workstation, make sure git init has been run
if [ ! -d ".git" ]; then
	git init
	git add .
	git commit -a -m "Initial commit"
fi

echo
echo
echo "Setting up git deployment for the $1 environment of $APP_NAME"
ssh -t $SSH_OPT $SSH_HOST $ENVSETUP
cat > tmp-post-receive <<ENDCAT
#!/bin/sh
GIT_WORK_TREE=$WWW_APP_DIR git checkout -f
cd $WWW_APP_DIR
mrt bundle $APPS_DIR/$APP_NAME/bundle.tgz
cd $APPS_DIR/$APP_NAME
tar -zxvf bundle.tgz
rm bundle.tgz
#rebuild fibers
cd $BUNDLE_DIR/server/node_modules
rm -r fibers
npm install fibers@1.0.0
#set up variables
cd $BUNDLE_DIR
sudo PORT=$PORT ROOT_URL="$ROOT_URL" MONGO_URL="$MONGO_URL" MAIL_URL="$MAIL_URL" forever start -l $LOG_DIR/forever.log -o $LOG_DIR/out.log -e $LOG_DIR/err.log -a main.js
ENDCAT
scp $SSH_OPT tmp-post-receive $SSH_HOST:$GIT_APP_DIR/hooks/post-receive
rm tmp-post-receive
ssh-add $EC2_PEM_FILE
git remote rm $1
git remote add $1 ssh://$SSH_HOST$GIT_APP_DIR
git push $1 master
echo
echo
echo
echo "Done! Now simply make and commit your changes and then redeploy as necessary with git push $1"
echo