#!/bin/bash
set -e  # Exit immediately on error
if [ "$UNCONFINED" = "true" ]; then
echo "WARNING: building unconfined!"
fi


lsb_release -a
# ========================
# PROJECT CONFIGURATION
# ========================
PROJECT_NAME="min"
INSTALL_DIR="${BUILD_DIR}/install"


# =================================================
# STEP 1: Build Rocket.Chat
# =================================================
echo "[1/8] Building Rocket.Chat ..."

ROCKETCHAT_VERSION="4.15.1"

  rm -r Rocket.Chat.Electron-$ROCKETCHAT_VERSION || true
  ROCKET_URL=https://github.com/RocketChat/Rocket.Chat.Electron/archive/refs/tags/$ROCKETCHAT_VERSION.tar.gz
  curl -L $ROCKET_URL | tar xz
  cd Rocket.Chat.Electron-$ROCKETCHAT_VERSION/

  echo "Apply patches"
  patch -p1 <  ${ROOT}/patches/Rocket.Chat/maximize-rootwindow.patch
  patch -p1 <  ${ROOT}/patches/Rocket.Chat/msg-keyboard-adapt.patch
  patch -p1 <  ${ROOT}/patches/Rocket.Chat/contentHub.patch


# Télécharger et exécuter le script d'installation
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.6/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm --version

nvm install 20
nvm use 20       # active Node 20 dans ce terminal
nvm alias default 20 

YARN_ENABLE_INLINE_BUILDS=1 node .yarn/releases/yarn-4.6.0.cjs install --immutable --inline-builds
node .yarn/releases/yarn-4.6.0.cjs postinstall
node .yarn/releases/yarn-4.6.0.cjs build-linux --arm64 --linux dir  -p never


# ===================================
# STEP 2: BUILD THE FAKE xdg-open
# ===================================
echo "[2/8] Building fake xdg-open ..."
cp -r ${ROOT}/utils/xdg-open/ ${BUILD_DIR}/
cd ${BUILD_DIR}/xdg-open/
mkdir -p build
cd build
cmake ..
make
mkdir -p $INSTALL_DIR/bin/

cp -r ${ROOT}/utils/placeholder-killer/ ${BUILD_DIR}/
cd ${BUILD_DIR}/placeholder-killer/
mkdir -p build
cd build
cmake ..
make

# =================================================
# STEP 3: Downloading maliit-inputcontext-gtk3
# =================================================
echo "[3/8] Building maliit-inputcontext-gtk3 and download dependencies..."

cd ${BUILD_DIR}

PKGNAME="maliit-inputcontext-gtk"
VERSION_MALIIT="0.99.1+git20151116.72d7576"
ORIG_URL="https://ports.ubuntu.com/ubuntu-ports/ubuntu-ports/pool/universe/m/maliit-inputcontext-gtk/maliit-inputcontext-gtk_0.99.1+git20151116.72d7576.orig.tar.xz"
DEBIAN_URL="https://ports.ubuntu.com/ubuntu-ports/ubuntu-ports/pool/universe/m/maliit-inputcontext-gtk/maliit-inputcontext-gtk_0.99.1+git20151116.72d7576-3build3.debian.tar.xz"



WORKDIR_MALIIT="${BUILD_DIR}/${PKGNAME}-${VERSION_MALIIT}"
rm -rvf $WORKDIR_MALIIT/ || true
mkdir -p "$WORKDIR_MALIIT"
cd "$WORKDIR_MALIIT"

echo "📦 Download sources..."
wget -q "$ORIG_URL" -O "${PKGNAME}_${VERSION_MALIIT}.orig.tar.xz"
wget -q "$DEBIAN_URL" -O "${PKGNAME}_${VERSION_MALIIT}.debian.tar.xz"

echo "📂 Extract original code..."
tar -xf "${PKGNAME}_${VERSION_MALIIT}.orig.tar.xz"
SRC_DIR_MALIIT=$(tar -tf "${PKGNAME}_${VERSION_MALIIT}.orig.tar.xz" | head -1 | cut -d/ -f1)

