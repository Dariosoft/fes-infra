#!/usr/bin/env python3
"""Comprueba que los manifiestos base, el ingress de producción y los secretos
del overlay de Hostinger concuerden entre sí.

No reemplaza a kubeconform (esquema) ni a las políticas (postura): verifica las
referencias cruzadas que ningún validador genérico puede resolver, que es donde
aparecen los errores que sólo se descubren al desplegar.
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

INFRA = Path(__file__).resolve().parents[2]
KUBERNETES = INFRA / "kubernetes"
BASE = KUBERNETES / "base"
PRODUCTION = KUBERNETES / "overlays" / "hostinger"

# Directorios con kustomization propia que no exponen un Service de aplicación.
NON_APP_DIRS = {"platform", "observability"}

WORKLOAD_KINDS = {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job", "Pod"}

errors: list[str] = []


def documents(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        return [doc for doc in yaml.safe_load_all(handle) if isinstance(doc, dict)]


def base_documents() -> list[dict]:
    docs: list[dict] = []
    for path in sorted(BASE.rglob("*.yaml")):
        docs.extend(documents(path))
    return docs


def pod_spec(document: dict) -> dict | None:
    if document.get("kind") == "Pod":
        return document.get("spec")
    if document.get("kind") in WORKLOAD_KINDS:
        return (document.get("spec") or {}).get("template", {}).get("spec")
    return None


def containers(document: dict) -> list[dict]:
    spec = pod_spec(document)
    if not spec:
        return []
    return list(spec.get("containers") or []) + list(spec.get("initContainers") or [])


def check_base_structure() -> None:
    """Cada servicio de base está listado y tiene Deployment y Service."""
    kustomization = documents(BASE / "kustomization.yaml")[0]
    listed = {Path(entry).name for entry in kustomization.get("resources", [])}

    for directory in sorted(BASE.iterdir()):
        if not directory.is_dir() or not (directory / "kustomization.yaml").exists():
            continue
        if directory.name not in listed:
            errors.append(
                f"base/kustomization.yaml no incluye el directorio {directory.name}"
            )
        if directory.name in NON_APP_DIRS:
            continue
        for required in ("deployment.yaml", "service.yaml"):
            if not (directory / required).exists():
                errors.append(f"base/{directory.name} no tiene {required}")


def check_ingress_backends(base_docs: list[dict]) -> None:
    """Cada backend del ingress corresponde a un Service real con ese puerto."""
    services: dict[str, set[int]] = {}
    for document in base_docs:
        if document.get("kind") != "Service":
            continue
        ports = {port.get("port") for port in document.get("spec", {}).get("ports", [])}
        services[document["metadata"]["name"]] = ports

    for document in documents(PRODUCTION / "ingress.yaml"):
        for rule in document.get("spec", {}).get("rules", []):
            for path in rule.get("http", {}).get("paths", []):
                service = path["backend"]["service"]
                service_name = service["name"]
                port = (service.get("port") or {}).get("number")

                if service_name not in services:
                    errors.append(
                        f"el ingress apunta al Service {service_name}, que no existe en base"
                    )
                elif port is not None and port not in services[service_name]:
                    errors.append(
                        f"el ingress usa el puerto {port} de {service_name}, que el Service no declara"
                    )


def check_secret_references(base_docs: list[dict]) -> None:
    """Cada secretKeyRef y configMapRef de base existe en el overlay de producción."""
    secrets: dict[str, set[str]] = {}
    config_maps: set[str] = set()

    for document in documents(PRODUCTION / "secrets.placeholder.yaml"):
        if document.get("kind") != "Secret":
            continue
        keys = set(document.get("stringData") or {}) | set(document.get("data") or {})
        secrets[document["metadata"]["name"]] = keys

    for document in base_docs:
        if document.get("kind") == "ConfigMap":
            config_maps.add(document["metadata"]["name"])

    for document in base_docs:
        for container in containers(document):
            for env in container.get("env") or []:
                reference = (env.get("valueFrom") or {}).get("secretKeyRef")
                if not reference:
                    continue
                secret_name = reference["name"]
                key = reference["key"]
                if secret_name not in secrets:
                    errors.append(
                        f"{container.get('name')} usa el Secret {secret_name}, que el overlay de Hostinger no declara"
                    )
                elif key not in secrets[secret_name]:
                    errors.append(
                        f"{container.get('name')} usa la clave {key} del Secret {secret_name}, que el placeholder no declara"
                    )

            for source in container.get("envFrom") or []:
                config_map = (source.get("configMapRef") or {}).get("name")
                if config_map and config_map not in config_maps:
                    errors.append(
                        f"{container.get('name')} usa el ConfigMap {config_map}, que no existe en base"
                    )
                secret_name = (source.get("secretRef") or {}).get("name")
                if secret_name and secret_name not in secrets:
                    errors.append(
                        f"{container.get('name')} usa el Secret {secret_name}, que el overlay de Hostinger no declara"
                    )


def main() -> int:
    base_docs = base_documents()
    check_base_structure()
    check_ingress_backends(base_docs)
    check_secret_references(base_docs)

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("Referencias cruzadas consistentes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
