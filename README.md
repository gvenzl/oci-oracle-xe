# oci-oracle-xe
Oracle Database Express Edition Container / Docker images.

The images are compatible with `podman` and `docker`.

## Image flavors

| Flavor        | Description                                                                                 | Use cases                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| 11.2.0.2-slim | An image focussed on smallest possible image size sacrificing on additional functionality.   | Best for where small images sizes are important but advanced functionality of Oracle Database is not needed. |
| 11.2.0.2      | A well-balanced image between image size and functionality. Recommended for most use cases. | Recommended for most use cases.                                                                              |
| 11.2.0.2-full | An image containing all functionality as provided by the Oracle Database installation.      | Best for extensions or customizations.                                                                       |

For more information, see [Image flavor details](#image-flavor-details).

## Quick start

### Reset passwords
```
docker exec <image name|id> resetPassword <your password>
```

## Image flavor details

There are three flavors of the image:
 * FULL (`-full` tag appended)
 * NORMAL (no tag appended)
 * SLIM (`-slim` tag appended)

### Full image flavor

The full image provides an Oracle Database XE installation "as is", meaning as provided by the RPM install file.
A couple of modifications have been performed to make the installation more suitable for running inside a container:

* The `REDO` logs have been relocated into `$ORACLE_BASE/oradata/$ORACLE_SID/`
* The fast recovery area has been relocated into `$ORACLE_BASE/oradata/$ORACLE_SID/`
* `DBMS_XDB.SETLISTENERLOCALACCESS()` has been set to `FALSE`
* An `OPS$ORACLE` externally identified user has been created and granted `CONNECT` and `SELECT_CATALOG_ROLE` (this is used for health check and other operations)

### Normal image flavor

The normal image has all customizations that the full image has.
Additionally, it also includes the following changes:

#### Database components
* Oracle APEX has been removed (you can download and install the latest and greatest from [apex.oracle.com](https://apex.oracle.com))
* The `HR` schema and folder have been removed
* The jdbc drivers have been removed

#### Operating system

* The following Linux packages are not installed: `binutils`, `gcc`, `glibc`, `make`

#### Data files

| Tablespace | Size   | Autoextend | Max size    |
| ---------- | -----: | ---------: | ----------- |
| `REDO`     | 20 MB  |      `N/A` | `N/A`       |
| `TEMP`     |  2 MB  |      10 MB | `UNLIMITED` |
| `UNDO`     | 10 MB  |      10 MB | `UNLIMITED` |
| `USERS`    | 10 MB  |      10 MB | `UNLIMITED` |

#### Others

* The `DEFAULT` profile has the following set:
  * `FAILED_LOGIN_ATTEMPTS=UNLIMITED`
  * `PASSWORD_LIFE_TIME=UNLIMITED`
