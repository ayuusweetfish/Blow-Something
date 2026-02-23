NODE=node
LOVEJS_INDEX=misc/lovejs-env/node_modules/love.js/index.js

rm -rf release/Blow-Something-web
${NODE} ${LOVEJS_INDEX} -c -t "Blow Something" -m 64000000 "release/Blow Something.love" release/Blow-Something-web
cp misc/web_index.html release/Blow-Something-web/index.html
cp misc/polygon_rast.wasm release/Blow-Something-web/polygon_rast.wasm
# Patch for filesystem access
perl -pi -e 's/var SYSCALLS/try{if(!window.FS)window.FS=FS;}catch(e){}var SYSCALLS/' release/Blow-Something-web/love.js
rm -rf release/Blow-Something-web/theme

# To run:
# (cd release/Blow-Something-web; python3 -m http.server)
