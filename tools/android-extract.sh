#!/bin/bash

# Global Variables:
# Input/Output Variables
IMAGE="$1"                    # Input factory image
VENDOR="$2"                   # Vendor identifier
KEEPSTUFF="$4"               # Flag to preserve extracted files
VENDORMODE="$5"              # Vendor-specific mode (default 0)

# Log Files
MY_TMP="extract.sum"         # Summary log
MY_OUT="extract.db"          # Database log
MY_USB="extract.usb"         # USB log
MY_PROP="extract.prop"       # Properties log
TIZ_LOG="tizen.log"          # Samsung Tizen log
PAC_LOG="spd_pac.log"        # Lenovo PAC log
SBF_LOG="sbf.log"            # Motorola SBF log
MZF_LOG="mzf.log"            # Motorola MZF log
RAW_LOG="raw.log"            # Asus RAW log
KDZ_LOG="kdz.log"            # LG KDZ log

# Directory Variables
MY_DIR="extract/$2"          # Vendor-specific directory
MY_FULL_DIR="$(pwd)/extract/$2"  # Full path to vendor directory
TOP_DIR="extract"            # Top-level directory
AT_CMD='AT\+|AT\*|AT!|AT@|AT#|AT\$|AT%|AT\^|AT&'  # AT command patterns

# Temporary Directories
DIR_TMP="$HOME/atsh_tmp$3"   # Main temporary directory
MNT_TMP="$HOME/atsh_tmp$3/mnt"  # Mount point directory
APK_TMP="$HOME/atsh_apk$3"   # APK processing directory
ZIP_TMP="$HOME/atsh_zip$3"   # ZIP processing directory
ODEX_TMP="$HOME/atsh_odex$3" # ODEX processing directory
TAR_TMP="$HOME/atsh_tar$3"   # TAR processing directory
MSC_TMP="$HOME/atsh_msc$3"   # Miscellaneous directory
JAR_TMP="dex.jar"            # JAR file name

# Tool Paths
DEPPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )/atsh_setup"
USINGDEPPATH=1

# Tool Executables
DEX2JAR="$DEPPATH/dex2jar/dex-tools/target/dex2jar-2.1-SNAPSHOT/d2j-dex2jar.sh"
JDCLI="$DEPPATH/jd-cmd/jd-cli/target/jd-cli.jar"
BAKSMALI="$DEPPATH/baksmali-2.2b4.jar"
SMALI="$DEPPATH/smali-2.2b4.jar"
JADX="$DEPPATH/jadx/build/jadx/bin/jadx"
UNKDZ="$DEPPATH/kdztools/unkdz"
UNDZ="$DEPPATH/kdztools/undz"
UPDATA="$DEPPATH/split_updata.pl/splitupdate"
UNSPARSE="$DEPPATH/combine_unsparse.sh"
SDAT2IMG="$DEPPATH/sdat2img/sdat2img.py"
SONYFLASH="$DEPPATH/flashtool/FlashToolConsole"
SONYELF="$DEPPATH/unpackelf/unpackelf"
IMGTOOL="$DEPPATH/imgtool/imgtool.ELF64"
KITCHEN="$DEPPATH/Kitchen/kitchen.sh"
HTCRUUDEC="$DEPPATH/htcruu-decrypt3.6.5/RUU_Decrypt_Tool"
SPLITQSB="$DEPPATH/split_qsb.pl"
LESZB="$DEPPATH/szbtool/leszb"
UNYAFFS="$DEPPATH/unyaffs/unyaffs"

# Processing Variables
BOOT_OAT=""                  # Boot OAT file path
BOOT_OAT_64=""              # 64-bit Boot OAT file path
AT_RES=""                    # Result status
SUB_SUB_TMP="extract_sub"   # Sub-subdirectory

# Chunk Processing Flags
CHUNKED=0                    # system.img chunk flag
CHUNKEDO=0                   # oem.img chunk flag
CHUNKEDU=0                   # userdata.img chunk flag
COMBINED0=0                  # system combined flag
COMBINED1=0                  # userdata combined flag
COMBINED2=0                  # cache combined flag
COMBINED3=0                  # factory combined flag
COMBINED4=0                  # preload combined flag
COMBINED5=0                  # without_carrier_userdata flag
TARNESTED=0                  # Nested TAR counter

# Function Definitions
clean_up() {
    return 0
}

# Recursively extract all archives in all subdirectories
recursive_unzip_all() {
    local found_archives=1
    while [ $found_archives -ne 0 ]; do
        found_archives=0
        # Find all zip, tar, tar.gz, tgz, rar, 7z files recursively
        find . -type f \( -iname "*.zip" -o -iname "*.tar" -o -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.rar" -o -iname "*.7z" \) | while read -r archive; do
            found_archives=1
            local dir=$(dirname "$archive")
            local base=$(basename "$archive")
            echo "Extracting $archive in $dir"
            case "$base" in
                *.zip)
                    unzip -o "$archive" -d "$dir"
                    ;;
                *.tar)
                    tar -xf "$archive" -C "$dir"
                    ;;
                *.tar.gz|*.tgz)
                    tar -xzf "$archive" -C "$dir"
                    ;;
                *.rar)
                    unrar x -o+ "$archive" "$dir"
                    ;;
                *.7z)
                    7z x "$archive" -o"$dir"
                    ;;
            esac
            rm -f "$archive"
        done
    done
}

# Decompress the zip-like file
# Return good if the decompression is successful
# Otherwise bad
# NOTE: to support more decompressing methods, please add them here
at_unzip()
{
	local filename="$1"
	local dir="$2"
	local format=`file -b "$filename" | cut -d" " -f1`
	local format2=`file -b "$filename" | cut -d" " -f2`
	if [ "$format" == "zip" ] || [ "$format" == "ZIP" ] || [ "$format" == "Zip" ]; then
		if [ -z "$dir" ]; then
			unzip "$filename"
		else
			unzip -d "$dir" "$filename"
		fi
		AT_RES="good"
	elif [ "$format" == "Java" ]; then
		# mischaracterization of zip file as Java archive data for HTC
		# or it is actually a JAR, but unzip works to extract contents
		if [ -z "$dir" ]; then
			unzip "$filename"
		else
			unzip -d "$dir" "$filename"
		fi
		AT_RES="good"
	elif [ "$format" == "POSIX" ] && [ "$format2" == "tar" ]; then
		if [ -z "$dir" ]; then
			tar xvf "$filename"
		else
			tar xvf "$filename" -C "$dir"
		fi
		AT_RES="good"
	elif [ "$format" == "PE32" ] && [ "$vendor" == "htc" ]; then # HTC exe (HTC-specific)
	        $HTCRUUDEC -sf "$filename" # expect to be passed in SUB_SUB_TMP as arg2
	        local decoutput=`ls | grep "OUT"`
		rm -r "$dir"
	        mv "$decoutput" "$dir"
		AT_RES="good"
	elif [ "$format" == "RAR" ]; then
		if [ -z "$dir" ]; then
			unrar x "$filename"
			if [ "$vendor" == "samsung" ]; then
				tar xvf `basename "$filename" ".rar"`".md5"
			fi
		else
			local bakfromrar=`pwd`
			# mkdir "$dir"
			cp "$filename" "$dir"
			cd "$dir"
			unrar x "$filename"
			if [ "$vendor" == "samsung" ]; then
				tar xvf `basename "$filename" ".rar"`".md5"
			fi
			rm "$filename"
			cd "$bakfromrar"
		fi
		AT_RES="good"
	elif [ "$format" == "gzip" ]; then
		# gunzip is difficult to redirect
		if [ -z "$dir" ]; then
			gunzip "$filename"
			if [ "$vendor" == "motorola" ] && 
[[ "$filename" == *".tar.gz" ]]; then # only if tar.gz, not sbf.gz or mzf.gz
				tar xvf `basename "$filename" ".gz"`
			fi
		else
			local backfromgz=`pwd`
			# mkdir "$dir"
			cp "$filename" "$dir"
			cd "$dir"
			gunzip "$filename"
			if [ "$vendor" == "motorola" ] &&
[[ "$filename" == *".tar.gz" ]]; then # only if tar.gz, not sbf.gz or mzf.gz
				tar xvf `basename "$filename" ".gz"`
			fi
			# rm "$filename"
			cd "$bakfromgz"
		fi
		rm "$filename"
		AT_RES="good"
	elif [ "$format" == "7-zip" ]; then
		if [ -z "$dir" ]; then
			7z x "$filename"
		else
			7z x -o"$dir" "$filename"
		fi
		AT_RES="good"
	else
		AT_RES="bad"
	fi
}

handle_text() {
    # Handle text file processing
    return 0
}

handle_binary() {
    # Handle binary file processing
    return 0
}

handle_elf() {
    # Handle ELF file processing
    return 0
}

handle_x86() {
    # Handle x86 boot sector processing
    return 0
}

handle_bootimg()
{
	# Currently no special handling for Android bootimg
	# possibly use unpackbootimg tool available at: https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/android-serialport-api/android_bootimg_tools.tar.gz

	# above tool results in segfault, instead relying on IMGTOOL
	local name=`basename "$1"`
	# local dir=`dirname $1`
	# local extracted=`dirname $IMGTOOL`
	
	if [[ "$name" == "boot"* ]] || [[ "$name" == "recovery"* ]] || [[ "$name" == "hosd"* ]] ||
[[ "$name" == "droidboot"* ]] || [[ "$name" == "fastboot"* ]] || [[ "$name" == "okrecovery"* ]] ||
[[ "$name" == "BOOT"* ]] || [[ "$name" == "RECOVERY"* ]] ||
[[ "$name" == *".recovery"*".bin" ]] || [[ "$name" == *".boot"*".bin" ]] ||
[[ "$name" == *".factory"*".bin" ]] || [[ "$name" == "laf"*".bin" ]]; then
        echo "Handling bootimg $1"

		# NOTE: recovery, boot, factory, and laf bins are LG-specific
		$KITCHEN unpack "$1" "$MY_FULL_DIR"/"$SUB_DIR" "boot.img"
		
		# Copy the extracted boot image to the destination directory
		if [ -f "$MY_FULL_DIR"/"$SUB_DIR"/boot.img ]; then
			mkdir -p "$DEST_PATH"
			cp "$MY_FULL_DIR"/"$SUB_DIR"/boot.img "$DEST_PATH"/boot.img
			echo "Copied boot.img to $DEST_PATH/boot.img"
		fi
	else
		echo "Skipping bootimg decode as no name match"
		handle_binary "$1"
	fi
}

handle_apk() {
    # Handle APK file processing
    return 0
}

handle_jar() {
    # Handle JAR file processing
    return 0
}

handle_java() {
    # Handle Java file processing
    return 0
}

handle_odex() {
    # Handle ODEX file processing
    return 0
}

