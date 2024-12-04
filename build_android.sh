#!/bin/bash

if [ -f .env ]; then
    source .env
fi

ROOT=$PWD
SDK_VER=23

BORINGSSL_VERSION="0.20241203.0"
NGHTTP2_VERSION="1.64.0"
NGHTTP3_VERSION="1.6.0"
NGTCP2_VERSION="1.9.1"
CURL_VERSION="8.11.0"

if [ -z "$ANDROID_NDK_ROOT" ]; then
    echo "ANDROID_NDK_ROOT is not set"
    exit 1
fi

# sh build_android.sh --arch=armv7
while [[ "$#" -gt 0 ]]; do
    case $1 in
    --arch) ARCH="$2" shift ;;
    *)
        echo "Unknown parameter passed: $1"
        exit 1
        ;;
    esac
    shift
done

if [ -z "$ARCH" ]; then
    echo "ARCH is not set. Use --arch to specify the architecture."
    exit 1
fi

case $ARCH in
armv7) ABI="armeabi-v7a" ;;
arm64) ABI="arm64-v8a" ;;
x86) ABI="x86" ;;
x86_64) ABI="x86_64" ;;
*)
    echo "Unknown architecture: $ARCH, only support: [armv7, arm64, x86, x86_64]"
    exit 1
    ;;
esac

fail() {
    error "$@"
    exit 1
}

error() {
    echo "Error: $@" >&2
}

BUILD_PATH="$ROOT/build/$ABI"
OUT_PATH="$ROOT/out/$ABI"
DEPS_PATH="$ROOT/deps"

# Remove previous output files

rm -rf "$OUT_PATH"

# Build boringssl

if [ ! -d "$DEPS_PATH/boringssl-$BORINGSSL_VERSION" ]; then
    echo "Cloning boringssl..."
    git clone --branch $BORINGSSL_VERSION --single-branch --depth 1 https://boringssl.googlesource.com/boringssl "$DEPS_PATH/boringssl-$BORINGSSL_VERSION" || fail "Failed to clone boringssl"
fi

rm -rf "$BUILD_PATH/boringssl"
mkdir -p "$BUILD_PATH/boringssl"
cd "$BUILD_PATH/boringssl"

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OUT_PATH" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$ABI \
    -DANDROID_PLATFORM=android-$SDK_VER "$DEPS_PATH/boringssl-$BORINGSSL_VERSION" || fail "Failed to configure boringssl"

make -j$(nproc) || fail "Failed to build boringssl"
make install || fail "Failed to install boringssl"
make clean

# Build nghttp2

if [ ! -d "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION" ]; then
    curl -L https://github.com/nghttp2/nghttp2/releases/download/v$NGHTTP2_VERSION/nghttp2-$NGHTTP2_VERSION.tar.gz -o "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION.tar.gz" || fail "Failed to download nghttp2"
    tar -xvf "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract nghttp2"
    rm "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION.tar.gz"
fi

rm -rf "$BUILD_PATH/nghttp2"
mkdir -p "$BUILD_PATH/nghttp2"
cd "$BUILD_PATH/nghttp2"

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OUT_PATH" \
    -DENABLE_LIB_ONLY=ON \
    -DENABLE_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$ABI \
    -DANDROID_PLATFORM=android-$SDK_VER \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION" || fail "Failed to configure nghttp2"
make -j$(nproc) || fail "Failed to build nghttp2"
make install || fail "Failed to install nghttp2"
make clean

# Build nghttp3

if [ ! -d "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION" ]; then
    curl -L https://github.com/ngtcp2/nghttp3/releases/download/v$NGHTTP3_VERSION/nghttp3-$NGHTTP3_VERSION.tar.gz -o "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION.tar.gz" || fail "Failed to download nghttp3"
    tar -xvf "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract nghttp3"
    rm "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION.tar.gz"
fi

rm -rf "$BUILD_PATH/nghttp3"
mkdir -p "$BUILD_PATH/nghttp3"
cd "$BUILD_PATH/nghttp3"

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OUT_PATH" \
    -DENABLE_LIB_ONLY=ON \
    -DENABLE_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$ABI \
    -DANDROID_PLATFORM=android-$SDK_VER \
    -DENABLE_SHARED_LIB=OFF \
    -DENABLE_STATIC_LIB=ON "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION" || fail "Failed to configure nghttp3"
