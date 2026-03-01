#!/bin/sh
# Patch @anon-aadhaar/core to not expose raw .ts as types
# (their package.json has "types": "./src/index.ts" which breaks tsc)
PKG="node_modules/@anon-aadhaar/core/package.json"
if [ -f "$PKG" ]; then
  sed -i 's|"types": "./src/index.ts"|"types": "./dist/index.d.ts"|' "$PKG"
fi
