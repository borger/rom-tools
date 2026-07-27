# rom-tools

A single container image bundling the command-line tools needed to convert,
inspect, and manage a multi-console ROM library — CHD conversion, PS3/PS4
packaging, disc-image (de)compression, and per-platform format tools for
Nintendo, Sony, Sega, and Microsoft systems.

Built for `linux/amd64` and published to the GitHub Container Registry:

```
ghcr.io/borger/rom-tools:latest
```

## What's inside

| Tool | Platform / purpose |
|---|---|
| `chdman` (mame-tools) | CHD ⇄ CUE/GDI/ISO — PSX, Saturn, Dreamcast, PS2, Sega/PCE CD, Neo Geo CD |
| `PS3Dec` | PS3 disc-key ISO decryption |
| `PkgTool.Core` (LibOrbisPkg) | PS4 PKG build / validate / inspect / extract |
| `maxcso` | PSP / PS2 CSO / ZSO (de)compression |
| `wit`, `wwt` (Wiimms ISO Tools) | GameCube / Wii — ISO ⇄ WBFS ⇄ CISO |
| `hactool` | Switch — NCA / NSP / XCI extract + decrypt |
| `nsz` | Switch — NSZ / XCZ (de)compression |
| `ctrtool`, `makerom` | 3DS — CIA / NCCH extract + build |
| `ndstool` | Nintendo DS — `.nds` extract / rebuild |
| `extract-xiso` | Xbox / Xbox 360 — ISO pack / unpack |
| `7z`, `unzip`, `unar`, `zip`, `xorriso`, `genisoimage` | archives + ISO authoring |
| `python3`, `jq`, `sqlite3`, `rsync`, `curl`, `xxd`, `file` | glue + verification |

Run `rom-tools` inside the container for a live inventory of every binary and
its path.

### Keys are not included

A few tools need copyrighted keys that must come from **your own hardware** —
they are deliberately **not** shipped in the image:

- **Switch** (`hactool`, `nsz`) → `prod.keys`
- **3DS** (`ctrtool`) → `boot9` / AES key material

Mount them into the container at runtime when you need those platforms.

## Usage

Run it directly with Docker/Podman:

```bash
docker run --rm -it -v "$PWD:/work" ghcr.io/borger/rom-tools:latest
# e.g. convert a CUE to CHD:
chdman createcd -i game.cue -o game.chd
```

Or run it as a Kubernetes worker pod — see [`k8s/rom-worker.example.yaml`](k8s/rom-worker.example.yaml)
for a template (mount your ROM library, exec in, run conversions).

## Workflow scripts

Beyond the raw tools, a few higher-level workflows ship as commands on `PATH`
([`scripts/`](scripts/)):

| Command | What it does |
|---|---|
| `rom-tools` | List the bundled toolchain and confirm every binary is present |
| `ps3-decrypt <src_dir> <dkey_dir> <out_dir>` | Batch-decrypt Redump PS3 images with their disc keys; SCE-verifies each result and drops bad ones |
| `ps4-fpkg <extracted_dir> <out_dir> [--category gd]` | Repack an extracted PS4 game into a single fake-PKG (`gen-gp4` → `pkg_build` → `pkg_validate`) |
| `chd-convert <src_dir> <out_dir>` | Convert every `.cue`/`.gdi` to CHD and build `.m3u` for multi-disc sets |
| `gen-gp4` | Generate a LibOrbisPkg GP4 project from an extracted PS4 directory (used by `ps4-fpkg`) |

> A PKG produced by `ps4-fpkg`/`gen-gp4` is a **fake PKG** — self-signed with a
> fake passcode, so it will not hash-verify against a retail/Redump reference.
> `pkg_validate` confirms internal consistency only. Emulators like shadPS4
> accept it because they skip fake-PKG crypto.

## Building

The image builds in CI ([`.github/workflows/build.yml`](.github/workflows/build.yml))
on every push to `main`, or locally:

```bash
docker build -t rom-tools .
```

The build compiles the from-source tools (PS3Dec, maxcso, hactool, ndstool,
extract-xiso) and fetches pinned prebuilt releases for the rest, then runs a
smoke test that fails the build if any expected binary is missing from `PATH`.

## License

MIT — see [LICENSE](LICENSE). Bundled tools retain their own upstream licenses.