make -j$(nproc) || fail "Failed to build nghttp3"
make install || fail "Failed to install nghttp3"
make clean

# Build ngtcp2

if [ ! -d "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION" ]; then
    curl -L https://github.com/ngtcp2/ngtcp2/releases/download/v$NGTCP2_VERSION/ngtcp2-$NGTCP2_VERSION.tar.gz -o "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION.tar.gz" || fail "Failed to download ngtcp2"
    tar -xvf "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract ngtcp2"
    rm "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION.tar.gz"
fi

rm -rf "$BUILD_PATH/ngtcp2"
mkdir -p "$BUILD_PATH/ngtcp2"
cd "$BUILD_PATH/ngtcp2"

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OUT_PATH" \
    -DBUILD_TESTING=OFF \
    -DENABLE_OPENSSL=OFF \
    -DENABLE_BORINGSSL=ON \
    -DBORINGSSL_INCLUDE_DIR="$OUT_PATH/include" \
    -DBORINGSSL_LIBRARIES="$OUT_PATH/lib/libcrypto.a;$OUT_PATH/lib/libssl.a" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$ABI \
    -DANDROID_PLATFORM=android-$SDK_VER \
    -DENABLE_SHARED_LIB=OFF \
    -DENABLE_STATIC_LIB=ON \
    "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION" || fail "Failed to configure ngtcp2"
make -j$(nproc) check || fail "Failed to build ngtcp2"
make install || fail "Failed to install ngtcp2"
make clean

# Build curl

if [ ! -d "$DEPS_PATH/curl-$CURL_VERSION" ]; then
    curl -L https://curl.se/download/curl-$CURL_VERSION.tar.gz -o "$DEPS_PATH/curl-$CURL_VERSION.tar.gz" || fail "Failed to download curl"
    tar -xvf "$DEPS_PATH/curl-$CURL_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract curl"
    rm "$DEPS_PATH/curl-$CURL_VERSION.tar.gz"
fi

rm -rf "$BUILD_PATH/curl"
mkdir -p "$BUILD_PATH/curl"
cd "$BUILD_PATH/curl"

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$OUT_PATH" \
    -DBUILD_CURL_EXE=OFF \
    -DCURL_USE_OPENSSL=ON \
    -DOPENSSL_INCLUDE_DIR="$OUT_PATH/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$OUT_PATH/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$OUT_PATH/lib/libssl.a" \
    -DOPENSSL_LIBRARIES="$OUT_PATH/lib/libcrypto.a;$OUT_PATH/lib/libssl.a" \
    -DUSE_NGHTTP2=ON \
    -DNGHTTP2_INCLUDE_DIR="$OUT_PATH/include" \
    -DNGHTTP2_LIBRARY="$OUT_PATH/lib/libnghttp2.a" \
    -DNGHTTP3_INCLUDE_DIR="$OUT_PATH/include" \
    -DNGHTTP3_LIBRARY="$OUT_PATH/lib/libnghttp3.a" \
    -DUSE_NGTCP2=ON \
    -DNGTCP2_INCLUDE_DIR="$OUT_PATH/include" \
    -DNGTCP2_LIBRARY="$OUT_PATH/lib/libngtcp2.a" \
    -Dngtcp2_crypto_boringssl_LIBRARY="$OUT_PATH/lib/libngtcp2_crypto_boringssl.a" \
    -DNGTCP2_LIBRARIES="$OUT_PATH/lib/libngtcp2.a;$OUT_PATH/lib/libngtcp2_crypto_boringssl.a" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$ABI \
    -DANDROID_PLATFORM=android-$SDK_VER \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DCMAKE_EXE_LINKER_FLAGS="-lstdc++" "$DEPS_PATH/curl-$CURL_VERSION" || fail "Failed to configure curl"
make -j$(nproc) || fail "Failed to build curl"
make install || fail "Failed to install curl"
make clean
