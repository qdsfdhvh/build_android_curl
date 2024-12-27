#!/bin/bash

if [ -f .env ]; then
    source .env
fi

ROOT=$PWD
SDK_VER=21

ZLIB_VERSION="1.3.1"
PSL_VERSION="0.21.5"
BORINGSSL_VERSION="0.20241209.0"
NGHTTP2_VERSION="1.64.0"
NGHTTP3_VERSION="1.7.0"
NGTCP2_VERSION="1.9.1"
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

export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
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
MESON_PATH="$ROOT/meson"

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
./configure --prefix="$OUT_PATH" || fail "Failed to configure zlib"

make clean
make -j$CORES || fail "Failed to build zlib"
make install || fail "Failed to install zlib"

# Build psl

if [ ! -d "$DEPS_PATH/libpsl-$PSL_VERSION" ]; then
    curl -L https://github.com/rockdaboot/libpsl/releases/download/$PSL_VERSION/libpsl-$PSL_VERSION.tar.gz -o "$DEPS_PATH/psl-$PSL_VERSION.tar.gz" || fail "Failed to download psl"
    tar -zxf "$DEPS_PATH/psl-$PSL_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract psl"
    rm "$DEPS_PATH/psl-$PSL_VERSION.tar.gz" || fail "Failed to remove psl"
fi

cd "$DEPS_PATH/libpsl-$PSL_VERSION"

meson setup --prefix="$OUT_PATH" \
    --buildtype=release \
    --cross-file "$MESON_PATH/$HOST.txt" \
    --default-library=static \
    build || fail "Failed to configure psl"

ninja -C build clean
ninja -C build -j$CORES || fail "Failed to build psl"
ninja -C build install || fail "Failed to install psl"

# Build boringssl

if [ ! -d "$DEPS_PATH/boringssl-$BORINGSSL_VERSION" ]; then
    curl -L https://github.com/google/boringssl/releases/download/$BORINGSSL_VERSION/boringssl-$BORINGSSL_VERSION.tar.gz -o "$DEPS_PATH/boringssl-$BORINGSSL_VERSION.tar.gz" || fail "Failed to download boringssl"
    tar -xvf "$DEPS_PATH/boringssl-$BORINGSSL_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract boringssl"
    rm "$DEPS_PATH/boringssl-$BORINGSSL_VERSION.tar.gz"
fi

cd "$DEPS_PATH/boringssl-$BORINGSSL_VERSION"

cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$OUT_PATH" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$ABI \
    -DANDROID_PLATFORM=android-$SDK_VER \
    -DBUILD_SHARED_LIBS=ON \
    -GNinja -B build || fail "Failed to configure boringssl"

ninja -C build clean
ninja -C build -j$CORES || fail "Failed to build boringssl"
ninja -C build install || fail "Failed to install boringssl"

# Build nghttp2

if [ ! -d "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION" ]; then
    curl -L https://github.com/nghttp2/nghttp2/releases/download/v$NGHTTP2_VERSION/nghttp2-$NGHTTP2_VERSION.tar.gz -o "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION.tar.gz" || fail "Failed to download nghttp2"
    tar -xvf "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract nghttp2"
    rm "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION.tar.gz"
fi

cd "$DEPS_PATH/nghttp2-$NGHTTP2_VERSION"

./Configure \
    PKG_CONFIG_LIBDIR="$OUT_PATH/lib/pkgconfig" \
    LDFLAGS="-fPIE -pie -L$OUT_PATH/lib" \
    CPPFLAGS="-fPIE -I$OUT_PATH/include" \
    --prefix="$OUT_PATH" \
    --host=$HOST \
    --build=$(dpkg-architecture -qDEB_BUILD_GNU_TYPE) \
    --disable-shared \
    --disable-examples \
    --without-systemd \
    --without-jemalloc \
    --enable-lib-only || fail "Failed to configure nghttp2"

make clean
make -j$CORES || fail "Failed to build nghttp2"
make install || fail "Failed to install nghttp2"

# Build nghttp3

if [ ! -d "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION" ]; then
    curl -L https://github.com/ngtcp2/nghttp3/releases/download/v$NGHTTP3_VERSION/nghttp3-$NGHTTP3_VERSION.tar.gz -o "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION.tar.gz" || fail "Failed to download nghttp3"
    tar -xvf "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract nghttp3"
    rm "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION.tar.gz"
fi

cd "$DEPS_PATH/nghttp3-$NGHTTP3_VERSION"

autoreconf -i

./configure --prefix="$OUT_PATH" \
    --host=$HOST \
    --enable-lib-only \
    --disable-shared || fail "Failed to configure nghttp3"

make clean
make -j$CORES || fail "Failed to build nghttp3"
make install || fail "Failed to install nghttp3"

# Build ngtcp2

if [ ! -d "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION" ]; then
    curl -L https://github.com/ngtcp2/ngtcp2/releases/download/v$NGTCP2_VERSION/ngtcp2-$NGTCP2_VERSION.tar.gz -o "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION.tar.gz" || fail "Failed to download ngtcp2"
    tar -xvf "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION.tar.gz" -C "$DEPS_PATH" || fail "Failed to extract ngtcp2"
    rm "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION.tar.gz"
fi

cd "$DEPS_PATH/ngtcp2-$NGTCP2_VERSION"

autoreconf -i

./configure \
    PKG_CONFIG_PATH=$OUT_PATH/lib/pkgconfig \
    BORINGSSL_LIBS="-L$OUT_PATH/lib -lssl -lcrypto" \
    BORINGSSL_CFLAGS="-I$OUT_PATH/include" \
    LIBNGHTTP3_LIBS="-L$OUT_PATH/lib -lnghttp3" \
    LIBNGHTTP3_CFLAGS="-I$OUT_PATH/include" \
    --prefix="$OUT_PATH" \
    --host=$HOST \
    --with-libnghttp3 \
    --with-boringssl \
    --enable-lib-only \
    --disable-shared || fail "Failed to configure ngtcp2"

make clean
make -j$CORES || fail "Failed to build ngtcp2"
make install || fail "Failed to install ngtcp2"

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
    --with-libpsl="$OUT_PATH" \
    --with-ssl="$OUT_PATH" \
    --with-nghttp2="$OUT_PATH" \
    --with-nghttp3="$OUT_PATH" \
    --with-ngtcp2="$OUT_PATH" \
    --with-ca-bundle="/system/etc/security/cacert.pem" \
    --with-ca-path="/system/etc/security/cacerts" \
    --with-pic \
    --disable-shared || fail "Failed to configure curl"

make clean
make -j$CORES || fail "Failed to build curl"
make install || fail "Failed to install curl"

echo "Build completed successfully"

# print versions
rm -f "version.txt"
cat > "version.txt" <<EOF
ZLIB version: $ZLIB_VERSION
PSL version: $PSL_VERSION
BORINGSSL version: $BORINGSSL_VERSION
NGHTTP2 version: $NGHTTP2_VERSION
NGHTTP3 version: $NGHTTP3_VERSION
NGTCP2 version: $NGTCP2_VERSION
CURL version: $CURL_VERSION
EOF
