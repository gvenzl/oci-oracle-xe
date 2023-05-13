#
# Since: September, 2021
# Author: gvenzl
# Name: Dockerfile.2130
# Description: Dockerfile to build Oracle DB XE 21.3.0
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

FROM oraclelinux:8-slim as builder

ARG BUILD_MODE

ENV ORACLE_BASE=/opt/oracle \
    ORACLE_BASE_CONFIG=/opt/oracle \
    ORACLE_BASE_HOME=/opt/oracle/homes/OraDBHome21cXE \
    ORACLE_HOME=/opt/oracle/product/21c/dbhomeXE \
    ORACLE_SID=XE \
    PATH=${PATH}:/opt/oracle/product/21c/dbhomeXE/bin:/opt/oracle \
    NLS_LANG=.AL32UTF8

COPY oracle-database-xe-21c-1.0-1.ol8.x86_64.rpm install.2130.sh container-entrypoint.sh resetPassword createAppUser healthcheck.sh /install/

RUN /install/install.2130.sh "${BUILD_MODE}"

##########################################################################################
### Layer 1 --> Core OS
##########################################################################################

FROM scratch as os_layer

# Redefine environment variables, etc. as we copied everything from an empty image (scratch)
ENV ORACLE_BASE=/opt/oracle \
    ORACLE_BASE_CONFIG=/opt/oracle \
    ORACLE_BASE_HOME=/opt/oracle/homes/OraDBHome21cXE \
    ORACLE_HOME=/opt/oracle/product/21c/dbhomeXE \
    ORACLE_SID=XE \
    PATH=${PATH}:/opt/oracle/product/21c/dbhomeXE/bin:/opt/oracle \
    NLS_LANG=.AL32UTF8

COPY --from=builder / /
RUN rm -rf "${ORACLE_BASE}"

##########################################################################################
### Layer 2 --> Oracle Home without bin/oracle, lib, rdbms, and "${ORACLE_SID}".7z
##########################################################################################

FROM os_layer as oracle_home

COPY --from=builder --chown=oracle:oinstall "${ORACLE_BASE}" "${ORACLE_BASE}"

RUN rm    "${ORACLE_HOME}"/bin/oracle
RUN rm -r "${ORACLE_HOME}"/lib
RUN rm -r "${ORACLE_HOME}"/rdbms
RUN rm    "${ORACLE_BASE}"/"${ORACLE_SID}".7z


##########################################################################################
### Layer 3 --> Oracle binary (bin/oracle)
##########################################################################################

FROM oracle_home as oracle_binary

COPY --from=builder --chown=oracle:oinstall "${ORACLE_HOME}"/bin/oracle "${ORACLE_HOME}"/bin/oracle

##########################################################################################
### Layer 4 --> Oracle lib
##########################################################################################

FROM oracle_binary as oracle_lib

COPY --from=builder --chown=oracle:oinstall "${ORACLE_HOME}"/lib "${ORACLE_HOME}"/lib

##########################################################################################
### Layer 5 --> Oracle lib
##########################################################################################

FROM oracle_lib as oracle_rdbms

COPY --from=builder --chown=oracle:oinstall "${ORACLE_HOME}"/rdbms "${ORACLE_HOME}"/rdbms

##########################################################################################
### Layer 6 --> Oracle (compressed) db files
##########################################################################################

FROM oracle_rdbms as db_files

COPY --from=builder --chown=oracle:oinstall "${ORACLE_BASE}"/"${ORACLE_SID}".7z  "${ORACLE_BASE}"/

LABEL org.opencontainers.image.source https://github.com/gvenzl/oci-oracle-xe

USER oracle
WORKDIR ${ORACLE_BASE}

HEALTHCHECK CMD "${ORACLE_BASE}"/healthcheck.sh >/dev/null || exit 1

ENTRYPOINT ["container-entrypoint.sh"]
