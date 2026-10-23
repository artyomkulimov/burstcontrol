#!/bin/zsh
set -eu
cd "${0:A:h}"
source_app="$PWD/dist/Burst Control.app"
target_app="$HOME/Applications/Burst Control.app"
if [[ ! -d "$source_app" ]]; then
    echo "Build the app first with ./build-app.sh" >&2
    exit 1
fi
if pgrep -x BurstControl >/dev/null; then
    echo "Quit Burst Control before installing." >&2
    exit 1
fi
mkdir -p "$HOME/Applications"
ditto "$source_app" "$target_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"
echo "Installed: $target_app"
echo "Ad-hoc builds change identity when rebuilt. If permission is stale, remove the old Input Monitoring entry and add this installed app again."
