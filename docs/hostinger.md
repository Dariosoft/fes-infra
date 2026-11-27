# Hostinger Preparation

The Hostinger overlay and Terraform code are templates and are not applied automatically. Published GHCR tags belong to that overlay. Minikube does not pull them: `make deploy` mounts the local application checkouts and reloads frontends and backends from those files.

Before deployment:

1. Contract or select a VPS in Brazil and measure latency from Argentina.
2. Replace `REPLACE_GITHUB_OWNER`, `REPLACE_BASE_DOMAIN` and `REPLACE_EMAIL`. The same
   `REPLACE_BASE_DOMAIN` marker also resolves the Storefront origin that `catalog-api` receives in
   `BROWSER_ORIGINS` (`catalog-api-env-patch.yaml`), so both stay on the environment's own domain.
3. Publish multi-architecture application images to GHCR.
4. Install K3s and cert-manager.
5. Create encrypted SOPS secrets.
6. Point DNS records at the VPS IPv4 address.
7. Render and inspect `kustomize build kubernetes/overlays/hostinger`.
8. Apply the overlay and verify every rollout. The `order-api` and `catalog-api` pods include
   `initContainers` that wait for `job/rabbitmq-topology` to exist and complete, so they do not
   start their main container before the queues exist.
9. Wait for the `rabbitmq-topology` Job in `platform` to reach `Completed` before closing the
   deployment; it declares the same RabbitMQ exchanges, queues, TTLs and bindings as Minikube
   (`kubectl -n platform wait --for=condition=complete --timeout=300s job/rabbitmq-topology`). The
   Job is kept after completion so the application `initContainers` can observe it on later pod
   restarts. If the broker volume is lost while the `Job` is `Completed`, delete the `Job` and
   reapply the overlay.
10. Wait for the `kafka-topology` Job in `platform` to reach `Completed` before closing the
    deployment; it declares the `orders.events` topic consumed by `analytics-api` and
    `notifications-api` (`kubectl -n platform wait --for=condition=complete --timeout=300s
    job/kafka-topology`). The Job is kept after completion for the application `initContainers`.
    If the Kafka volume is lost, delete the Job and reapply the overlay.

Terraform is disabled by default because applying an enabled Hostinger VPS resource can purchase a subscription, while destroying it can cancel that subscription. Review the provider behavior and plan output before changing `enable_vps_provisioning`.
