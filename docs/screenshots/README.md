# Screenshots

Every zone of the tower mid-run, the doors between zones, party races and the low detail path, made with:

    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots

Add `group=zones` (or transitions, party, detail) for one group; the README is only rewritten by a whole run.

## Zones

Each zone a little way in, with the pilot flying an expert bot's line.

- [Test Lab](zones/lab.jpg)
- [Test Lab, further in](zones/lab_deeper.jpg)
- [Server Hall](zones/servers.jpg)
- [Server Hall, further in](zones/servers_deeper.jpg)
- [Robot Bay](zones/bay.jpg)
- [Robot Bay, further in](zones/bay_deeper.jpg)
- [The Atrium](zones/atrium.jpg)
- [The Atrium, further in](zones/atrium_deeper.jpg)
- [Downtown](zones/downtown.jpg)
- [Downtown, further in](zones/downtown_deeper.jpg)
- [Halberd's Floor](zones/halberd.jpg)
- [Halberd's Floor, further in](zones/halberd_deeper.jpg)

## Doors between zones

The room where each zone starts, flown into from the zone before: a doorway inside the tower, out through the Atrium's glass onto the rooftops, and in through Halberd's window.

- [Test Lab to Server Hall](transitions/lab_to_servers.jpg)
- [Server Hall to Robot Bay](transitions/servers_to_bay.jpg)
- [Robot Bay to The Atrium](transitions/bay_to_atrium.jpg)
- [The Atrium to Downtown](transitions/atrium_to_downtown.jpg)
- [The Atrium to Downtown, through the glass](transitions/atrium_to_downtown_through.jpg)
- [Downtown to Halberd's Floor](transitions/downtown_to_halberd.jpg)
- [Downtown to Halberd's Floor, through the glass](transitions/downtown_to_halberd_through.jpg)
- [Halberd's Floor to Test Lab](transitions/halberd_to_lab.jpg)

## Party races

Four pilots in a party race against bots.

- [Party race in Test Lab](party/lab.jpg)
- [Party race in Robot Bay](party/bay.jpg)
- [Party race in Downtown](party/downtown.jpg)
- [Party race in Halberd's Floor](party/halberd.jpg)

## Low detail and Calm background

Low detail is what handhelds run (fewer lights, a smaller city, simpler effects). Calm background dims the city and the far wall.

- [Test Lab, low detail](detail/lab_low.jpg)
- [Server Hall, low detail](detail/servers_low.jpg)
- [Robot Bay, low detail](detail/bay_low.jpg)
- [The Atrium, low detail](detail/atrium_low.jpg)
- [Downtown, low detail](detail/downtown_low.jpg)
- [Halberd's Floor, low detail](detail/halberd_low.jpg)
- [The Atrium, Calm background](detail/atrium_calm.jpg)
- [Downtown, Calm background](detail/downtown_calm.jpg)
