# Product Images Storage

MinIO stores the product images in the `product-images` bucket. This document covers the
manual configuration that is not generated from code: the local backup folder, the bucket, the
least-privilege policy and the dedicated credentials.

Related documents: [`secrets.md`](secrets.md), [`hostinger.md`](hostinger.md), [`backups.md`](backups.md).

The wiring lives in `kubernetes/base` (env and ConfigMap); the overlays only change the secret
material.

| Piece | Value |
|-------|-------|
| Bucket | `product-images` |
| Policy | `product-images-rw` (least privilege, scoped to the bucket) |
| Dedicated credentials | `product-images-access-key` / `product-images-secret-key` in `app-secrets` |
| catalog-api env | `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` |
| panel-api config | `CATALOG_API_BASE_URL` |
| NetworkPolicy | `platform-ingress` allows TCP `9000` from `apps` to MinIO (already in base) |

## MinIO volume: Minikube vs Hostinger

MinIO keeps its base `volumeClaimTemplates` (PVC) in both environments:

- **Minikube:** PVC on the node's local disk. Images persist across pod restarts and
  `make stop` / `make start`, and are lost with `make destroy`.
- **Hostinger:** the same PVC pattern; images persist on the node's storage and the dedicated
  credentials arrive through the encrypted secret.

MinIO cannot run directly on the workspace `hostPath`: `minikube mount` serves that mount as a
`9p` filesystem that does not support the rename semantics the MinIO erasure backend needs
(`FATAL ... Rename across devices not allowed`). The local folder is therefore a **backup
target**, not the live backend.

## Local backup folder (Minikube)

A reserved folder on the host keeps an on-demand copy of the bucket objects:

| Where | Path |
|-------|------|
| Host (macOS) | `/Users/dariogutierrez/projects/friendly-e-shop/media/images` |

The application always reads and writes MinIO through its PVC; the folder is only touched by the
backup and restore commands.

The backup and restore run automatically as part of the cluster lifecycle:

- `make destroy` backs up the bucket to the folder **before** deleting the profile (best effort:
  only when the profile is running; it never blocks the destroy).
- `make deploy` uploads **missing** objects from the folder back into the bucket (no overwrite), so
  recreating the environment (`make destroy` → `make minikube-create` → `make deploy`) restores the
  images without touching newer ones.

You can also run them manually:

```bash
make backup-images   # mirror the bucket to the folder (overwrite)
make restore-images  # mirror the folder to the bucket (overwrite)
```

Both commands open a temporary port-forward to `service/minio` and use `mc mirror`. Override the
folder and bucket with `PRODUCT_IMAGES_DIR` and `PRODUCT_IMAGES_BUCKET`. The scripts read the root
credentials from `platform-secrets` for administration only. `RESTORE_OVERWRITE=0` makes the
restore copy only missing objects (this is what `make deploy` uses).

## Bucket and least-privilege policy

The bucket is `product-images`. The dedicated user gets only the `product-images-rw` policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::product-images"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::product-images/*"]
    }
  ]
}
```

The dedicated credentials are **not** the MinIO root credentials (`minio-root-user` /
`minio-root-password`), which stay only in `platform-secrets` for administration.

### Minikube: idempotent script

`make deploy` calls `scripts/ensure-product-images-bucket.sh` automatically after MinIO is ready.
It opens a temporary port-forward (`MINIO_FORWARD_PORT`, default `19001`), creates the bucket,
policy and dedicated user, and is safe to run again:

```bash
./scripts/ensure-product-images-bucket.sh
```

Repeating it never duplicates the bucket and never fails when the bucket, policy or user already
exist. It reads the root credentials from `platform-secrets` (administration only) and the
dedicated credentials from `app-secrets`.

### Hostinger: manual procedure

There is no automatic script for Hostinger. Run the equivalent `mc` commands with the MinIO admin
alias (replace `<admin-user>` / `<admin-password>` with the root credentials from the rendered
secret):

```bash
mc alias set minio https://minio.<base-domain> <admin-user> <admin-password>
mc mb --ignore-existing minio/product-images
mc admin policy create minio product-images-rw product-images-rw.json   # the JSON above
mc admin user add minio <product-images-access-key> <product-images-secret-key>
mc admin policy attach minio product-images-rw --user <product-images-access-key>
```

## Dedicated credentials

The dedicated credentials live in `app-secrets` as `product-images-access-key` and
`product-images-secret-key`.

- **Minikube:** development-only values in
  `kubernetes/overlays/minikube/resources/secrets.yaml`
  (`catalog-images` / `catalog-images-local`). They are not production secrets.
- **Hostinger:** `kubernetes/overlays/hostinger/secrets.placeholder.yaml` ships the keys as
  `REPLACE_ME`. Replace them, then encrypt with SOPS before deploying
  (`AGE_RECIPIENT=age1... ./scripts/encrypt-secrets.sh` and swap the resource to
  `secrets.enc.yaml`). See [`secrets.md`](secrets.md) for the full flow.

Never commit the real credentials in clear text, and never reuse `minio-root-*` for the application.

## Environment wiring

- `catalog-api` (`kubernetes/base/catalog-api/deployment.yaml`):
  - `S3_ENDPOINT=http://minio.platform.svc.cluster.local:9000`
  - `S3_BUCKET=product-images`
  - `S3_ACCESS_KEY` ← `secretKeyRef` `app-secrets/product-images-access-key`
  - `S3_SECRET_KEY` ← `secretKeyRef` `app-secrets/product-images-secret-key`
- `catalog-api` public URL (overlay env patches `catalog-api-env-patch.yaml`):
  - `PUBLIC_API_BASE_URL=https://api.friendly-e-shop.duckdns.org` (Minikube)
  - `PUBLIC_API_BASE_URL=https://api.REPLACE_BASE_DOMAIN` (Hostinger)
- `panel-api` (`kubernetes/base/panel-api/deployment.yaml`, ConfigMap `panel-api-config`):
  - `CATALOG_API_BASE_URL=http://catalog-api.apps.svc.cluster.local:8080`

The cluster DNS values are identical in Minikube and Hostinger; the overlays change the secret
material and the public API URL used to build image links.

## Missing bucket or credentials

Following the spec, nothing is invented:

- If the bucket does not exist, create it with the script (Minikube) or with `mc mb` (Hostinger).
- If the dedicated keys are missing from `app-secrets`, `scripts/ensure-product-images-bucket.sh`
  creates the bucket and warns instead of guessing values, and catalog-api will not receive valid
  S3 credentials until the operator sets them. Set the keys and rerun the script.

## Verification

- `kubectl -n platform exec minio-0 -- mc ls local/product-images` (or `mc ls friendly/product-images`
  after running the script) lists the bucket.
- `kubectl -n apps get deployment catalog-api -o jsonpath='{.spec.template.spec.containers[0].env}'`
  shows the four S3 variables.
- After `make backup-images`, the bucket objects appear under
  `/Users/dariogutierrez/projects/friendly-e-shop/media/images`.
