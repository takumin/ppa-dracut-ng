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
$ sudo apt install docker.io
```

The other tools ([just](https://just.systems/) as the task runner, [curl](https://github.com/stunnel/static-curl) for downloading the source package and [aptly](https://www.aptly.info/) for generating the apt repository) are managed by [aqua](https://aquaproj.github.io/).

```console
$ aqua install
```

Generating the web assets (`just webpage`) additionally requires `gnupg`, which reads the details of the GPG public key embedded in `index.html`.
Generating a new GPG signing key (`just generate-gpg`) additionally requires `gnupg` and `pwgen`.

# Usage
```console
$ just package           # build packages for all platforms
$ just package trixie    # build packages for a single platform
$ just repository        # generate an unsigned apt repository into public/
$ just                   # build, generate and sign the apt repository
$ just --list            # list all recipes
```

Update `SOURCE_VERSION` and `SOURCE_SHA256` (the SHA-256 of the `.dsc` file) in `Justfile` to follow a new Debian release.

# Reference
- Upstream Repository
  - https://github.com/dracut-ng/dracut-ng
- Debian Kernel Team
  - https://salsa.debian.org/kernel-team/dracut
