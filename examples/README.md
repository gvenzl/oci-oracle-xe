# Examples 

| Script | Parameters | Description |
|--------|------------|-------------|
| dkr-create-oracle-xe-server | hostXePort containerName | Create Oracle XE Container using docker |
| setup-tde.sh | <None> | Configures the database for Transparent Data Encryption in United Mode, mount/copy under `/container-entrypoint-initdb.d` inside the container. |
| setup-columnar-store.sh | <None> | Configures the database with the In-Memory Columnar Store. |

## Mount file-only example with Podman

```sh
podman run -e ORACLE_PASSWORD=test -p 1521:1521 --mount type=bind,src=./setup-columnar-store.sh,dst=/container-entrypoint-initdb.d/setup-columnar-store.sh,relabel=shared gvenzl/oracle-xe:21.3.0-slim
```
