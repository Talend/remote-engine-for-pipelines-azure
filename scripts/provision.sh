#!/usr/bin/env bash

set -e
set -u

# Prepare library
sudo yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2

# Add docker repo
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

sudo yum -y install zip bind-utils

# Install epel release
sudo yum install -y epel-release

DOCKER_VERSION="18.03.0"
DOCKER_COMPOSE_VERSION="1.20.1"
TALEND_DIR="/opt/talend"
USER_ID=61000
APP_USERNAME="talend"
REGION=${1}
PRE_AUTHORIZED_KEY=${2}

# Install python deps and docker
sudo yum install -y python-pip
sudo yum install -y docker-ce-${DOCKER_VERSION}.ce
sudo pip install docker-compose==${DOCKER_COMPOSE_VERSION}

sudo useradd  --create-home --home $TALEND_DIR -s /bin/bash -u $USER_ID --user-group $APP_USERNAME

# Check if this is a problem at all - the current user should be able to
sudo chmod 777 $TALEND_DIR

sudo gpasswd --add talend docker

sudo systemctl enable docker
sudo systemctl start docker


cd ${TALEND_DIR}

curl -O https://re4pstorageprodus.blob.core.windows.net/archives/pipeline-remote-engine.tar.gz
tar xvf pipeline-remote-engine.tar.gz
cd pipeline-remote-engine

# We export them otherwise they are not visible in the system service creation
export PIPELINE_REMOTE_ENGINE_DIR=$TALEND_DIR/pipeline-remote-engine
export APP_USERNAME=${APP_USERNAME}

touch ${PIPELINE_REMOTE_ENGINE_DIR}/services.env

ENVIRONMENT_ENDPOINT="https://pair.${REGION}.cloud.talend.com"
APPLICATION_WEBSOCKET_HOST="engine.${REGION}.cloud.talend.com"
VAULT_ADDR="https://vault-gateway.${REGION}.cloud.talend.com"

# the remote engine archive doesn't have a newline at the end...
echo '' >> ${PIPELINE_REMOTE_ENGINE_DIR}/.env
echo ENVIRONMENT_ENDPOINT=${ENVIRONMENT_ENDPOINT} >> ${PIPELINE_REMOTE_ENGINE_DIR}/.env
echo APPLICATION_WEBSOCKET_HOST=${APPLICATION_WEBSOCKET_HOST} >> ${PIPELINE_REMOTE_ENGINE_DIR}/.env
echo VAULT_ADDR=${VAULT_ADDR} >> ${PIPELINE_REMOTE_ENGINE_DIR}/.env

# ---- Service related part ---- #

# those are for the system service
echo PRE_AUTHORIZED_KEY=${PRE_AUTHORIZED_KEY} >> ${PIPELINE_REMOTE_ENGINE_DIR}/services.env
echo TALEND_DIR=${PIPELINE_REMOTE_ENGINE_DIR} >> ${PIPELINE_REMOTE_ENGINE_DIR}/services.env

sudo -Eu root bash -c 'cat > /etc/systemd/system/remote-engine-for-pipelines.service <<EOF
[Unit]
Description=Talend Remote Engine for Pipelines Client Services
After=docker.service
[Service]
Type=idle
User=${APP_USERNAME}
EnvironmentFile=${PIPELINE_REMOTE_ENGINE_DIR}/services.env
WorkingDirectory=${PIPELINE_REMOTE_ENGINE_DIR}
ExecStart=/usr/local/bin/remote-engine-for-pipelines.sh start
ExecStop=/usr/local/bin/remote-engine-for-pipelines.sh stop
RemainAfterExit=yes
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
'

curl -O https://raw.githubusercontent.com/Talend/remote-engine-for-pipelines-azure/master/scripts/remote-engine-for-pipelines.sh
sudo mv remote-engine-for-pipelines.sh /usr/local/bin
sudo chmod +x /usr/local/bin/remote-engine-for-pipelines.sh
sudo systemctl enable remote-engine-for-pipelines.service
sudo chown -R talend:talend /opt/talend
sudo chmod -R 770 $TALEND_DIR
sudo systemctl start remote-engine-for-pipelines.service
