#!/bin/bash
#
# Since: February, 2023
# Author: loiclefevre
# Name: setup-columnar-store.sh
# Description: A script to configure the database with the In-Memory Columnar Store.
# Documentation:
# - 21c: https://docs.oracle.com/en/database/oracle/oracle-database/21/inmem/intro-to-in-memory-column-store.html
# - 18c: https://docs.oracle.com/en/database/oracle/oracle-database/18/inmem/intro-to-in-memory-column-store.html
#
# Copyright 2023 Loïc Lefèvre
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

sqlplus -s / as sysdba <<EOF
   -- Exit on any errors
   WHENEVER SQLERROR EXIT SQL.SQLCODE

   -- Reconfigure SGA and PGA to enable the maximum memory for analytics workload.
   ALTER SYSTEM SET SGA_TARGET=1568M SCOPE=SPFILE;
   ALTER SYSTEM SET PGA_AGGREGATE_TARGET=412M SCOPE=SPFILE;
   
   -- Configure the size of the In-Memory Columnar Store to 1 GiB.
   ALTER SYSTEM SET INMEMORY_SIZE=1G SCOPE=SPFILE;
   
   SHUTDOWN IMMEDIATE;
   STARTUP;

   exit;
EOF

echo "Database is now configured with the In-Memory Columnar Store (size = 1 GiB)."
