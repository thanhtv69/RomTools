#!/bin/bash
#############################################
# File Name: start.sh
# Version: v1.2
# Author: chuest2
# Organization: chuest
# Github: https://github.com/chuest2/RomTools
#############################################
#
# Usage: start.sh < miui_HOUJI_*.zip >
#
# Note: Please change the SUPERKEY located at TODO
#
# sudo apt-get update
# sudo apt-get install aapt openjdk-17-jdk zip aria2 bc -y

echo "****************************"
echo "     HyperOS Rom Modify     "
echo "****************************"

N='\033[0m'
R='\033[1;31m'
G='\033[1;32m'
B='\033[1;34m'

URL="$1"   
GITHUB_ENV="$2"
GITHUB_WORKSPACE="$3"

os_version=$(echo ${URL} | cut -d"/" -f4)  
echo "os_version=$os_version" >>$GITHUB_ENV

rootPath="${GITHUB_WORKSPACE:-$(pwd)}"
sudo chmod -R 777 ${rootPath}/lib
sudo chmod -R 777 ${rootPath}/bin

function main(){
    romName=${1}
    export LD_LIBRARY_PATH=${rootPath}/lib

    cd $rootPath

    # print rootPath
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] rootPath: ${rootPath}"

    mkdir work

    if [ ! -f ${romName} ] ;then
        # romLink=https://cdnorg.d.miui.com/$(echo "${romName}" | awk -F "_" '{print $3}')/${romName}
        romLink=https://bn.d.miui.com/$(echo "${romName}" | awk -F "_" '{print $3}')/${romName}
        # romLink=https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/$(echo "${romName}" | awk -F "_" '{print $3}')/${romName}
        echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Downloading ${romName}"
        aria2c -s 8 -x 8 $romLink
    fi

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Unzipping ${romName}"
    # export UNZIP_DISABLE_ZIPBOMB_DETECTION=TRUE
    unzip -o $rootPath/$romName -d $rootPath/work

    # rm -f $romName
    
    cd work
    mkdir -p "${rootPath}/work/images"
    rm -rf META-INF apex_info.pb care_map.pb payload_properties.txt

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Dumping images from payload.bin"

    $rootPath/bin/payload_extract -s -o "$rootPath"/work/images/ -i "$rootPath"/work/payload.bin -x -T0
    # ${rootPath}/bin/payload-dumper -o $rootPath/work/images $rootPath/work/payload.bin 

    # rm -rf payload.bin

    unpackErofsImg system
    unpackErofsImg vendor
    unpackErofsImg product
    unpackErofsImg system_ext

    removeAVB
    removeSignVerify
    replaceApks
    removeFiles
    themeManagerPatch
    preventThemeRecovery
    personalAssistantPatch
    mmsVerificationCodeAutoCopy
    powerKeeperPatch
    settingsPatch
    miuiSystemUIPatch
    modify

    repackErofsImg system
    repackErofsImg vendor
    repackErofsImg product
    repackErofsImg system_ext

    # mv images/odm.img odm.img
    # mv images/mi_ext.img mi_ext.img
    # mv images/system_dlkm.img system_dlkm.img
    # mv images/vendor_dlkm.img vendor_dlkm.img

    removeVbmetaVerify
    replaceCust
    # kernelsuPatch
    # apatchPatch <SUPERKEY> # TODO
    makeSuperImg

    rm -rf system vendor product system_ext system.img vendor.img product.img system_ext.img odm.img mi_ext.img system_dlkm.img vendor_dlkm.img init_boot.img boot.img
    cp -rf ${rootPath}/files/flash.bat ${rootPath}/work/flash.bat
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Compressing all images"
    zip -q -r rom.zip images flash.bat
    name=TV_Corot_$(echo "${romName}" | awk -F "_" '{print $3}')_$(((md5sum rom.zip) | awk '{print $1}') | cut -c -10)_14.0.zip
    mv rom.zip ${name}
    echo "rom_name=$name" >>$GITHUB_ENV
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Done"
}

function unpackErofsImg(){
    cd ${rootPath}/work
    mv ${rootPath}/work/images/${1}.img ${1}.img
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Unpacking ${1} image"
    ${rootPath}/bin/extract.erofs -s -i ${1}.img -x
    rm -rf ${1}.img
}

function repackErofsImg(){
    name=${1}
    fileContexts="${rootPath}/work/config/${name}_file_contexts"
    fsConfig="${rootPath}/work/config/${name}_fs_config"
    outImg="${rootPath}/work/${name}.img"
    inFiles="${rootPath}/${name}"
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Repacking ${1} image"
    ${rootPath}/bin/mkfs.erofs --quiet -zlz4hc,9 -T1230768000 --mount-point=/$name --fs-config-file=$fsConfig --file-contexts=$fileContexts $outImg $inFiles
}

