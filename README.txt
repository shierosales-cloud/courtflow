CourtFlow - install on your phone
1. Follow SETUP.md once (creates the free online account system), then paste your two keys into index.html.
2. Upload ALL files in this folder to any HTTPS web host (free: Netlify Drop, GitHub Pages, Cloudflare Pages).
3. Open the site's address on your phone.
   iPhone/iPad (Safari): Share > Add to Home Screen.
   Android (Chrome): tap Install app (or menu > Install app / Add to Home screen).
4. Create an account or sign in. Your sessions follow you to any device. It works offline after the first load and syncs when back online.
5. In a session, tap Share Live View to give players a QR code or link to follow the courts, line-up and leaderboard (run supabase-live.sql first, and again after upgrading; see SETUP.md). The link keeps working while the session runs, even if your phone goes offline, and stops when you stop sharing or end the session.

v9 - Fair pairing
- Generated line-ups and auto-added matches now track both partners AND opponents. Nobody plays with or against the same player again until they have met everyone else; when repeats are unavoidable they are spread evenly.
- Winners only stay on court if that does not repeat a partner or opponent more than rotating would.
- Generate Many reports how many partner/opponent repeats (if any) were unavoidable.

v10 - Fair turn order
- Generate Many now guarantees everyone plays once before anyone plays twice (and so on): at every point in the line-up, no player is more than one game ahead of anyone else.
- Match types (mixed / women's / men's / open) are ordered so men and women take turns evenly.
- Repeat partners/opponents, when unavoidable, are pushed as late in the line-up as possible.

v11 - New branding
- Replaced the logo (app header) and app icon (favicon, home-screen, PWA, maskable) with the new CourtFlow artwork.
- In dark mode the logo sits on a white rounded plate so the navy lettering stays readable.

v12 - Updated logo
- App header logo replaced with the improved flat-colour CourtFlow logo (transparent background).

v13 - Bigger logo
- Logo now spans the full width of the screen (up to 900px on large screens).
- Dark mode uses a dedicated light-lettered version of the logo instead of a white box.

v23 - Dynamic scheduling, fair rotation and manual lineup choice
- Use Court / Use This Court asks which lineup supplies the match: Beginner or Open Skill. Asked every time, nothing is remembered, nothing is pre-selected.
  If only one lineup has an eligible match it is used automatically; if neither does you get a message. Auto-Queue only fills a court by itself when exactly one lineup is eligible.
- Court assignment is atomic (validate, commit, check, roll back on any failure) and refuses overlapping requests. A player, match or court can't be double-booked.
- Adding a player, switching a player OFF/ON, removing a player, or a rating moving someone between Beginner and Open Skill recalculates ONLY unassigned line-up matches, once, per group.
  Matches on a court, in progress or finished are never touched. Hand-built (manual) matches keep their players except that OFF players are removed from them.
- Fair order: fewest completed matches, then longest since last completed match (or activation), then longest since becoming available, then earlier arrival, then fewest repeated partners/opponents.
  Waiting times are compared in 5-minute bands. Late arrivals are no longer given pretend games, so they catch up first.
- New per-player session stats: arrival, activation, last completed match, completed / court-assigned / ongoing / upcoming counts, teammates, opponents (Players tab > Stats). Kept through OFF/ON, reset only when a new session starts.
- No Supabase/SQL changes. New fields live inside the existing saved session data; old saves upgrade automatically.

v23.2 - Rest rule
- A player is never lined up again within the next N games, where N = number of courts (1 court: not back-to-back; 2: skip the next 2 games; 3: skip the next 3). Applies to Generate, to refilling slots when players go OFF/ON or join late, and to the load-levelling swaps. Matches that break it are flagged "Plays too soon". If there aren't enough players (about 4 x (courts+1)), the closest-possible schedule is made and the message says so.
- Assigned matches no longer start by themselves; a lineup popup opens for a court after every completed match.

v23.3 - Uneven men/women
- Generate now fills mixed, men's and women's games first (as many as the player counts allow, balanced against each other); Open Doubles only takes the leftover spots, so every player still gets equal games.
- The leftover spots are shared out across the Open games before building, so an Open game can't use up players a mixed game still needs. If a split truly can't work you still get a message.

