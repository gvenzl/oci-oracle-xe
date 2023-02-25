#!/bin/bash
#
# Since: January, 2022
# Author: gvenzl
# Name: setup-tde.sh
# Description: A script to configure the database for Transparent Data Encryption in United Mode.
#
# Copyright 2022 Gerald Venzl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Exit on errors
# Great explanation on https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -Eeuo pipefail

RANDOM_KEYSTORE_PASSWORD=$(date +%s | sha256sum | base64 | head -c 8)

sqlplus -s / as sysdba <<EOF
   -- Exit on any errors
   WHENEVER SQLERROR EXIT SQL.SQLCODE

   -- Unfortunately TDE_CONFIGURATION cannot be set if this parameter is not yet active.
   -- Which means the database need to be restarted before setting TDE_CONFIGURATION.
   ALTER SYSTEM SET WALLET_ROOT='${ORACLE_BASE}/oradata/dbconfig/XE' SCOPE=SPFILE;

   SHUTDOWN IMMEDIATE;
   STARTUP;

   ALTER SYSTEM SET TDE_CONFIGURATION='KEYSTORE_CONFIGURATION=FILE';

   ADMINISTER KEY MANAGEMENT CREATE KEYSTORE
   IDENTIFIED BY ${RANDOM_KEYSTORE_PASSWORD};

   ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE
   FROM KEYSTORE
   IDENTIFIED BY ${RANDOM_KEYSTORE_PASSWORD};

   ADMINISTER KEY MANAGEMENT SET KEY
   FORCE KEYSTORE
   IDENTIFIED BY ${RANDOM_KEYSTORE_PASSWORD}
   WITH BACKUP
   CONTAINER=ALL;

   exit;
EOF

echo "Database is now configured for Transparent Data Encryption in United Mode."
