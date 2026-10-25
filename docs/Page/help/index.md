---
layout: default
help: true
title: Sentrio help
description: Route audio devices and keep BusyLight behavior predictable.
---

# Sentrio help

Sentrio keeps the audio route you expect ready in the menu bar. Set the order once, then let Sentrio choose an eligible output and input when devices appear or disappear.

![The Sentrio menu bar panel]({{ '/assets/help/bar-menu.png' | relative_url }})

## Start with device priorities

Open **Settings**, then choose **Output** and **Input**. Put the device you prefer first and keep alternatives below it. Sentrio uses the highest eligible device in each list. Device-specific output, input and alert volumes return when macOS makes the device available again.

![Output device priorities]({{ '/assets/help/preferences-output.png' | relative_url }})

For similar devices, give each one a clear name and icon. This makes the active route understandable without opening every setting.

## Choose input behavior

Input has its own priority order. Use it to keep a preferred microphone ready while headphones, speakers or docks change around it.

![Input device priorities]({{ '/assets/help/preferences-input.png' | relative_url }})

Continuity and iPhone routes require an explicit connection. If that connection is unavailable, Sentrio continues with the next eligible device instead of leaving audio in an unknown state.

## BusyLight

<a id="busylight"></a>

Connect a supported BusyLight, then use **Settings > BusyLight** to choose automatic rules or a manual state. Sentrio briefly identifies a newly detected light, applies the current rule or manual action, and turns the light off when the app quits.

![BusyLight settings]({{ '/assets/help/preferences-busy-light.png' | relative_url }})

## Settings and backup

<a id="settings-and-backup"></a>

When the routing feels right, export the settings. Import the same file on another Mac or after a reset. The general settings page also contains the controls for normal app behavior.

![General settings]({{ '/assets/help/preferences-general.png' | relative_url }})

If a route does not change as expected, first check that macOS sees the device, then confirm its priority and whether it is eligible. A backup lets you return to a working configuration without rebuilding it by hand.
