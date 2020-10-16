DIST_DIR ?= dist/
GOOS ?= $(shell uname -s | tr "[:upper:]" "[:lower:]")
GOARCH ?= $(shell uname -m)
BUILDINFOSDET ?=
UDP_PROXY_2020_ARGS ?=

PROJECT_VERSION    := 0.0.5
DOCKER_REPO        := synfinatic
PROJECT_NAME       := udp-proxy-2020
PROJECT_TAG        := $(shell git describe --tags 2>/dev/null $(git rev-list --tags --max-count=1))
ifeq ($(PROJECT_TAG),)
PROJECT_TAG        := NO-TAG
endif
PROJECT_COMMIT     := $(shell git rev-parse HEAD)
ifeq ($(PROJECT_COMMIT),)
PROJECT_COMMIT     := NO-CommitID
endif
VERSION_PKG        := $(shell echo $(PROJECT_VERSION) | sed 's/^v//g')
LICENSE            := GPLv3
URL                := https://github.com/$(DOCKER_REPO)/$(PROJECT_NAME)
DESCRIPTION        := UDP Proxy 2020: A bad hack for a stupid problem
BUILDINFOS         := $(shell date +%FT%T%z)$(BUILDINFOSDET)
HOSTNAME           := $(shell hostname)
LDFLAGS            := -X "main.Version=$(PROJECT_VERSION)" -X "main.Buildinfos=$(BUILDINFOS)" -X "main.Tag=$(PROJECT_TAG)" -X "main.CommitID=$(PROJECT_COMMIT)"
OUTPUT_NAME        := $(DIST_DIR)$(PROJECT_NAME)-$(PROJECT_VERSION)-$(GOOS)-$(GOARCH)
STR2PCAP_NAME      := $(DIST_DIR)str2pcap-$(PROJECT_VERSION)-$(GOOS)-$(GOARCH)


ALL: $(OUTPUT_NAME) str2pcap ## Build binary

str2pcap: $(STR2PCAP_NAME)