v25 - Simplified settings, leaderboard and announcements
- Removed the Auto-Queue and Everyone Rotates switches from Settings (courts are never filled automatically; everyone always rotates).
- Removed the explanatory caption at the top of the Match Line-Up and the Leaderboard / Beginner leaderboard captions.
- Leaderboard: removed the Win % column. Games, Won, Lost and Rating now show on both phone and large screens.
- Court announcements now read: "Court 1, Ayen with Rey.. versus, Joshua with Shiela, please proceed to Court 1. (short pauses between parts; speed 0.95x)" Speech speed is 0.95x.
- Fair match counts: when late players arrive or become active, and when Generate is pressed, matches already on a court, in progress or finished are now counted, so players who are playing no longer end up with one extra match.
- Late arrivals / players switched ON late are given the latest matches in the line-up, so their last match is at the end of the line-up order.
- Line-up: back-to-back games for the same player are now almost never allowed (generation, late arrivals, ON/OFF refills); the generator keeps retrying until nobody is back-to-back, unless there are too few players for that to be possible.

v26 - Add Matches scheduler (replaces Generate Line-Up)
- Add Matches: each tap appends (courts x 2) matches to the end of the Beginner or Open line-up. Existing matches are never regenerated, rebalanced or replaced. Every match has a unique id, a sequential queue number and a batch id. Double taps and overlapping requests are refused.
- If there are too few eligible players, only valid matches are created and the reason is shown.
- New players start OFF. Only players switched ON are used. Each OFF to ON activation is recorded.
- Waiting time counts only while a player is ON and waiting (not on court). OFF time is excluded, ON again resumes, a completed match resets it.
- Rotation: the player with the fewest matches (including on court, in progress and queued) goes first, so everyone gets one before anyone gets a second; first-match players go before later-activated players; then longest active wait, then fewer completed matches, then fewest repeated partners/opponents. Players from the match just before are avoided unless nobody else is available. Beginner and Open Skill never mix.
- Protected Up Next: the first match per court (Settings: Protected Up Next, default 1) cannot be edited, moved, swapped or deleted. If a player in it goes OFF it is flagged "Organizer Action Needed" and can then be edited.
- test-scheduling.js was rewritten for the new scheduler (node test-scheduling.js).

v26b - Session-wide fairness
- Fairness uses each player's projected matches: completed + ongoing + court-assigned + protected + queued. Lowest projected count goes first, then longest active waiting time (OFF time excluded), avoiding back-to-back and rotating across all courts.
- Late arrivals (switched ON) join the pool right after the protected matches and take open spots in unprotected matches until their count catches up. They are not parked at the end of the line-up.
- Only unprotected upcoming matches are rebalanced: on Add Matches, when players are switched ON/OFF, and once when an existing session is first opened in this version. Ongoing, court-assigned and protected Up Next matches, completed history and statistics are never changed.
- The Protected Up Next setting was removed from the top settings; protection itself still works (first match per court).
- Leaderboard ranking now uses wins and losses only (most wins, then fewest losses; same record shares a rank). Rating is still shown but no longer affects the order.

v27 - New rating scale (from the rating checklist)
- Six levels: Newbie 2.0, Novice 2.5, Low Intermediate 3.0, High Intermediate 3.5, Advanced 4.0, Expert 4.5-5.0. Ratings run from 2.0 to 5.0.
- New players start in the middle of the level picked (2.25, 2.75, 3.25, 3.75, 4.25, 4.75).
- Beginner line-up = Newbie level (rated 2.0-2.49). Open Skill = rated 2.5 and above.
- Rating Chart rewritten from the checklist, with a "Reality check" for each level and the Final reality check.
- One-time migration: saved players and past sessions on the old 1.0-6.0 scale are clamped into 2.0-5.0 and their level is recalculated.