echo "📂 Extract debian files..."
tar -xf "${PKGNAME}_${VERSION_MALIIT}.debian.tar.xz" -C "$SRC_DIR_MALIIT"

echo "Apply patch..."
cd ${BUILD_DIR}/$SRC_DIR_MALIIT/maliit-inputcontext-gtk-$VERSION_MALIIT/
patch ${BUILD_DIR}/$SRC_DIR_MALIIT/maliit-inputcontext-gtk-$VERSION_MALIIT/gtk-input-context/client-gtk/client-imcontext-gtk.c  ${ROOT}/patches/maliit-inputcontext-gtk/client-imcontext-gtk.c.patch
echo "${ROOT}/patches/maliit-inputcontext-gtk/client-imcontext-gtk.c.patch"

echo "Compile..."
EDITOR=true dpkg-source --commit . fix-keyboard
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -a arm64


# =================================================
# STEP 4: Install dependencies
# =================================================
echo "[4/8] Install dependencies..."

cd ${BUILD_DIR}
DEPENDENCIES="libhybris-utils xdotool libmaliit-glib2 libxdo3 x11-utils libsecret-1-0"

for dep in $DEPENDENCIES ; do
    apt download $dep:arm64
    mv ${dep}_*.deb ${dep}.deb
    rm -rvf "${dep}.deb_extract_chsdjksd" || true
    mkdir "${dep}.deb_extract_chsdjksd"
    dpkg-deb -x "${dep}.deb" "${dep}.deb_extract_chsdjksd"
done

wget https://ports.ubuntu.com/pool/main/c/coreutils/coreutils_9.4-3ubuntu6_arm64.deb
rm -rvf "coreutils_9.4-3ubuntu6_arm64.deb_extract_chsdjksd" || true
mkdir "coreutils_9.4-3ubuntu6_arm64.deb_extract_chsdjksd"
dpkg-deb -x "coreutils_9.4-3ubuntu6_arm64.deb" "coreutils_9.4-3ubuntu6_arm64.deb_extract_chsdjksd"


# ===================================
# STEP 5: BUILD QML modules
# ===================================
echo "[5/8] Building QML modules ..."
rm -rvf ${BUILD_DIR}/download-helper
cp -r ${ROOT}/utils/download-helper/ ${BUILD_DIR}/download-helper
cd ${BUILD_DIR}/download-helper/qml-download-helper-module/
mkdir build
cd build
cmake ..
cmake --build .

rm -rvf ${BUILD_DIR}/upload-helper
cp -r ${ROOT}/utils/upload-helper/ ${BUILD_DIR}/upload-helper
cd ${BUILD_DIR}/upload-helper/qml-upload-helper-module/
mkdir build
cd build
cmake ..
cmake --build .

rm -rvf ${BUILD_DIR}/mic-permission-requester/
cp -r ${ROOT}/utils/mic-permission-requester/ ${BUILD_DIR}/mic-permission-requester
cd ${BUILD_DIR}/mic-permission-requester/AudioModule/
mkdir build
cd build
cmake ..
cmake --build .

# =================================================
# STEP 9: Build libnotify
# =================================================
echo "[6/8] Building libnotify..."

rm -rvf ${BUILD_DIR}/libnotify || true
mkdir -p ${BUILD_DIR}/libnotify
cd ${BUILD_DIR}/libnotify

PKGNAME="libnotify"
VERSION="0.8.3"
ORIG_URL="https://ports.ubuntu.com/pool/main/libn/libnotify/libnotify_0.8.3.orig.tar.xz"
DEBIAN_URL="https://ports.ubuntu.com/pool/main/libn/libnotify/libnotify_0.8.3-1build2.debian.tar.xz"

echo "📦 Download sources..."
wget -q "$ORIG_URL" -O "${PKGNAME}_${VERSION}.orig.tar.xz"
wget -q "$DEBIAN_URL" -O "${PKGNAME}_${VERSION}.debian.tar.xz"

