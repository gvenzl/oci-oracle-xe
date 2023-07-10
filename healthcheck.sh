#!/bin/bash
# Since: January, 2021
# Author: gvenzl
# Name: healthcheck.sh
# Description: Checks the health of the database
#              Parameter 1: the PDB name to check for (18c and onwards only)
#
# Copyright 2021 Gerald Venzl
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

# Check DB version
ORACLE_VERSION=$(sqlplus -version | grep "Release" | awk '{ print $3 }')

# 11g doesn't have PDBs yet, so just check v\$instance
if [[ "${ORACLE_VERSION}" = "11.2"* ]]; then

  db_status=$(sqlplus -s / << EOF
     set heading off;
     set pagesize 0;
     SELECT 'READY'
       FROM v\$instance
         WHERE status = 'OPEN';
     exit;
EOF
  )

# 18c onwards
else
  #  Either the PDB passed on as \$ORACLE_DATABASE or the default "XEPDB1"
  DATABASE=${1:-${ORACLE_DATABASE:-XEPDB1}}

  db_status=$(sqlplus -s / << EOF
     set heading off;
     set pagesize 0;
     SELECT 'READY'
      FROM (
        SELECT name, open_mode
         FROM v\$pdbs
        UNION ALL
        SELECT name, open_mode
         FROM v\$database) dbs
       WHERE dbs.name = UPPER('${DATABASE}')
        AND dbs.open_mode = 'READ WRITE';
     exit;
EOF
  )
fi;

if [ "${db_status}" == "READY" ]; then
   exit 0;
else
   exit 1;
fi;