function makeSuperImg(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Repacking Super image"
    
    # 9126805504
    ${rootPath}/bin/lpmake --metadata-size 65536 \
    --super-name super \
    --device super:9126805504 \
    --group main_a:9126805504 \
    --group main_b:9126805504 \
    --metadata-slots 3 --virtual-ab \
    --partition system_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/system.img) | bc):main_a \
    --image system_a=system.img \
    --partition system_b:readonly:0:main_b \
    --partition vendor_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/vendor.img) | bc):main_a \
    --image vendor_a=vendor.img \
    --partition vendor_b:readonly:0:main_b \
    --partition product_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/product.img) | bc):main_a \
    --image product_a=product.img \
    --partition product_b:readonly:0:main_b \
    --partition system_ext_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/system_ext.img) | bc):main_a \
    --image system_ext_a=system_ext.img --partition system_ext_b:readonly:0:main_b \
    --partition odm_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/odm.img) | bc):main_a \
    --image odm_a=odm.img \
    --partition odm_b:readonly:0:main_b \
    --partition mi_ext_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/images/mi_ext.img) | bc):main_a \
    --image mi_ext_a=mi_ext.img \
    --partition mi_ext_b:readonly:0:main_b \
    --partition system_dlkm_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/images/system_dlkm.img) | bc):main_a \
    --image system_dlkm_a=system_dlkm.img \
    --partition system_dlkm_b:readonly:0:main_b \
    --partition vendor_dlkm_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/images/vendor_dlkm.img) | bc):main_a \
    --image vendor_dlkm_a=vendor_dlkm.img \
    --partition vendor_dlkm_b:readonly:0:main_b \
    --partition odm_dlkm_a:readonly:$(echo $(stat -c "%s" ${rootPath}/work/images/odm_dlkm.img) | bc):main_a \
    --image odm_dlkm_a=odm_dlkm.img \
    --partition odm_dlkm_b:readonly:0:main_b \
    --sparse \
    --output ${rootPath}/work/images/super.img

    rm -rf ${rootPath}/work/system.img
    rm -rf ${rootPath}/work/vendor.img
    rm -rf ${rootPath}/work/product.img
    rm -rf ${rootPath}/work/system_ext.img
    rm -rf ${rootPath}/work/odm.img
    rm -rf ${rootPath}/work/images/mi_ext.img
    rm -rf ${rootPath}/work/images/system_dlkm.img
    rm -rf ${rootPath}/work/images/vendor_dlkm.img
    rm -rf ${rootPath}/work/images/odm_dlkm.img
}

function removeVbmetaVerify(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Removing verification of vbmeta"
    cp -rf ${rootPath}/files/images/vbmeta.img images/vbmeta.img
    cp -rf ${rootPath}/files/images/vbmeta_system.img images/vbmeta_system.img

    # sed -i 's/\x00\x00\x00\x00\x00\x61\x76\x62\x74\x6F\x6F\x6C\x20/\x02\x00\x00\x00\x00\x61\x76\x62\x74\x6F\x6F\x6C\x20/g' ${rootPath}/work/images/vbmeta.img
    # sed -i 's/\x00\x00\x00\x00\x00\x61\x76\x62\x74\x6F\x6F\x6C\x20/\x02\x00\x00\x00\x00\x61\x76\x62\x74\x6F\x6F\x6C\x20/g' ${rootPath}/work/images/vbmeta_system.img
    # ${rootPath}/bin/magiskboot hexpatch ${rootPath}/work/images/vbmeta.img 0000000000000000617662746F6F6C20 0000000200000000617662746F6F6C20
}

function removeAVB(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Removing AVB in vendor image"

    sed -i 's/avb,//g;s/avb=vbmeta,//g;s/avb=vbmeta_system,//g' vendor/vendor/etc/fstab.qcom
    sed -i 's/,avb_keys=\/avb\/q-gsi.avbpubkey:\/avb\/r-gsi.avbpubkey:\/avb\/s-gsi.avbpubkey:\/avb\/t-gsi.avbpubkey:\/avb\/u-gsi.avbpubkey//g' vendor/vendor/etc/fstab.qcom
    sed -i 's/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g' vendor/vendor/etc/fstab.qcom
    sed -i 's/,metadata_encryption=aes-256-xts:wrappedkey_v0//g' vendor/vendor/etc/fstab.qcom

    # sed -i '/lowerdir=\/mnt\/vendor\/mi_ext/d;/lowerdir=\/product\/pangu\/system/d' vendor/vendor/etc/fstab.qcom
}

function replaceApks(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Replacing APKs"

    rm -rf product/product/app/AnalyticsCore/
    cp -rf ${rootPath}/files/app/AnalyticsCore product/product/app/

    rm -rf product/product/app/MIUISystemUIPlugin/
    cp -rf ${rootPath}/files/app/MIUISystemUIPlugin product/product/app/

    rm -rf product/product/priv-app/MiuiHome/
    cp -rf ${rootPath}/files/app/MiuiHome product/product/priv-app/

    rm -rf product/product/priv-app/MIUIPackageInstaller/
    cp -rf ${rootPath}/files/app/MIUIPackageInstaller product/product/priv-app/

    rm -rf product/product/priv-app/MIUISecurityCenter/
    cp -rf ${rootPath}/files/app/MIUISecurityCenter product/product/priv-app/
}

