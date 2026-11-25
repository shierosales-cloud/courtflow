# CourtFlow Rewards – Deployment Notes

This update adds an opt-in loyalty enrollment section to the existing public player registration link, an optional Birthday field, organizer-specific loyalty card customization, an in-app player loyalty card, stamp/reward records, and organizer loyalty management.

## Required order

**Run the Supabase migration before deploying the new site.** The updated registration form calls the new `cf_save_player_profile_v2` RPC even when the player does not opt into loyalty, so the migration is required to preserve registration functionality.

1. Back up the Supabase project/database.
2. Open the correct Supabase project and go to **SQL Editor**.
3. Open `supabase-loyalty-registration.sql` from this app folder, copy the entire file into a new SQL query, and run it once.
4. Confirm the query completes successfully. It adds the optional `birthday` column, creates loyalty tables and RPC functions, and creates the `cf-loyalty-assets` Storage bucket and access policies.
5. Deploy the contents of `CourtFlow-app-final-v27` to the existing Netlify site, preserving the existing site URL and configuration.
6. Sign in to CourtFlow and open **Home → Loyalty**.
7. Customize the card, upload your logo/background/custom stamp artwork, and select **Save & Publish Design** with enrollment activated.
8. Use the existing registration link (or generate it from the Loyalty tab) and test it with a test player.

## Registration behaviour

- All existing player registration fields remain: Display Name, Full Name, Gender, Playing Level, rating guide, WhatsApp Number and Profile Photo.
- Birthday is an additional optional field and is not displayed publicly to other players.
- The loyalty checkbox appears only when the organizer has an active loyalty program.
- The checkbox is unchecked by default. Normal registration continues when it is not selected.
- Selecting it records opt-in and creates one organizer-specific loyalty membership/card.
- No historical attendance is converted into stamps. A newly enrolled player starts with zero loyalty stamps.

## Card customization

The Loyalty tab supports organizer-specific club/program names, subtitles and welcome text, preset card layouts, background image/full-artwork upload, logo upload, colors, built-in sports/achievement stamp icons and custom stamp artwork. Published design changes update the in-app card presentation without changing stamp balances or rewards.

Accepted artwork formats: PNG, JPEG and WebP. Logo uploads are limited to 2 MB, background/full artwork to 5 MB, and custom stamp artwork to 512 KB.

## Rewards and eligibility

The initial rules are fixed: 10 eligible attended sessions earn one free open-play reward. One stamp is awarded per player per session. Monthly subscribers must be active; Pay Per Play must be paid; attendance must be present in the saved session attendee list. Duplicate player/session awards are blocked by a database uniqueness constraint.

## Important scope note

This package implements the in-app CourtFlow card and its organizer management. Apple Wallet and Google Wallet pass issuance/update services are not yet included; those remain a separate integration phase that needs Apple/Google issuer setup and credentials.

## Deployment/testing note

The inline JavaScript passed `node --check` and the ZIP integrity check is part of packaging. The app could not be connected to the user's live Supabase project from this environment, so the SQL migration still needs to be run in the actual Supabase SQL Editor and tested there before public launch. A full live database/browser regression test has not been performed.
