default: bin/aws-iam-authenticator

PKG ?= sigs.k8s.io/aws-iam-authenticator
GORELEASER := $(shell command -v goreleaser 2> /dev/null)

VERSION ?= v0.5.3
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
GOPROXY ?= $(shell go env GOPROXY)
SOURCES := $(shell find . -name '*.go')
GIT_COMMIT ?= $(shell git rev-parse HEAD)
BUILD_DATE ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
OUTPUT ?= _output
CHECKSUM_FILE ?= $(OUTPUT)/bin/authenticator_$(VERSION)_checksums.txt

# Architectures for binary builds
BIN_ARCH_LINUX ?= amd64 arm64
BIN_ARCH_WINDOWS ?= amd64
BIN_ARCH_DARWIN ?= amd64

ALL_LINUX_BIN_TARGETS = $(foreach arch,$(BIN_ARCH_LINUX),$(OUTPUT)/bin/aws-iam-authenticator_$(VERSION)_linux_$(arch))
ALL_WINDOWS_BIN_TARGETS = $(foreach arch,$(BIN_ARCH_WINDOWS),$(OUTPUT)/bin/aws-iam-authenticator_$(VERSION)_windows_$(arch).exe)
ALL_DARWIN_BIN_TARGETS = $(foreach arch,$(BIN_ARCH_DARWIN),$(OUTPUT)/bin/aws-iam-authenticator_$(VERSION)_darwin_$(arch))
ALL_BIN_TARGETS = $(ALL_LINUX_BIN_TARGETS) $(ALL_WINDOWS_BIN_TARGETS) $(ALL_DARWIN_BIN_TARGETS)

.PHONY: bin
bin:
ifeq ($(GOOS),windows)
	$(MAKE) $(OUTPUT)/bin/aws-iam-authenticator.exe
else
	$(MAKE) $(OUTPUT)/bin/aws-iam-authenticator
endif

# Function checksum
# Parameters:
# 1: Target file on which to perform checksum
# 2: Checksum file to append the result
# Note: the blank line at the end of the function is required.
define checksum
sha256sum $(1) | sed 's|$(OUTPUT)/bin/||' >> $(2)

endef

.PHONY: checksums
checksums: $(CHECKSUM_FILE)

$(CHECKSUM_FILE): build-all-bins
	rm -f $(CHECKSUM_FILE)
	@echo $(ALL_BIN_TARGETS)
	$(foreach target,$(ALL_BIN_TARGETS),$(call checksum,$(target),$(CHECKSUM_FILE)))

$(OUTPUT)/bin/%: $(SOURCES)
	GO111MODULE=on \
		CGO_ENABLED=0 \
		GOOS=$(GOOS) \
		GOARCH=$(GOARCH) \
		GOPROXY=$(GOPROXY) \
		go build \
		-o=$@ \
		-ldflags="-w -s -X $(PKG)/pkg.Version=$(VERSION) -X $(PKG)/pkg.BuildDate=$(BUILD_DATE) -X $(PKG)/pkg.CommitID=$(GIT_COMMIT)" \
		./cmd/aws-iam-authenticator/

# Function build-bin
# Parameters:
# 1: Target OS
# 2: Target architecture
# 3: Target file extension
# Note: the blank line at the end of the function is required.
define build-bin
$(MAKE) $(OUTPUT)/bin/aws-iam-authenticator_$(VERSION)_$(1)_$(2)$(3) GOOS=$(1) GOARCH=$(2)

endef

.PHONY: build-all-bins
build-all-bins:
	$(foreach arch,$(BIN_ARCH_LINUX),$(call build-bin,linux,$(arch),))
	$(foreach arch,$(BIN_ARCH_WINDOWS),$(call build-bin,windows,$(arch),.exe))
	$(foreach arch,$(BIN_ARCH_DARWIN),$(call build-bin,darwin,$(arch),))

.PHONY: image
image:
	docker build \
		--build-arg image=public.ecr.aws/eks-distro-build-tooling/eks-distro-minimal-base-nonroot:2021-08-26-1630012071 \
		--tag aws-iam-authenticator:$(VERSION)_$(GIT_COMMIT)_$(shell date +%s) .

.PHONY: goreleaser
goreleaser:
ifndef GORELEASER
	$(error "goreleaser not found (`go get -u -v github.com/goreleaser/goreleaser` to fix)")
endif
	$(GORELEASER) --skip-publish --rm-dist --snapshot

.PHONY: test
test:
	go test -v -coverprofile=coverage.out -race $(PKG)/pkg/...
	go tool cover -html=coverage.out -o coverage.html

.PHONY: integration
integration:
	./hack/test-integration.sh

.PHONY: format
format:
	test -z "$$(find . -path ./vendor -prune -type f -o -name '*.go' -exec gofmt -d {} + | tee /dev/stderr)" || \
	test -z "$$(find . -path ./vendor -prune -type f -o -name '*.go' -exec gofmt -w {} + | tee /dev/stderr)"

.PHONY: codegen
codegen:
	./hack/update-codegen.sh

.PHONY: clean
clean:
	rm -rf $(shell pwd)/_output
