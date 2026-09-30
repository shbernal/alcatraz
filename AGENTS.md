# AI project guidelines

`alcatraz`: macOS in a container. One Docker image runs QEMU/KVM with OSX-KVM's OpenCore and installs macOS from Apple's recovery servers. Hard fork of sickcodes/Docker-OSX.

- Key commands
  - `docker build -t alcatraz .`
  - Tests (shellcheck, offline checks, boot smoke test): see CONTRIBUTING.md

- Key documentation
  - [README.md](README.md), [FAQ.md](FAQ.md)
  - [CONTRIBUTING.md](CONTRIBUTING.md): build, layout, testing, bumping OSX-KVM
  - [docs/metadata-files.md](docs/metadata-files.md)

- Project rules
  - Naming and layout follow what makes sense in this project, not Docker-OSX. Renames that break users go in a major release with a row in the README's upgrade table.
  - Upstream OSX-KVM in `/opt/osx-kvm` stays as fetched; container state lives only in `/data`.
  - GPL-3.0-or-later. `LICENSE` stays byte-for-byte; attribution lives in `CREDITS.md`.
  - `OSX_KVM_REF` bumps are deliberate and need a boot test.

- Iron Laws
  - Tokens are expensive, state of the art models need minimal guidance, don't repeat yourself, don't babysit, don't be over-specific.
  - AI-native project. All code is AI-generated.
  - Minimal attention when model implements without errors, we document in more detail when model struggles.
  - Do not expect the user to have read each line, don't lose him on the internals, give visibility on a higher-architectural level.
  - No journaling: code comments / documentation describe current state, they don't carry a log of their own edit history.
