# Secrets

Minikube uses committed development-only values. They must never be reused outside the local cluster.

Hostinger uses `secrets.placeholder.yaml` only so the template can be rendered and validated. Do not deploy those values.

1. Generate an age key with `age-keygen -o ~/.config/sops/age/keys.txt`.
2. Copy its public recipient into `.sops.yaml` or export it as `AGE_RECIPIENT`.
3. Replace every placeholder in `kubernetes/overlays/hostinger/secrets.placeholder.yaml`.
4. Run `AGE_RECIPIENT=age1... ./scripts/encrypt-secrets.sh`.
5. Replace `secrets.placeholder.yaml` with `secrets.enc.yaml` in the Hostinger kustomization.
6. Render secrets at deployment time with `sops --decrypt`; never commit plaintext or the private age key.

Grafana Cloud's `authorization` value must contain `Basic <base64(instance-id:api-key)>`.
