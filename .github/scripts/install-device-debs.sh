#!/usr/bin/env bash
# Install the marble device DEB set with the target distribution's own APT
# resolver and verify the result. This script is shared by the Debian and
# Ubuntu rootfs workflows and by the cross-distribution install test.
#
# Rules it enforces:
#   * every downloaded DEB is a valid arm64/all package with a readable payload;
#   * build/debug/documentation packages are excluded by an explicit rule;
#   * all local packages are resolved *together* by APT, never dpkg -i;
#   * an installed package may only disappear when a selected package
#     declares both Provides and Conflicts/Replaces for that exact name
#     (modemmanager-marble -> modemmanager, iio-sensor-proxy-ssc ->
#     iio-sensor-proxy); every other removal is a build failure;
#   * every expected package is checked for exact version and "ii " state;
#   * dpkg --audit output is inspected (its exit status alone is not enough).
#
# Environment:
#   ROOTFS_MOUNT  target root (chroot mode). Unset = operate on the current
#                 root, used by the container install tests.
#   DEB_DIR       directory holding the downloaded DEBs (default: debs).

set -euo pipefail

ROOTFS_MOUNT="${ROOTFS_MOUNT:-}"
DEB_DIR="${DEB_DIR:-debs}"
STAGE_DIR=/tmp/device-debs

# Runtime floor required by modemmanager-marble (libmbim >= 1.32) and by
# marble-device-support (libqmi >= 1.39.1).
LIBMBIM_MIN_VERSION=1.32.0
LIBQMI_MIN_VERSION=1.39.1

# These packages must be present in every release. libmbim is handled
# separately because a newer target archive may replace the local copy.
REQUIRED_PACKAGES=(
    linux-xiaomi-marble
    firmware-xiaomi-marble
    marble-device-support
    modemmanager-marble
    libmm-glib0
    libqmi-glib5
    libqmi-proxy
    libssc
    iio-sensor-proxy-ssc
    libva-v4l2
)

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '  %s\n' "$*"
}

if [ "$(id -u)" -eq 0 ]; then
    as_root() { "$@"; }
else
    command -v sudo >/dev/null 2>&1 || fail "sudo is required to write into $ROOTFS_MOUNT"
    as_root() { sudo "$@"; }
fi

if [ -n "$ROOTFS_MOUNT" ]; then
    [ -d "$ROOTFS_MOUNT" ] || fail "ROOTFS_MOUNT is not a directory: $ROOTFS_MOUNT"
    run_target() { as_root chroot "$ROOTFS_MOUNT" "$@"; }
    stage_host="$ROOTFS_MOUNT$STAGE_DIR"
else
    [ "$(id -u)" -eq 0 ] || fail "run as root when ROOTFS_MOUNT is unset"
    run_target() { "$@"; }
    stage_host="$STAGE_DIR"
fi

command -v dpkg-deb >/dev/null 2>&1 || fail "dpkg-deb is required on the build host"

