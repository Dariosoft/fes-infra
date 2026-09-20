# PostgreSQL Backups

`make backup` creates one custom-format PostgreSQL dump per application database and sends it to the `backups` bucket in MinIO. The script opens a temporary local port-forward and does not write database dumps to disk.

List objects with:

```bash
mc ls friendly/backups
```

Restore one database with:

```bash
make restore DATABASE=catalog OBJECT=catalog-20260918T120000Z.dump
```

A backup stored in MinIO on the same single VPS does not protect against loss of that VPS. Before Hostinger is used for real data, replicate this bucket to an independent provider and test restoration periodically.
