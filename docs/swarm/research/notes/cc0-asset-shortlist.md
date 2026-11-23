# CC0 asset shortlist for the art-direction interview (sw-kys.9)

Verification date: 2026-11-21 (brief date; run 2026-11-22). Web-verification only: nothing downloaded, no GDD edits.
Feeds README Open topic 3 (art direction) as **options only; the user decides.**
Context: `docs/swarm/research/summaries/art-styles-and-assets-for-a-clear-easy-to-read-accessible-ta.md` line 13.
Page content below is quoted as data.

## Verdicts

| # | Candidate | Verdict |
|---|---|---|
| 1 | Kenney isometric packs | **Usable** (carried forward) |
| 2 | Screaming Brain Studios, Isometric Tiles - Town Pack | **Usable** (verified on pack page) |
| 3 | SBS other iso packs (Floor / Overworld / Wall / Object) | **Unverified: unusable until checked** |
| 4 | OpenGameArt, Blarumyrran's publicdomain Wesnoth sprites | **Unverified: unusable until checked** |

## 1. Kenney isometric packs: usable (carried forward)
- URL: https://kenney.nl/assets/tag:isometric
- Licence: CC0, verified on the pack pages by the art-styles research summary (point 4). Not re-fetched in this run.
- Note: check each individual pack page's licence line when a pack is picked.

## 2. Screaming Brain Studios, Isometric Tiles - Town Pack: usable
- URL: https://screamingbrainstudios.itch.io/iso-town-pack (HTTP 200, read directly)
- Licence statements, verbatim from the page:
  - Description: "All assets in this pack have been released under the Public Domain (CC0) license, and are free to use however you like in any project, commercial or non-commercial."
  - "Asset license" field: "Creative Commons Zero v1.0 Universal"
  - Tag: "CC0"
  - Creator comment (https://itch.io/post/3146692): "All Screaming Brain Studios assets are CC0, no credit required!"
- Provenance: the tiles are made from Golgotha textures. A creator comment (https://itch.io/post/11536765) says "...since the Golgotha textures are all CC0 as well!". This is the creator's own claim; the upstream licence was not independently checked.
- Other: "Name your own price" download, tagged "No generative AI was used." Files are a .rar (3.9 MB); we have not downloaded it.
- Style fit: textured tiles, so terrain may need desaturating for readability.

## 3. SBS other iso packs: unverified
- The Town Pack page names "Isometric Floor Tiles, Isometric Overworld Tiles, Isometric Wall Tiles, and Isometric Object Tiles packs" but links none of them, and shows no licence text for them.
- The creator comment "All Screaming Brain Studios assets are CC0" is a blanket claim, not a per-pack statement. Author page https://screamingbrainstudios.itch.io was not fetched.
- Verdict: unusable until each pack's own page is read. Follow-up for the interview or a later bead.

## 4. Blarumyrran's publicdomain Wesnoth sprites: unverified
- URL: https://opengameart.org/content/blarumyrrans-publicdomain-wesnoth-sprites
- Direct fetch returned HTTP 403 with no body. It was not retried.
- One alternate-source attempt (a web search) gave only excerpts, which do not count as page verification. They report the License field as CC0, attribution optional, and an author note that most Wesnoth assets are not public domain but these are. The same search showed that some related Blarumyrran uploads reuse Wesnoth animations the author says they cannot license as CC0.
- Verdict: **unusable/unverified.** The exact licence text could not be read. Per-sprite provenance is unclear, and mainline Wesnoth art is GPL/CC-BY-SA (share-alike risk for Workshop packages, GDD 01 pillar 5). A person can open the page in a browser to confirm.

## Excluded without checking (by brief)
- Mainline Wesnoth art (GPL / CC-BY-SA): share-alike risk for derivative Workshop content packages.
- Sprite-rip archives.
- Packs with unclear licences (for example Tiny Swords).
