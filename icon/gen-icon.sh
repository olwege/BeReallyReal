#!/bin/bash

latexmk -pdf icon.tex
magick -density 3000 icon.pdf -resize 1024x1024 -gravity center -extent 1024x1024 icon.png