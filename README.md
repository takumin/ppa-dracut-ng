# ppa-dracut-ng
Personal Package Archive for dracut-ng

# Motivation
dracut-ng is the actively maintained successor of dracut, but the official Apt repositories of Debian stable and Ubuntu LTS ship older versions of it.
This PPA repository rebuilds the latest dracut package maintained by the Debian Kernel Team (from Debian unstable) for Debian 12, Debian 13, Ubuntu 24.04 and Ubuntu 26.04.

# Supported platforms
| Distribution | Codename | Version suffix |
| ------------ | -------- | -------------- |
| Debian 12    | bookworm | `~deb12+1`       |
| Debian 13    | trixie   | `~deb13+1`       |
| Ubuntu 24.04 | noble    | `~ubuntu24.04+1` |
| Ubuntu 26.04 | resolute | `~ubuntu26.04+1` |

Packages are versioned below the original Debian version (e.g. `112-7~deb13+1`), so an official package of the same version takes precedence.

# Backporting changes
The following adjustments are applied automatically at build time (see `assets/build.sh`).

- debhelper compat level 14 is not available on any supported platform, so it falls back to compat level 13 and adds `${misc:Depends}` and `${shlibs:Depends}`, which compat level 14 applies implicitly.
- Debian 12 does not ship `systemd-dev`, so the build dependency is replaced with `systemd`, which provides `systemd.pc` there.
- Tests are skipped with the `nocheck` build profile.

# Required
```console
$ sudo apt install make docker.io apt-utils gnupg pwgen
```

# Usage
```console
$ make package           # build packages for all platforms
$ make package-trixie    # build packages for a single platform
$ make repository        # generate an unsigned apt repository into public/
$ make                   # build, generate and sign the apt repository
```

Update `SOURCE_VERSION` and `SOURCE_SHA256` (the SHA-256 of the `.dsc` file) in `Makefile` to follow a new Debian release.

# Reference
- Upstream Repository
  - https://github.com/dracut-ng/dracut-ng
- Debian Kernel Team
  - https://salsa.debian.org/kernel-team/dracut
