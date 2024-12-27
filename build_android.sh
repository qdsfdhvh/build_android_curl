#!/bin/bash

if [ -f .env ]; then
    source .env
fi

ROOT=$PWD
SDK_VER=24

ZLIB_VERSION="1.3.1"
OPENSSL_VERSION="3.4.0"
CURL_VERSION="8.11.1"

if [ -z "$ANDROID_NDK_ROOT" ]; then
    echo "ANDROID_NDK_ROOT is not set"
    exit 1
fi

# 解析参数 --arch, 运行: sh build_android.sh --arch armv7
while [ "$#" -gt 0 ]; do
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
armv7)
    ABI="armeabi-v7a"
    HOST="armv7a-linux-androideabi"
    ;;
arm64)
    ABI="arm64-v8a"
    HOST="aarch64-linux-android"
    ;;
x86)
    ABI="x86"
    HOST="i686-linux-android"
    ;;
x86_64)
    ABI="x86_64"
    HOST="x86_64-linux-android"
    ;;
*)
    echo "Unknown architecture: $ARCH"
    exit 1
    ;;
esac

# 获取 CPU 核心数

get_cpu_cores() {
    if command -v nproc >/dev/null; then
        nproc
    elif command -v sysctl >/dev/null; then
        sysctl -n hw.ncpu
    elif [ -f /proc/cpuinfo ]; then
        grep -c ^processor /proc/cpuinfo
    else
        getconf _NPROCESSORS_ONLN
    fi
}
CORES=$(get_cpu_cores)

# 输出错误信息

fail() {
    error "$@"
    exit 1
}

error() {
    echo "Error: $@" >&2
}

# 配置 NDK 工具链

case "$(uname -s)" in
Darwin) export HOST_TAG=darwin-x86_64 ;;
Linux) export HOST_TAG=linux-x86_64 ;;
*)
    echo "Unknown platform: $(uname -s)"
    exit 1
    ;;
esac

export TOOLCHAIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG"

export PATH="$TOOLCHAIN/bin:$PATH"
export PATH="$ANDROID_NDK_ROOT/prebuilt/$NDK_PLATFORM/bin:$PATH"

export AR="$TOOLCHAIN/bin/llvm-ar"
export AS="$TOOLCHAIN/bin/llvm-as"
export CC="$TOOLCHAIN/bin/$HOST$SDK_VER-clang"
export CXX="$TOOLCHAIN/bin/$HOST$SDK_VER-clang++"
export LD="$TOOLCHAIN/bin/ld"
export RANDLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"

echo "========================================"
echo "SDK_VER: $SDK_VER"
echo "ARCH: $ARCH"
echo "ABI: $ABI"
echo "HOST: $HOST"
echo "ANDROID_NDK_ROOT: $ANDROID_NDK_ROOT"
echo "TOOLCHAIN: $TOOLCHAIN"
echo "AR: $AR"
echo "AS: $AS"
echo "CC: $CC"
echo "CXX: $CXX"
echo "LD: $LD"
echo "RANDLIB: $RANDLIB"
echo "STRIP: $STRIP"
echo "========================================"

# 配置编译相关路径

OUT_PATH="$ROOT/out/$ABI"
DEPS_PATH="$ROOT/deps"

# 尝试创建依赖目录

mkdir -p $DEPS_PATH

# 删除旧 out 路径

rm -rf "$OUT_PATH"

# Build zlib

if [ ! -d "$DEPS_PATH/zlib-$ZLIB_VERSION" ]; then
    curl -L https://zlib.net/zlib-$ZLIB_VERSION.tar.gz -o "$DEPS_PATH/zlib-$ZLIB_VERSION.tar.gz" || fail "Failed to download zlib"
    tar -xvf "$DEPS_PATH/zlib-$ZLIB_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract zlib"
    rm "$DEPS_PATH/zlib-$ZLIB_VERSION.tar.gz"
fi

cd "$DEPS_PATH/zlib-$ZLIB_VERSION"

export CHOST=$HOST
./configure --prefix="$OUT_PATH" --static || fail "Failed to configure zlib"

make clean
make -j$CORES || fail "Failed to build zlib"
make install || fail "Failed to install zlib"

# Build openssl

if [ ! -d "$DEPS_PATH/openssl-$OPENSSL_VERSION" ]; then
    curl -L https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz -o "$DEPS_PATH/openssl-$OPENSSL_VERSION.tar.gz" || fail "Failed to download openssl"
    tar -xvf "$DEPS_PATH/openssl-$OPENSSL_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract openssl"
    rm "$DEPS_PATH/openssl-$OPENSSL_VERSION.tar.gz"
fi

cd "$DEPS_PATH/openssl-$OPENSSL_VERSION"

./Configure android-$ARCH \
    -D__ANDROID_API__=$SDK_VER \
    --prefix="$OUT_PATH" \
    no-shared || fail "Failed to configure openssl"

make clean
make -j$CORES || fail "Failed to build openssl"
make install_sw || fail "Failed to install openssl"

# Build curl

if [ ! -d "$DEPS_PATH/curl-$CURL_VERSION" ]; then
    curl -L https://curl.se/download/curl-$CURL_VERSION.tar.gz -o "$DEPS_PATH/curl-$CURL_VERSION.tar.gz" || fail "Failed to download curl"
    tar -xvf "$DEPS_PATH/curl-$CURL_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract curl"
    rm "$DEPS_PATH/curl-$CURL_VERSION.tar.gz"
fi

cd "$DEPS_PATH/curl-$CURL_VERSION"

rm -rf "$BUILD_PATH/curl"
mkdir -p "$BUILD_PATH/curl"
cd "$BUILD_PATH/curl"

./configure --prefix="$OUT_PATH" \
    --host=$HOST \
    --with-zlib="$OUT_PATH" \
    --without-libpsl \
    --with-ssl="$OUT_PATH" \
    --with-pic \
    --enable-ipv6 \
    --enable-unix-sockets \
    --enable-tls-srp \
    --disable-ldap \
    --disable-ldaps \
    --disable-dict \
    --disable-gopher \
    --disable-imap \
    --disable-smtp \
    --disable-rtsp \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-mqtt \
    --disable-ftp \
    --disable-smb \
    --enable-static \
    --disable-shared || fail "Failed to configure curl"
# --with-nghttp2="$OUT_PATH" \
# --with-nghttp3="$OUT_PATH" \
# --with-ngtcp2="$OUT_PATH" \
# --enable-ech \
# --with-ca-bundle="/system/etc/security/cacert.pem" \
# --with-ca-path="/system/etc/security/cacerts" \

make clean
make -j$CORES || fail "Failed to build curl"
make install || fail "Failed to install curl"

echo "Build completed successfully"

# print versions
rm -f "$OUT_PATH/version.txt"
cat >"$OUT_PATH/version.txt" <<EOF
ZLIB version: $ZLIB_VERSION
OPENSSL version: $OPENSSL_VERSION
CURL version: $CURL_VERSION
EOF
