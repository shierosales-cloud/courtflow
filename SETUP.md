# CourtFlow cloud accounts: setup (about 10 minutes, free)

CourtFlow uses Supabase for sign-up, sign-in, password reset and saving each user's sessions online.

1. **Create a project** at https://supabase.com (free plan is fine). Choose a region near your players.
2. **Create the table:** open *SQL Editor*, paste everything from `supabase-setup.sql`, click *Run*.
3. **Email sign-in:** *Authentication > Providers > Email* must be on (it is by default).
   - "Confirm email" ON: new users must click a link in their email before they can sign in.
   - "Confirm email" OFF: users are signed in immediately. Handy while testing.
4. **Tell Supabase your app's address:** *Authentication > URL Configuration*.
   - Site URL: the address where you host CourtFlow, e.g. `https://courtflow.example.com/`
   - Redirect URLs: add the same address. Password-reset and confirmation links return here.
5. **Copy your keys:** *Project Settings > API*. Copy the **Project URL** and the **anon public** key.
   Open `index.html`, find `var CFG={url:'...',key:'...'}` near the top of the script and paste them in.
   (The anon key is meant to be public. Row Level Security from step 2 protects the data. Never paste the `service_role` key.)
6. **Host all files** on HTTPS (Netlify, GitHub Pages, Cloudflare Pages) and open the address.

## Live view for players (QR code / link)
Run `supabase-live.sql` once in *SQL Editor* (same way as step 2). After that, in any session tap **Share Live View**
to get a QR code and link. Players need no account: they see the courts, the match line-up, the leaderboard and recent matches
on their own phone, updated every ~10 seconds. View-only, so they can't change anything.
- The link contains a random secret code. Only people you give the link/QR to can view it, and there is no way to browse other sessions.
- **The link works for as long as the session is running.** A lost connection, a closed browser or a crashed phone never switches it off. Players keep seeing the last update, with "Updated … ago" showing how old it is, and it catches up when your phone is back online.
- The link stops working only when the session itself changes: you tap **Stop Sharing**, end the session, or start a different one. It then shows "Live Session Ended". The server checks your saved session on every view, so this holds even if your phone was offline at that moment (it applies as soon as the app saves online).
- If you abandon a session without ending it, its link keeps working. Open CourtFlow on any device you're signed in to and end the session to switch it off.
- **Upgrading from an earlier build:** run the new `supabase-live.sql` again (it is safe to re-run). Then tap **Share Live View** to make a fresh link.
- Players see the names, levels, genders, scores and ratings that you've entered in the session.

## Good to know
- **Emails:** Supabase's built-in email sender is limited to a few emails per hour. For real use, add your own
  SMTP provider under *Authentication > SMTP Settings*. You can also edit the reset/confirm email wording under *Email Templates*.
- **Sync:** changes save to the cloud a moment after you make them. The app re-checks the cloud when you open it,
  switch back to it, come back online, or tap *Sync Now*. Offline changes sync automatically later.
- **Two devices at once:** the newest save wins for the whole account. Avoid editing the same session on two devices at the same moment.
- **Sign out** saves any pending changes first, then removes the local copy from that device.
