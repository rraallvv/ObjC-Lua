#!/bin/sh
################################################################################
#                                 IMPORTANT
################################################################################
#  This script is intended to be called from the build-phase in Xcode to build
#  LuaJIT as a staic library.
#
#  Pass only those environment variables that are used in the script, otherwise
#  the build process may fail.
#
#  To use it just copy and paste the following in a run script phase either for
#  iOS, OS X, or both, and uncomment the line.
#
#   env -i \
#		ISDK="$SDKROOT" \
#		ARCHS="$ARCHS" \
#		PLATFORM_NAME="$PLATFORM_NAME" \
#		BUILT_PRODUCTS_DIR="$BUILT_PRODUCTS_DIR" \
#		EXECUTABLE_NAME="$EXECUTABLE_NAME" \
#		EXECUTABLE_PREFIX="$EXECUTABLE_PREFIX" \
#		PRODUCT_NAME="$PRODUCT_NAME" \
#		MACOSX_MINVER="$MACOSX_DEPLOYMENT_TARGET" \
#		IPHONEOS_MINVER="$IPHONEOS_DEPLOYMENT_TARGET" \
#		IOS_SIMULATOR_MINVER="$IOS_SIMULATOR_DEPLOYMENT_TARGET" \
#		$SRCROOT/build-luajit.sh
#
################################################################################

shopt -s extglob

LUAJIT=luajit/src

# Get architectures contained in the previously build fat library
LIPO_ARCHS=""

if [ -e $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME ]; then
    LIPO_ARCHS=`lipo -info $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME | sed -e 's,^Archi.* are: ,,' -e 's,^Non-fat.*ture: ,,'`
fi

# Create the products dir
mkdir -p $BUILT_PRODUCTS_DIR

# Build a static library for each architecture in the list of targeted ones
for ARCH in $ARCHS ; do
    # Skip build if the architecture is already in the fat binary
	if [[ $LIPO_ARCHS =~ (^| )$ARCH($| ) ]]; then
		continue
	fi

    # Build the library
	HOST_ARCH="-m32 -arch i386"

	if [ "$ARCH" == "arm64" ] || [ "$ARCH" == "x86_64" ] ; then
		HOST_ARCH="-m64 -arch x86_64"
	fi

	TARGET_SYSTEM="Darwin"
	MINVER="-mmacosx-version-min=$MACOSX_MINVER"

	if [ $PLATFORM_NAME == "iphoneos" ] || [ $PLATFORM_NAME == "iphonesimulator" ] ; then
		TARGET_SYSTEM="iOS"
		if [ $PLATFORM_NAME == "iphoneos" ] ; then
			MINVER="-miphoneos-version-min=$IPHONEOS_MINVER"
		else
			MINVER="-mios-simulator-version-min=$IOS_SIMULATOR_MINVER"
		fi
	fi

	make -C $LUAJIT \
		HOST_CC="gcc $HOST_ARCH" \
		CROSS=/usr/bin/ \
		TARGET_FLAGS="-arch $ARCH -isysroot $ISDK $MINVER" \
		TARGET_SYS=iOS \
		clean libluajit.a

	if [ ! -e "$LUAJIT/libluajit.a" ]; then
		exit 1
	fi

    # Add the library to the fat binary
	mv "$LUAJIT/libluajit.a" $BUILT_PRODUCTS_DIR/libluajit-$ARCH.a

    if [ -e $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME ]; then
        lipo -create $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME $BUILT_PRODUCTS_DIR/libluajit-$ARCH.a -output $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME
    else
        lipo -create $BUILT_PRODUCTS_DIR/libluajit-$ARCH.a -output $BUILT_PRODUCTS_DIR/$EXECUTABLE_NAME
    fi

    # Remove all specific architecture libraries keeping only the fat version
    rm $BUILT_PRODUCTS_DIR/!($EXECUTABLE_PREFIX$PRODUCT_NAME).a
done
