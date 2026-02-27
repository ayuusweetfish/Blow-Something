if [ "$1" = "boon" ]; then
  BOON=boon
  TARGET=${1:-all}
  ${BOON} build . --target ${TARGET}
else
  rm -f release/Blow\ Something.love
  t=$(mktemp -d)
  wd=$PWD
  cp -pr aud fnt img main.lua src "$t/"
  (
    cd "$t/" || exit
    pwd
    find . -exec touch -t 198001010000 {} +
    zip "$wd/release/Blow Something.love" -Xr * -9
  )
  rm -rf "$t"
fi
