
OPENSSL_VERSION="3.4.0"
BORINGSSL_VERSION="0.20241209.0"
NGHTTP2_VERSION="1.64.0"
NGHTTP3_VERSION="1.7.0"
NGTCP2_VERSION="1.9.1"

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
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
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

./configure \
    PKG_CONFIG_LIBDIR="$OUT_PATH/lib/pkgconfig" \
    LDFLAGS="-fPIE -pie -L$OUT_PATH/lib" \
    CPPFLAGS="-fPIE -I$OUT_PATH/include" \
    --prefix="$OUT_PATH" \
    --host=$HOST \
    --build=$(dpkg-architecture -qDEB_BUILD_GNU_TYPE) \
    --disable-static \
    --enable-shared \
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
    --disable-static \
    --enable-shared || fail "Failed to configure nghttp3"

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
    --disable-static \
    --enable-shared || fail "Failed to configure ngtcp2"

make clean
make -j$CORES || fail "Failed to build ngtcp2"
make install || fail "Failed to install ngtcp2"
