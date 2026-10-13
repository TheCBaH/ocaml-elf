ARG VARIANT=13
FROM debian:${VARIANT}
ARG VARIANT
ARG RISCV32_TOOLCHAIN_TAG=v0.0.1
ENV PATH="/usr/local/riscv32-linux-gnu-toolchain/bin:${PATH}"
# RV32 uses the published riscv32-linux-gnu toolchain (Debian has no rv32 glibc cross
# toolchain); its sysroot is at /usr/riscv32-linux-gnu and its tools under /usr/local.
# The portable suite also assembles rv32 with riscv64-linux-gnu-as -march=rv32... and
# ld -m elf32lriscv. qemu-system-riscv provides qemu-system-riscv32/64. The cross packages
# and the archive exist for 64-bit hosts only; the 32-bit CI legs run the portable suite
# and skip the rest.
RUN set -eux;\
    apt-get update;\
    ARCH="$(dpkg --print-architecture)";\
    case "$ARCH" in\
      amd64|arm64) extra='gcc-riscv64-linux-gnu libc6-dev-riscv64-cross binutils-i686-linux-gnu binutils-x86-64-linux-gnu binutils-arm-linux-gnueabihf binutils-aarch64-linux-gnu binutils-riscv64-linux-gnu qemu-user qemu-system-arm qemu-system-x86 qemu-system-riscv nodejs xz-utils' ;;\
      *) extra='' ;;\
    esac;\
    env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends\
  ca-certificates\
  curl\
  git\
  make\
  $extra\
;\
    case "${VARIANT}:${ARCH}" in\
      12:amd64) riscv32_version='12.4.0'; riscv32_sha256='bcf2f732735e266bdc5e0053ba457e40572582a8a655cd543fa3fee6c98f8e81' ;;\
      12:arm64) riscv32_version='12.4.0'; riscv32_sha256='a44d36346c34d95927cd2c61caf75db4b1217bf0b285098ac30d701e69dc8c7f' ;;\
      13:amd64) riscv32_version='14.2.0'; riscv32_sha256='d3614cb182c72a34dcde5d78e000a561b433fb3f5fb3ffcc9d3221c1296fcc64' ;;\
      13:arm64) riscv32_version='14.2.0'; riscv32_sha256='21d0baece4b124259a99045b6b9ab6498c234c546f5b5d868e8c3df2a5adff47' ;;\
      *) riscv32_version=''; riscv32_sha256='' ;;\
    esac;\
    if [ -n "$riscv32_version" ]; then\
      riscv32_asset="riscv32-linux-gnu-${riscv32_version}-debian-${VARIANT}-${ARCH}.tar.xz";\
      curl -fsSLO "https://github.com/TheCBaH/riscv32-linux-gnu.builder/releases/download/${RISCV32_TOOLCHAIN_TAG}/${riscv32_asset}";\
      echo "${riscv32_sha256}  ${riscv32_asset}" | sha256sum -c -;\
      tar -C / -xJf "$riscv32_asset";\
      rm "$riscv32_asset";\
      riscv32-linux-gnu-gcc --version;\
    fi;\
    apt-get autoremove -y; apt-get clean -y; rm -rf /var/lib/apt/lists/*;\
    echo DONE