check_for_suffix() {
    # Check file suffix for type determination
    return 0
}

handle_special() {
    # Handle special file types
    return 0
}

at_extract()
{
	local filename="$1"
	local format=`file -b "$filename" | cut -d" " -f1`
	local justname=`basename "$filename"`

#	echo "IN at_extract, filename = $filename"
#	echo "IN at_extract, format = $format"

	# Check for special files
	handle_special "$filename"

	if [ "$format" == "data" ] || [ "$format" == "apollo" ] || [ "$format" == "FoxPro" ] || [ "$format" == "Mach-O" ] || 
[ "$format" == "DOS/MBR" ] || [ "$format" == "PE32" ] || [ "$format" == "PE32+" ] || [ "$format" == "dBase" ] || [ "$format" == "MS" ] || 
[ "$format" == "PDP-11" ] || [ "$format" == "zlib" ] || [ "$format" == "ISO-8859" ] ||
[ "$format" == "Composite" ] || [ "$format" == "very" ] || [ "$format" == "Hitachi" ] || [ "$format" == "SQLite" ]; then
		# Handle normal binary file
		# FoxPro, dBase, MS, PDP-11, zlib, ISO-8859 (rarely) found in Motorola (might have to make it moto-specific)
		# Mach-O, DOS/MBR, and PE32 found in Nextbit (binaries)
		# DOS/MBR can be mounted as vfat, but no difference running strings on mounted contents vs. running strings on unmounted .bin
		# Composite Document File V2 Document (msi for xiaomi flash tool)
		# very short file (no magic) from BLU
		# Hitachi may be a misclassification of BLU's appsboot.bn
		# SQLite from alcatel's SP Flash Tool (strings is appropriate, so handle_binary)
		handle_binary "$filename"
		AT_RES="good"
	elif [ "$format" == "ELF" ]; then
		# Handle ELF
		handle_elf "$filename"
		# Handle Odex as well
		check_for_suffix "$filename"
		if [ "$AT_RES" == "odex" ]; then
			handle_odex "$filename"
		fi
		AT_RES="good"
	elif [ "$format" == "x86" ]; then
		# Handle x86 boot sector file
		handle_x86 "$filename"
		AT_RES="good"
	elif [ "$format" == "DOS" ]; then
		# handle the bat file
		handle_text "$filename"
		AT_RES="good"
	elif [ "$format" == "Java" ]; then
		# Handle the jar file
		handle_java "$filename"
		AT_RES="good"
	elif [ "$format" == "POSIX" ] || [ "$format" == "Bourne-Again" ]; then
		# handle the sh file
		handle_text "$filename"
		AT_RES="good"
	elif [ "$format" == "ASCII" ] || [ "$format" == "XML" ] || [ "$format" == "TeX" ] || [ "$format" == "html" ] || [ "$format" == "UTF-8" ] || [ "$format" == "C" ] || [ "$format" == "Pascal" ] || [ "$format" == "python" ]; then
		# handle the txt file
		handle_text "$filename"
		AT_RES="good"
	elif [ "$format" == "Windows" ]; then # assuming all Windows setup INFormation files
		handle_text "$filename"
		AT_RES="good"
	elif [ "$format" == "Zip" ]; then
		# handle the zip quirk: file returns zip but is apk/jar essentially
		check_for_suffix "$filename"
		if [ "$AT_RES" == "java" ]; then
			handle_java "$filename"
			AT_RES="good"
		else
			# handle the zip file
			handle_zip "$filename" "zip"
			AT_RES="good"
		fi
	elif [ "$format" == "gzip" ] || [ "$format" == "XZ" ]; then
		# handle the gzip file
		handle_zip "$filename" "gzip"
		AT_RES="good"
	elif [ "$format" == "Android" ]; then # originally in process_file function!
		echo "processing img as binary..."
		handle_bootimg "$filename" # saying oem.img is a bootimg may be a misclassification
		AT_RES="good"
	elif [ "$format" ==  "broken" ] || [ "$format" == "symbolic" ] || [ "$format" == "SE" ] || [ "$format" == "empty" ] || [ "$format" == "directory" ] || [ "$format" == "Ogg" ] || [ "$format" == "PNG" ] || [ "$format" == "JPEG" ] || [ "$format" == "PEM" ] || [ "$format" == "TrueType" ] || [ "$format" == "LLVM" ] || [ "$format" == "Device" ]; then
		# format == dBase was being skipped before; now handled as binary (jochoi)
		# format == Device Tree Blob after extracting boot/recovery img; ignoring
		# Skip broken/symbolic/sepolicy/empty/dir/...
		AT_RES="skip"
	else
		AT_RES="bad"
	fi
}

handle_zip() {
    # Handle ZIP file processing
    return 0
}

handle_chunk() {
    # Handle chunked image processing
    return 0
}

handle_ext4() {
    # Handle ext4 filesystem processing
    return 0
}

handle_simg()
{
	echo "Extracting system.img"
	local img="$1"
	local nam=`basename -s .img "$img"`
	local ext="$nam.img"
	local arch=""
	local mnt_name="${MNT_TMP}_${ext}"
	mkdir $DIR_TMP
	mkdir $mnt_name
	cp "$img" $DIR_TMP/"$ext"

	# NOTE: needs sudo or root permission
	sudo mount -o loop,ro $DIR_TMP/"$ext" $mnt_name
	# Find the boot.oat for RE odex
	BOOT_OAT=""
	BOOT_OAT_64=""
	while read file
	do
		# Debug
		#echo "DEBUG: boot.oat - $file"
		arch=`file -b "$file" | cut -d" " -f2 | cut -d"-" -f1`
		if [ "$arch" == "64" ]; then
			BOOT_OAT_64="$file"
		else
			BOOT_OAT="$file"
		fi
	done < <(sudo find $mnt_name -name boot.oat -print)
	AT_RES="good"
}

# almost exact duplicate of handle_ext4, except mounting as vfat
handle_vfat()
{
	echo "Extracting vfat"
	local img="$1"
	local ext=`basename "$img"`
	local arch=""
	local mnt_name="${MNT_TMP}_${ext}"
	mkdir $DIR_TMP
	mkdir $mnt_name
	# Make a copy
	cp "$img" $DIR_TMP/"$ext"
	# NOTE: needs sudo or root permission
	sudo mount -o ro -t vfat $DIR_TMP/"$ext" $mnt_name
	# Find the boot.oat for RE odex
	BOOT_OAT=""
	BOOT_OAT_64=""
	while read file
	do
		# Debug
		#echo "DEBUG: boot.oat - $file"
		arch=`file -b "$file" | cut -d" " -f2 | cut -d"-" -f1`
		if [ "$arch" == "64" ]; then
			BOOT_OAT_64="$file"
		else
			BOOT_OAT="$file"
		fi
	done < <(sudo find $mnt_name -name boot.oat -print)
	AT_RES="good"
}

handle_unsparse() {
    # Handle unsparse image processing
    return 0
}

handle_sdat() {
    # Handle SDAT image processing
    return 0
}

handle_qsbszb() {
    # Handle QSB/SZB archive processing
    return 0
}

# Go thru each from within sub_sub_dir
# Currently no special handling for bootloader.img, radio.img and modem.img
process_file()
{
	local filename="$1"
	local justname=`basename "$filename"`
#	local format=`file -b $filename | cut -d" " -f1`
	local handled=false
#	echo "Processing file: $filename" >> ../$MY_TMP # printing out the file being processed
#	echo "IN process_file | handling file: $filename"
#-------------------------------------------------------------------------------
	if [ "$VENDOR" == "aosp" ]; then
		if [ "$justname" == "system.img" ] || [ "$justname" == "system_other.img" ] || [ "$justname" == "vendor.img" ]; then
			# Handle sparse ext4 fs image
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == "radio"*".img" ]]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "samsung" ]; then
		local samformat=`file -b "$filename" | cut -d" " -f1`
		# handle LZ4 compressed images
		if [[ "$justname" == *".lz4" ]] ; then
			newname=`basename "$justname" ".lz4"`
			newfilename=`basename "$filename" ".lz4"`

			echo "file is LZ4 compressed"
			unlz4 "$filename" "$newfilename"

			justname="$newname"
			filename="$newfilename"
		fi

		if [ "$justname" == "*.img.ext4" ] || [ "$justname" == "system.img.ext4" ] || [ "$justname" == "cache.img.ext4" ] || 
