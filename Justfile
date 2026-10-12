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
repository *targets:
    #!/usr/bin/env bash
    set -euo pipefail
    for dist in {{ if targets == "" { dists } else { targets } }}; do
        mkdir -p "public/pool/${dist}/main" build/conf
        for arch in {{ architectures }} all; do
            mkdir -p "public/dists/${dist}/main/binary-${arch}"
        done
        mkdir -p "public/dists/${dist}/main/source"
        cp "build/${dist}"/*.dsc "build/${dist}"/*.tar.* "build/${dist}"/*.deb "public/pool/${dist}/main/"
        sed -e "s/@CODENAME@/${dist}/g" -e "s/@ARCHITECTURES@/{{ architectures }}/g" \
            assets/repos.conf.in > "build/conf/${dist}-repos.conf"
        sed -e "s/@CODENAME@/${dist}/g" -e "s/@ARCHITECTURES@/{{ architectures }}/g" \
            assets/meta.conf.in > "build/conf/${dist}-meta.conf"
        (cd public && apt-ftparchive generate "../build/conf/${dist}-repos.conf")
        (cd public && apt-ftparchive -c "../build/conf/${dist}-meta.conf" release "dists/${dist}" > "dists/${dist}/Release")
    done

# Generate a signed apt repository into public/ (all platforms by default)
reposign *targets: import-gpg (repository targets)
    #!/usr/bin/env bash
    set -euo pipefail
    for dist in {{ if targets == "" { dists } else { targets } }}; do
        gpg --homedir secret/gpghome --batch \
            --pinentry-mode loopback \
            --passphrase "$(cat secret/passphrase)" \
            --yes \
            --clearsign \
            -o "public/dists/${dist}/InRelease" \
            "public/dists/${dist}/Release"
        gpg --homedir secret/gpghome --batch \
            --pinentry-mode loopback \
            --passphrase "$(cat secret/passphrase)" \
            --yes \
            -abs \
            -o "public/dists/${dist}/Release.gpg" \
            "public/dists/${dist}/Release"
    done

# Generate and sign the apt repository with the web assets
assets: reposign
    cp assets/index.html public/index.html
    cp assets/public.gpg.asc public/public.gpg.asc

# Import the GPG signing key
import-gpg:
    mkdir -p -m 0700 secret/gpghome
    gpg --homedir secret/gpghome --batch \
        --pinentry-mode loopback \
        --passphrase "$(cat secret/passphrase)" \
        --import \
        --allow-secret-key-import \
        secret/secret.gpg.asc

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
    rm -fr build public secret/gpghome

# Remove the build outputs, the download cache and the builder images
deepclean: clean
    rm -fr cache
    for dist in {{ dists }}; do docker rmi -f "{{ docker_image }}:${dist}" >/dev/null 2>&1 || true; done
