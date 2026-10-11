SOURCE_PACKAGE := dracut
SOURCE_VERSION := 112-7
SOURCE_DSC     := $(SOURCE_PACKAGE)_$(SOURCE_VERSION).dsc
SOURCE_SHA256  := 6f0d1e4a2c3e903af1261dace7ce4dc3962f1885a141ba476e894146b842f289
SOURCE_POOL    := https://deb.debian.org/debian/pool/main/d/$(SOURCE_PACKAGE)

DEBFULLNAME ?= Takumi Takahashi
DEBEMAIL    ?= takumiiinn@gmail.com

DOCKER_IMAGE      ?= takumi/ppa-dracut-ng
DOCKER_BUILD_ARGS ?= --build-arg "DEBFULLNAME=$(DEBFULLNAME)" --build-arg "DEBEMAIL=$(DEBEMAIL)"

# full: source + architecture-dependent + architecture-independent packages
# any:  architecture-dependent packages only (for additional architectures)
BUILD_TYPE ?= full

ARCHITECTURES := amd64 arm64

# codename => base image / version suffix
DISTS := bookworm trixie noble resolute

IMAGE_bookworm  := docker.io/library/debian:12-slim
IMAGE_trixie    := docker.io/library/debian:13-slim
IMAGE_noble     := docker.io/library/ubuntu:24.04
IMAGE_resolute  := docker.io/library/ubuntu:26.04

SUFFIX_bookworm := deb12
SUFFIX_trixie   := deb13
SUFFIX_noble    := ubuntu24.04
SUFFIX_resolute := ubuntu26.04

.PHONY: all
all: package assets

.PHONY: builder
builder: $(addprefix builder-,$(DISTS))
builder-%:
	@docker build $(DOCKER_BUILD_ARGS) --build-arg "BASE_IMAGE=$(IMAGE_$*)" --tag $(DOCKER_IMAGE):$* .

.PHONY: download
download: cache/$(SOURCE_DSC)
cache/$(SOURCE_DSC):
	@mkdir -p cache
	@curl -fsSL -o "cache/$(SOURCE_DSC).tmp" "$(SOURCE_POOL)/$(SOURCE_DSC)"
	@echo "$(SOURCE_SHA256)  cache/$(SOURCE_DSC).tmp" | sha256sum -c -
	@for f in $$(sed -n '/^Files:/,/^$$/p' "cache/$(SOURCE_DSC).tmp" | awk 'NF == 3 { print $$3 }'); do \
		test -f "cache/$$f" || curl -fsSL -o "cache/$$f" "$(SOURCE_POOL)/$$f"; \
	done
	@mv "cache/$(SOURCE_DSC).tmp" "cache/$(SOURCE_DSC)"

.PHONY: package
package: $(addprefix package-,$(DISTS))
package-%: download builder-%
	@mkdir -p build
	@docker run --rm \
		-e "HOST_UID=$$(id -u)" \
		-e "HOST_GID=$$(id -g)" \
		-v "$(CURDIR)/assets/build.sh:/build.sh:ro" \
		-v "$(CURDIR)/cache:/cache:ro" \
		-v "$(CURDIR)/build:/build" \
		$(DOCKER_IMAGE):$* \
		sh /build.sh "/cache/$(SOURCE_DSC)" "$*" "$(SUFFIX_$*)" "$(BUILD_TYPE)"

.PHONY: repository
repository: $(addprefix repository-,$(DISTS))
repository-%:
	@mkdir -p public/pool/$*/main build/conf
	@$(foreach arch,$(ARCHITECTURES) all,mkdir -p public/dists/$*/main/binary-$(arch);)
	@mkdir -p public/dists/$*/main/source
	@cp build/$*/*.dsc build/$*/*.tar.* build/$*/*.deb public/pool/$*/main/
	@sed -e "s/@CODENAME@/$*/g" -e "s/@ARCHITECTURES@/$(ARCHITECTURES)/g" \
		assets/repos.conf.in > build/conf/$*-repos.conf
	@sed -e "s/@CODENAME@/$*/g" -e "s/@ARCHITECTURES@/$(ARCHITECTURES)/g" \
		assets/meta.conf.in > build/conf/$*-meta.conf
	@cd public && apt-ftparchive generate ../build/conf/$*-repos.conf
	@cd public && apt-ftparchive -c ../build/conf/$*-meta.conf release dists/$* > dists/$*/Release

.PHONY: reposign
reposign: import-gpg repository $(addprefix reposign-,$(DISTS))
reposign-%: import-gpg repository-%
	@gpg --homedir secret/gpghome --batch \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--yes \
		--clearsign \
		-o public/dists/$*/InRelease \
		public/dists/$*/Release
	@gpg --homedir secret/gpghome --batch \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--yes \
		-abs \
		-o public/dists/$*/Release.gpg \
		public/dists/$*/Release

.PHONY: assets
assets: reposign
	@cp assets/index.html public/index.html
	@cp assets/public.gpg.asc public/public.gpg.asc

.PHONY: import-gpg
import-gpg:
	@mkdir -p -m 0700 secret/gpghome
	@gpg --homedir secret/gpghome --batch \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--import \
		--allow-secret-key-import \
		secret/secret.gpg.asc

.PHONY: generate-gpg
generate-gpg: assets/public.gpg.asc secret/secret.gpg.asc
secret/passphrase:
	@mkdir -p -m 0700 secret
	@pwgen -ncys1 64 > secret/passphrase
	@chmod 0600 secret/passphrase
secret/gpghome: secret/passphrase
	@mkdir -p -m 0700 secret/gpghome
	@gpg --homedir secret/gpghome --batch \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--quick-generate-key "$(DEBFULLNAME) <$(DEBEMAIL)>" \
		default default 10y
assets/public.gpg.asc: secret/gpghome
	@gpg --homedir secret/gpghome --batch \
		--export --armor \
		--output assets/public.gpg.asc \
		--yes \
		"$(DEBFULLNAME) <$(DEBEMAIL)>"
secret/secret.gpg.asc: secret/gpghome secret/passphrase
	@gpg --homedir secret/gpghome --batch \
		--pinentry-mode loopback \
		--passphrase "$$(cat secret/passphrase)" \
		--export-secret-keys --armor \
		--output secret/secret.gpg.asc \
		--yes \
		"$(DEBFULLNAME) <$(DEBEMAIL)>"

.PHONY: clean
clean:
	@rm -fr build
	@rm -fr public
	@rm -fr secret/gpghome

.PHONY: deepclean
deepclean: clean
	@rm -fr cache
	@$(foreach dist,$(DISTS),docker rmi -f $(DOCKER_IMAGE):$(dist) >/dev/null 2>&1;) true
