# Image details

Here you can find a full description of all changes that have been made to the Oracle Database and OS installation for the various image flavors.

## 21c XE

### Full image flavor (`21-full`)

The full image provides an Oracle Database XE installation "as is", meaning as provided by the RPM install file.
A couple of modifications have been performed to make the installation more suitable for running inside a container.

#### Database settings

* `DBMS_XDB.SETLISTENERLOCALACCESS(FALSE)`
* `ALTER SYSTEM SET CONTROL_MANAGEMENT_PACK_ACCESS='DIAGNOSTIC+TUNING'` (see https://github.com/gvenzl/oci-oracle-xe/issues/112)
* `ALTER SYSTEM SET AUDIT_TRAIL=NONE SCOPE=SPFILE;`
* `ALTER SYSTEM SET AUDIT_SYS_OPERATIONS=FALSE SCOPE=SPFILE;`
* `COMMON_USER_PREFIX=''`
* `LOCAL_LISTENER=''`
* `CPU_COUNT=2` (see https://github.com/gvenzl/oci-oracle-xe/issues/64 and https://github.com/gvenzl/oci-oracle-xe/pull/107)
* An `OPS$ORACLE` externally identified user has been created and granted `CONNECT` and `SELECT_CATALOG_ROLE` (this is used for health check and other operations)
* `ALTER SYSTEM SET SERVICE_NAMES=XE,FREE;` (Service `FREE` for instance `XE` to provide upward compatibility with `gvenzl/oracle-free`)
* A service `FREEPDB1` has been created for `XEPDB1` to provide upward compatibility with `gvenzl/oracle-free`
* `DISABLE_OOB=ON` in `sqlnet.ora` (see https://github.com/gvenzl/oci-oracle-xe/issues/43)
* `BREAK_POLL_SKIP=1000` in `sqlnet.ora` (see https://github.com/gvenzl/oci-oracle-xe/issues/43)
* `NLS_LANG=.AL32UTF8` set for `oracle` user to run client sessions on DB server in UTF-8 (see https://github.com/gvenzl/oci-oracle-xe/issues/109)

#### Operating system

* `/var/log/lastlog` has been cleaned

### Regular image flavor (`21`)

The regular image strives to balance between the functionality required by most users and image size. It has all customizations that the full image has and removes additional components to further decrease the image size:

#### Database components

* `Oracle Workspace Manager` has been removed
* `Oracle Database Java Packages` have been removed
* `Oracle Multimedia` has been removed (`$ORACLE_HOME/ord/im`)
* `Oracle XDK` has been removed (`$ORACLE_HOME/xdk`)
* `JServer JAVA Virtual Machine` has been removed (`$ORACLE_HOME/javavm`)
* `Oracle OLAP API` has been removed (`$ORACLE_HOME/olap`)
* `OLAP Analytic Workspace` has been removed
* `OPatch` utility has been removed (`$ORACLE_HOME/OPatch`)
* `QOpatch` utility has been removed (`$ORACLE_HOME/QOpatch`)
* `Oracle Database Assistants` have been removed (`$ORACLE_HOME/assistants`)
* The `inventory` directory has been removed (`$ORACLE_HOME/inventory`)
* `JDBC` drivers have been removed (`$ORACLE_HOME/jdbc`, `$ORACLE_HOME/jlib`)
* `Universal Connection Pool` driver has been removed (`$ORACLE_HOME/ucp`)
* `Intel Math Kernel` libraries have been removed (`$ORACLE_HOME/lib/libmkl_*`)
* Zip files in lib/ have been removed (`$ORACLE_HOME/lib/*.zip`)
* Jar files in lib/ have been removed (`$ORACLE_HOME/lib/*.jar`)
* Old timezone files have been removed (`$ORACLE_HOME/oracore/zoneinfo/*` except the current timezone file)
* Additional Java libraries have been removed (`$ORACLE_HOME/rdbms/jlib`)
* The `Cluster Ready Services` directory has been removed (`$ORACLE_HOME/crs`)
* The `Cluster Verification Utility` directory has been removed (`$ORACLE_HOME/cv`)
* The `install` directory has been emptied, except `orabasetab` (`$ORACLE_HOME/install`)
* The `network/jlib` directory has been removed (`$ORACLE_HOME/network/jlib`)
* The `network/tools` directory has been removed (`$ORACLE_HOME/network/tools`)
* The `Oracle Process Manager and Notification` directory has been removed (`$ORACLE_HOME/opmn`)
* The `Oracle Machine Learning 4 Python` directory has been removed (`$ORACLE_HOME/oml4py`)
* `Python` has been removed (`$ORACLE_HOME/python`)
* Replay Upgrade has been removed (`pdb_sync$` table cleaned up in `CDB$ROOT`)

##### Database binaries

The following binaries have been removed from the `$ORACLE_HOME/bin` directory:

* `$ORACLE_HOME/bin/acfs*`       (ACFS File system components)
* `$ORACLE_HOME/bin/adrci`       (Automatic Diagnostic Repository Command Interpreter)
* `$ORACLE_HOME/bin/agtctl`      (Multi-Threaded extproc agent control utility)
* `$ORACLE_HOME/bin/afd*`        (ASM Filter Drive components)
* `$ORACLE_HOME/bin/amdu`        (ASM Disk Utility)
* `$ORACLE_HOME/bin/dg4*`        (Database Gateway)
* `$ORACLE_HOME/bin/dgmgrl`      (Data Guard Manager CLI)
* `$ORACLE_HOME/bin/dbnest*`     (DataBase NEST)
* `$ORACLE_HOME/bin/orion`       (ORacle IO Numbers benchmark tool)
* `$ORACLE_HOME/bin/oms_daemon`  (Oracle Memory Speed (PMEM support) daemon)
* `$ORACLE_HOME/bin/omsfscmds`   (Oracle Memory Speed command line utility)
* `$ORACLE_HOME/bin/proc`        (Pro*C/C++ Precompiler)
* `$ORACLE_HOME/bin/procob`      (Pro COBOL Precompiler)
* `$ORACLE_HOME/bin/renamedg`    (Rename Disk Group binary)

The following binaries have been replaced by shell scripts with static output:

* `orabase`
* `orabasehome`
* `orabaseconfig`

##### Database libraries

The following libraries have been removed from the `$ORACLE_HOME/lib` directory:

* `$ORACLE_HOME/lib/libmle.so` (Multilingual Engine)
* `$ORACLE_HOME/lib/libopc.so` (Oracle Public Cloud)
* `$ORACLE_HOME/lib/libosbws.so` (Oracle Secure Backup Cloud Module)
* `$ORACLE_HOME/lib/libra.so` (Recovery Appliance)

#### Database settings

* The `DEFAULT` profile has the following set:
  * `FAILED_LOGIN_ATTEMPTS=UNLIMITED`
  * `PASSWORD_LIFE_TIME=UNLIMITED`
* `SHARED_SERVERS=0`

#### Operating system

* The following Linux packages are not installed:
  * `glibc-devel`
  * `glibc-headers`
  * `kernel-headers`
  * `libpkgconf`
  * `libxcrypt-devel`
  * `pkgconf`
  * `pkgconf-m4`
  * `pkgconf-pkg-config`

### Slim image flavor (`21-slim`)

The slim images aims for smallest possible image size with only the Oracle Database relational components. It has all customizations that the regular image has and removes all non-relational components (where possible) to further decrease the image size:

#### Database components

* `Oracle Text` has been uninstalled and removed (`$ORACLE_HOME/ctx`)
* `Oracle Spatial` has been uninstalled and removed (`$ORACLE_HOME/md`)
* `Oracle Locator` has been uninstalled and removed (`$ORACLE_HOME/md`)
* The demo samples directory has been removed (`$ORACLE_HOME/demo`)
* `ODBC` driver samples have been removed (`$ORACLE_HOME/odbc`)
* `TNS` demo samples have been removed (`$ORACLE_HOME/network/admin/samples`)
* `NLS LBuilder` directory has been removed (`$ORACLE_HOME/nls/lbuilder`)
* The hs directory has been removed (`$ORACLE_HOME/hs`)
* The `precomp` directory has been removed (`$ORACLE_HOME/precomp`)
* The `rdbms/public` directory has been removed (`$ORACLE_HOME/rdbms/public`)
* The `rdbms/xml` directory has been removed (`$ORACLE_HOME/rdbms/xml`)
* The `ord` directory has been removed (`$ORACLE_HOME/ord`)
* `Oracle R` has been removed (`$ORACLE_HOME/R`)
* The `deinstall` directory has been removed (`$ORACLE_HOME/deinstall`)
* The `Oracle Universal installer` has been removed (`$ORACLE_HOME/oui`)
* `Perl` has been removed (`$ORACLE_HOME/perl`)

##### Database binaries

The following binaries have been removed from the `$ORACLE_HOME/bin` directory:

* `$ORACLE_HOME/bin/ctx*`    (Oracle Text binaries)
* `$ORACLE_HOME/bin/cursize` (Cursor Size binary)
* `$ORACLE_HOME/bin/dbfs*`   (DataBase File System)
* `$ORACLE_HOME/bin/ORE`     (Oracle R Enterprise)
* `$ORACLE_HOME/bin/rman`    (Oracle Recovery Manager)
* `$ORACLE_HOME/bin/wrap`    (PL/SQL Wrapper)

##### Database libraries

The following libraries have been removed from the `$ORACLE_HOME/lib` directory:

* `$ORACLE_HOME/lib/asm*` (Oracle Automatic Storage Management)
* `$ORACLE_HOME/lib/libolapapi.so` (Oracle OLAP API)
* `$ORACLE_HOME/lib/ore.so` (Oracle R Enterprise)

## 18c XE

### Full image flavor (`18-full`)

The full image provides an Oracle Database XE installation "as is", meaning as provided by the RPM install file.
A couple of modifications have been performed to make the installation more suitable for running inside a container.

#### Database settings

* `DBMS_XDB.SETLISTENERLOCALACCESS(FALSE)`
* `ALTER SYSTEM SET CONTROL_MANAGEMENT_PACK_ACCESS='DIAGNOSTIC+TUNING'` (see https://github.com/gvenzl/oci-oracle-xe/issues/112)
* `ALTER SYSTEM SET AUDIT_TRAIL=NONE SCOPE=SPFILE;`
* `ALTER SYSTEM SET AUDIT_SYS_OPERATIONS=FALSE SCOPE=SPFILE;`
* `COMMON_USER_PREFIX=''`
* `LOCAL_LISTENER=''`
* `CPU_COUNT=2` (see https://github.com/gvenzl/oci-oracle-xe/issues/64 and https://github.com/gvenzl/oci-oracle-xe/pull/107)
* An `OPS$ORACLE` externally identified user has been created and granted `CONNECT` and `SELECT_CATALOG_ROLE` (this is used for health check and other operations)
* `ALTER SYSTEM SET SERVICE_NAMES=XE,FREE;` (Service `FREE` for instance `XE` to provide upward compatibility with `gvenzl/oracle-free`)
* A service `FREEPDB1` has been created for `XEPDB1` to provide upward compatibility with `gvenzl/oracle-free`
* `NLS_LANG=.AL32UTF8` set for `oracle` user to run client sessions on DB server in UTF-8 (see https://github.com/gvenzl/oci-oracle-xe/issues/109)

#### Operating system

* `/var/log/lastlog` has been cleaned

### Regular image flavor (`18`)

The regular image strives to balance between the functionality required by most users and image size. It has all customizations that the full image has and removes additional components to further decrease the image size:

#### Database components

* The `HR` schema has been removed
* `Oracle Workspace Manager` has been removed
* `Oracle Multimedia` has been removed (`$ORACLE_HOME/ord/im`)
* `Oracle Database Java Packages` have been removed
* `Oracle XDK` has been removed (`$ORACLE_HOME/xdk`)
* `JServer JAVA Virtual Machine` has been removed (`$ORACLE_HOME/javavm`)
* `Oracle OLAP API` has been removed (`$ORACLE_HOME/olap`)
* `OLAP Analytic Workspace` has been removed
* `Oracle PGX` has been removed (`$ORACLE_HOME/md/property_graph`)
* `OPatch` utility has been removed (`$ORACLE_HOME/OPatch`)
* `QOpatch` utility has been removed (`$ORACLE_HOME/QOpatch`)
* `Oracle Database Assistants` have been removed (`$ORACLE_HOME/assistants`)
* `Oracle Database Migration Assistant for Unicode` has been removed (`$ORACLE_HOME/dmu`)
* The `inventory` directory has been removed (`$ORACLE_HOME/inventory`)
* `JDBC` drivers have been removed (`$ORACLE_HOME/jdbc`, `$ORACLE_HOME/jlib`)
* `Universal Connection Pool` driver has been removed (`$ORACLE_HOME/ucp`)
* `Intel Math Kernel` libraries have been removed (`$ORACLE_HOME/lib/libmkl_*`)
* Zip files in lib/ have been removed (`$ORACLE_HOME/lib/*.zip`)
* Jar files in lib/ have been removed (`$ORACLE_HOME/lib/*.jar`)
* Old timezone files have been removed (`$ORACLE_HOME/oracore/zoneinfo/*` except the current timezone file)
* Additional Java libraries have been removed (`$ORACLE_HOME/rdbms/jlib`)
* The `Cluster Ready Services` directory has been removed (`$ORACLE_HOME/crs`)
* The `Cluster Verification Utility` directory has been removed (`$ORACLE_HOME/cv`)
* The `install` directory has been removed (`$ORACLE_HOME/install`)
* The `network/jlib` directory has been removed (`$ORACLE_HOME/network/jlib`)
* The `network/tools` directory has been removed (`$ORACLE_HOME/network/tools`)
* The `Oracle Process Manager and Notification` directory has been removed (`$ORACLE_HOME/opmn`)

##### Database binaries

The following binaries have been removed from the `$ORACLE_HOME/bin` directory:

* `$ORACLE_HOME/bin/acfs*`     (ACFS File system components
* `$ORACLE_HOME/bin/adrci`     (Automatic Diagnostic Repository Command Interpreter
* `$ORACLE_HOME/bin/agtctl`    (Multi-Threaded extproc agent control utility)
* `$ORACLE_HOME/bin/afd*`      (ASM Filter Drive components)
* `$ORACLE_HOME/bin/amdu`      (ASM Disk Utility)
* `$ORACLE_HOME/bin/ctx*`      (Oracle Text binaries)
* `$ORACLE_HOME/bin/dg4*`      (Database Gateway)
* `$ORACLE_HOME/bin/dgmgrl`    (Data Guard Manager CLI)
* `$ORACLE_HOME/bin/drda*`     (Distributed Relational Database Architecture components)
* `$ORACLE_HOME/bin/orion`     (ORacle IO Numbers benchmark tool)
* `$ORACLE_HOME/bin/proc`      (Pro*C/C++ Precompiler)
* `$ORACLE_HOME/bin/procob`    (Pro COBOL Precompiler)
* `$ORACLE_HOME/bin/renamedg`  (Rename Disk Group binary)

The following binaries have been replaced by shell scripts with static output:

* `orabase`
* `orabasehome`
* `orabaseconfig`

##### Database libraries

The following libraries have been removed from the `$ORACLE_HOME/lib` directory:

* `$ORACLE_HOME/lib/libra.so` (Recovery Appliance)
* `$ORACLE_HOME/lib/libolapapi18.so` (Oracle OLAP API)
* `$ORACLE_HOME/lib/libopc.so` (Oracle Public Cloud)
* `$ORACLE_HOME/lib/libosbws.so` (Oracle Secure Backup Cloud Module)

#### Database settings

* The `DEFAULT` profile has the following set:
  * `FAILED_LOGIN_ATTEMPTS=UNLIMITED`
  * `PASSWORD_LIFE_TIME=UNLIMITED`
* `SHARED_SERVERS=0`

#### Operating system

* The following Linux packages are not installed:
  * `glibc-devel`
  * `glibc-headers`
  * `kernel-headers`
  * `libpkgconf`
  * `libxcrypt-devel`
  * `pkgconf`
  * `pkgconf-m4`
  * `pkgconf-pkg-config`

### Slim image flavor (`18-slim`)

The slim images aims for smallest possible image size with only the Oracle Database relational components. It has all customizations that the regular image has and removes all non-relational components (where possible) to further decrease the image size:

#### Database components

* `Oracle Text` has been uninstalled and removed (`$ORACLE_HOME/ctx`)
* The demo samples directory has been removed (`$ORACLE_HOME/demo`)
* `ODBC` driver samples have been removed (`$ORACLE_HOME/odbc`)
* `TNS` demo samples have been removed (`$ORACLE_HOME/network/admin/samples`)
* `NLS LBuilder` directory has been removed (`$ORACLE_HOME/nls/lbuilder`)
* The hs directory has been removed (`$ORACLE_HOME/hs`)
* The `precomp` directory has been removed (`$ORACLE_HOME/precomp`)
* The `rdbms/public` directory has been removed (`$ORACLE_HOME/rdbms/public`)
* The `rdbms/xml` directory has been removed (`$ORACLE_HOME/rdbms/xml`)
* `Oracle Spatial` has been uninstalled and removed (`$ORACLE_HOME/md`)
* The `ord` directory has been removed (`$ORACLE_HOME/ord`)
* The `ordim` directory has been removed (`$ORACLE_HOME/ordim`)
* `Oracle R` has been removed (`$ORACLE_HOME/R`)
* The `deinstall` directory has been removed (`$ORACLE_HOME/deinstall`)
* The `Oracle Database Provider for Distributed Relational Database Architecture (DRDA)` has been removed (`$ORACLE_HOME/drdaas`)
* The `Oracle Universal installer` has been removed (`$ORACLE_HOME/oui`)
* `Perl` has been removed (`$ORACLE_HOME/perl`)

##### Database binaries

The following binaries have been removed from the `$ORACLE_HOME/bin` directory:

* `$ORACLE_HOME/bin/ctx*`    (Oracle Text binaries)
* `$ORACLE_HOME/bin/cursize` (Cursor Size binary)
* `$ORACLE_HOME/bin/dbfs*`   (DataBase File System)
* `$ORACLE_HOME/bin/ORE`     (Oracle R Enterprise)
* `$ORACLE_HOME/bin/rman`    (Oracle Recovery Manager)
* `$ORACLE_HOME/bin/wrap`    (PL/SQL Wrapper)

##### Database libraries

The following libraries have been removed from the `$ORACLE_HOME/lib` directory:

* `$ORACLE_HOME/lib/asm*` (Oracle Automatic Storage Management)
* `$ORACLE_HOME/lib/ore.so` (Oracle R Enterprise)

## 11g XE

### Full image flavor (`11-full`)

The full image provides an Oracle Database XE installation "as is", meaning as provided by the RPM install file.
A couple of modifications have been performed to make the installation more suitable for running inside a container.

#### Database settings

* Automatic Memory Management has been disabled (`MEMORY_TARGET`)
* `CPU_COUNT=1` (via initial pfile, see https://github.com/gvenzl/oci-oracle-xe/issues/64 and https://github.com/gvenzl/oci-oracle-xe/pull/107)
* `DBMS_XDB.SETLISTENERLOCALACCESS()` has been set to `FALSE`
* An `OPS$ORACLE` externally identified user has been created and granted `CONNECT` and `SELECT_CATALOG_ROLE` (this is used for health check and other operations)
* The `REDO` logs have been located into `$ORACLE_BASE/oradata/$ORACLE_SID/`
* The fast recovery area has been removed (`DB_RECOVERY_FILE_DEST=''`)
* `ALTER SYSTEM SET SERVICE_NAMES=XE,FREE;` (Service `FREE` for instance `XE` to provide upward compatibility with `gvenzl/oracle-free`)
* `NLS_LANG=.AL32UTF8` set for `oracle` user to run client sessions on DB server in UTF-8 (see https://github.com/gvenzl/oci-oracle-xe/issues/109)

#### Operating system

* `/var/log/lastlog` has been cleaned

### Regular image flavor (`11`)

The regular image strives to balance between the functionality required by most users and image size. It has all customizations that the full image has and removes additional components to further decrease the image size:

#### Database components

* Oracle APEX has been removed (you can download and install the latest and greatest from [apex.oracle.com](https://apex.oracle.com)
* The `HR` schema has been removed
* `JDBC` drivers have been removed (`$ORACLE_HOME/jdbc`, `$ORACLE_HOME/jlib`)

#### Database settings

* The `DEFAULT` profile has the following set:
  * `FAILED_LOGIN_ATTEMPTS=UNLIMITED`
  * `PASSWORD_LIFE_TIME=UNLIMITED`
* `SHARED_SERVERS=0`

#### Operating system

* The following Linux packages are not installed:
  * `binutils`
  * `gcc`
  * `glibc`
  * `make`

### Slim image flavor (`11-slim`)

The slim images aims for smallest possible image size with only the Oracle Database relational components. It has all customizations that the regular image has and removes all non-relational components (where possible) to further decrease the image size:

#### Database components

* `Oracle Text` has been uninstalled and removed (`$ORACLE_HOME/ctx`)
* `XML DB` has been uninstalled
* `XDK` has been removed (`$ORACLE_HOME/xdk`)
* `Oracle Spatial` has been uninstalled and removed (`$ORACLE_HOME/md`)
* The demo samples directory has been removed (`$ORACLE_HOME/demo`)
* `ODBC` driver samples have been removed (`$ORACLE_HOME/odbc`)
* `TNS` demo samples have been removed (`$ORACLE_HOME/network/admin/samples`)
* `NLS` demo samples have been removed (`$ORACLE_HOME/nls/demo`)
* The hs directory has been removed (`$ORACLE_HOME/hs`)
* The ldap directory has been removed (`$ORACLE_HOME/ldap`)
* The precomp directory has been removed (`$ORACLE_HOME/precomp`)
* The rdbms/demo directory has been removed (`$ORACLE_HOME/rdbms/demo`)
* The rdbms/jlib directory has been removed (`$ORACLE_HOME/rdbms/jlib`)
* The rdbms/public directory has been removed (`$ORACLE_HOME/rdbms/public`)
* The rdbms/xml directory has been removed (`$ORACLE_HOME/rdbms/xml`)

## Fast start image flavor (`*-faststart`)

The `*-faststart` images contain already expanded database files inside the image. Their aim is to provide a faster container/database startup time by trading off on the image size. These images are larger on disk due to the non-compressed database files inside them. All the functionality provided by them are, however, identical to their non-faststart siblings. It is also important to understand that container images are, in general, always pulled/pushed compressed over the network. The compressed size is of these images is not substantially larger than the non-faststart images as the compression method inside the non-faststart images is fairly similar to the one used by the container runtime. Additionally, these images are based on the non-faststart images, meaning that they only add one additional layer on top of the non-faststart images with expanded database data files. This leads to two benefits:

1. Only the third/additional layer needs to be pulled if the non-faststart images are already present on the system.
2. Container runtimes are usually capable to pull multiple layers in parallel, meaning that the third layer will be pulled concurrently with the other layers. If there is enough network bandwidth available, the download time will not significantly increase compared to the non-faststart images.