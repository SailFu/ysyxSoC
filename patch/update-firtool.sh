#!/usr/bin/env bash
set -eu

# Notes:
# - CIRCT releases currently provide linux-x64 and macos-x64 prebuilt tarballs.
# - On Linux aarch64/arm64, we build firtool from source at the matching tag.

# Usage:
#   replace_firtool <firtool_url> <firtool_sha256_url> <firtool_update_version>
replace_firtool() {
    local firtool_url=$1
    local firtool_sha256_url=$2
    local firtool_update_version=$3
    local firtool_patch_dir=$4

    # Check if firtool directory exists
    if [ -d $firtool_patch_dir ]; then
        echo "Found existing firtool directory in $firtool_patch_dir"
        echo "If you want to update firtool, please remove the existing firtool directory"
        exit 0
    fi

    # Create temporary directory
    local firtool_temp=$(mktemp -d)
    echo "Downloading firtool version $firtool_update_version from $firtool_url..."
    curl -L -o $firtool_temp/firtool.tar.gz $firtool_url
    echo "Downloading SHA256 checksum from $firtool_sha256_url..."
    # Check SHA256 checksum
    check_sha256=$(curl -L $firtool_sha256_url)
    echo "Checking SHA256 checksum..."
    echo "$check_sha256 $firtool_temp/firtool.tar.gz" | sha256sum -c -

    if [ $? -ne 0 ]; then
        echo "SHA256 checksum failed"
        exit 1
    fi

    # Extract firtool to patch directory
    mkdir -p $firtool_patch_dir
    tar -xzf $firtool_temp/firtool.tar.gz -C $firtool_patch_dir
    chmod +x $firtool_patch_dir/firtool-$firtool_update_version/bin/firtool
}

build_firtool_from_source() {
    local firtool_update_version=$1
    local firtool_patch_dir=$2

    if [ -d "$firtool_patch_dir" ]; then
        echo "Found existing firtool directory in $firtool_patch_dir"
        echo "If you want to update firtool, please remove the existing firtool directory"
        exit 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "git not found, cannot build firtool from source"
        exit 1
    fi
    if ! command -v cmake >/dev/null 2>&1; then
        echo "cmake not found, cannot build firtool from source"
        exit 1
    fi
    if ! command -v ninja >/dev/null 2>&1; then
        echo "ninja not found, cannot build firtool from source"
        exit 1
    fi

    local firtool_temp
    firtool_temp=$(mktemp -d)
    echo "Building firtool version $firtool_update_version from source (this may take a while)..."
    echo "Cloning llvm/circt tag firtool-$firtool_update_version ..."
    git clone --depth 1 --branch "firtool-$firtool_update_version" https://github.com/llvm/circt.git "$firtool_temp/circt-src"
    # The LLVM sources are provided as a git submodule in the CIRCT repo.
    # We need it to build MLIR/CIRCT tools like firtool.
    echo "Initializing LLVM submodule (this may take a while)..."
    git -C "$firtool_temp/circt-src" submodule update --init --recursive --depth 1

    mkdir -p "$firtool_temp/circt-src/build"
    cmake -G Ninja -S "$firtool_temp/circt-src/llvm/llvm" -B "$firtool_temp/circt-src/build" \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_TARGETS_TO_BUILD=host \
      -DLLVM_ENABLE_PROJECTS=mlir \
      -DLLVM_EXTERNAL_PROJECTS=circt \
      -DLLVM_EXTERNAL_CIRCT_SOURCE_DIR="$firtool_temp/circt-src"

    ninja -C "$firtool_temp/circt-src/build" firtool om-linker

    mkdir -p "$firtool_patch_dir/firtool-$firtool_update_version/bin"
    cp -f "$firtool_temp/circt-src/build/bin/firtool" "$firtool_patch_dir/firtool-$firtool_update_version/bin/firtool"
    cp -f "$firtool_temp/circt-src/build/bin/om-linker" "$firtool_patch_dir/firtool-$firtool_update_version/bin/om-linker"
    chmod +x "$firtool_patch_dir/firtool-$firtool_update_version/bin/firtool" \
             "$firtool_patch_dir/firtool-$firtool_update_version/bin/om-linker"
    echo "firtool built and installed to $firtool_patch_dir/firtool-$firtool_update_version/bin"
}

update_firtool() {
    local firtool_update_version=$1
    local firtool_patch_dir=$2

    # If directory exists, ensure firtool is runnable; otherwise fail fast with a clear message.
    if [ -d "$firtool_patch_dir" ]; then
        echo "Found existing firtool directory in $firtool_patch_dir"
        local maybe_firtool="$firtool_patch_dir/firtool-$firtool_update_version/bin/firtool"
        if [ -x "$maybe_firtool" ] && "$maybe_firtool" --version >/dev/null 2>&1; then
            exit 0
        fi
        echo "Existing firtool is not runnable on this machine (likely wrong architecture)."
        echo "Please remove it and re-run make:"
        echo "  rm -rf \"$firtool_patch_dir\""
        exit 1
    fi

    case "$(uname -s)" in
        Linux*)
            case "$(uname -m)" in
                x86_64|amd64) firtool_arch="linux-x64";;
                aarch64|arm64) firtool_arch="linux-aarch64";;
                *) echo "Unsupported Linux architecture: $(uname -m)"; exit 1;;
            esac
            ;;
        Darwin*)
            if [ "$(uname -m)" == "arm64" ]; then
                # CIRCT does not release darwin arm64 binary yet
                # so we need to build it from source
                echo "Unsupported darwin architecture"
                echo "Please build firtool from source, see: https://github.com/llvm/circt?tab=readme-ov-file#setting-this-up"
                echo "Then copy the built firtool binary to $firtool_patch_dir/firtool-$firtool_update_version/bin/firtool"
                exit 1
            else
                firtool_arch="macos-x64"
            fi
            ;;
        *) echo "Unsupported OS"; exit 1;;
    esac

    local firtool_url="https://github.com/llvm/circt/releases/download/firtool-${firtool_update_version}/firrtl-bin-${firtool_arch}.tar.gz"
    local firtool_sha256="https://github.com/llvm/circt/releases/download/firtool-${firtool_update_version}/firrtl-bin-${firtool_arch}.tar.gz.sha256"

    case "$(uname -s)" in
        Linux*)
            if [ "$firtool_arch" = "linux-aarch64" ]; then
                # As of now, CIRCT releases often do not provide linux-aarch64 prebuilt tarballs.
                # If the URL exists in the future, use it; otherwise build from source.
                if command -v curl >/dev/null 2>&1 && curl -fsI "$firtool_url" >/dev/null 2>&1; then
                    replace_firtool $firtool_url $firtool_sha256 $firtool_update_version $firtool_patch_dir
                else
                    build_firtool_from_source $firtool_update_version $firtool_patch_dir
                fi
            else
                replace_firtool $firtool_url $firtool_sha256 $firtool_update_version $firtool_patch_dir
            fi
            ;;
        Darwin*) replace_firtool $firtool_url $firtool_sha256 $firtool_update_version $firtool_patch_dir;;
        *) echo "Unsupported OS"; exit 1;;
    esac
}

# Call update_firtool with version and patch directory
# e.g. update_firtool 1.105.0 `pwd`/patch/firtool
update_firtool $1 $2