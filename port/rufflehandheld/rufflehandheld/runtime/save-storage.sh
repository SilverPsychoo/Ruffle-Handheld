#!/bin/bash
# Keep Flash SharedObject data outside the temporary native content tree.

rh_prepare_save_storage() {
    local content_dir="$1" swf="$2" rom_root="$3"
    local base safe checksum saves staged item name
    base="$(basename -- "$swf")"
    safe="$(printf '%s' "$base" | sed 's/[^A-Za-z0-9._-]/_/g')"
    [ -n "$safe" ] || safe="game.swf"
    checksum="$(printf '%s' "$base" | cksum | awk '{print $1}')"
    saves="$rom_root/flash_data/storage/$safe-$checksum"
    staged="$content_dir/storage"

    mkdir -p "$saves" || { echo "ERROR: cannot create persistent Flash saves: $saves"; return 1; }
    [ -w "$saves" ] || { echo "ERROR: Flash saves are not writable: $saves"; return 1; }

    # A multifile sidecar may already contain a storage folder. Bring over
    # entries that have no existing save, without replacing saved progress.
    if [ -d "$staged" ] && [ ! -L "$staged" ]; then
        for item in "$staged"/* "$staged"/.[!.]* "$staged"/..?*; do
            [ -e "$item" ] || [ -L "$item" ] || continue
            name="$(basename -- "$item")"
            [ -e "$saves/$name" ] || [ -L "$saves/$name" ] ||
                cp -a "$item" "$saves/$name" || return 1
        done
        rm -rf -- "$staged" || return 1
    elif [ -e "$staged" ] || [ -L "$staged" ]; then
        echo "ERROR: unexpected Flash storage path: $staged"
        return 1
    fi
    ln -s "$saves" "$staged" || return 1
    echo "Flash saves: $saves"
}
