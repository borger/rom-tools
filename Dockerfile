# syntax=docker/dockerfile:1
#
# rom-tools — a reusable ROM conversion / management toolchain for the homelab.
#
# Multi-stage: the `builder` stage compiles the from-source tools and downloads
# the prebuilt ones; the final image is Ubuntu 24.04 + apt tooling + the
# collected binaries. Built for linux/amd64 (the MicroK8s nodes are amd64).
#
# Some tools require YOUR OWN dumped keys at runtime (not shipped in the image):
#   - Switch  (hactool, nsz): prod.keys
#   - 3DS     (ctrtool)      : boot9 / aes_keys
# Mount them into the container when you need those platforms.

########################  builder  ########################
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake git ca-certificates curl unzip xz-utils \
      autoconf automake libtool pkg-config \
      liblz4-dev zlib1g-dev libssl-dev libuv1-dev \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /out/bin
WORKDIR /build

# --- Sony PS3: PS3Dec (disc-key ISO decryption) ---
RUN git clone --recursive --depth 1 https://github.com/al3xtjames/PS3Dec.git \
 && cmake -S PS3Dec -B PS3Dec/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build PS3Dec/build -j"$(nproc)" \
 && install -m755 "$(find PS3Dec/build -type f -name PS3Dec -perm -u+x | head -1)" /out/bin/PS3Dec

# --- Sony PSP/PS2: maxcso (CSO/ZSO (de)compression) ---
RUN git clone --depth 1 https://github.com/unknownbrackets/maxcso.git \
 && make -C maxcso -j"$(nproc)" \
 && install -m755 maxcso/maxcso /out/bin/maxcso

# --- Switch: hactool (NCA/NSP/XCI extract + decrypt; needs prod.keys at runtime) ---
RUN git clone --depth 1 https://github.com/SciresM/hactool.git \
 && cp hactool/config.mk.template hactool/config.mk \
 && make -C hactool -j"$(nproc)" \
 && install -m755 hactool/hactool /out/bin/hactool

# --- Nintendo DS: ndstool (.nds extract / rebuild) ---
RUN git clone --depth 1 https://github.com/devkitPro/ndstool.git \
 && cd ndstool && ./autogen.sh && ./configure && make -j"$(nproc)" \
 && install -m755 ndstool /out/bin/ndstool

# --- Xbox / Xbox 360: extract-xiso (ISO pack / unpack) ---
RUN git clone --depth 1 https://github.com/XboxDev/extract-xiso.git \
 && cmake -S extract-xiso -B extract-xiso/build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build extract-xiso/build -j"$(nproc)" \
 && install -m755 extract-xiso/build/extract-xiso /out/bin/extract-xiso

# --- Sony PS4: LibOrbisPkg PkgTool.Core (fpkg build / validate / inspect) ---
RUN curl -fsSL -o pkgtool.zip \
      https://github.com/maxton/LibOrbisPkg/releases/download/v0.2/PkgTool.Core-linux-x64-0.2.231.zip \
 && unzip -q pkgtool.zip -d pkgtool \
 && install -m755 pkgtool/PkgTool.Core /out/bin/PkgTool.Core

# --- 3DS: ctrtool + makerom (CIA/NCCH extract + build) — prebuilt ---
RUN CTRTOOL_VER=v1.3.0 ; MAKEROM_VER=v0.19.0 ; \
    curl -fsSL -o ctrtool.zip "https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-${CTRTOOL_VER}/ctrtool-${CTRTOOL_VER}-ubuntu_x86_64.zip" \
 && unzip -q ctrtool.zip -d ctrtool && install -m755 "$(find ctrtool -type f -name ctrtool | head -1)" /out/bin/ctrtool \
 && curl -fsSL -o makerom.zip "https://github.com/3DSGuy/Project_CTR/releases/download/makerom-${MAKEROM_VER}/makerom-${MAKEROM_VER}-ubuntu_x86_64.zip" \
 && unzip -q makerom.zip -d makerom && install -m755 "$(find makerom -type f -name makerom | head -1)" /out/bin/makerom

# --- GameCube / Wii: Wiimms ISO Tools (wit, wwt) — prebuilt ---
RUN WIT_TARBALL=wit-v3.05a-r8638-x86_64.tar.gz ; \
    curl -fsSL -o wit.tar.gz "https://wit.wiimm.de/download/${WIT_TARBALL}" \
 && tar xzf wit.tar.gz \
 && install -m755 "$(find . -type f -name wit  -perm -u+x | head -1)" /out/bin/wit \
 && install -m755 "$(find . -type f -name wwt  -perm -u+x | head -1)" /out/bin/wwt

########################  runtime  ########################
FROM ubuntu:24.04
LABEL org.opencontainers.image.title="rom-tools" \
      org.opencontainers.image.description="ROM conversion/management toolchain: CHD, PS3/PS4, PSP/PS2 CSO, Switch, 3DS, DS, Xbox/360, GC/Wii" \
      org.opencontainers.image.source="https://github.com/borger/rom-tools"
ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
RUN apt-get update && apt-get install -y --no-install-recommends \
      mame-tools \
      p7zip-full unzip zip unar xorriso genisoimage \
      python3 python3-pip \
      rsync curl wget ca-certificates xxd file coreutils git jq sqlite3 \
      liblz4-1 zlib1g libicu74 libssl3 libuv1 \
 && rm -rf /var/lib/apt/lists/*
# PkgTool.Core is a 2020 .NET Core 3.x binary linked against libssl1.1, which
# Ubuntu 24.04 no longer ships (it has libssl3). Fetch the focal .deb so the
# binary can actually run — being on PATH is not enough (see execution smoke
# test below, which is what caught this).
RUN curl -fsSLO http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb \
 && dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb \
 && rm -f libssl1.1_1.1.1f-1ubuntu2_amd64.deb
# Switch NSZ/XCZ (de)compression (Python, PEP668 override on 24.04)
RUN pip3 install --no-cache-dir --break-system-packages nsz
COPY --from=builder /out/bin/ /usr/local/bin/
# Workflow scripts ship as extensionless commands on PATH (rom-tools, ps3-decrypt,
# ps4-fpkg, chd-convert, gen-gp4).
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*
# Smoke test — presence on PATH AND actual execution for the runtime-linked
# binary. Presence alone is NOT enough: PkgTool.Core was on PATH yet aborted at
# runtime for a missing libssl1.1. `version` is a safe no-op that exercises the
# .NET runtime + its native deps.
RUN set -e; for t in chdman PS3Dec PkgTool.Core maxcso hactool nsz ndstool \
        extract-xiso ctrtool makerom wit wwt 7z xorriso \
        rom-tools ps3-decrypt ps4-fpkg chd-convert gen-gp4; do \
      command -v "$t" >/dev/null || { echo "MISSING: $t"; exit 1; }; \
    done; \
    PkgTool.Core version >/dev/null || { echo "PkgTool.Core present but will not execute"; exit 1; }; \
    echo "rom-tools: tools present; PkgTool executes"
WORKDIR /work
CMD ["/bin/bash"]
