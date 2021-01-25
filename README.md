# oci-oracle-xe
Oracle Database Express Edition Container / Docker images.

The images are compatible with `podman` and `docker`.

## Image flavors

| Flavor        | Description |                                                                               | Use cases                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| 11.2.0.2-slim | An image focussed on smalles possible image size sacrificing on additional functionality.   | Best for where small images sizes are important but advanced functionality of Oracle Database is not needed. |
| 11.2.0.2      | A well-balanced image between image size and functionality. Recommended for most use cases. | Recommended for most use cases.                                                                              |
| 11.2.0.2-full | An image containing all functionality as provided by the Oracle Database installation.      | Best for extensions or customizations.                                                                       |

For more information see [Image flavor details](#image-flavor-details).

## Quick start

### Reset passwords
```
docker exec <image name|id> resetPassword <your password>
```

### Image flavor details