echo "📂 Extract original code..."
tar -xf "${PKGNAME}_${VERSION}.orig.tar.xz"
SRC_DIR_LIBNOTIFY=$(tar -tf "${PKGNAME}_${VERSION}.orig.tar.xz" | head -1 | cut -d/ -f1)

echo "📂 Extract debian files..."
tar -xf "${PKGNAME}_${VERSION}.debian.tar.xz" -C "$SRC_DIR_LIBNOTIFY"

echo "Apply patch..."
cd ${BUILD_DIR}/libnotify/$SRC_DIR_LIBNOTIFY/
patch -p1 < ${ROOT}/patches/libnotify/notification.c.diff

EDITOR=true dpkg-source --commit . ut-notif
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -a arm64

# ==============================
# STEP 6: Copying files
# ==============================  
echo "[7/8] Copying files..." 
rm -rvf $INSTALL_DIR/opt/ || true
mkdir -p "$INSTALL_DIR/opt/"
cp -r ${BUILD_DIR}/Rocket.Chat.Electron-$ROCKETCHAT_VERSION/dist/linux-arm64-unpacked "$INSTALL_DIR/opt/Rocket.Chat" || true

# Copy project files
#Copy built logos
# cp ${BUILD_DIR}/icon.png "$INSTALL_DIR/"
# cp ${BUILD_DIR}/icon-splash.png "$INSTALL_DIR/"

cp ${ROOT}/rocketchat.desktop "$INSTALL_DIR/"
cp ${ROOT}/manifest.json "$INSTALL_DIR/"
cp ${ROOT}/pushexec "$INSTALL_DIR/"
cp ${ROOT}/push-apparmor.json "$INSTALL_DIR/"
cp ${ROOT}/rocketchat-push.apparmor "$INSTALL_DIR/"
cp ${ROOT}/rocketchat-push-helper.json "$INSTALL_DIR/"

cp ${BUILD_DIR}/Rocket.Chat.Electron-$ROCKETCHAT_VERSION/build/appx/Square150x150Logo.png "$INSTALL_DIR/icon.png"
cp ${BUILD_DIR}/Rocket.Chat.Electron-$ROCKETCHAT_VERSION/build/appx/StoreLogo.png "$INSTALL_DIR/icon-spash.png"


    cp ${ROOT}/rocketchat.apparmor "$INSTALL_DIR/"
    cp ${ROOT}/launcher.sh "$INSTALL_DIR/"

mkdir -p "$INSTALL_DIR/utils/"
cp ${ROOT}/utils/rm.sh "$INSTALL_DIR/utils/"
cp ${ROOT}/utils/sleep.sh "$INSTALL_DIR/utils/"
cp ${ROOT}/utils/mkdir.sh "$INSTALL_DIR/utils/"
cp ${ROOT}/utils/get-scale.sh "$INSTALL_DIR/utils/"
cp ${ROOT}/utils/filedialog-deamon.sh "$INSTALL_DIR/utils/"

echo "Copying libraries dependencies..."
cd ${BUILD_DIR}
# Copie des fichiers du dossier /lib/ de chaque paquet
rm -rvf $INSTALL_DIR/lib
mkdir -p "$INSTALL_DIR/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/"
for DIR in *_extract_chsdjksd; do
    if [ -d "$DIR/usr/lib/aarch64-linux-gnu/" ]; then
        cp -r "$DIR/usr/lib/aarch64-linux-gnu/"* "$INSTALL_DIR/lib/aarch64-linux-gnu/"
    fi
done

