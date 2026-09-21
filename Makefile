SHELL := /usr/bin/env bash

.PHONY: bootstrap doctor minikube-create images-build deploy status smoke-test tunnel observability backup restore validate destroy

bootstrap:
	./scripts/bootstrap.sh

doctor:
	./scripts/doctor.sh

minikube-create:
	./scripts/minikube-create.sh

images-build:
	./scripts/images-build.sh

deploy:
	./scripts/deploy.sh

status:
	./scripts/status.sh

smoke-test:
	./scripts/smoke-test.sh

tunnel:
	minikube tunnel --profile "$${MINIKUBE_PROFILE:-friendly-e-shop}"

observability:
	./scripts/observability.sh

backup:
	./scripts/backup.sh

restore:
	@test -n "$(DATABASE)" -a -n "$(OBJECT)" || (echo "Use DATABASE=name OBJECT=file make restore"; exit 1)
	./scripts/restore.sh "$(DATABASE)" "$(OBJECT)"

validate:
	./scripts/validate.sh

destroy:
	minikube delete --profile "$${MINIKUBE_PROFILE:-friendly-e-shop}"