[ "$justname" == "omr.img.ext4" ] || [ "$justname" == "userdata.img.ext4" ]; then
			# may be either ext4 or sparse img
			if [ "$samformat" == "Linux" ]; then
				echo "processing ext4 img..."
				echo "-----------------------------"
				handle_ext4 "$filename"
				echo "-----------------------------"
			else
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "cache.img" ] || [ "$justname" == "hidden.img" ] || [ "$justname" == "omr.img" ] ||
[ "$justname" == "hidden.img.md5" ] || [ "$justname" == "cache.img.md5" ] || [ "$justname" == "persist.img" ] || [ "$justname" == "factoryfs.img" ] || [ "$justname" == "vendor.img" ]; then
			# Handle sparse ext4 fs image
			# note 2 firmware layout has different naming (.img) instead of (.img.ext4)
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.img" ] || [ "$justname" == "userdata.img" ] ||
[ "$justname" == "system.img.md5" ] || [ "$justname" == "userdata.img.md5" ]; then
			if [ "$samformat" == "DOS/MBR" ]; then
				echo "processing vfat img"
				echo "-----------------------------"
				handle_vfat "$filename"
			else
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
			fi
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "adspso.bin" ]; then
			# Handle ext4 fs image
			echo "processing ext4 img..."
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.rfs" ] || [ "$justname" == "csc.rfs" ] || 
[ "$justname" == "efs.img" ] || [ "$justname" == "factoryfs.rfs" ] || [ "$justname" == "cache.rfs" ] ||
[ "$justname" == "hidden.rfs" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "fota.zip" ]; then
			# Skip the passwd-protected zip file
			echo "skipping passwd-protected fota.zip..."
			handled=true
		elif [[ "$justname" == *".tar"* ]] || [[ "$justname" == *".TAR"* ]]; then
			# this is a nested tar... how far of a nesting need we account for?
			# recursion here? # what is the current directory?
			# echo `pwd`
			TARNESTED=$((TARNESTED + 1)) # increment TARNESTED
			mkdir "nestedPOSIXtar$TARNESTED"
			tar xvpf "$filename" --xattrs -C "nestedPOSIXtar$TARNESTED"
			find "nestedPOSIXtar$TARNESTED" -print0 | while IFS= read -r -d '' c
			do
				process_file "$c"
				echo "$c processed: $AT_RES"
			done
			[ $? == 55 ] && exit 55
			echo "-------------------------"
			rm -r "nestedPOSIXtar$TARNESTED"
			TARNESTED=$((TARNESTED - 1)) # decrement TARNESTED
			handled=true
			#at_unzip "$filename" 
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "motorola" ]; then
		local motoformat=`file -b "$filename" | cut -d" " -f1`
		if [[ "$justname" == *".sbf" ]]; then
			# proprietary motorola format
			# the only available tool, sbf_flash, is unreliable, skip and record only FIXME
			echo "$IMAGE" >> $SBF_LOG
		elif [[ "$justname" == *".mzf" ]]; then
			# unclear how to extract from .mzf (no tools found) FIXME
			echo "$IMAGE" >> $MZF_LOG
		# not attempting to deal with shx or nb0 files either (5)
		# nb0 utils unpacker simply unpacks as data, not imgs
		elif [[ "$justname" == "system.img_sparsechunk."* ]]; then
			# sparsechunks specific to motorola
			# will only end up here once, after which img is reconstructed from all sparsechunks
			if [ $CHUNKED -eq 0 ]; then
				echo "processing sparsechunks into ext4..."
				echo "-----------------------------"
				handle_chunk "$filename" 0
				CHUNKED=1 # no need to duplicate work per sparsechunk
				echo "-----------------------------"
			fi
			handled=true
		elif [[ "$justname" == "system.img_sparsechunk"* ]]; then
			# if there is no period after sparsechunk, diff handling
			if [ $CHUNKED -eq 0 ]; then
				echo "processing sparsechunks into ext4..."
				echo "-----------------------------"
				handle_chunk "$filename" 1
				CHUNKED=1 # no need to duplicate work per sparsechunk
				echo "-----------------------------"
			fi
		elif [[ "$justname" == "oem.img_sparsechunk."* ]]; then
			if [ $CHUNKEDO -eq 0 ]; then
				echo "processing sparsechunks into ext4..."
				echo "-----------------------------"
				handle_chunk_lax "$filename" 0
				CHUNKEDO=1 # no need to duplicate work per sparsechunk
				echo "-----------------------------"
			fi
			handled=true
		elif [[ "$justname" == "userdata.img_sparsechunk"* ]]; then
			if [ $CHUNKEDU -eq 0 ]; then
				echo "processing sparsechunks into ext4..."
				echo "-----------------------------"
				handle_chunk_lax "$filename" 1
				CHUNKEDU=1 # no need to duplicate work per sparsechunk
				echo "-----------------------------"
			fi
			handled=true
		elif [[ "$justname" == "system_b.img_sparsechunk."* ]]; then
			if [ $CHUNKEDB -eq 0 ]; then
				echo "processing sparsechunks into ext4..."
				echo "-----------------------------"
				handle_chunk_lax "$filename" 2
				CHUNKEDB=1 # no need to duplicate work per sparsechunk
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "adspso.bin" ] || [ "$justname" == "fsg.mbn" ] ||
[ "$justname" == "preinstall.img" ] || [ "$justname" == "radio.img" ]; then
			# Handle ext4 fs image
			echo "processing ext4 img..."
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system_signed" ] || [ "$justname" == "modem_signed" ]; then
			if [ "$motoformaat" == "Linux" ]; then
				# Handle ext4 fs image
				echo "processing ext4 img..."
				echo "-----------------------------"
				handle_ext4 "$filename"
				echo "-----------------------------"
				handled=true
			fi
		elif [ "$justname" == "BTFM.bin" ] || [ "$justname" == "cache.img" ] ||
[ "$justname" == "preload.img" ]; then
			# Handle sparse ext4 fs image
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "NON-HLOS.bin" ]; then
			if [ "$motoformat" == "Linux" ]; then
				# Handle ext4 fs image
				echo "processing ext4 img..."
				echo "-----------------------------"
				handle_ext4 "$filename"
				echo "-----------------------------"
			elif [ "$motoformat" == "Android" ]; then
				# Handle sparse ext4 fs image
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			fi
			handled=true
		# not all images follow the sparsechunk; may be sparseimg already
		elif [ "$justname" == "system.img" ]; then
			# ignore; want to avoid double work of handle_chunk
			if [ $CHUNKED -eq 1 ]; then # not sure if we end up here; just in case
				echo "not processing system.img (handled by handle_chunk)..."
			elif [ "$motoformat" == "Linux" ]; then
				# Handle ext4 fs image
				echo "processing ext4 img..."
				echo "-----------------------------"
				handle_ext4 "$filename"
				echo "-----------------------------"
			elif [ "$motoformat" == "Android" ]; then
				# Handle sparse ext4 fs image
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "userdata.img" ]; then
			# ignore; want to avoid double work of handle_chunk
			if [ $CHUNKEDU -eq 1 ]; then
				echo "not processing userdata.img (handled by handle_chunk)..."
			else
				# Handle sparse ext4 fs image
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "oem.img" ]; then
			# ignore; want to avoid double work of handle_chunk
			if [ $CHUNKEDO -eq 1 ]; then
				echo "not processing oem.img (handled by handle_chunk)..."
			else
				# Handle sparse ext4 fs image
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "system_b.img" ]; then
			# ignore; want to avoid double work of handle_chunk
			if [ $CHUNKEDB -eq 1 ]; then
				echo "not processing system_b.img (handled by handle_chunk)..."
			else
				# Handle sparse ext4 fs image
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "system.new.dat" ]; then
			# maybe needed for system.patch.dat (though this has been found empty)
			echo "processing sdat img"
			echo "-----------------------------"
			handle_sdat "$filename" "system"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "nextbit" ]; then
		# NextBit phone firmware shares the characteristics of aosp (only system.img needs to be handled as simg)
		# however, there are some additional .img files which need to be processed as binaries (not simg or ext4)
		if [ "$justname" == "system.img" ] ||
[[ "$justname" == *"persist.img" ]] || [[ "$justname" == *"cache.img" ]] || [[ "$justname" == *"hidden.img.ext4" ]]; then
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "lg" ]; then
		if [ "$justname" == "system.image" ] || [ "$justname" == "vendor_a.image" ] || [ "$justname" == "system_a.image" ] || [ "$justname" == "userdata.image" ] ||
[ "$justname" == "cache.image" ] || [ "$justname" == "cust.image" ] || [ "$justname" == "boot.image" ] ||
[[ "$justname" == "persist_"*".bin" ]]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == *"modem_"*".bin" ]]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		# newly downloaded LG firmware (bumped) matching physical device has different names
		# for firmwares as zip; not expected to use these for the kdz extraction
		elif [ "$justname" == "system.img" ]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "modem.img" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "htc" ]; then
		# HTC Firmware (first 3 are observed in both ZIP and RUU-EXE) have a few vfat mountables
		if [ "$justname" == "wcnss.img" ] || [ "$justname" == "adsp.img" ] || [ "$justname" == "radio.img" ] ||
[ "$justname" == "cpe.img" ] || [ "$justname" == "venus.img" ] || [ "$justname" == "slpi.img" ] ||
[ "$justname" == "rfg_3.img" ] || [ "$justname" == "bluetooth.img" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		# ~~~ start EXE-specific handling
		# ~~~ the existence of or proper formatting of other ~.img varies across firmwares
		elif [ "$justname" == "system.img" ] || [ "$justname" == "appreload.img" ] || [ "$justname" == "cota.img" ] ||
[ "$justname" == "cache.img" ] || [ "$justname" == "dsp.img" ]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == "userdata"*".img" ]] || [ "$justname" == "persist.img" ]; then
			echo "processing sparse ext4 img"
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "ramdisk.img" ]; then
			echo "processing separate ramdisk img"
			echo "-----------------------------"
			mkdir ramdiskseparate
			mv ramdisk.img ramdiskseparate
			cd ramdiskseparate
			gunzip -c ramdisk.img | cpio -i
			rm ramdisk.img
			cd ..
	                find "ramdiskseparate" -print0 | while IFS= read -r -d '' file
        	        do
                                at_extract "$file"
                        	echo "$file processed: $AT_RES"
                	done
                	rm -r ramdiskseparate
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	#elif [ "$VENDOR" == "alcatel" ]; then
		# nothing special here besides potentially unhandled file types:
		# Windows, DOS, Linux, SQLite
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "blu" ]; then
		# ext4 = cache.img, system.img, userdata.img; these are also the only mountables (ext4)
		if [ "$justname" == "system.img" ] || [ "$justname" == "cache.img" ] ||
[ "$justname" == "userdata.img" ]; then
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "huawei" ]; then
		# TODO: USERDATA.img does not mount after simg2img processing; did updata fail?
		# TODO: no current handling for ~~~-sign.img. Only 5 firmwares of this form
		# ----: not obvious how to handle these, unfortunately
		# NOTE: no mountable vfat was found
		if [ "$justname" == "CACHE.img" ] ||
