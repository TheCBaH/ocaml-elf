ARG VARIANT=13
FROM debian:${VARIANT}
# Cross binutils only (no cross GCC): RV32 uses riscv64-linux-gnu-as -march=rv32... and
# ld -m elf32lriscv. qemu-system-riscv provides qemu-system-riscv32/64. The cross packages exist
# for 64-bit hosts only; the 32-bit CI legs run the portable suite and skip the rest.
RUN set -eux;\
    apt-get update;\
    ARCH="$(dpkg --print-architecture)";\
    case "$ARCH" in\
      amd64|arm64) extra='binutils-i686-linux-gnu binutils-x86-64-linux-gnu binutils-arm-linux-gnueabihf binutils-aarch64-linux-gnu binutils-riscv64-linux-gnu qemu-user qemu-system-arm qemu-system-x86 qemu-system-riscv nodejs' ;;\
      *) extra='' ;;\
    esac;\
    env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends\
  ca-certificates\
  curl\
  git\
  make\
  $extra\
;\
    apt-get autoremove -y; apt-get clean -y; rm -rf /var/lib/apt/lists/*;\
    echo DONE
