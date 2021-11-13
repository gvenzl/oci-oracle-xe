# Image details

Here you can find a full description of all changes that have been made to the Oracle Database and OS installation for the various image flavors.

## 21c XE

### Full image flavor (`21-full`)

The full image provides an Oracle Database XE installation "as is", meaning as provided by the RPM install file.
A couple of modifications have been performed to make the installation more suitable for running inside a container.

#### Database settings

* `DBMS_XDB.SETLISTENERLOCALACCESS(FALSE)`
* `COMMON_USER_PREFIX=''`
* `LOCAL_LISTENER=''`
* An `OPS$ORACLE` externally identified user has been created and granted `CONNECT` and `SELECT_CATALOG_ROLE` (this is used for health check and other operations)
* `DISABLE_OOB=ON` in `sqlnet.ora` (see https://github.com/gvenzl/oci-oracle-xe/issues/43)
* `BREAK_POLL_SKIP=1000` in `sqlnet.ora` (see https://github.com/gvenzl/oci-oracle-xe/issues/43)

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
* Additional Java libraries have been removed (`$ORACLE_HOME/rdbms/jlib`)
* The `Cluster Ready Services` directory has been removed (`$ORACLE_HOME/crs`)
* The `Cluster Verification Utility` directory has been removed (`$ORACLE_HOME/cv`)
* The `install` directory has been emptied, except `orabasetab` (`$ORACLE_HOME/install`)
* The `network/jlib` directory has been removed (`$ORACLE_HOME/network/jlib`)
* The `network/tools` directory has been removed (`$ORACLE_HOME/network/tools`)
* The `Oracle Process Manager and Notification` directory has been removed (`$ORACLE_HOME/opmn`)
* The `Oracle Machine Learning 4 Python` directory has been removed (`$ORACLE_HOME/oml4py`)
* `Python` has been removed (`$ORACLE_HOME/python`)

##### Database binaries

The following binaries have been removed from the `$ORACLE_HOME/bin` directory:

* `$ORACLE_HOME/bin/afd*` (ASM Filter Drive components)
* `$ORACLE_HOME}/bin/proc` (Pro\*C/C++ Precompiler)
* `$ORACLE_HOME/bin/procob` (Pro COBOL Precompiler)
* `$ORACLE_HOME/bin/orion` (ORacle IO Numbers benchmark tool)

The following binaries have been replaced by shell scripts with static output:

* `orabase`
* `orabasehome`
* `orabaseconfig`

##### Database libraries

The following libraries have been removed from the `$ORACLE_HOME/lib` directory:

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

## 18c XE

### Full image flavor (`18-full`)

The full image provides an Oracle Database XE installation "as is", meaning as provided by the RPM install file.
A couple of modifications have been performed to make the installation more suitable for running inside a container.

#### Database settings

* `DBMS_XDB.SETLISTENERLOCALACCESS(FALSE)`
* `COMMON_USER_PREFIX=''`
* `LOCAL_LISTENER=''`
* An `OPS$ORACLE` externally identified user has been created and granted `CONNECT` and `SELECT_CATALOG_ROLE` (this is used for health check and other operations)

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
* Additional Java libraries have been removed (`$ORACLE_HOME/rdbms/jlib`)
* The `Cluster Ready Services` directory has been removed (`$ORACLE_HOME/crs`)
* The `Cluster Verification Utility` directory has been removed (`$ORACLE_HOME/cv`)
* The `install` directory has been removed (`$ORACLE_HOME/install`)
* The `network/jlib` directory has been removed (`$ORACLE_HOME/network/jlib`)
* The `network/tools` directory has been removed (`$ORACLE_HOME/network/tools`)
* The `Oracle Process Manager and Notification` directory has been removed (`$ORACLE_HOME/opmn`)

##### Database binaries

The following binaries have been removed from the `$ORACLE_HOME/bin` directory:

* `$ORACLE_HOME/bin/afd*` (ASM Filter Drive components)
* `$ORACLE_HOME}/bin/proc` (Pro\*C/C++ Precompiler)
* `$ORACLE_HOME/bin/procob` (Pro COBOL Precompiler)
* `$ORACLE_HOME/bin/orion` (ORacle IO Numbers benchmark tool)
* `$ORACLE_HOME/bin/drda*` (Distributed Relational Database Architecture components)

The following binaries have been replaced by shell scripts with static output:

* `orabase`
* `orabasehome`
* `orabaseconfig`

##### Database libraries

The following libraries have been removed from the `$ORACLE_HOME/lib` directory:

* `$ORACLE_HOME/lib/libra.so` (Recovery Appliance)
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

* `$ORACLE_HOME/bin/rman` (Oracle Recovery Manager)
* `$ORACLE_HOME/bin/wrap` (PL/SQL Wrapper)

##### Database libraries

The following libraries have been removed from the `$ORACLE_HOME/lib` directory:

* `$ORACLE_HOME/lib/asm*` (Oracle Automatic Storage Management)

## 11g XE

### Full image flavor (`11-full`)

The full image provides an Oracle Database XE installation "as is", meaning as provided by the RPM install file.
A couple of modifications have been performed to make the installation more suitable for running inside a container.

#### Database settings

* Automatic Memory Management has been disables (`MEMORY_TARGET`)
* `DBMS_XDB.SETLISTENERLOCALACCESS()` has been set to `FALSE`
* An `OPS$ORACLE` externally identified user has been created and granted `CONNECT` and `SELECT_CATALOG_ROLE` (this is used for health check and other operations)
* The `REDO` logs have been located into `$ORACLE_BASE/oradata/$ORACLE_SID/`
* The fast recovery area has been removed (`DB_RECOVERY_FILE_DEST=''`)

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