shopt -s nullglob
mapfile -t debs < <(find "$DEB_DIR" -maxdepth 3 -type f -name '*.deb' -print | sort)
((${#debs[@]} > 0)) || fail "no device DEBs found in $DEB_DIR"

declare -A pkg_version=()
declare -A pkg_deb=()

echo "--- validating downloaded DEBs ---"
for deb in "${debs[@]}"; do
    [ -s "$deb" ] || fail "empty DEB: $deb"

    dpkg-deb --info "$deb" >/dev/null 2>&1 || fail "not a readable DEB: $deb"
    dpkg-deb --fsys-tarfile "$deb" | tar -tf - >/dev/null 2>&1 \
        || fail "corrupt DEB payload: $deb"

    name=$(dpkg-deb -f "$deb" Package) || fail "missing Package in $deb"
    version=$(dpkg-deb -f "$deb" Version) || fail "missing Version in $deb"
    arch=$(dpkg-deb -f "$deb" Architecture) || fail "missing Architecture in $deb"

    [ -n "$name" ] || fail "empty Package in $deb"
    [ -n "$version" ] || fail "empty Version in $deb"
    case "$arch" in
        arm64|all) ;;
        *) fail "unsupported architecture '$arch' in $deb" ;;
    esac

    [ -z "${pkg_version[$name]+x}" ] || fail "duplicate package: $name"
    pkg_version["$name"]="$version"
    pkg_deb["$name"]="$deb"

    info "$name $version ($arch)"
done

for required in "${REQUIRED_PACKAGES[@]}"; do
    [ -n "${pkg_version[$required]+x}" ] \
        || fail "release is missing required package: $required"
done

# Explicit classification: -dev/-doc/-dbgsym packages are build or debug
# artefacts. Everything else in the release is a runtime package and is
# installed; this keeps libqmi-utils, libqmi-proxy, gir data and libssc (which
# combines runtime and headers in one package) in the rootfs.
install_names=()
excluded=()
mapfile -t sorted_names < <(printf '%s\n' "${!pkg_version[@]}" | sort)
for name in "${sorted_names[@]}"; do
    case "$name" in
        *-dbgsym|*-dbg|*-dev|*-doc)
            excluded+=("$name (build/debug/documentation package)")
            ;;
        *)
            install_names+=("$name")
            ;;
    esac
done

echo "--- refreshing target APT metadata ---"
run_target apt-get update

target_name=$(run_target sh -c '. /etc/os-release 2>/dev/null; printf "%s" "${PRETTY_NAME:-unknown}"' 2>/dev/null || true)
[ -n "$target_name" ] || target_name=unknown

# libmbim 1.32 is a compatibility backport for Ubuntu 24.04 (1.31.2). Debian
# trixie already ships 1.32.0 and forky/sid ship 1.34.0, so the local copy must
# not downgrade those archives. Conversely, when the target archive is older
# than 1.32, the release must carry the backport or noble cannot satisfy
# modemmanager-marble.
skip_local_libmbim=0
libmbim_candidate="(none)"
if run_target apt-cache show libmbim-glib4 >/dev/null 2>&1; then
    libmbim_candidate=$(run_target apt-cache policy libmbim-glib4 \
        | awk '/Candidate:/ { print $2; exit }')
    if [ -n "$libmbim_candidate" ] && [ "$libmbim_candidate" != "(none)" ] \
        && dpkg --compare-versions "$libmbim_candidate" ge "$LIBMBIM_MIN_VERSION"; then
        skip_local_libmbim=1
    fi
fi

if [ "$skip_local_libmbim" -eq 0 ]; then
    for required in libmbim-glib4 libmbim-proxy; do
        [ -n "${pkg_version[$required]+x}" ] \
            || fail "$target_name has libmbim candidate $libmbim_candidate (< $LIBMBIM_MIN_VERSION), but the release does not contain $required; modemmanager-marble cannot be satisfied"
    done
fi

selected=()
if [ "$skip_local_libmbim" -eq 1 ]; then
    for name in "${install_names[@]}"; do
        case "$name" in
            libmbim*)
                excluded+=("$name (target archive already provides libmbim >= $LIBMBIM_MIN_VERSION)")
                ;;
            *)
                selected+=("$name")
                ;;
        esac
    done
else
    selected=("${install_names[@]}")
fi

