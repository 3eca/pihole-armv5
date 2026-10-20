#!/usr/bin/env bash
set -euo pipefail
jobs=${BUILD_JOBS:-2}
curl -fL --retry 3 https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz -o nettle.tar.gz
echo 'fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5  nettle.tar.gz' | sha256sum -c -
tar -xf nettle.tar.gz
(cd nettle-3.10.2 && ./configure --libdir=/usr/local/lib --enable-static --disable-shared \
    --disable-assembler --disable-fat --disable-openssl --disable-mini-gmp --disable-gcov --disable-documentation \
    && make -j "$jobs" && make install)
curl -fL --retry 3 https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-4.0.0/mbedtls-4.0.0.tar.bz2 -o mbedtls.tar.bz2
echo '2f3a47f7b3a541ddef450e4867eeecb7ce2ef7776093f3a11d6d43ead6bf2827  mbedtls.tar.bz2' | sha256sum -c -
tar -xf mbedtls.tar.bz2
sed -i '/#define MBEDTLS_THREADING_C/s|^//||; /#define MBEDTLS_THREADING_PTHREAD/s|^//||' \
    mbedtls-4.0.0/tf-psa-crypto/include/psa/crypto_config.h
cmake -S mbedtls-4.0.0 -B mbedtls-build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS -fomit-frame-pointer" -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF
cmake --build mbedtls-build --parallel "$jobs"
cmake --install mbedtls-build
