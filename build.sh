#!/bin/sh
################################################################
# IMPORTANT                                                    #
#  This script is called from the build-phase in Xcode,        #
#  it's only purpose is to build LuaJIT in a clean environment #
################################################################

shopt -s extglob

LUADIR="$SRCROOT/luajit"

# Get architectures contained in the fat binary
LIPO_ARCHS=""

if [ -e $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME ]; then
    LIPO_ARCHS=`lipo -info $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME | sed -e 's,^Archi.* are: ,,' -e 's,^Non-fat.*ture: ,,'`
fi

mkdir -p $BUILT_PRODUCTS_DIR

for ARCH in $ARCHS ; do
    # Skip build if architecture is already in the fat binary
	if [[ $LIPO_ARCHS =~ (^| )$ARCH($| ) ]]; then
		continue
	fi

    # Build the library
	HOST_ARCH="-m32 -arch i386"

	if [ "$ARCH" == "arm64" ] || [ "$ARCH" == "x86_64" ] ; then
		HOST_ARCH="-m64 -arch x86_64"
	fi

	TARGET_SYSTEM="Darwin"

	if [ $PLATFORM_NAME == "iphoneos" ] || [ $PLATFORM_NAME == "iphonesimulator" ] ; then
		TARGET_SYSTEM="iOS"
	fi

	make -C "$LUADIR" CC="clang" HOST_CC="clang $HOST_ARCH -I/usr/include -isysroot $DEVELOPER_SDK_DIR" HOST_LDFLAGS="-L/usr/lib" TARGET_SYS=$TARGET_SYSTEM CROSS="/usr/bin/" TARGET_FLAGS="-isysroot $SDKROOT -arch $ARCH" clean amalg

	if [ ! -e "$LUADIR/src/libluajit.a" ]; then
		exit 1
	fi

    # Add the library to the fat binary
	mv "$LUADIR/src/libluajit.a" $BUILT_PRODUCTS_DIR/libluajit-$ARCH.a

    if [ -e $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME ]; then
        lipo -create $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME $BUILT_PRODUCTS_DIR/libluajit-$ARCH.a -output $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME
    else
        lipo -create $BUILT_PRODUCTS_DIR/libluajit-$ARCH.a -output $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME
    fi

    # Remove all specific architecture libraries
    rm $BUILT_PRODUCTS_DIR/!($EXECUTABLE_PREFIX$PRODUCT_NAME).a
done

# Remove non active architectures from the fat binary
for ARCH in $LIPO_ARCHS ; do
	if [[ $ARCHS =~ (^| )$ARCH($| ) ]]; then
		continue
	fi
	lipo $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME -remove $ARCH -output $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME
done
