#!/bin/bash

# Purpose: EMR bootstrap script that installs Superset
# Author:  Gary A. Stafford (December 2020)
# Reference: https://superset.apache.org/docs/installation/installing-superset-from-scratch

# choose an open port for superset
SUPERSET_WEBSERVER_PORT=8280

# update and install required packages
sudo yum -y update
sudo yum -y install jq gcc gcc-c++ libffi-devel python-devel python-pip python-wheel \
  openssl-devel cyrus-sasl-devel openldap-devel boto3 ec2-metadata awswrangler
sudo yum -y install python3-devel.x86_64 # will get errors installing superset without this extra step

# install required Python package
sudo -u hadoop -i bash -c "python3 -m pip install --user --upgrade setuptools pip virtualenv"

sudo -u hadoop -i bash -c "python3 -m venv venv"
sudo -u hadoop -i bash -c ". venv/bin/activate"

# install and upgrade superset
sudo -u hadoop -i bash -c "python3 -m pip install apache-superset"
sudo -u hadoop -i bash -c "superset db upgrade"

# install a few db drivers: Amazon Athena, RedShift, Spark SQL/Presto, PostgreSQL, MySQL
# https://superset.apache.org/docs/databases/installing-database-drivers
sudo -u hadoop -i bash -c "python3 -m pip install PyAthenaJDBC>1.0.9 PyAthena>1.2.0 sqlalchemy-redshift pyhive mysqlclient"

sudo -u hadoop -i bash -c "echo \"export FLASK_APP=superset\" >> ~/.bashrc"

PYTHON_DIR="$(ls ~/venv/lib/ | head 1)" # should only be one dir in there
sudo -u hadoop -i bash -c "echo \"export SUPERSET_HOME=~/venv/lib/${PYTHON_DIR}/site-packages/superset/\" >> ~/.bashrc"

# enabling logging
# e.g. location: /home/hadoop/venv/lib64/python3.7/site-packages/superset/superset.log
sudo -u hadoop -i bash -c "touch superset_config.py"
sudo -u hadoop -i bash -c """
  echo \"ENABLE_TIME_ROTATE = True\" >> \"\~/venv/lib/${PYTHON_DIR}/site-packages/superset/superset_config.py\""""
sudo -u hadoop -i bash -c "echo \"export SUPERSET_CONFIG_PATH=~/superset_config.py\" >> ~/.bashrc"

ADMIN_USERNAME="SupersetAdmin"
ADMIN_PASSWORD="Admin1234"

# create superset admin
sudo -u hadoop -i bash -c """
  superset fab create-admin \
    --username ${ADMIN_USERNAME} \
    --firstname Superset \
    --lastname Admin \
    --email superset_admin@example.com \
    --password ${ADMIN_PASSWORD}"""

# load example datasets
sudo -u hadoop -i bash -c "superset load_examples"
sudo -u hadoop -i bash -c "superset init"

# create two sample superset users
sudo -u hadoop -i bash -c """
  superset fab create-user \
    --role Alpha \
    --username SupersetUserAlpha \
    --firstname Superset \
    --lastname UserAlpha \
    --email superset_user_alpha@example.com \
    --password UserAlpha1234"""

sudo -u hadoop -i bash -c """
  superset fab create-user \
    --role Gamma \
    --username SupersetUserGamma \
    --firstname Superset \
    --lastname UserGamma \
    --email superset_user_gamma@example.com \
    --password UserGamma1234"""

# get instance id
INSTANCE_ID="$(curl --silent http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .instanceId)"

# use instance id to get public dns of master node
PUBLIC_MASTER_DNS="$(aws ec2 describe-instances --instance-id ${INSTANCE_ID} | jq -r '.Reservations[0].Instances[0].PublicDnsName')"

# start superset in background
sudo -u hadoop -i bash -c """
  nohup superset run \
    --host ${PUBLIC_MASTER_DNS} \
    --port ${SUPERSET_WEBSERVER_PORT} \
    --with-threads --reload --debugger \
    >superset_output.log 2>&1 </dev/null &"""

# output key info
sudo -u hadoop -i bash -c "echo \"Apache Superset UI URL: http://${PUBLIC_MASTER_DNS}:${SUPERSET_WEBSERVER_PORT}\""
sudo -u hadoop -i bash -c "echo \"Superset Admin Username: ${ADMIN_USERNAME}, Password: ${ADMIN_PASSWORD}\""

# set aws region for boto3
sudo -u hadoop -i bash -c """
  aws configure set region \"$(curl --silent http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)\""""