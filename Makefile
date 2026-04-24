.PHONY: build test push dockerhub clean help

IMAGE_NAME ?= unbound
TAG ?= latest
DOCKERHUB_USER ?= luis

help:
	@echo "Available targets:"
	@echo "  build     - Build the Docker image (local)"
	@echo "  test      - Run a quick container test"
	@echo "  push      - Push to registry (set REGISTRY env, e.g. REGISTRY=ghcr.io/username)"
	@echo "  dockerhub - Push to Docker Hub (luis/unbound)"
	@echo "  clean     - Remove local image"

build:
	docker build -t $(IMAGE_NAME)-custom:$(TAG) .

test:
	@echo "Testing image build..."
	docker build -t $(IMAGE_NAME)-custom:test .
	@echo "Running container test (will exit after 5s)..."
	docker run --rm \
		-e UNBOUND_CONF_PATH=/etc/unbound/unbound.conf \
		$(IMAGE_NAME)-custom:test \
		unbound-checkconf -c /etc/unbound/unbound.conf
	@echo "✅ Config validation passed"

push:
	@if [ -z "$(REGISTRY)" ]; then echo "ERROR: Set REGISTRY env (e.g. REGISTRY=ghcr.io/username)"; exit 1; fi
	docker tag $(IMAGE_NAME)-custom:$(TAG) $(REGISTRY)/$(IMAGE_NAME):$(TAG)
	docker push $(REGISTRY)/$(IMAGE_NAME):$(TAG)

# Push to Docker Hub (default: luis/unbound)
dockerhub:
	@echo "Pushing to Docker Hub: $(DOCKERHUB_USER)/$(IMAGE_NAME):$(TAG)"
	docker tag $(IMAGE_NAME)-custom:$(TAG) docker.io/$(DOCKERHUB_USER)/$(IMAGE_NAME):$(TAG)
	docker push docker.io/$(DOCKERHUB_USER)/$(IMAGE_NAME):$(TAG)
	@echo "✅ Pushed to https://hub.docker.com/r/$(DOCKERHUB_USER)/$(IMAGE_NAME)"

clean:
	-docker rmi $(IMAGE_NAME)-custom:$(TAG) 2>/dev/null || true
	-docker rmi $(IMAGE_NAME)-custom:test 2>/dev/null || true
