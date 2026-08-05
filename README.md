# HavenObserver

Retail WoW observation recorder for reconstructing ambient NPC events in
BFA-HavenCore. It does not use GM commands or the HavenCore server bridge.

## Recording

1. Enable friendly and enemy nameplates.
2. Place the camera where the complete event is visible and keep it fixed.
3. Start OBS recording.
4. Run `/ho record`.
5. Add synchronisation markers with `/ho mark portal wave`, etc.
6. Wait up to five minutes or run `/ho stop`.
7. Run `/reload` or log out to flush SavedVariables to disk.

The log is written to:

`World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/HavenObserver.lua`

Copy that file together with the original video for analysis.

## Commands

- `/ho record`
- `/ho stop`
- `/ho mark <text>`
- `/ho status`
- `/ho clear`

## Limitations

Retail does not expose arbitrary NPC world coordinates through `UnitPosition`.
HavenObserver therefore records player world/map position and camera-relative
nameplate movement. Nameplate tracks are meaningful only while the camera stays
fixed and the relevant nameplates remain enabled and visible.
