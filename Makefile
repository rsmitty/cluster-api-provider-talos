TAG ?= $(shell gitmeta image tag)
REPO ?= autonomy/cluster-api-provider-talos

all: test docker-build

# Generate code
generate:
	go generate ./pkg/... ./cmd/...
	go fmt ./pkg/... ./cmd/...
	go vet ./pkg/... ./cmd/...

# Build manager binary
manager: generate
	go build -o bin/manager github.com/talos-systems/cluster-api-provider-talos/cmd/manager

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate
	go run ./cmd/manager/main.go

# Run tests
test:
	docker build . --target $@ -t $(REPO):test

# Install CRDs into a cluster
install: manifests
	kubectl apply -f config/crds

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	cat provider-components.yaml | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests:
	docker build . --target $@ -t $(REPO):manifests --build-arg IMG="$(REPO):$(TAG)"
	mkdir -p /tmp/manifests
	docker run $(REPO):manifests bash -c 'cat /tmp/manifests/provider-components.yaml' > /tmp/manifests/provider-components.yaml

# Build the docker image
docker-build:
	docker build . -t $(REPO):$(TAG)

# Push the docker image
docker-push:
	@docker tag $(REPO):$(TAG) $(REPO):latest
	@docker push $(REPO):$(TAG)
	@docker push $(REPO):latest

.PHONY: login
login:
	@docker login --username "$(DOCKER_USERNAME)" --password "$(DOCKER_PASSWORD)"

.PHONY: clientset
clientset: bin/client-gen bin/lister-gen bin/informer-gen ## Generate a typed clientset
	rm -rf pkg/client
	bin/client-gen --clientset-name clientset --input-base sigs.k8s.io/cluster-api/pkg/apis \
		--input cluster/v1alpha1 --output-package sigs.k8s.io/cluster-api/pkg/client/clientset_generated \
		--go-header-file=./hack/boilerplate/boilerplate.generatego.txt
	bin/lister-gen --input-dirs sigs.k8s.io/cluster-api/pkg/apis/cluster/v1alpha1 \
		--output-package sigs.k8s.io/cluster-api/pkg/client/listers_generated \
		--go-header-file=./hack/boilerplate/boilerplate.generatego.txt
	bin/informer-gen --input-dirs sigs.k8s.io/cluster-api/pkg/apis/cluster/v1alpha1 \
		--versioned-clientset-package sigs.k8s.io/cluster-api/pkg/client/clientset_generated/clientset \
		--listers-package sigs.k8s.io/cluster-api/pkg/client/listers_generated \
		--output-package sigs.k8s.io/cluster-api/pkg/client/informers_generated \
		--go-header-file=./hack/boilerplate/boilerplate.generatego.txt

bin/%-gen: ./vendor/k8s.io/code-generator/cmd/%-gen ## Build code-generator binaries
	go build -o $@ ./$<