function removeSignVerify(){
    sdkLevel=$(cat system/system/system/build.prop |grep "ro.build.version.sdk" |cut -d "=" -f 2 |awk 'NR==1')
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling services.jar"
    java -jar ${rootPath}/bin/apktool.jar d -q -api $sdkLevel system/system/system/framework/services.jar -o tmp/services

    findCode='getMinimumSignatureSchemeVersionForTargetSdk'
    find tmp/services/smali_classes2/com/android/server/pm tmp/services/smali_classes2/com/android/server/pm/pkg/parsing -maxdepth 1 -type f -name "*.smali" -exec grep -H "$findCode" {} \; | cut -d ':' -f 1 | while read i ;do
        lineNum=$(grep -n "$findCode" "$i" | cut -d ':' -f 1)
        regNum=$(tail -n +"$lineNum" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
        lineNumEnd=$(awk -v LN=$lineNum 'NR>=LN && /move-result /{print NR; exit}' "$i")
        replace="    const/4 v${regNum}, 0x0"
        sed -i "${lineNum},${lineNumEnd}d" "$i"
        sed -i "${lineNum}i\\${replace}" "$i";
    done

    # downgradeSmali="tmp/services/smali_classes2/com/android/server/pm/PackageManagerServiceUtils.smali"
    # lineNum=$(grep -n "isDowngradePermitted" "$downgradeSmali" | cut -d ':' -f 1)
    # lineNumStart=$(($lineNum+2))
    # lineNumEnd=$(($lineNum+3))
    # replace="    const/4 v0, 0x0"
    # sed -i "${lineNumStart},${lineNumEnd}d" "$downgradeSmali"
    # sed -i "${lineNumStart}i\\${replace}" "$downgradeSmali"

    captureSmali="tmp/services/smali_classes2/com/android/server/policy/PhoneWindowManager.smali"
    sed -i '/^.method private getScreenshotChordLongPressDelay()J/,/^.end method/{//!d}' $captureSmali
    sed -i -e '/^.method private getScreenshotChordLongPressDelay()J/a\    .locals 4\n\n    const-wide/16 v0, 0x0\n\n    return-wide v0' $captureSmali

    logAccessSmali="tmp/services/smali_classes2/com/android/server/logcat/LogcatManagerService.smali"
    sed -i '/^.method onLogAccessRequested/,/^.end method/{//!d}' $logAccessSmali
    sed -i -e '/^.method onLogAccessRequested/a\    .locals 5\n\n    return-void' $logAccessSmali

    rm -f system/system/system/framework/services.jar
    find system/system/system/framework/oat/arm64 -type f -name "services*" | xargs rm -f

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding services.jar"
    java -jar ${rootPath}/bin/apktool.jar b -q -f -api $sdkLevel tmp/services -o tmp/services.jar

    zipalign 4 tmp/services.jar system/system/system/framework/services.jar
    ${rootPath}/bin/dex2oat --dex-file=system/system/system/framework/services.jar --instruction-set=arm64 --compiler-filter=everything --profile-file=system/system/system/framework/services.jar.prof --oat-file=system/system/system/framework/oat/arm64/services.odex --app-image-file=system/system/system/framework/oat/arm64/services.art
    rm -rf tmp
}

function themeManagerPatch(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling MIUIThemeManager.apk"
    java -jar ${rootPath}/bin/APKEditor.jar d -t raw -f -no-dex-debug -i product/product/app/MIUIThemeManager/MIUIThemeManager.apk -o tmp/MIUIThemeManager >/dev/null 2>&1

    Mod0=$(find tmp/MIUIThemeManager/smali/classes*/com/android/thememanager/basemodule/ad/model/ -type f -name 'AdInfo.smali' 2>/dev/null | xargs grep -rl '.method public isVideoAd()Z' | sed 's/^\.\///' | sort)
    sed -i '/^.method public isVideoAd()Z/,/^.end method/{//!d}' $Mod0
    sed -i -e '/^.method public isVideoAd()Z/a\    .locals 1\n\n    const/4 p0, 0x0\n\n    return p0' $Mod0

    Mod1=$(find tmp/MIUIThemeManager/smali/classes*/com/android/thememanager/basemodule/ad/model/ -type f -name 'AdInfoResponse.smali' 2>/dev/null | xargs grep -rl '.method private static isAdValid' | sed 's/^\.\///' | sort)
    sed -i '/^.method private static isAdValid/,/^.end method/{//!d}' $Mod1
    sed -i -e '/^.method private static isAdValid/a\    .locals 1\n\n    const/4 p0, 0x0\n\n    return p0' $Mod1

    Mod2=$(find tmp/MIUIThemeManager/smali/classes*/com/android/thememanager/basemodule/resource/model/ -type f -name 'Resource.smali' 2>/dev/null | xargs grep -rl '.method public isAuthorizedResource()Z' | sed 's/^\.\///' | sort)
    sed -i '/^.method public isAuthorizedResource()Z/,/^.end method/{//!d}' $Mod2
    sed -i -e '/^.method public isAuthorizedResource()Z/a\    .locals 1\n\n    const/4 p0, 0x0\n\n    return p0' $Mod2

    Mod3=$(find tmp/MIUIThemeManager/smali/classes*/com/android/thememanager/*/*/ -type f -name '*.smali' 2>/dev/null | xargs grep -rl 'DRM_ERROR_UNKNOWN' | sed 's/^\.\///' | sort)
    sed -i 's/DRM_ERROR_UNKNOWN/DRM_SUCCESS/g' $Mod3

    Mod4=$(find tmp/MIUIThemeManager/smali/classes*/com/android/thememanager/module/detail/presenter/ -type f -name 'qrj.smali' 2>/dev/null | xargs grep -rl '.method public p()Z' | sed 's/^\.\///' | sort)
    sed -i '/OnlineResourceDetail;->bought:Z/i\    const/4 v0, 0x1' $Mod4
    sed -i '/OnlineResourceDetail;->bought:Z/i\    return v0' $Mod4

    Mod5=$(find tmp/MIUIThemeManager/smali/classes*/com/android/thememanager/module/detail/view/ -type f -name '*.smali' 2>/dev/null | xargs grep -rl 'Lcom/android/thememanager/detail/theme/model/OnlineResourceDetail;->bought:Z' | sed 's/^\.\///' | sort)

    findCode='iget-boolean v0, p0, Lcom/android/thememanager/detail/theme/model/OnlineResourceDetail;->bought:Z'
    lineNum=$(($(grep -n "$findCode" "$Mod5" | cut -d ':' -f 1)+2))
    replace="    if-eqz v0, :cond_2"
    sed -i "${lineNum},${lineNum}d" "$Mod5"
    sed -i "${lineNum}i\\${replace}" "$Mod5";

    findCode='iget-boolean v1, p1, Lcom/android/thememanager/detail/theme/model/OnlineResourceDetail;->bought:Z'
    lineNum=$(($(grep -n "$findCode" "$Mod5" | cut -d ':' -f 1)+2))
    replace="    if-eqz v1, :cond_6"
    sed -i "${lineNum},${lineNum}d" "$Mod5"
    sed -i "${lineNum}i\\${replace}" "$Mod5";

    Mod6=$(find tmp/MIUIThemeManager/smali/classes*/com/miui/maml/widget/edit/ -type f -name '*.smali' 2>/dev/null | xargs grep -rl 'DRM_ERROR_UNKNOWN' | sed 's/^\.\///' | sort)
    sed -i 's/DRM_ERROR_UNKNOWN/DRM_SUCCESS/g' $Mod6

    Mod7=$(find tmp/MIUIThemeManager/smali/classes*/com/miui/maml/widget/edit/ -type f -name 'MamlutilKt.smali' 2>/dev/null | xargs grep -rl '.method public static final themeManagerSupportPaidWidget' | sed 's/^\.\///' | sort)
    sed -i '/^.method public static final themeManagerSupportPaidWidget/,/^.end method/{//!d}' $Mod7
    sed -i -e '/^.method public static final themeManagerSupportPaidWidget/a\    .locals 1\n\n    const/4 p0, 0x0\n\n    return p0' $Mod7

    rm -rf product/product/app/MIUIThemeManager/MIUIThemeManager.apk
    rm -rf product/product/app/MIUIThemeManager/oat/arm64/*

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding MIUIThemeManager.apk"
    java -jar ${rootPath}/bin/APKEditor.jar b -f -i tmp/MIUIThemeManager -o tmp/MIUIThemeManager.apk >/dev/null 2>&1
    zipalign 4 tmp/MIUIThemeManager.apk product/product/app/MIUIThemeManager/MIUIThemeManager.apk
    ${rootPath}/bin/dex2oat --dex-file=product/product/app/MIUIThemeManager/MIUIThemeManager.apk --instruction-set=arm64 --compiler-filter=speed --oat-file=product/product/app/MIUIThemeManager/oat/arm64/MIUIThemeManager.odex
    rm -rf tmp
}

function preventThemeRecovery(){
    sdkLevel=$(cat system/system/system/build.prop |grep "ro.build.version.sdk" |cut -d "=" -f 2 |awk 'NR==1')
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling miui-services.jar"
    java -jar ${rootPath}/bin/apktool.jar d -q -api $sdkLevel system_ext/system_ext/framework/miui-services.jar -o tmp/miui-services

    themeSmali="tmp/miui-services/smali/com/android/server/am/ActivityManagerServiceImpl.smali"
    lineNum=$(grep -n "Lmiui/drm/DrmBroadcast;->getInstance(Landroid/content/Context;)Lmiui/drm/DrmBroadcast" "$themeSmali" | cut -d ':' -f 1)
    lineNumEnd=$(($lineNum+5))
    sed -i "${lineNum},${lineNumEnd}d" "$themeSmali"

    navigationSmali=$(find tmp/miui-services/smali/com/android/server/ -type f -name '*.smali' 2>/dev/null | xargs grep -rl '.method private isNavigationStatus' | sed 's/^\.\///' | sort)
    sed -i '/^.method private isNavigationStatus/,/^.end method/{//!d}' $navigationSmali
    sed -i -e '/^.method private isNavigationStatus/a\    .locals 0\n\n    const/4 p0, 0x1\n\n    return p0' $navigationSmali

    rm -f system_ext/system_ext/framework/miui-services.jar
    find system_ext/system_ext/framework/oat/arm64 -type f -name "miui-services*" | xargs rm -f
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding miui-services.jar"
    java -jar ${rootPath}/bin/apktool.jar b -q -f -api $sdkLevel tmp/miui-services -o tmp/miui-services.jar
    zipalign 4 tmp/miui-services.jar system_ext/system_ext/framework/miui-services.jar
    ${rootPath}/bin/dex2oat --dex-file=system_ext/system_ext/framework/miui-services.jar --instruction-set=arm64 --compiler-filter=everything --oat-file=system_ext/system_ext/framework/oat/arm64/miui-services.odex
    rm -rf tmp
}

function personalAssistantPatch(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling MIUIPersonalAssistantPhoneMIUI15.apk"
    java -jar ${rootPath}/bin/APKEditor.jar d -t raw -f -no-dex-debug -i product/product/priv-app/MIUIPersonalAssistantPhoneMIUI15/MIUIPersonalAssistantPhoneMIUI15.apk -o tmp/MIUIPersonalAssistantPhoneMIUI15 >/dev/null 2>&1

    Mod0=$(find tmp/MIUIPersonalAssistantPhoneMIUI15/smali/classes*/com/miui/maml/widget/edit/ -type f -name 'MamlutilKt.smali' 2>/dev/null | xargs grep -rl '.method public static final themeManagerSupportPaidWidget' | sed 's/^\.\///' | sort)
    sed -i '/^.method public static final themeManagerSupportPaidWidget/,/^.end method/{//!d}' $Mod0
    sed -i -e '/^.method public static final themeManagerSupportPaidWidget/a\    .locals 1\n\n    const v0, 0x0\n\n    return v0' $Mod0

    Mod1=$(find tmp/MIUIPersonalAssistantPhoneMIUI15/smali/classes*/com/miui/personalassistant/picker/business/detail/bean/ -type f -name 'PickerDetailResponse.smali' 2>/dev/null | xargs grep -rl '.method public final isBought()Z' | sed 's/^\.\///' | sort)
    sed -i '/^.method public final isBought()Z/,/^.end method/{//!d}' $Mod1
    sed -i -e '/^.method public final isBought()Z/a\    .locals 0\n\n    const p0, 0x1\n\n    return p0' $Mod1
    sed -i '/^.method public final isPay()Z/,/^.end method/{//!d}' $Mod1
    sed -i -e '/^.method public final isPay()Z/a\    .locals 0\n\n    const p0, 0x0\n\n    return p0' $Mod1

    Mod2=$(find tmp/MIUIPersonalAssistantPhoneMIUI15/smali/classes*/com/miui/personalassistant/picker/business/detail/bean/ -type f -name 'PickerDetailResponseWrapper.smali' 2>/dev/null | xargs grep -rl '.method public final isBought()Z' | sed 's/^\.\///' | sort)
    sed -i '/^.method public final isBought()Z/,/^.end method/{//!d}' $Mod2
    sed -i -e '/^.method public final isBought()Z/a\    .locals 0\n\n    const p0, 0x1\n\n    return p0' $Mod2
    sed -i '/^.method public final isPay()Z/,/^.end method/{//!d}' $Mod2
    sed -i -e '/^.method public final isPay()Z/a\    .locals 0\n\n    const p0, 0x0\n\n    return p0' $Mod2

    Mod3=$(find tmp/MIUIPersonalAssistantPhoneMIUI15/smali/classes*/com/miui/personalassistant/picker/business/detail/utils/ -type f -name 'PickerDetailDownloadManager$Companion.smali' 2>/dev/null | xargs grep -rl '.method private final isCanDownload' | sed 's/^\.\///' | sort)
    sed -i '/^.method private final isCanDownload/,/^.end method/{//!d}' $Mod3
    sed -i -e '/^.method private final isCanDownload/a\    .locals 1\n\n    const v0, 0x1\n\n    return v0' $Mod3

    Mod4=$(find tmp/MIUIPersonalAssistantPhoneMIUI15/smali/classes*/com/miui/personalassistant/picker/business/detail/utils/ -type f -name 'PickerDetailUtil.smali' 2>/dev/null | xargs grep -rl '.method public static final isCanAutoDownloadMaMl()Z' | sed 's/^\.\///' | sort)
    sed -i '/^.method public static final isCanAutoDownloadMaMl()Z/,/^.end method/{//!d}' $Mod4
    sed -i -e '/^.method public static final isCanAutoDownloadMaMl()Z/a\    .locals 1\n\n    const v0, 0x1\n\n    return v0' $Mod4

    Mod5=$(find tmp/MIUIPersonalAssistantPhoneMIUI15/smali/classes*/com/miui/personalassistant/picker/business/detail/ -type f -name 'PickerDetailViewModel.smali' 2>/dev/null | xargs grep -rl '.method private final isTargetPositionMamlPayAndDownloading(I)Z' | sed 's/^\.\///' | sort)
    sed -i '/^.method private final isTargetPositionMamlPayAndDownloading(I)Z/,/^.end method/{//!d}' $Mod5
    sed -i -e '/^.method private final isTargetPositionMamlPayAndDownloading(I)Z/a\    .locals 1\n\n    const v0, 0x0\n\n    return v0' $Mod5
    sed -i '/^.method public final checkIsIndependentProcessWidgetForPosition(I)Z/,/^.end method/{//!d}' $Mod5
    sed -i -e '/^.method public final checkIsIndependentProcessWidgetForPosition(I)Z/a\    .locals 1\n\n    const v0, 0x1\n\n    return v0' $Mod5
    sed -i '/^.method public final isCanDirectAddMaMl(I)Z/,/^.end method/{//!d}' $Mod5
    sed -i -e '/^.method public final isCanDirectAddMaMl(I)Z/a\    .locals 1\n\n    const v0, 0x1\n\n    return v0' $Mod5
    sed -i '/^.method public final shouldCheckMamlBoughtState(I)Z/,/^.end method/{//!d}' $Mod5
    sed -i -e '/^.method public final shouldCheckMamlBoughtState(I)Z/a\    .locals 1\n\n    const v0, 0x0\n\n    return v0' $Mod5

    rm -f product/product/priv-app/MIUIPersonalAssistantPhoneMIUI15/MIUIPersonalAssistantPhoneMIUI15.apk
    rm -f product/product/priv-app/MIUIPersonalAssistantPhoneMIUI15/oat/arm64/*

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding MIUIPersonalAssistantPhoneMIUI15.apk"
    java -jar ${rootPath}/bin/APKEditor.jar b -f -i tmp/MIUIPersonalAssistantPhoneMIUI15 -o tmp/MIUIPersonalAssistantPhoneMIUI15.apk >/dev/null 2>&1
    zipalign 4 tmp/MIUIPersonalAssistantPhoneMIUI15.apk product/product/priv-app/MIUIPersonalAssistantPhoneMIUI15/MIUIPersonalAssistantPhoneMIUI15.apk
    ${rootPath}/bin/dex2oat --dex-file=product/product/priv-app/MIUIPersonalAssistantPhoneMIUI15/MIUIPersonalAssistantPhoneMIUI15.apk --instruction-set=arm64 --compiler-filter=speed --oat-file=product/product/priv-app/MIUIPersonalAssistantPhoneMIUI15/oat/arm64/MIUIPersonalAssistantPhoneMIUI15.odex
    rm -rf tmp
}

function mmsVerificationCodeAutoCopy(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling MiuiMms.apk"
    java -jar ${rootPath}/bin/APKEditor.jar d -t raw -f -no-dex-debug -i product/product/priv-app/MiuiMms/MiuiMms.apk -o tmp/MiuiMms >/dev/null 2>&1

    smsSmali=$(find tmp/MiuiMms/smali/classes*/com/android/mms/transaction/ -type f -name '*.smali' 2>/dev/null | xargs grep -rl 'const-string v4, "is_verification_code"' | sed 's/^\.\///' | sort)
    sed -i '/const-string v4, \"is_verification_code\"/i\    invoke-static {v2}, Lh7/e;->a(Ljava\/lang\/CharSequence;)V\n' $smsSmali

    rm -f product/product/priv-app/MiuiMms/MiuiMms.apk
    rm -f product/product/priv-app/MiuiMms/oat/arm64/*

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding MiuiMms.apk"
    java -jar ${rootPath}/bin/APKEditor.jar b -f -i tmp/MiuiMms -o tmp/MiuiMms.apk >/dev/null 2>&1
    zipalign 4 tmp/MiuiMms.apk product/product/priv-app/MiuiMms/MiuiMms.apk
    ${rootPath}/bin/dex2oat --dex-file=product/product/priv-app/MiuiMms/MiuiMms.apk --instruction-set=arm64 --compiler-filter=speed --oat-file=product/product/priv-app/MiuiMms/oat/arm64/MiuiMms.odex
    rm -rf tmp
}

function powerKeeperPatch(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling PowerKeeper.apk"
    java -jar ${rootPath}/bin/APKEditor.jar d -t raw -f -no-dex-debug -i system/system/system/app/PowerKeeper/PowerKeeper.apk -o tmp/PowerKeeper >/dev/null 2>&1

	targetUpdateSmali=$(find tmp/PowerKeeper/smali/classes*/com/miui/powerkeeper/cloudcontrol/ -type f -name 'LocalUpdateUtils.smali' 2>/dev/null | xargs grep -rl '.method public static startCloudSyncData' | sed 's/^\.\///' | sort)
    sed -i '/^.method public static startCloudSyncData/,/^.end method/{//!d}' $targetUpdateSmali
    sed -i -e '/^.method public static startCloudSyncData/a\    .locals 1\n\n    return-void' $targetUpdateSmali

	targetFrameSmali=$(find tmp/PowerKeeper/smali/classes*/com/miui/powerkeeper/statemachine/ -type f -name 'DisplayFrameSetting.smali' 2>/dev/null | xargs grep -rl '.method public setScreenEffect(II)V' | sed 's/^\.\///' | sort)
	sed -i '/^.method public static isFeatureOn()Z/,/^.end method/{//!d}' $targetFrameSmali
    sed -i -e '/^.method public static isFeatureOn()Z/a\    .locals 1\n\n    const\/4 v0, 0x0\n\n    return v0' $targetFrameSmali
	sed -i '/^.method public setScreenEffect(II)V/,/^.end method/{//!d}' $targetFrameSmali
    sed -i -e '/^.method public setScreenEffect(II)V/a\    .locals 1\n\n    return-void' $targetFrameSmali

    rm -f system/system/system/app/PowerKeeper/PowerKeeper.apk
    rm -f system/system/system/app/PowerKeeper/oat/arm64/*

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding PowerKeeper.apk"
    java -jar ${rootPath}/bin/APKEditor.jar b -f -i tmp/PowerKeeper -o tmp/PowerKeeper.apk >/dev/null 2>&1
    zipalign 4 tmp/PowerKeeper.apk system/system/system/app/PowerKeeper/PowerKeeper.apk
    ${rootPath}/bin/dex2oat --dex-file=system/system/system/app/PowerKeeper/PowerKeeper.apk --instruction-set=arm64 --compiler-filter=speed --oat-file=system/system/system/app/PowerKeeper/oat/arm64/PowerKeeper.odex
    rm -rf tmp
}

function settingsPatch(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling Settings.apk"
    java -jar ${rootPath}/bin/APKEditor.jar d -t xml -f -no-dex-debug -i system_ext/system_ext/priv-app/Settings/Settings.apk -o tmp/Settings >/dev/null 2>&1

    cp -rf ${rootPath}/files/app/Settings/com/ tmp/Settings/smali/classes/
    cp -f ${rootPath}/files/app/Settings/device_layout.xml tmp/Settings/resources/package_1/res/layout/
    cp -f ${rootPath}/files/app/Settings/miui_version_card.xml tmp/Settings/resources/package_1/res/layout/
    cp -f ${rootPath}/files/app/Settings/my_device_info_item.xml tmp/Settings/resources/package_1/res/layout/
    cp -f ${rootPath}/files/app/Settings/my_device_info_item2.xml tmp/Settings/resources/package_1/res/layout/

    publicFile="tmp/Settings/resources/package_1/res/values/public.xml"
    findCode='type="layout" name="zone_picker_item"'
    lineNum=$(grep -n "$findCode" "$publicFile" | cut -d ':' -f 1)
    id=$(awk -v LN="$lineNum" 'NR==LN {print $2}' "$publicFile" | cut -d '"' -f 2)
    nextId=$(printf "0x%x" "$(( $id + 1 ))")
    replace="  <public id=\"${nextId}\" type=\"layout\" name=\"my_device_info_item2\" />"
    sed -i "${lineNum}i\\${replace}" "$publicFile"

    layoutSmali=$(find tmp/Settings/smali/classes*/com/android/settings/ -type f -name '*.smali' 2>/dev/null | xargs grep -rl '.field public static final my_device_info_item' | sed 's/^\.\///' | sort)
    sed -i -e "/^.field public static final my_device_info_item/a\    .field public static final my_device_info_item2:I = ${nextId}" $layoutSmali

    memoryCardSmali=$(find tmp/Settings/smali/classes*/com/android/settings/device/ -type f -name 'MiuiMemoryCard.smali' 2>/dev/null | xargs grep -rl 'my_device_info_item' | sed 's/^\.\///' | sort)
    sed -i 's/my_device_info_item/my_device_info_item2/g' $memoryCardSmali

    basicInfoSmali=$(find tmp/Settings/smali/classes*/com/android/settings/device/ -type f -name 'DeviceBasicInfoPresenter.smali' 2>/dev/null | xargs grep -rl '.method private getLineNum()' | sed 's/^\.\///' | sort)
    replace=$(<${rootPath}/files/app/Settings/basicInfoReplace.smali)
    sed -i '/^.method private getLineNum()/,/^.end method/{//!d}' $basicInfoSmali
    printf '%s\n' "$replace" | sed -i '/^.method private getLineNum()/r /dev/stdin' "$basicInfoSmali"

    arraysFile="tmp/Settings/resources/package_1/res/values/arrays.xml"
    sed -i '/<item>@string\/display_notification_icon_3<\/item>/a\    <item>@string\/display_notification_icon_3<\/item>\n    <item>@string\/display_notification_icon_3<\/item>' $arraysFile
    sed -i '/<string-array name="notification_icon_counts_values">/,/<\/string-array>/ {
        /<item>3<\/item>/ {
            a\
        <item>5<\/item>
            a\
        <item>7<\/item>
        }
    }' $arraysFile

    notificationSmali="tmp/Settings/smali/classes2/com/android/settings/NotificationStatusBarSettings.smali"
    sed -i '/filled-new-array {v1, v2, v0}/i\    const/4 v3, 0x5\n\n    const/4 v4, 0x7\n' $notificationSmali
    sed -i 's/filled-new-array {v1, v2, v0}/filled-new-array {v1, v2, v0, v3, v4}/g' $notificationSmali

    aboutPhoneSmali=$(find tmp/Settings/smali/classes*/com/android/settings/device/ -type f -name 'MiuiAboutPhoneUtils.smali' 2>/dev/null | xargs grep -rl '.method public static isLocalCnAndChinese()Z' | sed 's/^\.\///' | sort)
    sed -i '/^.method public static isLocalCnAndChinese()Z/,/^.end method/{//!d}' $aboutPhoneSmali
    sed -i -e '/^.method public static isLocalCnAndChinese()Z/a\    .registers 2\n\n    const/4 v0, 0x0\n\n    return v0' $aboutPhoneSmali

    featureSmali=$(find tmp/Settings/smali/classes*/com/android/settings/utils/ -type f -name 'SettingsFeatures.smali' 2>/dev/null | xargs grep -rl '.method public static isNeedHideShopEntrance' | sed 's/^\.\///' | sort)
    sed -i '/^.method public static isNeedHideShopEntrance/,/^.end method/{//!d}' $featureSmali
    sed -i -e '/^.method public static isNeedHideShopEntrance/a\    .registers 3\n\n    const/4 v0, 0x1\n\n    return v0' $featureSmali

    miuiSettingsSmali=$(find tmp/Settings/smali/classes*/com/android/settings/ -type f -name 'MiuiSettings.smali' 2>/dev/null | xargs grep -rl 'sget-boolean v0, Lmiui/os/Build;->IS_GLOBAL_BUILD:Z' | sed 's/^\.\///' | sort)
    sed -i 's/sget-boolean v0, Lmiui\/os\/Build;->IS_GLOBAL_BUILD:Z/const\/4 v0, 0x1/g' $miuiSettingsSmali

    rm -f system_ext/system_ext/priv-app/Settings/Settings.apk
    rm -f system_ext/system_ext/priv-app/Settings/oat/arm64/*

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding Settings.apk"
    java -jar ${rootPath}/bin/APKEditor.jar b -f -i tmp/Settings -o tmp/Settings.apk >/dev/null 2>&1
    zipalign 4 tmp/Settings.apk system_ext/system_ext/priv-app/Settings/Settings.apk
    ${rootPath}/bin/dex2oat --dex-file=system_ext/system_ext/priv-app/Settings/Settings.apk --instruction-set=arm64 --compiler-filter=speed --oat-file=system_ext/system_ext/priv-app/Settings/oat/arm64/Settings.odex
    rm -rf tmp

}

function miuiSystemUIPatch(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Decompiling MiuiSystemUI.apk"
    java -jar ${rootPath}/bin/APKEditor.jar d -t raw -f -no-dex-debug -i system_ext/system_ext/priv-app/MiuiSystemUI/MiuiSystemUI.apk -o tmp/MiuiSystemUI >/dev/null 2>&1

    targetArg='0x3e8' # 1s
	targetSpeedFile=$(find tmp/MiuiSystemUI/smali/classes*/com/android/systemui/statusbar/policy/ -type f -name 'NetworkSpeedController*.smali' 2>/dev/null | xargs grep -rl 'const-wide/16 v0, 0xfa0' | sed 's/^\.\///' | sort)
	sed -i "s/const-wide\/16 v0, 0xfa0/const-wide\/16 v0, $targetArg/" $targetSpeedFile

    rm -f system_ext/system_ext/priv-app/MiuiSystemUI/MiuiSystemUI.apk
    rm -f system_ext/system_ext/priv-app/MiuiSystemUI/oat/arm64/*

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Rebuilding MiuiSystemUI.apk"
    java -jar ${rootPath}/bin/APKEditor.jar b -f -i tmp/MiuiSystemUI -o tmp/MiuiSystemUI.apk >/dev/null 2>&1
    zipalign 4 tmp/MiuiSystemUI.apk system_ext/system_ext/priv-app/MiuiSystemUI/MiuiSystemUI.apk
    ${rootPath}/bin/dex2oat --dex-file=system_ext/system_ext/priv-app/MiuiSystemUI/MiuiSystemUI.apk --instruction-set=arm64 --compiler-filter=speed --oat-file=system_ext/system_ext/priv-app/MiuiSystemUI/oat/arm64/MiuiSystemUI.odex
    rm -rf tmp
}

function modify(){
    # sh -c "cat ${rootPath}/files/config/productConfigAdd >> product/config/product_fs_config"
    # sh -c "cat ${rootPath}/files/config/productContextAdd >> product/config/product_file_contexts"

    sed -i 's/persist.miui.extm.enable=1/persist.miui.extm.enable=0/g' system_ext/system_ext/etc/build.prop
    sed -i 's/persist.miui.extm.enable=1/persist.miui.extm.enable=0/g' product/product/etc/build.prop

    sed -i 's/<bool name=\"support_hfr_video_pause\">false<\/bool>/<bool name=\"support_hfr_video_pause\">true<\/bool>/g' product/product/etc/device_features/*.xml
    sed -i 's/<bool name=\"support_dolby\">false<\/bool>/<bool name=\"support_dolby\">true<\/bool>/g' product/product/etc/device_features/*.xml
    sed -i 's/<bool name=\"support_video_hfr_mode\">false<\/bool>/<bool name=\"support_video_hfr_mode\">true<\/bool>/g' product/product/etc/device_features/*.xml
    sed -i 's/<bool name=\"support_hifi\">false<\/bool>/<bool name=\"support_hifi\">true<\/bool>/g' product/product/etc/device_features/*.xml
}

function removeFiles(){
    for file in $(cat ${rootPath}/files/config/removeFiles) ; do
        if [ -f "${file}" ] || [ -d "${file}" ] ;then
            echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Delete $(echo "${file}" | awk -F "/" '{print $4}')"
            rm -rf "${file}"
        fi
    done
}

function replaceCust(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Replacing cust image"
    cp -rf ${rootPath}/files/images/cust.img ${rootPath}/work/images/cust.img
}

function kernelsuPatch(){
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Patching init_boot image using KernelSu"

    mv images/init_boot.img init_boot.img
    outputImg=$(${rootPath}/bin/ksud boot-patch -b init_boot.img --kmi android14-6.1 --magiskboot ${rootPath}/bin/magiskboot | grep -A 1 'Output file is written to' | sed -n '2p' | grep -Eo '/.+$')
    mv $outputImg images/init_boot.img
}

function apatchPatch(){

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Patching boot image using Apatch"
    SUPERKEY=${1}
    mv images/boot.img boot.img

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Unpacking boot image"
    ${rootPath}/bin/magiskboot unpack boot.img >/dev/null 2>&1

    mv kernel kernel.ori
    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Patching kernel"
    ${rootPath}/bin/kptools -p -i kernel.ori -S "$SUPERKEY" -k ${rootPath}/bin/kpimg -o kernel >/dev/null 2>&1
    rm -f kernel.ori

    echo -e "$(date "+%m/%d %H:%M:%S") [${G}NOTICE${N}] Repacking boot image"
    ${rootPath}/bin/magiskboot repack boot.img >/dev/null 2>&1
    rm -f kernel boot.img
    mv new-boot.img images/boot.img
}

main ${1}
