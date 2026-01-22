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
echo "[1/7] Building Rocket.Chat ..."

rm -r Rocket.Chat.Electron-4.11.2 || true
ROCKET_URL=https://github.com/RocketChat/Rocket.Chat.Electron/archive/refs/tags/4.11.2.tar.gz
curl -L $ROCKET_URL | tar xz
cd Rocket.Chat.Electron-4.11.2/

echo "git apply"
cat ${ROOT}/patches/Rocket.Chat/maximize-rootwindow.patch
patch -p1 <  ${ROOT}/patches/Rocket.Chat/maximize-rootwindow.patch
patch -p1 <  ${ROOT}/patches/Rocket.Chat/msg-keyboard-adapt.patch

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
echo "[2/7] Building fake xdg-open ..."
cp -r ${ROOT}/utils/xdg-open/ ${BUILD_DIR}/
cd ${BUILD_DIR}/xdg-open/
mkdir -p build
cd build
cmake ..
make
mkdir -p $INSTALL_DIR/bin/

# =================================================
# STEP 3: Downloading maliit-inputcontext-gtk3
# =================================================
echo "[3/7] Building maliit-inputcontext-gtk3 and download dependencies..."


PKGNAME="maliit-inputcontext-gtk"
VERSION="0.99.1+git20151116.72d7576"
ORIG_URL="https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/maliit-inputcontext-gtk/0.99.1+git20151116.72d7576-3build3/maliit-inputcontext-gtk_0.99.1+git20151116.72d7576.orig.tar.xz"
DEBIAN_URL="https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/maliit-inputcontext-gtk/0.99.1+git20151116.72d7576-3build3/maliit-inputcontext-gtk_0.99.1+git20151116.72d7576-3build3.debian.tar.xz"



WORKDIR_MALIIT="${BUILD_DIR}/${PKGNAME}-${VERSION}"
rm -rvf $WORKDIR_MALIIT/ || true
mkdir -p "$WORKDIR_MALIIT"
cd "$WORKDIR_MALIIT"

echo "📦 Download sources..."
wget -q "$ORIG_URL" -O "${PKGNAME}_${VERSION}.orig.tar.xz"
wget -q "$DEBIAN_URL" -O "${PKGNAME}_${VERSION}.debian.tar.xz"

echo "📂 Extract original code..."
tar -xf "${PKGNAME}_${VERSION}.orig.tar.xz"
SRC_DIR_MALIIT=$(tar -tf "${PKGNAME}_${VERSION}.orig.tar.xz" | head -1 | cut -d/ -f1)

echo "📂 Extract debian files..."
tar -xf "${PKGNAME}_${VERSION}.debian.tar.xz" -C "$SRC_DIR_MALIIT"

echo "Apply patch..."
cd ${BUILD_DIR}/$SRC_DIR_MALIIT/maliit-inputcontext-gtk-$VERSION/
patch ${BUILD_DIR}/$SRC_DIR_MALIIT/maliit-inputcontext-gtk-$VERSION/gtk-input-context/client-gtk/client-imcontext-gtk.c  ${ROOT}/patches/maliit-inputcontext-gtk/client-imcontext-gtk.c.patch
echo "${ROOT}/patches/maliit-inputcontext-gtk/client-imcontext-gtk.c.patch"

echo "Compile..."
EDITOR=true dpkg-source --commit . fix-keyboard
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -a arm64


# =================================================
# STEP 4: Install dependencies
# =================================================
echo "[4/7] Install dependencies..."

cd ${BUILD_DIR}
DEPENDENCIES="libhybris-utils xdotool libmaliit-glib2 libxdo3 x11-utils libsecret-1-0"

for dep in $DEPENDENCIES ; do
    apt download $dep:arm64
    mv ${dep}_*.deb ${dep}.deb
    rm -rvf "${dep}.deb_extract_chsdjksd" || true
    mkdir "${dep}.deb_extract_chsdjksd"
    dpkg-deb -x "${dep}.deb" "${dep}.deb_extract_chsdjksd"
done


# ===================================
# STEP 5: BUILD QML modules
# ===================================
echo "[5/7] Building QML modules ..."
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

# ==============================
# STEP 6: Copying files
# ==============================  
echo "[6/7] Copying files..." 
rm -rvf $INSTALL_DIR/opt/ || true
mkdir -p "$INSTALL_DIR/opt/"
cp -r ${BUILD_DIR}/Rocket.Chat.Electron-4.11.2/dist/linux-arm64-unpacked "$INSTALL_DIR/opt/Rocket.Chat" || true

# Copy project files
#Copy built logos
# cp ${BUILD_DIR}/icon.png "$INSTALL_DIR/"
# cp ${BUILD_DIR}/icon-splash.png "$INSTALL_DIR/"

cp ${ROOT}/rocketchat.desktop "$INSTALL_DIR/"
cp ${ROOT}/manifest.json "$INSTALL_DIR/"

cp ${BUILD_DIR}/Rocket.Chat.Electron-4.11.2/build/appx/Square150x150Logo.png "$INSTALL_DIR/icon.png"
cp ${BUILD_DIR}/Rocket.Chat.Electron-4.11.2/build/appx/StoreLogo.png "$INSTALL_DIR/icon-spash.png"


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
cp ${BUILD_DIR}/xdg-open/build/xdg-open $INSTALL_DIR/bin/


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

echo "Copying maliit-input-context..."
cp $WORKDIR_MALIIT/maliit-inputcontext-gtk-$VERSION/builddir/gtk3/gtk-3.0/im-maliit.so $INSTALL_DIR/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/

# ========================
# STEP 7: BUILD THE CLICK PACKAGE
# ========================
echo "[7/7] Building click package..."
# click build "$INSTALL_DIR"

echo "✅ Preparation done, building the .click package."
 