echo "Copying binaries dependencies..."
mkdir -p "$INSTALL_DIR/bin"
cp *_extract_chsdjksd/usr/bin/xdotool "$INSTALL_DIR/bin/"
cp *_extract_chsdjksd/usr/bin/getprop "$INSTALL_DIR/bin/"
cp *_extract_chsdjksd/usr/bin/xprop "$INSTALL_DIR/bin/"
cp *_extract_chsdjksd/usr/bin/xev "$INSTALL_DIR/bin/"
cp *_extract_chsdjksd/usr/bin/md5sum "$INSTALL_DIR/bin/"
cp ${BUILD_DIR}/xdg-open/build/xdg-open $INSTALL_DIR/bin/
cp ${BUILD_DIR}/placeholder-killer/build/placeholder-killer $INSTALL_DIR/bin/

echo "Copying libnotify"
cp ${BUILD_DIR}/libnotify/libnotify-0.8.3/obj-aarch64-linux-gnu/libnotify/* $INSTALL_DIR/lib/aarch64-linux-gnu/ || true

chmod +x $INSTALL_DIR/utils/rm.sh
chmod +x $INSTALL_DIR/utils/sleep.sh
chmod +x $INSTALL_DIR/utils/mkdir.sh
chmod +x $INSTALL_DIR/utils/get-scale.sh
chmod +x $INSTALL_DIR/launcher.sh
chmod +x $INSTALL_DIR/opt/Rocket.Chat/rocketchat-desktop.bin
chmod +x $INSTALL_DIR/opt/Rocket.Chat/chrome_crashpad_handler
chmod +x $INSTALL_DIR/opt/Rocket.Chat/v8_context_snapshot.bin
chmod +x $INSTALL_DIR/opt/Rocket.Chat/snapshot_blob.bin
chmod +x $INSTALL_DIR/utils/filedialog-deamon.sh
chmod +x $INSTALL_DIR/pushexec

mkdir $INSTALL_DIR/utils/download-helper/
cp -r ${BUILD_DIR}/download-helper/qml $INSTALL_DIR/utils/download-helper/
mkdir -p $INSTALL_DIR/utils/download-helper/Pparent/DownloadHelper
cp ${BUILD_DIR}/download-helper/qml-download-helper-module/build/libDownloadHelperPlugin.so $INSTALL_DIR/utils/download-helper/Pparent/DownloadHelper/
cp ${BUILD_DIR}/download-helper/qml-download-helper-module/qmldir $INSTALL_DIR/utils/download-helper/Pparent/DownloadHelper/

mkdir $INSTALL_DIR/utils/upload-helper/
cp -r ${BUILD_DIR}/upload-helper/qml $INSTALL_DIR/utils/upload-helper/
mkdir -p $INSTALL_DIR/utils/upload-helper/Pparent/UploadHelper
cp ${BUILD_DIR}/upload-helper/qml-upload-helper-module/build/libUploadHelperPlugin.so $INSTALL_DIR/utils/upload-helper/Pparent/UploadHelper/
cp ${BUILD_DIR}/upload-helper/qml-upload-helper-module/qmldir $INSTALL_DIR/utils/upload-helper/Pparent/UploadHelper/


mkdir -p $INSTALL_DIR/utils/mic-permission-requester/AudioWriter/ || true
cp ${BUILD_DIR}/mic-permission-requester/AudioModule/libaudiowriter.so $INSTALL_DIR/utils/mic-permission-requester/AudioWriter/
cp ${BUILD_DIR}/mic-permission-requester/AudioModule/qmldir $INSTALL_DIR/utils/mic-permission-requester/AudioWriter/

cp -r ${ROOT}/utils/mic-permission-requester "$INSTALL_DIR/utils/"
cp $INSTALL_DIR/icon.png "$INSTALL_DIR/utils/mic-permission-requester/"


echo "Copying maliit-input-context..."
cp $WORKDIR_MALIIT/maliit-inputcontext-gtk-$VERSION_MALIIT/builddir/gtk3/gtk-3.0/im-maliit.so $INSTALL_DIR/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/

# ========================
# STEP 7: BUILD THE CLICK PACKAGE
# ========================
echo "[8/8] Building click package..."
# click build "$INSTALL_DIR"

echo "✅ Preparation done, building the .click package."
 
