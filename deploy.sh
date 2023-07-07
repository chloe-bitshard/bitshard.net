#!/usr/bin/env sh

git add .
git commit -m "AutoDeploy $(date)"
git push origin main

pipenv run pelican content -o output -s pelicanconf.py
pipenv run ghp-import output -b gh-pages

git push origin gh-pages
