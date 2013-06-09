#!/bin/bash

if [ -z "$1" ]; then
	echo "Usage: deploymeteor <environment>"
	echo "For example, type deploymeteor staging to deploy to a staging environment. This environment will be created and initialized on the remote server and added as a remote repository for this git repository."
	exit 1
fi

##make sure git init has been run
if [ ! -d ".git" ]; then
	git init
	git add .
	git commit -a -m "Initial commit"
fi

APP_NAME=${PWD##*/}

#prompt for needed info
read -e -p "Enter the hostname or IP address of the Amazon Linux EC2 server (e.g., 11.111.11.111 or ec2-11-111-11-111.us-west-2.compute.amazonaws.com): " APP_HOST
read -e -p "Enter the path to your EC2 .pem file on this machine: " EC2_PEM_FILE
read -e -p "Enter the root URL for this website, as users will access it, including protocol (e.g., http://mysite.com or https://mysite.com) (default: http://$APP_HOST): " ROOT_URL
ROOT_URL=${ROOT_URL:-http://$APP_HOST}
read -e -p "Enter the port on which to host this website: " PORT
PORT=${PORT:-80}
read -e -p "Enter the hostname or IP address of the server hosting your MongoDB database: " MONGO_HOST
MONGO_HOST=${MONGO_HOST:-localhost}
read -e -p "Enter the port through which your MongoDB database is accessible: " MONGO_PORT 
MONGO_PORT =${MONGO_PORT:-27017}
read -e -p "Enter the name of your MongoDB database: " MONGO_DBNAME
MONGO_DBNAME=${MONGO_DBNAME:$APP_NAME}
APP_DIR=/home/meteor
LOG_DIR=$APP_DIR/logs/$APP_NAME/
BUNDLE_DIR=$APP_DIR/bundles/$APP_NAME/
ROOT_URL=http://$APP_HOST
MONGO_URL=mongodb://$MONGO_HOST:$MONGO_PORT/MONGO_DBNAME
SSH_HOST="ec2-user@$APP_HOST" SSH_OPT="-i $EC2_PEM_FILE"

SETUP="
sudo yum install gcc-c++ make;
sudo yum install openssl-devel;
sudo yum install git;
git clone git://github.com/joyent/node.git;
cd node;
git checkout v0.10.10;
./configure;
make;
sudo make install;
sudo -H npm install -g forever;
curl https://install.meteor.com | /bin/sh;
sudo -H npm install -g meteorite;
mkdir -p $APP_DIR;
cd $APP_DIR;
mkdir -p bundles
mkdir -p logs
mkdir -p $APP_NAME.git;
cd $APP_NAME.git;
git init;
cat > hooks/post-receive <<ENDCAT
#!/bin/sh
mrt bundle ../bundles/$APP_NAME/bundle.tgz;
cd ../bundles/$APP_NAME/
tar -zxvf bundle.tgz;
export MONGO_URL=$MONGO_URL;
export ROOT_URL=$ROOT_URL;
export PORT=$PORT;
sudo forever start -l $LOG_DIR/forever.log -o $LOG_DIR/out.log -e $LOG_DIR/err.log bundle/main.js;
ENDCAT;
chmod +x hooks/post-receive;
"

ssh $SSH_OPT $SSH_HOST $SETUP;
git remote add $1 ssh://$SSH_HOST$APP_DIR/$APP_NAME.git;
git push $1 +master:refs/heads/master;
