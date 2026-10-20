#!/usr/bin/env bash
set -euo pipefail
jobs=${BUILD_JOBS:-4}
git clone --depth 1 --branch "$FTL_VERSION" https://github.com/pi-hole/FTL.git FTL
test "$(git -C FTL rev-parse HEAD)" = "$FTL_COMMIT"
git -C FTL apply /build/armv5-events.patch
cp /build/event_atomic.h FTL/src/event_atomic.h
cmake -S FTL -B ftl-build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$CFLAGS" \
    -DUSE_MBED_TLS=ON -DUSE_READLINE=ON | tee /build/ftl-configure.log
grep -q "Building FTL with TLS support: YES" /build/ftl-configure.log
cmake --build ftl-build --parallel "$jobs"
mkdir -p /out
cp ftl-build/pihole-FTL /out/pihole-FTL
file /out/pihole-FTL | tee /out/file.txt
readelf -A /out/pihole-FTL | tee /out/attributes.txt
grep -q 'Tag_CPU_arch: v5TE' /out/attributes.txt
if grep -q 'Tag_ABI_VFP_args: VFP registers' /out/attributes.txt; then
    echo 'Unexpected hard-float ABI' >&2; exit 1
fi
/out/pihole-FTL --version
ldd /out/pihole-FTL | tee /out/libraries.txt
(cd /out && sha256sum pihole-FTL > SHA256SUMS)
git -C FTL rev-parse HEAD > /out/FTL_COMMIT
cp FTL/LICENSE /out/LICENSE