((${#selected[@]} > 0)) || fail "no runtime packages left to install"

# Refuse an implicit downgrade instead of letting apt fail late or, worse,
# silently keeping the archive version and producing a mixed ABI set.
echo "--- checking target archive versions ---"
for name in "${selected[@]}"; do
    if run_target apt-cache show "$name" >/dev/null 2>&1; then
        candidate=$(run_target apt-cache policy "$name" \
            | awk '/Candidate:/ { print $2; exit }')
        if [ -n "$candidate" ] && [ "$candidate" != "(none)" ] \
            && dpkg --compare-versions "$candidate" gt "${pkg_version[$name]}"; then
            fail "target archive has $name $candidate, newer than release ${pkg_version[$name]}; refusing a downgrade"
        fi
    fi
done

echo "--- install set ---"
for name in "${selected[@]}"; do
    info "$name ${pkg_version[$name]}"
done
if ((${#excluded[@]} > 0)); then
    echo "--- excluded by classification/compatibility rule ---"
    for reason in "${excluded[@]}"; do
        info "$reason"
    done
fi

# Only allow removal of an installed archive package when a selected local
# package declares both Provides and Conflicts/Replaces for that exact name.
# Different package names are never compared by version; this is a name-based
# replacement, not a downgrade.
field_names() {
    local field="$1"
    [ -n "$field" ] || return 0
    printf '%s\n' "$field" \
        | tr ',' '\n' \
        | sed -E 's/\([^)]*\)//g; s/[[:space:]]+//g' \
        | tr '|' '\n' \
        | sed -E 's/:any$//' \
        | awk 'NF'
}

declare -A allowed_removal=()
for name in "${selected[@]}"; do
    deb="${pkg_deb[$name]}"
    provides=$(field_names "$(dpkg-deb -f "$deb" Provides || true)")
    conflicts=$(field_names "$(dpkg-deb -f "$deb" Conflicts || true)")
    replaces=$(field_names "$(dpkg-deb -f "$deb" Replaces || true)")
    replacement_names=$(printf '%s\n%s\n' "$conflicts" "$replaces" | awk 'NF' | sort -u)
    for provided in $provides; do
        if printf '%s\n' "$replacement_names" | grep -qxF "$provided"; then
            allowed_removal["$provided"]="$name"
        fi
    done
done

if ((${#allowed_removal[@]} > 0)); then
    echo "--- declared package replacements ---"
    mapfile -t replaced_names < <(printf '%s\n' "${!allowed_removal[@]}" | sort)
    for replaced in "${replaced_names[@]}"; do
        info "$replaced -> ${allowed_removal[$replaced]}"
    done
fi

before_file=$(mktemp)
after_file=$(mktemp)
cleanup() {
    rm -f "$before_file" "$after_file"
}
trap cleanup EXIT

run_target dpkg-query -W -f='${Package} ${db:Status-Abbrev}\n' \
    | awk '$2 == "ii" { print $1 }' | sort > "$before_file"

echo "--- staging DEBs inside the target root ---"
as_root rm -rf "$stage_host"
as_root install -d "$stage_host"
for name in "${selected[@]}"; do
    as_root cp -- "${pkg_deb[$name]}" "$stage_host/"
done

echo "--- installing with the target distribution's APT resolver ---"
if [ -n "$ROOTFS_MOUNT" ]; then
    as_root chroot "$ROOTFS_MOUNT" /bin/bash -euo pipefail -c '
        shopt -s nullglob
        debs=(/tmp/device-debs/*.deb)
        ((${#debs[@]} > 0)) || { echo "ERROR: no staged DEBs" >&2; exit 1; }
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y "${debs[@]}"
    '
else
    bash -euo pipefail -c '
        shopt -s nullglob
        debs=(/tmp/device-debs/*.deb)
        ((${#debs[@]} > 0)) || { echo "ERROR: no staged DEBs" >&2; exit 1; }
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y "${debs[@]}"
    '
fi

echo "--- verifying installed packages ---"
for name in "${selected[@]}"; do
    actual=$(run_target dpkg-query -W -f='${Version}' "$name" 2>/dev/null) \
        || fail "$name is not installed"
    status=$(run_target dpkg-query -W -f='${db:Status-Abbrev}' "$name" 2>/dev/null) \
        || fail "$name has no dpkg state"
    [ "$actual" = "${pkg_version[$name]}" ] \
        || fail "version mismatch for $name: expected ${pkg_version[$name]}, got $actual"
    [ "$status" = "ii " ] \
        || fail "$name is not fully installed (state: '$status')"
    info "$name $actual ii"
done

for required in "${REQUIRED_PACKAGES[@]}"; do
    status=$(run_target dpkg-query -W -f='${db:Status-Abbrev}' "$required" 2>/dev/null) \
        || fail "required package $required is not installed"
    [ "$status" = "ii " ] \
        || fail "required package $required is not fully installed (state: '$status')"
done

libmbim_version=$(run_target dpkg-query -W -f='${Version}' libmbim-glib4) \
    || fail "libmbim-glib4 is not installed"
dpkg --compare-versions "$libmbim_version" ge "$LIBMBIM_MIN_VERSION" \
    || fail "libmbim-glib4 $libmbim_version is older than $LIBMBIM_MIN_VERSION"

libmbim_proxy_version=$(run_target dpkg-query -W -f='${Version}' libmbim-proxy) \
    || fail "libmbim-proxy is not installed"
dpkg --compare-versions "$libmbim_proxy_version" ge "$LIBMBIM_MIN_VERSION" \
    || fail "libmbim-proxy $libmbim_proxy_version is older than $LIBMBIM_MIN_VERSION"

libqmi_version=$(run_target dpkg-query -W -f='${Version}' libqmi-glib5) \
    || fail "libqmi-glib5 is not installed"
dpkg --compare-versions "$libqmi_version" ge "$LIBQMI_MIN_VERSION" \
    || fail "libqmi-glib5 $libqmi_version is older than $LIBQMI_MIN_VERSION"

krel=$(run_target cat /usr/share/linux-xiaomi-marble/kernel.release) \
    || fail "kernel release marker is missing"
[ -n "$krel" ] || fail "kernel release marker is empty"
run_target test -d "/usr/lib/modules/$krel" \
    || fail "kernel modules for $krel are missing"
run_target test -s "/boot/vmlinuz-$krel" \
    || fail "/boot/vmlinuz-$krel is missing"
run_target test -s "/boot/sm8475-xiaomi-marble-$krel.dtb" \
    || fail "/boot/sm8475-xiaomi-marble-$krel.dtb is missing"

run_target test -s /boot/efi/marble/vmlinuz \
    || fail "kernel postinst did not write /boot/efi/marble/vmlinuz"
run_target test -s /boot/efi/marble/sm8475-xiaomi-marble.dtb \
    || fail "kernel postinst did not write the DTB to the ESP"
run_target test -s /boot/efi/extlinux/extlinux.conf \
    || fail "kernel postinst did not write /boot/efi/extlinux/extlinux.conf"

run_target dpkg-query -W -f='${Package} ${db:Status-Abbrev}\n' \
    | awk '$2 == "ii" { print $1 }' | sort > "$after_file"
removed=$(comm -23 "$before_file" "$after_file" || true)
if [ -n "$removed" ]; then
    while IFS= read -r removed_pkg; do
        [ -n "$removed_pkg" ] || continue
        replacement="${allowed_removal[$removed_pkg]:-}"
        [ -n "$replacement" ] \
            || fail "APT removed unexpected package: $removed_pkg"
        status=$(run_target dpkg-query -W -f='${db:Status-Abbrev}' "$replacement" 2>/dev/null) \
            || fail "APT removed $removed_pkg but replacement $replacement is not installed"
        [ "$status" = "ii " ] \
            || fail "replacement $replacement is not fully installed (state: '$status')"
        info "replaced $removed_pkg with $replacement"
    done <<< "$removed"
fi

audit_output=$(run_target dpkg --audit 2>&1 || true)
if [ -n "$audit_output" ]; then
    echo "ERROR: dpkg --audit reported unfinished packages:" >&2
    printf '%s\n' "$audit_output" >&2
    exit 1
fi

run_target apt-get check

as_root rm -rf "$stage_host"
echo "All device packages installed and verified ($krel)"