v27 (update) - Editing, Round Robin, ranking and rating history
- Bluetooth/AirPlay audio fix included (announcements go to the connected speaker; needs iOS 16.4+).
- Protection removed: no match is locked. Up Next, scheduled and court matches can all be edited. Add Matches and rebalancing still keep counts fair and never reorder matches you edited by hand.
- Editable court management: tap any player name on a court, a scheduled match or an Up Next card to replace them (shows each player's match count). Picking someone already in the match swaps places. A player taken off a court returns to the front of the queue.
- Round Robin match type (tick it in the line-up settings; it replaces the other types while ticked): partners rotate so nobody repeats a partner until everyone has partnered with everyone, then a new round starts. A Round Robin progress panel shows who still has to partner with whom. Matches are tagged Round Robin in history.
- Leaderboard no longer shows ratings (organizer, live view and past-session tables).
- Top Players: players with no losses and at least 3 wins (UNB_MIN in index.html) rank first and are tagged Unbeaten; then most wins, then fewest losses.
- New Ratings tab (organizer and live view): all players with rating, change this session and matches played. Tap a player for rating before/after and adjustment for every match, per-session summary (W-L, start, end, change), full match history and a progression chart.
- Rating changes from record resets or level changes are logged as adjustments. History keeps the last 400 entries per player.
- test-scheduling.js now has 41 tests (all pass).

v27 (update 2) - Level floor and Ratings table
- A player's set level is a floor: losses never drop them into a lower level (e.g. a Novice stays at 2.50 or above). Wins can still move a player up a level.
- Final reality check box removed from the Rating Chart (the per-level Reality check lines remain).
- Ratings tab is one table: Now, Prev (rating before last match), Change (up/down arrow with amount) and Rated matches. Same in the live view.
- test-scheduling.js: 45 tests, all pass.

v27 (update 3) - Ratings tab
- Level has its own column (organizer and live view); the Rated column was removed.
- A player who moves up a level during the session gets a green caption under their name ("Moved up: Novice -> Low Intermediate").
- The tab lists only players in the current session, not everyone from earlier sessions.
- test-scheduling.js: 47 tests, all pass.
- Ratings tab: added a W-L column (session wins-losses), compact layout so all columns fit on phones.

v27 (update 4)
- Current Session stats: "Active Players" counts only players switched ON (Men/Women likewise); paused players are not counted.
- Audio route: a silent looping media track now keeps the page on the media route (with a Now Playing entry) so speech follows the connected Bluetooth/AirPlay speaker. Needs one tap anywhere in the app after opening it. Not verified on a real iPad.

v27 (update 5) - Audio
- The app no longer touches audio at page load or on taps, so Spotify and other music keeps playing.
- During an announcement only: the page requests a "transient-solo" audio session (pauses other audio) and plays a silent track so the media route (Bluetooth/AirPlay speaker) is used; when speech ends the session is released so the music can resume. Needs iOS/iPadOS 16.4+. Not verified on a real iPad.
- sw.js cache bumped to courtflow-v35 so devices pick up this version.

v27 (update 6) - Up Next panel
- New "Up Next" panel under the courts (normal view) shows the next lined-up match for each skill group with an Announce button, even when every court is busy.
- Up Next announcements (panel, game cards, empty-court Up-Next) now say: "Up Next, Ray with Ayen.. versus, Joshua with Shiela.. Players, be ready." at a slower 0.8x speed. Court announcements are unchanged (0.95x).
- sw.js cache bumped to courtflow-v36.

v27 (update 7) - Line-up game cards stack Team A over Team B on phones so player names no longer break across lines. sw.js cache courtflow-v37.

v27 (update 8) - Up Next card (panel and Up-Next game in the line-up) now uses the brand lime. sw.js cache courtflow-v38.

v27 (update 9) - Announcement voice routed as audio
- Announcements are now fetched as an audio file (online text-to-speech) and played in an audio element, which iOS/iPadOS routes to a connected Bluetooth/AirPlay speaker. The built-in device voice cannot be routed by a web page and stays on the iPad speaker.
- If the audio cannot load within 5 seconds (offline, blocked), the app falls back to the device voice automatically.
- The sentence is unchanged: "Up Next, Ray with Ayen.. versus, Joshua with Shiela.. Players, be ready." and "Court 1, Ayen with Rey.. versus, Joshua with Shiela, please proceed to Court 1."
- To use only the device voice, set VOICE_ONLINE=false in index.html.
- The text of the announcement (player names) is sent to the voice service. Not verified on a real iPad.
- sw.js cache courtflow-v39.

v27 (update 10) - The device voice is unlocked inside the tap so the fallback still speaks if the online audio fails; failure is detected within 3 s and a notice says the device voice is used. sw.js cache courtflow-v40.

v27 (update 11) - Voice selector under the Up Next card: Device voice (default, plays on the iPad, known to work) or Online voice (test, for Bluetooth). The choice is remembered on the device. If the online voice fails a notice shows the error and the device voice is used. sw.js cache courtflow-v41.

v27 (update 12) - Online voice now requests a 'playback' audio session (media route, follows Bluetooth) instead of 'transient-solo'; released to 'auto' when it ends. Not verified on a real iPad. sw.js cache courtflow-v42.

v27 (update 13) - Online voice is now the default and uses plain audio playback only (no audio-session changes, no speech-engine unlock) so iPadOS routes it like YouTube/Spotify. Device voice remains as selectable option and automatic fallback. sw.js cache courtflow-v43.

v27 (update 14) - Device voice is unlocked inside the tap again so the fallback speaks; a status line under the Voice selector shows whether the online voice played or failed (with the error code). sw.js cache courtflow-v44.

v27 (update 15) - Legacy cloud voice via Supabase Edge Function (superseded by offline Piper voice update below)
- The free web voice used before is blocked in Safari (error 4), so announcements fell back to the iPad's built-in voice (iPad speaker only).
- New: supabase/functions/tts/index.ts (Google Cloud Text-to-Speech, signed-in users only) and SETUP-VOICE.md (about 10 minutes, free tier).
- The app calls it, plays the MP3 in an audio element started inside the tap (so iPadOS routes it like Spotify/YouTube), and falls back to the device voice if the function is missing or fails. A status line under the Voice selector shows what happened.
- Not verified on a real iPad (function was tested with a mocked response only). sw.js cache courtflow-v45.

v27 (update 16) - Fixed leaderboard rows stacking vertically: the new Up Next panel reused the CSS class name 'unr', which the leaderboard already uses for unranked rows. Up Next now uses its own class. sw.js cache courtflow-v46.

v27 (update 17) - Rating history in the Live View
- Live View > Ratings: players tap their name to see the same detail as the organizer: current rating, session and overall change, W-L, progression chart, per-session summary and match-by-match history (before, after, adjustment, partner, opponents).
- The live link now carries each player's latest 50 rating changes (organizer keeps up to 400). If a player has more, the page says so.
- No SQL change needed: the history travels inside the existing live snapshot. Run Share Live View again or keep the session open; viewers get it within ~10 seconds. Anyone with the link sees every player's history.
- sw.js cache courtflow-v47.


VOICE UPDATE — OFFLINE NATURAL ANNOUNCEMENTS
- Up Next voice now defaults to Piper natural neural voice instead of the undeployed Supabase cloud TTS function.
- First use downloads the English voice model (approximately 63 MB) and required browser runtime from the public Piper browser demo repository.
- The model is synthesized locally in the browser; announcement text is not sent to a TTS service.
- Service worker cache version bumped so the new voice code is picked up.
- Select the JBL output in iPad Control Center. CourtFlow cannot force the iPadOS audio route.
- Device voice remains available as an alternate option.

- This offline Piper voice update supersedes the legacy cloud TTS implementation above; the app no longer calls the TTS Edge Function.

PLAYER PROFILE DIRECTORY (NEW)
------------------------------
The permanent player profile directory is separate from each session roster.
Players can register through one reusable organizer link, then keep their private
edit link to update display name, full name, photo, level, and WhatsApp number.
Registered profiles are NOT automatically added to a session. The organizer
chooses Add to Session beside each profile. WhatsApp numbers are only returned
to the signed-in organizer and are not included in live-session snapshots.

IMPORTANT: Before uploading this updated site to Netlify, open Supabase SQL
Editor for the same project used by CourtFlow and run the complete file
supabase-player-profiles.sql once. This creates the profile tables and secure
RPC functions. Do not skip this step: profile registration will not work until
that migration has completed. Back up the Supabase project first.

After running the SQL file, upload the contents of this folder to Netlify as a
new deployment. Sign in to CourtFlow, open a session, go to Players, then use
Player Profile Directory > Create / Copy Registration Link. Share that link
with players. The organizer can also show the QR code. Players should keep the
private edit link shown after they save their profile. The registration link
can be reused by new players and is not tied to a session.

Player profiles have a stable UUID in the directory. For compatibility with
existing match history and scheduling, the session's current display-name based
match records are retained; each session player record now carries the linked
profile UUID when imported. Avoid changing existing player display names in the
middle of an active session if preserving that session's name-based history is
important.


CLUB REWARDS MEMBERSHIP TYPE UPDATE
For an existing Supabase deployment, run supabase-rewards-membership-type-update.sql once before deploying the latest Club Rewards UI. This adds organizer-managed membership labels to the public Rewards card.