[ "$justname" == "USERDATA.img" ] || [ "$justname" == "PERSIST.img" ] ||
[ "$justname" == "cust.img" ] || [ "$justname" == "persist.img" ] ||
[ "$justname" == "modem.img" ] || [ "$justname" == "nvm1.img" ] || [ "$justname" == "nvm2.img" ] ||
[ "$justname" == "TOMBSTONES.img" ] || [ "$justname" == "MODEMIMAGE.img" ]; then
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "cache.img" ] || [ "$justname" == "userdata.img" ]; then
			local huaformat=`file -b "$filename" | cut -d" " -f1`
			# prioritize Android simg
			if [ "$huaformat" == "Android" ]; then
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			elif [ -e `dirname "$filename"`/*scatter*.txt ]; then
				# handle non-bin MTK
				echo "processing unusual ext4 img by padding..."
				echo "-----------------------------"
				local lbindir=`dirname "$filename"`
				dd if=/dev/zero of="$lbindir"/"padding.zer" bs=`ls -l "$filename" | awk '{ print $5 }'` count=1
				cat "$lbindir"/"padding.zer" >> "$filename"
				rm "$lbindir"/"padding.zer"
				handle_ext4 $filename
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "system.img" ] || [ "$justname" == "SYSTEM.img" ] ||
[ "$justname" == "CUST.img" ]; then
			# need special handling, because it may sometimes be simg, othertimes ext4
			# it may actually even fail when it is ext4 (too complex to handl here)
			# --- on those failing firmwares, cache, userdata also affected
			# --- example: Huawei_Honor_H30-T10-MT6572_20131216_4.2.2
			local huaformat=`file -b "$filename" | cut -d" " -f1`
			# may have additional name, e.g., MT6582_Android_scatter-Hol-U10-16GB.txt
			# prioritize Android simg
			if [ "$huaformat" == "Android" ]; then
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
				handled=true
			elif [ -e `dirname "$filename"`/*scatter*.txt ]; then
				# handle non-bin MTK
				echo "processing unusual ext4 img by padding..."
				echo "-----------------------------"
				local lbindir=`dirname "$filename"`
				dd if=/dev/zero of="$lbindir"/"padding.zer" bs=`ls -l "$filename" | awk '{ print $5 }'` count=1
				cat "$lbindir"/"padding.zer" >> "$filename"
				rm "$lbindir"/"padding.zer"
				handle_ext4 $filename
				echo "-----------------------------"
				handled=true
			elif [ "$huaformat" == "Linux" ]; then
				echo "processing ext4 img"
				echo "-----------------------------"
				handle_ext4 "$filename"
				echo "-----------------------------"
				handled=true
			fi
		elif [ "$justname" == "system.bin" ] || [ "$justname" == "userdata.bin" ] ||
[ "$justname" == "cache.bin" ] || [ "$justname" == "protect_s.bin" ] ||
[ "$justname" == "protect_f.bin" ]; then
			# rare case for huawei
			echo "processing unusual ext4 img by padding..."
			echo "-----------------------------"
			local lbindir=`dirname "$filename"`
			dd if=/dev/zero of="$lbindir"/"padding.zer" bs=`ls -l "$filename" | awk '{ print $5 }'` count=1
			cat "$lbindir"/"padding.zer" >> "$filename"
			rm "$lbindir"/"padding.zer"
			handle_ext4 $filename
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == "system_"*".unsparse" ]]; then
			if [ $COMBINED0 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse "$filename" "system" "rawprogram0.xml" "$VENDOR"
				echo "-----------------------------"
				COMBINED0=1
			fi
			handled=true
		elif [[ "$justname" == "userdata_"*".unsparse" ]]; then
			if [ $COMBINED1 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse $filename "userdata" "rawprogram0.xml" "$VENDOR"
				echo "-----------------------------"
				COMBINED1=1
			fi
			handled=true
		# unlike persist, which always has a single fragment, cache may have 1 or 2
		elif [[ "$justname" == "cache_"*".unsparse" ]]; then
			echo "processing cache unsparse ext4 img..."
			echo "-----------------------------"
			local lcachdir=`dirname "$filename"`
			if [ `ls "$lcachdir"/"cache_*"` -eq 1 ]; then # special handling, single
				dd if=/dev/zero of="$lcachdir"/"cache.zer" bs=512 count=246488
				# magic number found by comparison with a cache.img in some ROMs
				cat "$lcachdir"/"cache.zer" >> "$filename"
				rm "$lcachdir"/"cache.zer"
				handle_ext4 $filename
				echo "-----------------------------"
			else
				if [ $COMBINED2 -eq 0 ]; then
					echo "processing unsparse ext4 img..."
					echo "-----------------------------"
					handle_unsparse $filename "cache" "rawprogram0.xml" "$VENDOR"
					echo "-----------------------------"
					COMBINED2=1
				fi
			fi
			handled=true
		elif [[ "$justname" == "system_"*".img" ]]; then
			if [ $COMBINED0 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse "$filename" "system" "rawprogram0.xml" "$VENDOR""2"
				echo "-----------------------------"
				COMBINED0=1
			fi
			handled=true
		elif [[ "$justname" == "userdata_"*".img" ]]; then
			if [ $COMBINED1 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse $filename "userdata" "rawprogram0.xml" "$VENDOR""2"
				echo "-----------------------------"
				COMBINED1=1
			fi
			handled=true
		# unlike persist, which always has a single fragment, cache may have 1 or 2
		elif [[ "$justname" == "cache_"*".img" ]]; then
			echo "processing cache unsparse ext4 img..."
			echo "-----------------------------"
			local lcachdir=`dirname "$filename"`
			if [ `ls "$lcachdir"/"cache_*"` -eq 1 ]; then # special handling, single
				dd if=/dev/zero of="$lcachdir"/"cache.zer" bs=512 count=246488
				# magic number found by comparison with a cache.img in some ROMs
				cat "$lcachdir"/"cache.zer" >> "$filename"
				rm "$lcachdir"/"cache.zer"
				handle_ext4 $filename
				echo "-----------------------------"
			else
				if [ $COMBINED2 -eq 0 ]; then
					echo "processing unsparse ext4 img..."
					echo "-----------------------------"
					handle_unsparse $filename "cache" "rawprogram0.xml" "$VENDOR""2"
					echo "-----------------------------"
					COMBINED2=1
				fi
			fi
			handled=true
		elif [[ "$justname" == "persist_"*".unsparse" ]] || [[ "$justname" == "persist_"*".img" ]]; then
			echo "processing persist unsparse ext4 img..."
			echo "-----------------------------"
			local lpersdir=`dirname "$filename"`
			dd if=/dev/zero of="$lpersdir"/"persist.zer" bs=512 count=56120
			# magic number found by comparison with a persist.img in some ROMs
			cat "$lpersdir"/"persist.zer" >> "$filename"
			rm "$lpersdir"/"persist.zer"
			handle_ext4 $filename
			# handle_unsparse $filename "persist" "rawprogram_unsparse.xml" "$VENDOR"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "NON-HLOS.bin" ] || [ "$justname" == "MODEM.img" ] || 
[ "$justname" == "log.img" ] || [ "$justname" == "fat.img" ] || [ "$justname" == "fat.bin" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == *".pac" ]]; then
			echo "$IMAGE" >> $PAC_LOG
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "lenovo" ]; then
		if [ "$justname" == "system.img" ] || [ "$justname" == "userdata.img" ] || 
[ "$justname" == "cache.img" ] || [ "$justname" == "persist.img" ] || [ "$justname" == "fac.img" ] || 
[ "$justname" == "config.img" ] || [ "$justname" == "factory.img" ] || [ "$justname" == "country.img" ] || 
[ "$justname" == "preload.img" ] || [ "$justname" == "cpimage.img" ]; then
			# need special handling, because it may sometimes be simg, othertimes ext4
			local lenformat=`file -b "$filename" | cut -d" " -f1`
			if [ "$lenformat" == "Android" ]; then
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
				handled=true
			elif [ "$lenformat" == "Linux" ]; then
				echo "processing ext4 img"
				echo "-----------------------------"
				handle_ext4 "$filename"
				echo "-----------------------------"
				handled=true
			fi
		elif [ "$justname" == "adspso.bin" ] || [ "$justname" == "countrycode.img" ] ||
[ "$justname" == "system.img.ext4.unsparse" ]; then
			# Handle ext4 fs image
			echo "processing ext4 img..."
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "userdata.img.ext4" ] || [ "$justname" == "without_carrier_cache.img" ] ||
[[ "$justname" == *".rom" ]]; then
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "BTFM.bin" ] || [ "$justname" == "NON-HLOS.bin" ] ||
[ "$justname" == "fat.bin" ] || [ "$justname" == "udisk.bin" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		# Handle split up pieces of system_#.img, userdata_#.img, cache_#.img, persist_#.img, preload_#.img
		# Prevent duplicate processing
		elif [[ "$justname" == "system_"*".img" ]]; then
			if [ $COMBINED0 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram_unsparse.xml" ]; then
					handle_unsparse "$filename" "system" "rawprogram_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse "$filename" "system" "rawprogram0_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0.xml" ]; then # ought to use rawprogram0.xml
					handle_unsparse "$filename" "system" "rawprogram0.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"upgrade.xml" ]; then # rare case
					handle_unsparse "$filename" "system" "upgrade.xml" "$VENDOR"
				fi
				echo "-----------------------------"
				COMBINED0=1
			fi
			handled=true
		elif [[ "$justname" == "userdata_"*".img" ]]; then
			if [ $COMBINED1 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram_unsparse.xml" ]; then
					handle_unsparse "$filename" "userdata" "rawprogram_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse "$filename" "userdata" "rawprogram0_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0.xml" ]; then # ought to use rawprogram0.xml
					handle_unsparse "$filename" "userdata" "rawprogram0.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"upgrade.xml" ]; then # rare case
					handle_unsparse "$filename" "userdata" "upgrade.xml" "$VENDOR"
				fi
				echo "-----------------------------"
				COMBINED1=1
			fi
			handled=true
		elif [[ "$justname" == "without_carrier_userdata_"*".img" ]]; then
			if [ $COMBINED5 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse "$filename" "without_carrier_userdata" "rawprogram_unsparse_clean_carrier.xml" "$VENDOR"
				echo "-----------------------------"
				COMBINED5=1
			fi
			handled=true
		elif [[ "$justname" == "cache_"*".img" ]]; then # cache may have 1 or 2
			local lcachdir=`dirname "$filename"`
			if [ `ls "$lcachdir"/"cache_*"` -eq 1 ]; then # special handling, single
				dd if=/dev/zero of="$lcachdir"/"cache.zer" bs=512 count=755600
				# magic number found by comparison with a cache.img in some ROMs
				# different from Huawei's magic number
				cat "$lcachdir"/"cache.zer" >> "$filename"
				rm "$lcachdir"/"cache.zer"
				handle_ext4 $filename
				echo "-----------------------------"
			else
				if [ $COMBINED2 -eq 0 ]; then
					echo "processing unsparse ext4 img..."
					echo "-----------------------------"
					if [ -e `dirname "$filename"`/"rawprogram_unsparse.xml" ]; then
						handle_unsparse "$filename" "cache" "rawprogram_unsparse.xml" "$VENDOR"
					elif [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
						handle_unsparse "$filename" "cache" "rawprogram0_unsparse.xml" "$VENDOR"
					elif [ -e `dirname "$filename"`/"rawprogram0.xml" ]; then # ought to use rawprogram0.xml
						handle_unsparse "$filename" "cache" "rawprogram0.xml" "$VENDOR"
					elif [ -e `dirname "$filename"`/"upgrade.xml" ]; then # rare case
						handle_unsparse "$filename" "cache" "upgrade.xml" "$VENDOR"
					fi
					echo "-----------------------------"
					COMBINED2=1
				fi
			fi
			handled=true
		elif [[ "$justname" == "system_"*".unsparse" ]]; then
			if [ $COMBINED0 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse "$filename" "system" "rawprogram0.xml" "$VENDOR""2"
				echo "-----------------------------"
				COMBINED0=1
			fi
			handled=true
		elif [[ "$justname" == "userdata_"*".unsparse" ]]; then
			if [ $COMBINED1 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse $filename "userdata" "rawprogram0.xml" "$VENDOR""2"
				echo "-----------------------------"
				COMBINED1=1
			fi
			handled=true
		elif [[ "$justname" == "cache_"*".unsparse" ]]; then # cache may have 1 or 2
			local lcachdir=`dirname "$filename"`
			if [ `ls "$lcachdir"/"cache_*"` -eq 1 ]; then # special handling, single
				dd if=/dev/zero of="$lcachdir"/"cache.zer" bs=512 count=755600
				# magic number found by comparison with a cache.img in some ROMs
				cat "$lcachdir"/"cache.zer" >> "$filename"
				rm "$lcachdir"/"cache.zer"
				handle_ext4 $filename
				echo "-----------------------------"
			else
				if [ $COMBINED2 -eq 0 ]; then
					echo "processing unsparse ext4 img..."
					echo "-----------------------------"
					handle_unsparse $filename "cache" "rawprogram0.xml" "$VENDOR""2"
					echo "-----------------------------"
					COMBINED2=1
				fi
			fi
			handled=true
		elif [[ "$justname" == "persist_"*".img" ]] || [[ "$justname" == "persist_"*".unsparse" ]]; then
			echo "processing persist unsparse ext4 img..."
			echo "-----------------------------"
			local lpersdir=`dirname "$filename"`
			dd if=/dev/zero of="$lpersdir"/"persist.zer" bs=512 count=56120
			# magic number found by comparison with a persist.img in some ROMs
			cat "$lpersdir"/"persist.zer" >> "$filename"
			rm "$lpersdir"/"persist.zer"
			handle_ext4 $filename
			# handle_unsparse $filename "persist" "rawprogram_unsparse.xml" "$VENDOR"
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == "factory_"*".img" ]]; then
			if [ $COMBINED3 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram_unsparse.xml" ]; then
					handle_unsparse "$filename" "factory" "rawprogram_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse "$filename" "factory" "rawprogram0_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0.xml" ]; then # ought to use rawprogram0.xml
					handle_unsparse "$filename" "factory" "rawprogram0.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"upgrade.xml" ]; then # rare case
					handle_unsparse "$filename" "factory" "upgrade.xml" "$VENDOR"
				fi
				echo "-----------------------------"
				COMBINED3=1
			fi
			handled=true
		elif [[ "$justname" == "fac_"*".img" ]]; then
			if [ $COMBINED3 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram_unsparse.xml" ]; then
					handle_unsparse "$filename" "fac" "rawprogram_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse "$filename" "fac" "rawprogram0_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0.xml" ]; then # ought to use rawprogram0.xml
					handle_unsparse "$filename" "fac" "rawprogram0.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"upgrade.xml" ]; then # rare case
					handle_unsparse "$filename" "fac" "upgrade.xml" "$VENDOR"
				fi
				echo "-----------------------------"
				COMBINED3=1
			fi
			handled=true
		elif [[ "$justname" == "preload_"*".img" ]]; then
			if [ $COMBINED4 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram_unsparse.xml" ]; then
					handle_unsparse "$filename" "preload" "rawprogram_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse "$filename" "preload" "rawprogram0_unsparse.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"rawprogram0.xml" ]; then # ought to use rawprogram0.xml
					handle_unsparse "$filename" "preload" "rawprogram0.xml" "$VENDOR"
				elif [ -e `dirname "$filename"`/"upgrade.xml" ]; then # rare case
					handle_unsparse "$filename" "preload" "upgrade.xml" "$VENDOR"
				fi
				echo "-----------------------------"
				COMBINED4=1
			fi
			handled=true
		elif [ "$justname" == "system.new.dat" ]; then
			# maybe needed for system.patch.dat (though this has been found empty)
			echo "processing sdat img"
			echo "-----------------------------"
			handle_sdat "$filename" "system"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "data.new.dat" ]; then
			# maybe needed for system.patch.dat (though this has been found empty)
			echo "processing sdat img"
			echo "-----------------------------"
			handle_sdat "$filename" "data"
			echo "-----------------------------"
			handled=true
		# possible that these ramdisk images outside bootimg are duplicates; just in case handle
		elif [ "$justname" == "ramdisk.img" ] || [ "$justname" == "ramdisk-recovery.img" ]; then
			echo "processing separate ramdisk img"
			echo "-----------------------------"
			mkdir ramdiskseparate
			mv ramdisk.img ramdiskseparate
			cd ramdiskseparate
			gunzip -c ramdisk.img | cpio -i
			rm ramdisk.img
			cd ..
	                find "ramdiskseparate" -print0 | while IFS= read -r -d '' file
        	        do
                                at_extract "$file"
                        	echo "$file processed: $AT_RES"
                	done
                	rm -r ramdiskseparate
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == *".qsb" ]]; then
			echo "processing qsb archive"
			echo "-----------------------------"
			handle_qsbszb "$filename" 0
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == *".szb" ]]; then
			echo "processing szb archive"
			echo "-----------------------------"
			handle_qsbszb "$filename" 1
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.img.gz" ]; then
			gunzip "system.img.gz"
			echo "processing ext4 img..."
			echo "-----------------------------"
			handle_ext4 `dirname "$filename"`/`basename "$filename" ".gz"`
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == "systemchunk"*".img" ]]; then
			# simpler than handle_chunk
			local getback=`pwd`
			cd `dirname "$filename"`
			simg2img *chunk* system.img
			rm systemchunk*.img
			cd "$getback"
			echo "processing ext4 img..."
			echo "----------------------------"
			handle_ext4 `dirname "$filename"`/"system.img"
			echo "----------------------------"
			handled=true
		elif [[ "$justname" == *".pac" ]]; then
			echo "$IMAGE" >> $PAC_LOG
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "oneplus" ]; then
		if [ "$justname" == "adspso.bin" ]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "NON-HLOS.bin" ] || [ "$justname" == "BTFM.bin" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.new.dat" ]; then
			# maybe needed for system.patch.dat (though this has been found empty)
			echo "processing sdat img"
			echo "-----------------------------"
			handle_sdat "$filename" "system"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	# elif [ "$VENDOR" == "oppo" ]; then
		# absolutely nothing special to do for oppo; all image contents available w/o mounting
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "sony" ]; then
		# FLASHTOOL: need special tool for *.sin, *.sinb, and *.ta extracted from the ftf archive
		# Debugged the CLI version; requires modification of SWT variable
		# kernel.sin, loader.sin, partition-image.sin, system.sin, userdata.sin,
		# -- cache.sin, apps_log.sin, amss_fsg.sin, amss_fs_1.sin, amss_fs_2.sin
		if [[ "$justname" == *".sin" ]] || [[ "$justname" == *".sinb" ]]; then
			echo "processing sin img"
			echo "-----------------------------"
			handle_sin "$filename"
			echo "-----------------------------"
			handled=true
		fi
		# TA files are small scripts that change information in TrimArea of phone
		# may contain information such as IMEI, serial number, DRM keys, service info, etc.
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "vivo" ]; then
		if [ "$justname" == "adspso.bin" ]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "NON-HLOS.bin" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		fi
		# Handle split up pieces of system_#.img, userdata_#.img, cache_#.img, preload_#.img
		# Prevent duplicate processing
		# further unsparse combining deferred as not dealing with vivo now
		if [[ "$justname" == "system_"*".img" ]]; then
			if [ $COMBINED0 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				handle_unsparse "$filename" "system" "rawprogram_unsparse.xml" "$VENDOR" # FIXME: not supported
				echo "-----------------------------"
				COMBINED0=1
			fi
			handled=true
#		elif [[ "$justname" == "userdata_"*".img" ]]; then
#			if [ $COMBINED1 -eq 0 ]; then
#				echo "processing unsparse ext4 img..."
#				echo "-----------------------------"
#				handle_unsparse $filename "userdata" "rawprogram_unsparse.xml" "$VENDOR"
#				echo "-----------------------------"
#				COMBINED1=1
#			fi
#			handled=true
#		elif [[ "$justname" == "cache_"*".img" ]]; then
#			if [ $COMBINED2 -eq 0 ]; then
#				echo "processing unsparse ext4 img..."
#				echo "-----------------------------"
#				handle_unsparse $filename "cache" "rawprogram_unsparse.xml" "$VENDOR"
#				echo "-----------------------------"
#				COMBINED2=1
#			fi
#			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "xiaomi" ]; then
		# split up pieces of gpt_backup#.bin, gpt_both#.bin, gpt_empty#.bin, gpt_main#.bin
		# appear to be intended to be split-up (GPT = GUID Partition Table)
		if [ "$justname" == "system.img" ] || [ "$justname" == "userdata.img" ] ||
[ "$justname" == "cust.img" ] || [ "$justname" == "cache.img" ] || [ "$justname" == "persist.img" ]; then
			# Handle sparse ext4 fs image
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "adspso.bin" ]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "NON-HLOS.bin" ] || [ "$justname" == "BTFM.bin" ] ||
[ "$justname" == "logfs_ufs_8mb.bin" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "zte" ]; then
		# FIXME (?) Ignoring single ROM with ZTE One Key Upgrade Tool exe
		if [ "$justname" == "adspso.bin" ]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "NON-HLOS.bin" ] || [ "$justname" == "BTFM.bin" ] ||
[ "$justname" == "fat.img" ] || [ "$justname" == "fat.bin" ]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.bin" ] || [ "$justname" == "userdata.bin" ] ||
[ "$justname" == "cache.bin" ] || [ "$justname" == "protect_s.bin" ] ||
[ "$justname" == "protect_f.bin" ]; then
			echo "processing unusual ext4 img by padding..."
			echo "-----------------------------"
			local lbindir=`dirname "$filename"`
			dd if=/dev/zero of="$lbindir"/"padding.zer" bs=`ls -l "$filename" | awk '{ print $5 }'` count=1
			cat "$lbindir"/"padding.zer" >> "$filename"
			rm "$lbindir"/"padding.zer"
			handle_ext4 $filename
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == "system_"*".img" ]]; then
			# zte's unsparse system image follows lenovo's technique
			if [ $COMBINED0 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse "$filename" "system" "rawprogram0.xml" "lenovo"
				else
					handle_unsparse "$filename" "system" "rawprogram_unsparse.xml" "lenovo"
				fi
				echo "-----------------------------"
				COMBINED0=1
			fi
			handled=true
		elif [[ "$justname" == "userdata_"*".unsparse" ]]; then
			if [ $COMBINED1 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse $filename "userdata" "rawprogram0.xml" "$VENDOR"
				else
					handle_unsparse $filename "userdata" "rawprogram_unsparse.xml" "$VENDOR"
				fi
				echo "-----------------------------"
				COMBINED1=1
			fi
			handled=true
		elif [[ "$justname" == "cache_"*".unsparse" ]]; then
			if [ $COMBINED2 -eq 0 ]; then
				echo "processing unsparse ext4 img..."
				echo "-----------------------------"
				if [ -e `dirname "$filename"`/"rawprogram0_unsparse.xml" ]; then
					handle_unsparse $filename "cache" "rawprogram0.xml" "$VENDOR"
				else
					handle_unsparse $filename "cache" "rawprogram_unsparse.xml" "$VENDOR"
				fi
				echo "-----------------------------"
				COMBINED2=1
			fi
			handled=true
		elif [[ "$justname" == "persist_"*".img" ]]; then
			echo "processing persist unsparse ext4 img..."
			echo "-----------------------------"
			local lpersdir=`dirname "$filename"`
			dd if=/dev/zero of="$lpersdir"/"persist.zer" bs=512 count=56120
			# magic number found by comparison with a persist.img in some ROMs
			cat "$lpersdir"/"persist.zer" >> "$filename"
			rm "$lpersdir"/"persist.zer"
			handle_ext4 $filename
			# handle_unsparse $filename "persist" "rawprogram_unsparse.xml" "$VENDOR"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.img" ] || [ "$justname" == "cache.img" ] ||
[ "$justname" == "persist.img" ] || [ "$justname" == "userdata.img" ]; then
			# need special handling, because it may sometimes be simg, othertimes ext4
			local zteformat=`file -b "$filename" | cut -d" " -f1`
			# note: should be no worries of seeing the newly created
			# ----: images from handle_unsparse; dealt with separately
			if [ -e `dirname "$filename"`/*scatter.txt ]; then
				# handle non-bin MTK
				echo "processing unusual ext4 img by padding..."
				echo "-----------------------------"
				local lbindir=`dirname "$filename"`
				dd if=/dev/zero of="$lbindir"/"padding.zer" bs=`ls -l "$filename" | awk '{ print $5 }'` count=1
				cat "$lbindir"/"padding.zer" >> "$filename"
				rm "$lbindir"/"padding.zer"
				handle_ext4 $filename
				echo "-----------------------------"
			elif [ "$zteformat" == "Android" ]; then
				# Handle sparse ext4 fs image
				echo "processing sparse ext4 img..."
				echo "-----------------------------"
				handle_simg "$filename"
				echo "-----------------------------"
			elif [ "$zteformat" == "Linux" ]; then
				echo "processing ext4 img"
				echo "-----------------------------"
				handle_ext4 "$filename"
				echo "-----------------------------"
			fi
			handled=true
		elif [ "$justname" == "system.new.dat" ]; then
			# maybe needed for system.patch.dat (though this has been found empty)
			echo "processing sdat img"
			echo "-----------------------------"
			handle_sdat "$filename" "system"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "ramdisk.img_raw" ]; then
			echo "processing separate ramdisk img"
			echo "-----------------------------"
			mkdir ramdiskseparate
			mv ramdisk.img ramdiskseparate
			cd ramdiskseparate
			gunzip -c ramdisk.img | cpio -i
			rm ramdisk.img
			cd ..
			find "ramdiskseparate" -print0 | while IFS= read -r -d '' file
			do
				at_extract "$file"
				echo "$file processed: $AT_RES"
			done
			rm -r ramdiskseparate
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == *".pac" ]]; then
			echo "$IMAGE" >> $PAC_LOG
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "lineage" ]; then
		# ignoring "a /sbin/sh script" in install/bin directory; no AT commands there
		if [ "$justname" == "system.new.dat" ]; then
			# maybe needed for system.patch.dat (though this has been found empty)
			echo "processing sdat img"
			echo "-----------------------------"
			handle_sdat "$filename" "system"
			echo "-----------------------------"
			handled=true
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "asus" ]; then
		if [ "$justname" == "asusfw.img" ] || [[ "$justname" == *"adspso.bin" ]] || [ "$justname" == "APD.img" ] ||
[ "$justname" == "ADF.img" ] || [ "$justname" == "factory.img" ]; then
			echo "processing ext4 img"
			echo "-----------------------------"
			handle_ext4 "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.img" ] || [ "$justname" == "cache.img" ] || [ "$justname" == "persist.img" ]; then
			echo "processing sparse ext4 img..."
			echo "-----------------------------"
			handle_simg "$filename"
			echo "-----------------------------"
			handled=true
		elif [ "$justname" == "system.new.dat" ]; then
			# maybe needed for system.patch.dat (though this has been found empty)
			echo "processing sdat img"
			echo "-----------------------------"
			handle_sdat "$filename" "system"
			echo "-----------------------------"
			handled=true
		elif [[ "$justname" == *"NON-HLOS"*".bin" ]]; then
			echo "processing vfat img"
			echo "-----------------------------"
			handle_vfat "$filename"
			echo "-----------------------------"
			handled=true
		fi
	fi
#-------------------------------------------------------------------------------
	if [ "$handled" = false ]; then
		# Handle it directly
		at_extract "$filename"
	fi
}

# Main script execution
# MAIN()
# Get ready
echo "Android Firmware Extraction tool:"
echo "---------------------------"
echo "Developed by researchers from the Florida Institute for Cybersecurity Research (FICS Research)"
echo "Check out our webpage: https://atcommands.org"
echo ""

# if dependencies have not been updated (deppath = "")
if [ $USINGDEPPATH -eq 1 ] && [ "$DEPPATH" == "" ]; then
	echo "ERROR: variable DEPPATH not initialized on line 62" >&2
	echo "     : if not using DEPPATH and manually updated all dependency locations on lines 65-83" >&2
	echo "     : set USINGDEPPATH=0 to disable this check." >&2
	echo "" >&2
	echo "For additional guidance and a full list of dependencies, please refer to the provided README." >&2
	exit 1
fi

echo "DEPPATH -> $DEPPATH"

# print usage if not enough arguments provided
if [ "$#" -lt 4 ]; then
	echo "ERROR: not enough arguments provided." >&2
	echo "USAGE: ./android-extract.sh <firmware image file> <vendor> <index> <keepstuff flag> <vendor mode (optional)>" >&2
	echo "          firmware image file = path to the top-level packaged archive (zip, rar, 7z, kdz, etc.)" >&2
	echo "                                (may be absolute or relative path)" >&2
	echo "          vendor = the vendor who produced the firmware image (e.g., Samsung, LG)" >&2
	echo "                   currently supported = samsung, lg, lenovo, zte, huawei, motorola, asus, aosp," >&2
	echo "                                         nextbit, alcatel, blu, vivo, xiaomi, oneplus, oppo," >&2
	echo "                                         lineage, htc, sony" >&2
	echo "          index = to extract multiple images at the same time, temporary directories will" >&2
	echo "                  need different indices. For best results, supply an integer value > 0." >&2
	echo "          keepstuff = 0/1" >&2
	echo "                      if 0, will remove any extracted files after processing them" >&2
	echo "                      if 1, extracted files (e.g., filesystem contents, apps) will be kept" >&2
	echo "                            (useful for later manual inspection)" >&2
	echo "          vendor mode = some vendors will have several different image packagings" >&2
	echo "                        if so, supplying 1 as this optional argument will invoke an adjusted extraction" >&2
	echo "                        currently applies to:" >&2
	echo "                            password protected Samsung (.zip) image files from firmwarefile.com" >&2
	echo "                        extend as needed" >&2
	echo "" >&2
	echo "For additional guidance and a full list of dependencies, please refer to the provided README." >&2
	exit 1
elif [ "$#" -lt 5 ]; then
    echo "WARN : some images may require alternative steps for extraction, in which case you should supply" >&2
	echo "       an additional argument (1). currently applies to:" >&2
	echo "                        password protected Samsung (.zip) image files from firmwarefile.com" >&2
	echo "       Continuing after defaulting to 0!" >&2
    echo ""
	VENDORMODE=0
fi

echo "ALERT: Now initiating extraction process"
#exit 1

mkdir $TOP_DIR
mkdir $MY_DIR
cp "$IMAGE" $MY_DIR
cd $MY_DIR
#if [ "$VENDOR" == "samsung2" ] || [ "$VENDOR" == "samsung3" ]; then
#	VENDOR="samsung" # possibly the most elegant solution for new batch
#fi
#if [ "$VENDOR" == "lenovo2" ] || [ "$VENDOR" == "lenovo3" ]; then
#	VENDOR="lenovo" # possibly the most elegant solution for new batch
#fi

# new extraction will have directory suffix of -expanded
VENDOR=`basename "$VENDOR" "-expanded"`
echo $VENDOR

if [ "$VENDOR" == "samsung" ]; then
	if [ ! -f $TIZ_LOG ]; then
		touch $TIZ_LOG # create tizen log if not already existing
	fi
	TIZ_LOG="`pwd`/$TIZ_LOG"
elif [ "$VENDOR" == "lenovo" ] || [ "$VENDOR" == "zte" ] || [ "$VENDOR" == "huawei" ]; then
	if [ ! -f $PAC_LOG ]; then
		touch $PAC_LOG
	fi
	PAC_LOG="`pwd`/$PAC_LOG"
elif [ "$VENDOR" == "motorola" ]; then
	if [ ! -f $SBF_LOG ]; then
		touch $SBF_LOG
	fi
	SBF_LOG="`pwd`/$SBF_LOG"
	if [ ! -f $MZF_LOG ]; then
		touch $MZF_LOG
	fi
	MZF_LOG="`pwd`/$MZF_LOG"
elif [ "$VENDOR" == "asus" ]; then
	if [ ! -f $RAW_LOG ]; then
		touch $RAW_LOG
	fi
	RAW_LOG="`pwd`/$RAW_LOG"
elif [ "$VENDOR" == "lg" ]; then
	if [ ! -f $KDZ_LOG ]; then
		touch $KDZ_LOG
	fi
	KDZ_LOG="`pwd`/$KDZ_LOG"
fi

IMAGE=`basename "$IMAGE"`
echo "ALERT: Cleaning up temporary files from prior run (if any)."
clean_up

# Assume name.suffix format
# SUB_DIR=`echo $IMAGE | cut -d"." -f1` # jochoi: (fixed) will cut off moto image name earlier than expected
if [ "$VENDOR" == "asus" ]; then
	DIR_PRE=`echo "$IMAGE" | cut -d ? -f 1`
	SUB_EXT=${DIR_PRE: -4}
	SUB_DIR=`basename "$DIR_PRE" $SUB_EXT`
else
	SUB_EXT=${IMAGE: -4} # jochoi: edit to prevent premature cutoff
	SUB_DIR=`basename "$IMAGE" $SUB_EXT` # not helpful for ASUS
fi

echo "Output will be available in: $MY_DIR/$SUB_DIR"

mkdir $SUB_DIR
mv "$IMAGE" $SUB_DIR
cd $SUB_DIR

# Try to unzip
echo "unziping the image..."
#-------------------------------------------------------------------------------
if [ "$VENDOR" == "aosp" ]; then
	at_unzip "$IMAGE"
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "samsung" ]; then
	mkdir $SUB_SUB_TMP
	DECSUFFIX=${IMAGE: -4}
	if [ "$DECSUFFIX" == ".zip" ]; then
		if [ "$VENDORMODE" == "1" ]; then # password required, and need 7z
			7z x -p"firmwarefile.com" -o"$SUB_SUB_TMP" "$IMAGE"
		else
			at_unzip "$IMAGE" $SUB_SUB_TMP
		fi
	elif [ "$DECSUFFIX" == ".rar" ]; then
		cp "$IMAGE" $SUB_SUB_TMP
		cd $SUB_SUB_TMP
		unrar e -o+ "$IMAGE" # overwriting duplicates of Odin
		# one of the rars is really weird, containing two zips with images
		# should not overwrite them? untar attempt later should handle this
		rm "$IMAGE"
		cd ..
	elif [[ "$DECSUFFIX" == *".7z" ]]; then
		7z x -o"$SUB_SUB_TMP" "$IMAGE"
	fi
	cd $SUB_SUB_TMP
	if [ `ls | wc -l` -eq 1 ] && [ -d `ls` ]; then
		EXTRA_SUB=`ls`
		cp -r "$EXTRA_SUB"/* .
		rm -r "$EXTRA_SUB"
	fi # extra check for directory to be safe; other times may be single tar
	cd ..
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "motorola" ]; then
	# sometimes contains subfolder; other times not
	# starting with motorola, letting at_unzip handle various formats (top-level)
	mkdir $SUB_SUB_TMP
	at_unzip "$IMAGE" $SUB_SUB_TMP
	cd $SUB_SUB_TMP
	if [ `ls | wc -l` -eq 1 ] && [ -d `ls` ]; then
		EXTRA_SUB=`ls`
		cp -r $EXTRA_SUB/* .
		rm -r $EXTRA_SUB
	fi
	cd ..
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "nextbit" ]; then
	# sometimes contains a folder called __MACOSX; the contents can be safely ignored
	# sometimes contains subfolder; other times not
	mkdir $SUB_SUB_TMP
	at_unzip "$IMAGE" $SUB_SUB_TMP
	cd $SUB_SUB_TMP
	rm -r __MACOSX
	if [ `ls | wc -l` -eq 1 ]; then
		EXTRA_SUB=`ls`
		cp -r $EXTRA_SUB/* .
		rm -r $EXTRA_SUB
	fi
	cd ..
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "lg" ]; then
	# need special handling of the kdz file and dz file it contains
	# note: will not always be KDZ format, e.g., G3 physicalmatch firmware
	DECSUFFIX=${IMAGE: -4}
	echo "!!!!!!!!!!!!!!!!!! MADE IT HERE KDZ"
	if [ "$DECSUFFIX" == ".kdz" ]; then
		mkdir $SUB_SUB_TMP
		# there is a chance that KDZ will fail
		$UNKDZ -f "$IMAGE" -o $SUB_SUB_TMP -x
		if [ `ls $SUB_SUB_TMP | wc -l` -ne 1 ]; then
			rm $SUB_SUB_TMP/".kdz.params"
			DZFILE=`ls $SUB_SUB_TMP/*.dz`
			# the other partitions with more than one chunk don't get combined into image
			SYSCOUNT=`$UNDZ -f "$DZFILE" -l | egrep 'system_[0-9]+' | wc -l`
			VNDCOUNT=`$UNDZ -f "$DZFILE" -l | egrep 'vendor_[0-9]+' | wc -l`
			USDCOUNT=`$UNDZ -f "$DZFILE" -l | grep userdata_ | wc -l`
			CCHCOUNT=`$UNDZ -f "$DZFILE" -l | grep cache_ | wc -l`
			CSTCOUNT=`$UNDZ -f "$DZFILE" -l | grep cust_ | wc -l`
			BOOCOUNT=`$UNDZ -f "$DZFILE" -l | grep boot | wc -l`

			SYSNUM=`$UNDZ -f "$DZFILE" -l | egrep 'system_[0-9]+' | head -1 | cut -d"/" -f 1`
			VNDNUM=`$UNDZ -f "$DZFILE" -l | egrep 'vendor_[0-9]+' | head -1 | cut -d"/" -f 1`
			USDNUM=`$UNDZ -f "$DZFILE" -l | grep userdata_ | head -1 | cut -d"/" -f 1`
			CCHNUM=`$UNDZ -f "$DZFILE" -l | grep cache_ | head -1 | cut -d"/" -f 1`
			# cust may be either singular or multiple; both cases are handled
			CSTNUM=`$UNDZ -f "$DZFILE" -l | grep cust_ | head -1 | cut -d"/" -f 1`
			BOONUM=`$UNDZ -f "$DZFILE" -l | grep boot | head -1 | cut -d"/" -f 1`
			PREDZ=`ls $SUB_SUB_TMP | wc -l`

			$UNDZ -f "$DZFILE" -o $SUB_SUB_TMP -x
			mv dzextracted/* "$SUB_SUB_TMP"
			rmdir dzextracted

			if [ `ls $SUB_SUB_TMP | wc -l` -ne $PREDZ ]; then
				if [ "$SYSCOUNT" -ne 0 ]; then
					rm $SUB_SUB_TMP/system*.bin
					$UNDZ -f "$DZFILE" -o $SUB_SUB_TMP -s $SYSNUM # system.image
					rm $SUB_SUB_TMP/"system.image.params"
				fi
				if [ "$VNDCOUNT" -ne 0 ]; then
					rm $SUB_SUB_TMP/vendor*.bin
					$UNDZ -f "$DZFILE" -o $SUB_SUB_TMP -s $VNDNUM # system.image
					rm $SUB_SUB_TMP/"system.image.params"
				fi
				if [ "$USDCOUNT" -ne 0 ]; then
					rm $SUB_SUB_TMP/userdata*.bin
					$UNDZ -f "$DZFILE" -o $SUB_SUB_TMP -s $USDNUM # userdata.image
					rm $SUB_SUB_TMP/"userdata.image.params"
				fi
				if [ "$CCHCOUNT" -ne 0 ]; then
					rm $SUB_SUB_TMP/cache*.bin
					$UNDZ -f "$DZFILE" -o $SUB_SUB_TMP -s $CCHNUM # cache.image
					rm $SUB_SUB_TMP/"cache.image.params"
				fi
				if [ "$CSTCOUNT" -ne 0 ]; then
					rm $SUB_SUB_TMP/cust*.bin
					$UNDZ -f "$DZFILE" -o $SUB_SUB_TMP -s $CSTNUM # cust.image
					rm $SUB_SUB_TMP/"cust.image.params"
				fi
				if [ "$BOOCOUNT" -ne 0 ]; then
					rm $SUB_SUB_TMP/boot*.bin
					$UNDZ -f "$DZFILE" -o $SUB_SUB_TMP -s $BOONUM # cust.image
					rm $SUB_SUB_TMP/"boot.image.params"
				fi
				rm "$DZFILE"
				rm $SUB_SUB_TMP/".dz.params"
			else
				echo "DZ extraction failed for:" >> $KDZ_LOG
				echo "$IMAGE" >> $KDZ_LOG
			fi
		else
			echo "KDZ extraction failed for:" >> $KDZ_LOG
			echo "$IMAGE" >> $KDZ_LOG
		fi
	elif [ "$DECSUFFIX" == ".zip" ]; then
		mkdir $SUB_SUB_TMP
		at_unzip "$IMAGE" $SUB_SUB_TMP
#	elif [ "$DECSUFFIX" == ".tot" ]; then
		# TODO: none of the current images we collected are of tot format
	fi
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "huawei" ] || [ "$VENDOR" == "oneplus" ] || 
[ "$VENDOR" == "oppo" ] || [ "$VENDOR" == "lineage" ]; then
	# will be unzipped without a subfolder; no special handling
	mkdir $SUB_SUB_TMP
	at_unzip "$IMAGE" $SUB_SUB_TMP
	# need to dive one level deeper for dload-style ROMs
	cd $SUB_SUB_TMP
	if [ `ls | wc -l` -eq 1 ]; then
		EXTRA_SUB=`ls`
		cp -r "$EXTRA_SUB"/* .
		rm -r "$EXTRA_SUB"
	fi
	cd ..
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "htc" ]; then
	# need separate handling for HTC to support exe file
	DECSUFFIX=${IMAGE: -4}
	if [ "$DECSUFFIX" == ".exe" ]; then
		$HTCRUUDEC -sf "$IMAGE" # this saves in the tool's directory
		DECOUTPUT=`ls | grep "OUT"`
		mv $DECOUTPUT $SUB_SUB_TMP
	else
		mkdir $SUB_SUB_TMP
		at_unzip "$IMAGE" $SUB_SUB_TMP
	fi
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "alcatel" ] || [ "$VENDOR" == "blu" ] ||
[ "$VENDOR" == "vivo" ] || [ "$VENDOR" == "xiaomi" ]; then
	# limiting this part to doing the initial unzipping
	# additional handling in the next set of if-blocks
	at_unzip "$IMAGE"
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "sony" ]; then
	DECSUFFIX=${IMAGE: -4}
	mkdir $SUB_SUB_TMP
	if [ "$DECSUFFIX" == ".ftf" ]; then
		7z x -o"$SUB_SUB_TMP" "$IMAGE" # some of the ftf won't extract using 7z
	elif [ "$DECSUFFIX" == ".rar" ]; then
		# unreliable; many of them display checksum error; unexpected end
		at_unzip "$IMAGE" $SUB_SUB_TMP
		cd $SUB_SUB_TMP
		# the rar will contain ftf
		7z x `ls *.ftf`
		rm *.ftf # nested; not needed after extraction
		cd ..
	fi
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "lenovo" ] || [ "$VENDOR" == "zte" ]; then
	if [ "$VENDORMODE" == "1" ]; then # password required, and need 7z
		7z x -p"firmwarefile.com" "$IMAGE"
	else
		at_unzip "$IMAGE"
	fi
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "asus" ]; then
	# multiple variations, some with nested zip files
	mkdir $SUB_SUB_TMP
	at_unzip "$IMAGE" $SUB_SUB_TMP
	cd $SUB_SUB_TMP
	# single weird one-level nested case (ALL_HLOS.FILES.FASTBOOT)
	# but it may also be that there is a single zip or raw enclosed
	POTASUSZIP=`ls`
	DECSUFFIX=${POTASUSZIP: -4}
	if [ `ls | wc -l` -eq 1 ]; then
		if [ "$DECSUFFIX" == ".zip" ]; then
			unzip "$POTASUSZIP"
			rm "$POTASUSZIP"
		elif [ "$DECSUFFIX" == ".raw" ]; then
			echo "$IMAGE" >> $RAW_LOG
			echo "FIXME: need support for ASUS .raw format"
			exit
		fi
	elif [ `ls | wc -l` -eq 2 ]; then
		# not sure if this will come in useful (may be handled already elsewhere)
		# catches case with empty SD folder and zip (if needed, rerun)
		POTASUSZIP=`ls *.zip`
		unzip "$POTASUSZIP"
		rm "$POTASUSZIP"
	fi
	if [ `ls | wc -l` -eq 1 ]; then
		EXTRA_SUB=`ls`
		cp -r $EXTRA_SUB/* .
		rm -r $EXTRA_SUB
		# may be two-level nested (ASUS/Update); if so, contains zip
		if [ `ls | wc -l` -eq 1 ]; then
			if [ -d `ls` ]; then
				EXTRA_SUB=`ls`
				cp -r $EXTRA_SUB/* .
				rm -r $EXTRA_SUB
			fi # catching rar case; cp not needed for rar format
			NSTASUSZIP=`ls`
			unzip "$NSTASUSZIP"
			rm "$NSTASUSZIP"
		fi
	fi
	cd ..
#-------------------------------------------------------------------------------
else
	# Treat it as AOSP
	VENDOR="aosp"
	at_unzip "$IMAGE"
#-------------------------------------------------------------------------------
fi
#-------------------------------------------------------------------------------
if [ "$AT_RES" == "bad" ]; then
	echo "FIXME: need support for decompressing this image"
	exit
fi

# Remove the raw image since we have decompressed it already
rm -rf $IMAGE

# NOTE: assume there is only 1 dir after unziping
SUB_SUB_DIR=`ls`
if [ ! -f $MY_TMP ]; then
	touch $MY_TMP
	MY_TMP="`pwd`/$MY_TMP"
fi
if [ ! -f $MY_USB ]; then
	touch $MY_USB
	MY_USB="`pwd`/$MY_USB"
fi
if [ ! -f $MY_PROP ]; then
	touch $MY_PROP
	MY_PROP="`pwd`/$MY_PROP"
fi
MY_OUT="`pwd`/$MY_OUT"
if [ -d "$SUB_SUB_DIR" ]; then
	# NOTE: the processing happens under sub sub dir
	cd "$SUB_SUB_DIR"
else
	echo "ERROR: more than 1 sub dir found... $SUB_SUB_DIR"
	exit
fi

#-------------------------------------------------------------------------------
if [ "$VENDOR" == "aosp" ]; then
	echo "handling AOSP images..."
	# Recursively extract all archives in all subdirectories
	echo "Recursively extracting all archives..."
	recursive_unzip_all

	# Assume all the files will be flat in the same dir
	# without subdirs
	echo "extracting at commands..."
	echo "-------------------------"
	find . -type f -print0 | while IFS= read -r -d '' b; do
		process_file "$b"
		echo "$b processed: $AT_RES"
	done
	echo "-------------------------"
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "samsung" ]; then
	echo "handling Samsung images..."
	# After the unzip, we have 5 tar files, each of which needs to be extracted
	# in its own directory since they contain files with the same name...
	echo "unarchiving each zip inside..."
	# jochoi note: inconsistent handling vs. e.g., htc (all unzipped then all processed)
	# cont.: here, process as you unzip, deleting the whole unzipped contents
	# jochoi note: need to verify that the OS is not Tizen
	# jochoi note: sometimes there will be nested, other times not
	for f in *; do
		echo "attempting to untar $f" # what if it's not a tar? TODO
		mkdir $TAR_TMP
		at_unzip "$f" $TAR_TMP
		if [ "$AT_RES" == "good" ]; then
			echo "unzipped sub image $f"
			# Process files from the remote tar dir
			echo "extracting at commands..."
			echo "-------------------------"
			find $TAR_TMP -print0 | while IFS= read -r -d '' b
			do
				process_file "$b"
				echo "$b processed: $AT_RES"
			done
			[ $? == 55 ] && exit 55
			echo "-------------------------"
		else
			find "$f" -print0 | while IFS= read -r -d '' c
			do
				process_file "$c"
				echo "$c processed: $AT_RES"
			done
			[ $? == 55 ] && exit 55
			echo "-------------------------"
		fi
		if [ "$KEEPSTUFF" == "1" ]; then
			cp -r $TAR_TMP "$MY_FULL_DIR"/"$SUB_DIR"/$(basename "$f")
		fi
		rm -rf $TAR_TMP
	done
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "motorola" ]; then
	echo "handling Motorola images..."
	# files may NOT be flat in the same directory without subdirectories
	echo "assuming no nested zips to handle... (or handled previously)"
	echo "extracting at commands..."
	echo "-------------------------"
        find . -print0 | while IFS= read -r -d '' file
        do
                process_file "$file"
                echo "$file processed: $AT_RES"
        done
	echo "-------------------------"
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "nextbit" ]; then
	echo "handling NextBit images..."
	# Recursively extract all archives in all subdirectories
	echo "Recursively extracting all archives..."
	recursive_unzip_all

	echo "extracting at commands..."
	echo "-------------------------"
	find . -type f -print0 | while IFS= read -r -d '' b; do
		process_file "$b"
		echo "$b processed: $AT_RES"
	done
	echo "-------------------------"
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "lg" ]; then
	echo "handling LG images..."
	DECSUFFIX=${IMAGE: -4}
	if [ "$DECSUFFIX" == ".kdz" ]; then
		# Recursively extract all archives in all subdirectories
		echo "Recursively extracting all archives..."
		recursive_unzip_all

		# for now, there does not seem to be any additional archives within the top-level archive
		echo "assuming no nested zips to handle... (or handled previously)"
		echo "extracting at commands..."
		echo "-------------------------"
		find . -type f -print0 | while IFS= read -r -d '' b; do
			process_file "$b"
			echo "$b processed: $AT_RES"
		done
		echo "-------------------------"
	elif [ "$DECSUFFIX" == ".zip" ]; then
		# Recursively extract all archives in all subdirectories
		echo "Recursively extracting all archives..."
		recursive_unzip_all

		# files will NOT be flat in the same directory without subdirectories
		echo "extracting at commands..."
		echo "-------------------------"
	        find . -print0 | while IFS= read -r -d '' file
	        do
	                process_file "$file"
	                echo "$file processed: $AT_RES"
	        done
		echo "-------------------------"
	fi
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "htc" ]; then
	echo "handling HTC images..."
	# Recursively extract all archives in all subdirectories
	echo "Recursively extracting all archives..."
	recursive_unzip_all

	# files will NOT be flat in the same directory without subdirectories
	echo "extracting at commands..."
	echo "-------------------------"
        find . -print0 | while IFS= read -r -d '' file
        do
                process_file "$file"
                echo "$file processed: $AT_RES"
        done
	echo "-------------------------"
#-------------------------------------------------------------------------------
elif [ "$VENDOR" == "alcatel" ] || [ "$VENDOR" == "blu" ] || [ "$VENDOR" == "oneplus" ] ||
[ "$VENDOR" == "oppo" ] || [ "$VENDOR" == "xiaomi" ] || [ "$VENDOR" == "huawei" ] || [ "$VENDOR" == "lenovo" ] ||
[ "$VENDOR" == "sony" ] || [ "$VENDOR" == "vivo" ] || [ "$VENDOR" == "zte" ] || [ "$VENDOR" == "lineage" ] ||
[ "$VENDOR" == "asus" ]; then
#-------------------------------------------------------------------------------
	if [ "$VENDOR" == "alcatel" ]; then
		echo "handling Alcatel images..."
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "blu" ]; then
		echo "handling BLU images..."
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "oneplus" ]; then
		echo "handling OnePlus images..."
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "oppo" ]; then
		echo "handling Oppo images..."
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "xiaomi" ]; then
		echo "handling Xiaomi images..."
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "huawei" ]; then
		echo "handling Huawei images..."
		# UPDATE.APP in dload subdirectory; for now, assuming same filename across images
		# ignoring cust_dload directory for now (accompanied by dload)
		if [ -d "dload" ]; then
			cd "dload" # only about half of the downloaded images follow this format
			$UPDATA `pwd`"/UPDATE.APP"
			rm "UPDATE.APP"
			cd ..
		fi
		# may not be in dload subdir
		if [ -e "UPDATE.APP" ]; then
			$UPDATA `pwd`"/UPDATE.APP"
			rm "UPDATE.APP"
		fi
		if [ -e "update.zip" ]; then
			unzip "update.zip" # a couple firmwares have update.zip
			rm "update.zip"
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "lenovo" ]; then
		echo "handling Lenovo images..."
		if [ -e "update.zip" ]; then
			unzip "update.zip" # a couple firmwares have update.zip
			rm "update.zip"
		fi
		# may be stashed inside Firmware subfolder
		if [ -e "Firmware" ] && [ -e "Firmware/update.zip" ]; then
			cd Firmware
			unzip "update.zip"
			rm "update.zip"
			cd ..
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "sony" ]; then
		echo "handling Sony images..."
		if [ -e "Firmware" ] && [ -d "Firmware" ]; then
			cd "Firmware" # FIXME: which images does this occur in?
			unzip *.ftf # nested zip should be handled here; otherwise will ignore extracted contents
		# may consider modifying the at_unzip function to go through extracted contents
		# currently only handles contents as text or binary
			rm *.ftf # not needed after unzipping
			cd ..
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "vivo" ]; then
		echo "handling Vivo images..."
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "zte" ]; then
		echo "handling ZTE images..."
		# may need to make this more general, depending on if the zip file has another name
		if [ -e "update.zip" ]; then # not always
			at_unzip "update.zip"
			rm "update.zip"
		fi
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "lineage" ]; then
		echo "handling LineageOS images..."
#-------------------------------------------------------------------------------
	elif [ "$VENDOR" == "asus" ]; then # files not necessarily flat in same directory
		echo "handling Asus images..."
	fi
#-------------------------------------------------------------------------------

	# leave special handling for processfile
	# huawei: ~.APP file (in Firmware directory)
	# lenovo: system.img, userdata.img, etc. are in pieces
	# sony:   extract .ftf file via unzip (in Firmware directory)
	# vivo:   extract vivo_tools.zip (in Firmware directory)

	# files will NOT be flat in the same directory without subdirectories
	echo "extracting at commands..."
	echo "-------------------------"
        find . -print0 | while IFS= read -r -d '' file
        do
                process_file "$file"
                echo "$file processed: $AT_RES"
        done
	echo "-------------------------"
#-------------------------------------------------------------------------------
fi
#-------------------------------------------------------------------------------

# Summary
echo "summarizing..."
cd ..
if [ "$KEEPSTUFF" == "0" ]; then
	rm -rf $SUB_SUB_DIR
fi # otherwise keep for later analysis
# cat $MY_TMP | sort | uniq > $MY_OUT # need to ignore the column containing file name
# putting filename inline with each AT command will interfere with sort (unless we sort by column)
cat $MY_TMP | sort -k2 | uniq -f1 > $MY_OUT
# if we want to get rid of filename from MY_OUT, simply use the following line instead
# cat $MY_TMP | sort -k2 | uniq -f1 | cut -f2- > $MY_OUT
