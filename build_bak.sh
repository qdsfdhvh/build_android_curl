
OPENSSL_VERSION="3.4.0"

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
