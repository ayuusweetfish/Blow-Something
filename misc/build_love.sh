BOON=~/Downloads/boon-macos-amd64/boon
TARGET=${1:-all}
${BOON} build . --target ${TARGET}

# Alternative:
# zip release/Blow\ Something.love -r aud fnt img main.lua src -9
