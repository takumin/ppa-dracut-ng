#!/bin/sh
# Rebuild the Debian source package for the target distribution.
# Runs inside the builder container as root.
#
# Usage: build.sh <dsc> <codename> <version-suffix> <build-type>
#   build-type: "full" (source + any + all) or "any" (architecture-dependent only)

set -eu

DSC="$1"
CODENAME="$2"
SUFFIX="$3"
BUILD_TYPE="$4"

OUTDIR="/build/${CODENAME}"
SRCDIR="${OUTDIR}/source"

rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}"

if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
	trap 'chown -R "${HOST_UID}:${HOST_GID}" "${OUTDIR}"' EXIT
fi

dpkg-source -x "${DSC}" "${SRCDIR}"
cp "$(dirname "${DSC}")"/*.orig.tar.* "${OUTDIR}/"

cd "${SRCDIR}"

apt-get update

# Debian 12 does not ship systemd-dev; systemd.pc is provided by the systemd package.
if ! apt-cache show systemd-dev >/dev/null 2>&1; then
	sed -i 's/^\(\s*\)systemd-dev\(,\?\)$/\1systemd\2/' debian/control
fi

# debhelper compat 14 is only available in Debian testing/unstable.
# Fall back to compat 13 and list the substvars that compat 14 applies implicitly.
if ! dpkg-query -W -f '${Provides}' debhelper | grep -q 'debhelper-compat (= 14)'; then
	sed -i 's/debhelper-compat (= 14)/debhelper-compat (= 13)/' debian/control
	perl -0777 -i -pe '
		s{^(Package:.*?)(?=\n\n|\n*\z)}{
			my $s = $1;
			$s =~ s/^(Depends:[^\n]*(?:\n[ \t][^\n]*)*)/$1,\n         \${misc:Depends},\n         \${shlibs:Depends}/m
				or $s =~ s/^(Architecture:[^\n]*)/$1\nDepends: \${misc:Depends}, \${shlibs:Depends}/m;
			$s;
		}gems;
	' debian/control
fi

VERSION="$(dpkg-parsechangelog -S Version)~${SUFFIX}+1"
dch -b --newversion "${VERSION}" --distribution "${CODENAME}" --force-distribution \
	"Rebuild for ${CODENAME}."

apt-get build-dep -y --no-install-recommends -P nocheck .

case "${BUILD_TYPE}" in
	full) BUILD_OPTS="" ;;
	any)  BUILD_OPTS="-B" ;;
	*)    echo "unknown build type: ${BUILD_TYPE}" >&2; exit 1 ;;
esac

# shellcheck disable=SC2086
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc --build-profiles=nocheck ${BUILD_OPTS}
