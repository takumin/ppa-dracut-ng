set shell := ["bash", "-euo", "pipefail", "-c"]

source_package := "dracut"
source_version := "112-7"
source_dsc := source_package + "_" + source_version + ".dsc"
source_sha256 := "6f0d1e4a2c3e903af1261dace7ce4dc3962f1885a141ba476e894146b842f289"
source_pool := "https://deb.debian.org/debian/pool/main/d/" + source_package

debfullname := env("DEBFULLNAME", "Takumi Takahashi")
debemail := env("DEBEMAIL", "takumiiinn@gmail.com")

docker_image := env("DOCKER_IMAGE", "takumi/ppa-dracut-ng")

# full: source + architecture-dependent + architecture-independent packages
# any:  architecture-dependent packages only (for additional architectures)
build_type := env("BUILD_TYPE", "full")

architectures := "amd64 arm64"

dists := "bookworm trixie noble resolute"

aptly_origin := "takumi.tmfam.com"
aptly_label := "Personal Package Archive for dracut-ng"

# Build, generate and sign the apt repository
all: package assets

# Build the builder images (all platforms by default)
builder *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    for dist in {{ if targets == "" { dists } else { targets } }}; do
        case "${dist}" in
            bookworm) image="docker.io/library/debian:12-slim" ;;
            trixie)   image="docker.io/library/debian:13-slim" ;;
            noble)    image="docker.io/library/ubuntu:24.04" ;;
            resolute) image="docker.io/library/ubuntu:26.04" ;;
            *)        echo "unknown distribution: ${dist}" >&2; exit 1 ;;
        esac
        docker build \
            --build-arg "DEBFULLNAME={{ debfullname }}" \
            --build-arg "DEBEMAIL={{ debemail }}" \
            --build-arg "BASE_IMAGE=${image}" \
            --tag "{{ docker_image }}:${dist}" \
            .
    done

# Download and verify the Debian source package
download:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "cache/{{ source_dsc }}" && exit 0
    mkdir -p cache
    curl -fsSL -o "cache/{{ source_dsc }}.tmp" "{{ source_pool }}/{{ source_dsc }}"
    echo "{{ source_sha256 }}  cache/{{ source_dsc }}.tmp" | sha256sum -c -
    for f in $(sed -n '/^Files:/,/^$/p' "cache/{{ source_dsc }}.tmp" | awk 'NF == 3 { print $3 }'); do
        test -f "cache/${f}" || curl -fsSL -o "cache/${f}" "{{ source_pool }}/${f}"
    done
    mv "cache/{{ source_dsc }}.tmp" "cache/{{ source_dsc }}"

# Build packages (all platforms by default)
package *targets: download (builder targets)
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build
    for dist in {{ if targets == "" { dists } else { targets } }}; do
        case "${dist}" in
            bookworm) suffix="deb12" ;;
            trixie)   suffix="deb13" ;;
            noble)    suffix="ubuntu24.04" ;;
            resolute) suffix="ubuntu26.04" ;;
            *)        echo "unknown distribution: ${dist}" >&2; exit 1 ;;
        esac
        docker run --rm \
            -e "HOST_UID=$(id -u)" \
            -e "HOST_GID=$(id -g)" \
            -v "{{ justfile_directory() }}/assets/build.sh:/build.sh:ro" \
            -v "{{ justfile_directory() }}/cache:/cache:ro" \
            -v "{{ justfile_directory() }}/build:/build" \
            "{{ docker_image }}:${dist}" \
            sh /build.sh "/cache/{{ source_dsc }}" "${dist}" "${suffix}" "{{ build_type }}"
    done

# Generate an unsigned apt repository into public/ (all platforms by default)
repository *targets: (_publish "false" targets)

# Generate a signed apt repository into public/ (all platforms by default)
reposign *targets: (_publish "true" targets)

_publish sign *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    sign_opts=(-skip-signing)
    if [ "{{ sign }}" = "true" ]; then
        # The internal GPG provider of aptly only reads binary keyrings, so strip the ASCII armor.
        mkdir -p -m 0700 build/keyring
        dearmor() { sed -e '1,/^$/d' -e '/^=/,$d' "$1" | base64 -d > "$2"; }
        dearmor assets/public.gpg.asc build/keyring/public.gpg
        dearmor secret/secret.gpg.asc build/keyring/secret.gpg
        sign_opts=(
            -gpg-provider="internal"
            -keyring="{{ justfile_directory() }}/build/keyring/public.gpg"
            -secret-keyring="{{ justfile_directory() }}/build/keyring/secret.gpg"
            -passphrase-file="{{ justfile_directory() }}/secret/passphrase"
        )
    fi
    for dist in {{ if targets == "" { dists } else { targets } }}; do
        if [ ! -d "build/${dist}" ]; then
            echo "no packages for distribution: ${dist}" >&2
            exit 1
        fi
        conf="build/aptly/${dist}/aptly.conf"
        rm -fr "build/aptly/${dist}" "public/dists/${dist}"
        mkdir -p "build/aptly/${dist}" public
        printf '{"rootDir":"%s","FileSystemPublishEndpoints":{"public":{"rootDir":"%s","linkMethod":"copy"}}}\n' \
            "{{ justfile_directory() }}/build/aptly/${dist}" "{{ justfile_directory() }}/public" > "${conf}"
        aptly -config="${conf}" repo create \
            -distribution="${dist}" \
            -component="main" \
            "${dist}"
        aptly -config="${conf}" repo add "${dist}" "build/${dist}"/*.dsc "build/${dist}"/*.deb
        aptly -config="${conf}" publish repo \
            -batch \
            -architectures="{{ replace(architectures + " all source", " ", ",") }}" \
            -origin="{{ aptly_origin }}" \
            -label="{{ aptly_label }}" \
            "${sign_opts[@]}" \
            "${dist}" filesystem:public:.
    done

# Generate and sign the apt repository with the web assets
assets: reposign
    cp assets/index.html public/index.html
    cp assets/public.gpg.asc public/public.gpg.asc

# Generate a new GPG signing key (requires gnupg and pwgen)
generate-gpg:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f secret/passphrase ]; then
        mkdir -p -m 0700 secret
        pwgen -ncys1 64 > secret/passphrase
        chmod 0600 secret/passphrase
    fi
    if [ ! -d secret/gpghome ]; then
        mkdir -p -m 0700 secret/gpghome
        gpg --homedir secret/gpghome --batch \
            --pinentry-mode loopback \
            --passphrase "$(cat secret/passphrase)" \
            --quick-generate-key "{{ debfullname }} <{{ debemail }}>" \
            default default 10y
    fi
    gpg --homedir secret/gpghome --batch \
        --export --armor \
        --output assets/public.gpg.asc \
        --yes \
        "{{ debfullname }} <{{ debemail }}>"
    gpg --homedir secret/gpghome --batch \
        --pinentry-mode loopback \
        --passphrase "$(cat secret/passphrase)" \
        --export-secret-keys --armor \
        --output secret/secret.gpg.asc \
        --yes \
        "{{ debfullname }} <{{ debemail }}>"

# Remove the build outputs
clean:
    rm -fr build public

# Remove the build outputs, the download cache and the builder images
deepclean: clean
    rm -fr cache
    for dist in {{ dists }}; do docker rmi -f "{{ docker_image }}:${dist}" >/dev/null 2>&1 || true; done
