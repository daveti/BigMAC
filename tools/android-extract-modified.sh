# Global Variables:
# Input/Output Variables
IMAGE="$1"                    # Input factory image
VENDOR="$2"                   # Vendor identifier
KEEPSTUFF="$4"               # Flag to preserve extracted files
VENDORMODE="$5"              # Vendor-specific mode (default 0)
BOOT_SRC="$6"                # Source path for boot image
BOOT_DEST="$7"               # Destination path for boot image

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

# print usage if not enough arguments provided
if [ "$#" -lt 6 ]; then
	echo "ERROR: not enough arguments provided." >&2
	echo "USAGE: ./android-extract.sh <firmware image file> <vendor> <index> <keepstuff flag> <vendor mode> <boot src> <boot dest>" >&2
	echo "          firmware image file = path to the top-level packaged archive (zip, rar, 7z, kdz, etc.)" >&2
	echo "          vendor = the vendor who produced the firmware image (e.g., Samsung, LG)" >&2
	echo "          index = to extract multiple images at the same time" >&2
	echo "          keepstuff = 0/1 (remove/keep extracted files)" >&2
	echo "          vendor mode = some vendors will have several different image packagings" >&2
	echo "          boot src = source path for boot image" >&2
	echo "          boot dest = destination path for boot image" >&2
	exit 1
fi

# Create boot.img directory in destination
if [ ! -z "$BOOT_SRC" ] && [ ! -z "$BOOT_DEST" ]; then
    BOOT_DEST_DIR="$BOOT_DEST/boot.img"
    echo "Creating boot image directory at: $BOOT_DEST_DIR"
    mkdir -p "$BOOT_DEST_DIR"
    
    # Copy boot image if it exists
    if [ -f "$BOOT_SRC" ]; then
        echo "Copying boot image from $BOOT_SRC to $BOOT_DEST_DIR"
        cp "$BOOT_SRC" "$BOOT_DEST_DIR/"
    else
        echo "Error: Boot image not found at $BOOT_SRC"
        exit 1
    fi
else
    echo "Warning: Boot source or destination path not provided"
fi

	# Test with different values
	CPDIR="/source/path"  # Non-empty case
	DIRNAME="/dest/path"   # Non-empty case
	
	# Debug output
	echo "Testing with:"
	echo "CPDIR='$CPDIR'"
	echo "DIRNAME='$DIRNAME'"

	# Check if CPDIR and DIRNAME are not empty
	if [ ! -z "$CPDIR" ] && [ ! -z "$DIRNAME" ]; then
		echo "Both variables have values:"
		echo "CPDIR: $CPDIR"
		echo "DIRNAME: $DIRNAME"
	else
		echo "Error: CPDIR or DIRNAME is empty"
		return 1
	fi

	# Find the boot.oat for RE odex
	BOOT_OAT=""
	BOOT_OAT_64=""
	while read file
	do
		# Debug
		#echo "DEBUG: boot.oat - $file"
		arch=`file -b "$file" | cut -d" " -f2 | cut -d"-" -f1` > /dev/null 2>&1
		if [ "$arch" == "64" ]; then
			BOOT_OAT_64="$file"
		else
			BOOT_OAT="$file"
		fi
	done < <(sudo find $mnt_name -name boot.oat -print 2>/dev/null)

	handle_simg()
	{
		local CPDIR="$1"    # First parameter
		local DIRNAME="$2"   # Second parameter
		local img="$3"      # Third parameter
		echo "Image name: $img"
		local nam=`basename -s .img "$img"`
		local ext="$nam.img"
		local arch=""
		local mnt_name="${MNT_TMP}_${ext}"

		# Check if CPDIR and DIRNAME are not empty
		if [ ! -z "$CPDIR" ] && [ ! -z "$DIRNAME" ]; then
			echo "Using paths:"
			echo "CPDIR: $CPDIR"
			echo "DIRNAME: $DIRNAME"
		else
			echo "Error: CPDIR or DIRNAME is empty"
			return 1
		fi

		mkdir $DIR_TMP
		mkdir $mnt_name
		cp "$img" $DIR_TMP/"$ext"

		# NOTE: needs sudo or root permission
		echo "Mounting system.img"
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