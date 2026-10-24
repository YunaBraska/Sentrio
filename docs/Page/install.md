---
layout: default
title: Install
---

# Install

[Documentation](documentation.html) | [Install](install.html) | [Sentrio](index.html)

## Download

1. Open the [latest release](https://github.com/YunaBraska/Sentrio/releases/latest).
2. Download the DMG or ZIP file.
3. Move `Sentrio.app` to Applications.

## Homebrew

```sh
brew tap yunabraska/tap
brew install --cask sentrio
```

## Source

```sh
swift build
swift test
sh scripts/package.sh 0.0.1
```
