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
- **Wii** (`wii-cdn2wad`) → Wii common key, plus title keys or tickets for the
  titles you are packing

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
| `xiso-convert <extract\|create\|rewrite> <src_dir> <out_dir>` | Batch Xbox/360 XISO work — extract to trees, build ISOs from trees, or repack to strip padding; verifies `default.xbe`/`.xex` and drops bad output |
| `wii-cdn2wad <src_dir> <out_dir> [--title-keys FILE] [--tickets DIR]` | Pack raw Wii NUS/CDN title dumps into installable WADs for Dolphin or a real Wii; SHA-1 verifies every content in the written WAD and drops bad ones |
| `gen-gp4` | Generate a LibOrbisPkg GP4 project from an extracted PS4 directory (used by `ps4-fpkg`) |

> A PKG produced by `ps4-fpkg`/`gen-gp4` is a **fake PKG** — self-signed with a
> fake passcode, so it will not hash-verify against a retail/Redump reference.
> `pkg_validate` confirms internal consistency only. Emulators like shadPS4
> accept it because they skip fake-PKG crypto.

### Wii CDN dumps → WAD

A raw CDN dump (a TMD plus content files named by content ID) is the archival
form of a Wii title; Dolphin installs titles from WADs. `wii-cdn2wad` packs one
dump, or a folder of them, into `<out_dir>/<dump name>.wad`.

A WAD needs a ticket, and CDN dumps of paid titles don't include one. For each
title the script uses the first of these that actually decrypts the contents:

1. a `cetk` / `.tik` inside the dump
2. `--tickets DIR` — `.tik` files named `<title id>.tik`, or copied straight from
   a Wii NAND's `/ticket` folder (`<tid_hi>/<tid_lo>.tik`)
3. `--title-keys FILE` — one `<16-hex title ID> <32-hex title key>` per line

Keys are read from `/keys/wii` (override with `WII_KEYS_DIR` or the flags):

```
/keys/wii/common.key      # required — 16 raw bytes or 32 hex chars
/keys/wii/korean.key      # optional — only for Korean-region tickets
/keys/wii/titlekeys.txt   # optional — used automatically when present
```

```bash
docker run --rm -it -v "$PWD:/work" -v "$HOME/wii-keys:/keys/wii:ro" \
  ghcr.io/borger/rom-tools:latest wii-cdn2wad /work/cdn /work/wad
```

> WADs built from sources 1–2 carry the genuine signed ticket. A WAD built
> from a title key (source 3) needs a new ticket that can't carry Nintendo's
> signature, so it is **fakesigned**. Dolphin installs it anyway because its
> WAD import skips signature checks; a real Wii needs a patched IOS. Either
> way, no WAD from this tool will byte-match one made by another packer.

The WAD's certificate chain is Nintendo's public CA/CP/XS certificates. They
come from the dump itself when it has a `cetk`; otherwise the XS certificate
is fetched from the public NUS System Menu ticket. Pass `--cert-chain FILE` to
work offline.

## Building

The image builds in CI ([`.github/workflows/build.yml`](.github/workflows/build.yml))
on every push to `main`, or locally:

```bash
docker build -t rom-tools .
```

The build compiles the from-source tools (PS3Dec, maxcso, hactool, ndstool,
extract-xiso) and fetches pinned prebuilt releases for the rest, then runs a
smoke test that fails the build if any expected binary is missing from `PATH`,
or if `PkgTool.Core` or `wii-cdn2wad` is present but won't run.

## License

MIT — see [LICENSE](LICENSE). Bundled tools retain their own upstream licenses.
