#!/usr/bin/env bash
# VIOLATIONS PLANTED FOR QUALITY-SMOKE (do not fix):
# - SC2066-class: unquoted `for i in $items` (word-splitting/glob hazard in the loop list)
# - SC2145: argument mixes a literal string with an expansion in echo
items="alpha beta gamma"
prefixes=(pre post)
for i in $items; do
  echo "item=${prefixes[@]} -> $i"
done