$(STR2PCAP_NAME): str2pcap/*.go
	go build -o $(STR2PCAP_NAME) str2pcap/*.go

include help.mk  # place after ALL target and before all other targets

release: linux-static freebsd mips64-static arm64-static $(OUTPUT_NAME) ## Build our release binaries

.PHONY: run
run: cmd/*.go  ## build and run udp-proxy-2020 using $UDP_PROXY_2020_ARGS
	sudo go run cmd/*.go $(UDP_PROXY_2020_ARGS)

clean-all: vagrant-destroy docker-clean clean ## clean _everything_

clean: ## Remove all binaries in dist
	rm -f dist/*

clean-go: ## Clean Go cache
	go clean -i -r -cache -modcache

$(OUTPUT_NAME): cmd/*.go .prepare
	go build -ldflags='$(LDFLAGS)' -o $(OUTPUT_NAME) cmd/*.go
	@echo "Created: $(OUTPUT_NAME)"

.PHONY: build-race
build-race: .prepare ## Build race detection binary
	go build -race -ldflags='$(LDFLAGS)' -o $(OUTPUT_NAME) cmd/*.go

debug: .prepare ## Run debug in dlv
	dlv debug cmd/*.go

.PHONY: unittest
unittest: ## Run go unit tests
	go test ./...

.PHONY: test-race
test-race: ## Run `go test -race` on the code
	@echo checking code for races...
	go test -race ./...

.PHONY: vet
vet: ## Run `go vet` on the code
	@echo checking code is vetted...
	go vet $(shell go list ./...)

test: vet unittest ## Run all tests

.prepare: $(DIST_DIR)

$(DIST_DIR):
	@mkdir -p $(DIST_DIR)

.PHONY: fmt
fmt: ## Format Go code
	@go fmt cmd

.PHONY: test-fmt
test-fmt: fmt ## Test to make sure code if formatted correctly
	@if test `git diff cmd | wc -l` -gt 0; then \
	    echo "Code changes detected when running 'go fmt':" ; \
	    git diff -Xfiles ; \
	    exit -1 ; \
	fi

.PHONY: test-tidy
test-tidy:  ## Test to make sure go.mod is tidy
	@go mod tidy
	@if test `git diff go.mod | wc -l` -gt 0; then \
	    echo "Need to run 'go mod tidy' to clean up go.mod" ; \
	    exit -1 ; \
	fi

precheck: test test-fmt test-tidy  ## Run all tests that happen in a PR

######################################################################
# Docker targets for testing
######################################################################
.PHONY: docker-build
docker-build: ## Build binary in Docker for testing
	docker build -t $(DOCKER_REPO)/$(PROJECT_NAME):latest .
	docker run --rm \
	    --volume $(shell pwd)/dist:/build/$(PROJECT_NAME)/dist \
	    $(DOCKER_REPO)/$(PROJECT_NAME):latest

.PHONY: docker-clean
docker-clean: ## Delete Docker testing image
	docker image rm $(DOCKER_REPO)/$(PROJECT_NAME):latest

.PHONY: docker-shell
docker-shell: ## Get a shell in Docker testing container
	docker run -it --rm  \
	    --volume $(shell pwd)/dist:/build/$(PROJECT_NAME)/dist \
	    $(DOCKER_REPO)/$(PROJECT_NAME):latest /bin/bash

######################################################################
# Linux targets for building Linux in Docker
######################################################################
LINUX_S_NAME       := $(DIST_DIR)$(PROJECT_NAME)-$(PROJECT_VERSION)-linux-x86_64-static

.PHONY: linux-static
linux-static: ## Build static Linux/x86_64 binary using Docker
	docker build -t $(DOCKER_REPO)/$(PROJECT_NAME)-linux:latest -f Dockerfile.linux .
	docker run --rm \
	    --volume $(shell pwd)/dist:/build/$(PROJECT_NAME)/dist \
	    $(DOCKER_REPO)/$(PROJECT_NAME)-linux:latest

.PHONY: linux-clean
linux-clean: ## Remove Linux/x86_64 Docker image
	docker image rm $(DOCKER_REPO)/$(PROJECT_NAME)-linux:latest

.PHONY: linux-shell
linux-shell: ## Get a shell in Linux/x86_64 Docker container
	docker run -it --rm  \
	    --volume $(shell pwd)/dist:/build/$(PROJECT_NAME)/dist \
	    $(DOCKER_REPO)/$(PROJECT_NAME)-linux:latest /bin/bash

.linux-static: $(LINUX_S_NAME)
$(LINUX_S_NAME): .prepare
	LDFLAGS='-l/usr/lib/libpcap.a' CGO_ENABLED=1 \
	    go build -ldflags '$(LDFLAGS) -linkmode external -extldflags -static' -o $(LINUX_S_NAME) cmd/*.go
	@echo "Created: $(LINUX_S_NAME)"

######################################################################
# Vagrant targets for building for FreeBSD/pfSense
######################################################################
.PHONY: .vagrant-check
.vagrant-check:
	@which vagrant >/dev/null || "Please install Vagrant: https://www.vagrantup.com"
	@which VBoxManage >/dev/null || "Please install VirtualBox: https://www.virtualbox.org"

.PHONY: .vagrant-scp
.vagrant-scp: .vagrant-check ## Install the vagrant scp plugin
	@if test `vagrant plugin list | grep -c vagrant-scp` -eq 0 ; then \
	    vagrant plugin install vagrant-scp ; fi

freebsd: .vagrant-scp ## Build FreeBSD/pfSense binary using Vagrant VM
	vagrant provision && vagrant up && vagrant scp :$(PROJECT_NAME)/dist/*freebsd* dist/

freebsd-shell: ## SSH into FreeBSD Vagrant VM
	vagrant ssh

freebsd-clean: ## Destroy FreeBSD Vagrant VM
	vagrant destroy -f

######################################################################
# MIPS64 targets for building for Ubiquiti USG/Edgerouter
######################################################################
MIPS64_S_NAME      := $(DIST_DIR)$(PROJECT_NAME)-$(PROJECT_VERSION)-linux-mips64-static

.PHONY: mips64-static
mips64-static: .prepare ## Build Linux/MIPS64 static binary in Docker container
	docker build -t $(DOCKER_REPO)/$(PROJECT_NAME)-mips64:latest -f Dockerfile.mips64 .
	docker run --rm \
	    --volume $(shell pwd):/build/udp-proxy-2020 \
	    $(DOCKER_REPO)/$(PROJECT_NAME)-mips64:latest

.PHONY: mips64-shell
mips64-shell: .prepare ## SSH into Linux/MIPS64 build Docker container
	docker run -it --rm \
	    --volume $(shell pwd):/build/udp-proxy-2020 \
	    --entrypoint /bin/bash \
	    $(DOCKER_REPO)/$(PROJECT_NAME)-mips64:latest

.mips64-static: $(MIPS64_S_NAME)
$(MIPS64_S_NAME): .prepare
	LDFLAGS='-l/usr/mips64-linux-gnuabi64/lib/libpcap.a' \
	    GOOS=linux GOARCH=mips64 CGO_ENABLED=1 CC=mips64-linux-gnuabi64-gcc \
	    PKG_CONFIG_PATH=/usr/mips64-linux-gnuabi64/lib/pkgconfig \
	    go build -ldflags '$(LDFLAGS) -linkmode external -extldflags -static' -o $(MIPS64_S_NAME) cmd/*.go
	@echo "Created: $(MIPS64_S_NAME)"

.PHONY: mips64-clean
mips64-clean: ## Remove Linux/MIPS64 Docker image
	docker image rm $(DOCKER_REPO)/$(PROJECT_NAME)-mips64:latest

######################################################################
# ARM64 targets for building for Linux/ARM64 RaspberryPi/etc
######################################################################
ARM64_S_NAME      := $(DIST_DIR)$(PROJECT_NAME)-$(PROJECT_VERSION)-linux-arm64-static

.PHONY: arm64-static
arm64-static: .prepare ## Build Linux/arm64 static binary in Docker container
	docker build -t $(DOCKER_REPO)/$(PROJECT_NAME)-arm64:latest -f Dockerfile.arm64 .
	docker run --rm \
	    --volume $(shell pwd):/build/udp-proxy-2020 \
	    $(DOCKER_REPO)/$(PROJECT_NAME)-arm64:latest

.PHONY: arm64-shell
arm64-shell: .prepare ## SSH into Linux/arm64 build Docker container
	docker run -it --rm \
	    --volume $(shell pwd):/build/udp-proxy-2020 \
	    --entrypoint /bin/bash \
	    $(DOCKER_REPO)/$(PROJECT_NAME)-arm64:latest

.arm64-static: $(ARM64_S_NAME)
$(ARM64_S_NAME): .prepare
	LDFLAGS='-l/usr/aarch64-linux-gnu/lib/libpcap.a' \
	    GOOS=linux GOARCH=arm64 CGO_ENABLED=1 CC=aarch64-linux-gnu-gcc-10 \
	    PKG_CONFIG_PATH=/usr/aarch64-linux-gnu/lib/pkgconfig \
	    go build -ldflags '$(LDFLAGS) -linkmode external -extldflags -static' -o $(ARM64_S_NAME) cmd/*.go
	@echo "Created: $(arm64_S_NAME)"

.PHONY: arm64-clean
arm64-clean: ## Remove Linux/arm64 Docker image
	docker image rm $(DOCKER_REPO)/$(PROJECT_NAME)-arm64:latest
