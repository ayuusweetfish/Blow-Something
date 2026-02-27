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
    if [ "$1" = "min" ]; then
      for i in $(find . -type f -name '*.lua'); do
        node "$wd/misc/luamin-env/node_modules/luamin/bin/luamin" -f "$i" > "$t/_tmp"
        mv "$t/_tmp" "$i"
      done
    fi
    find . -exec touch -t 198001010000 {} +
    find . -type f -print | sort | zip "$wd/release/Blow Something.love" -X -@ -9
    echo "$wd/release/Blow Something.love"
    sha1sum "$wd/release/Blow Something.love"
  )
  rm -rf "$t"
fi
