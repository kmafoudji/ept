# Changelog

All notable changes to this distribution of ePT are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Versioning

Releases are numbered `<upstream>-<revision>`, for example `7.7.0-1`:

- `<upstream>` is the deforay/ept version the release is built on. It is the
  value of `APP_VERSION` in `constants.php` and the database schema version.
  It is never changed here, so upstream migrations keep applying.
- `<revision>` counts the releases made on top of that upstream version
  (`DISTRIBUTION_VERSION` in `constants.php`, shown in the footer).
- Each release is a Git tag `v<upstream>-<revision>`.

Database changes in this distribution go into `sql/init.sql` (fresh installs)
or are made without schema changes, never into a new migration number.

## [7.7.0-2] - 2026-11-14

Based on deforay/ept `ae87ce487` (7.7.0). Fixes found by repeating the full
TB round on a fresh install of 7.7.0-1.

### Fixed

- **"New shipment" email sent twice.** Each data manager got one email when
  labs were enrolled (subject left as `##SHIPCODE## (##SHIPTYPE##)`) and a
  second one when the PT survey was shipped. Both had an empty survey code and
  date and showed the scheme code (`tb`) instead of its name. The email is now
  sent once, when the survey is shipped, with every field filled. Labs added
  to a shipment that is already shipped get it when they are enrolled. A
  survey with several shipments now mails the labs of every shipment, not only
  the first.
- **Shipments Report hid shipments dated in the future.** The default date
  range ended today. It now runs from three years ago to one year ahead.
- **Login and password forms refused without a word.** An expired (over an
  hour) or already used form sent the user back to the form with no message.
  The participant and admin logins, *Forgot password* and the new-password
  page now say "This form has expired. Please try again." The *Forgot
  password* and new-password pages also showed no message at all (wrong
  captcha, for example); they now do.
- **JavaScript errors:** opening a dialog on a page with a date picker
  (*Participants > Add > Create Data Manager*) threw an error in
  `daterangepicker.js`; *Get New Image* under the captcha threw an error in
  jQuery `.load()`.

### Verified in the 7.7.0-1 retest

Fresh install with no manual step, cron jobs, evaluation, admin correction
with audit entry and notice to the lab, re-evaluation, reports (header row,
contact block, Ct chart), finalization, report emails with signed links that
require login, and the real count in the notification.

### Known issues (not fixed in this release)

- TB has no documentation score: the score is computed on the samples only,
  out of 100, so *Documentation Score* always shows 0.00. This is how the TB
  evaluation works, not a calculation error.
- TB summary report: the *Contact Information* block can split across two
  pages.
- *Evaluate > View* sometimes stays on "Please wait"; reload the page.
- An admin correction still replaces the lab's stored values; the original
  values are kept only in the audit log.
- Confirmations and validation messages use browser pop-ups; the *Email*
  button of the data manager list changes the login email.
- Default report texts (header, CDC contacts, XTPT programme text) must be
  replaced in *Configure > PDF Report Settings* and the scheme configuration.
- Not tested: schemes other than TB molecular, multi-lab rounds, bulk import,
  PTCC, reminders and deadline extension, corrective actions, certificates,
  upgrades of an existing installation.

## [7.7.0-1] - 2026-11-13

Based on deforay/ept `ae87ce487` (7.7.0, 2026-11-06). Found while testing a
complete TB proficiency-testing round on a fresh container install
(Podman, Ubuntu 26.04).

### Fixed

- **Fresh install database.** `sql/init.sql` lacked 22 columns and 3 indexes
  from migrations 7.3.1 to 7.4.4. Migration 7.6.23 failed and stopped all
  later ones (database stuck at 7.6.22 under 7.7.0 code), and "Forgot
  password" returned HTTP 500. A fresh install now migrates to 7.7.0 with no
  error.
- **Empty emails on fresh installs.** `mail_template` was created empty, so
  shipment notices, reminders and report emails had no body and were dropped.
  Default English templates are now seeded.
- **Emails reported as sent when they were not.** Emails refused before
  queueing (empty body, no valid recipient) are now listed in
  *Configure > Failed Emails* with the reason. *Send Reports via Email* reports
  how many emails were really queued.
- **Scheduled jobs never ran in the container image** (emails stayed
  *Pending*; evaluation, reports and certificates queued forever): cron log
  path not writable, PHP not on cron's PATH, `php.path` pointing to
  `/usr/bin/php`.
- **MySQL healthcheck** in `docker-compose.yml` used the socket and could stay
  *unhealthy* forever, so the application container never started.
- **TB individual report:** the participant header row on page 1 printed
  empty (malformed HTML), and *Result Submission Date* showed the deadline.
- **TB reports:** the *Contact Information* block printed raw HTML tags.
- **TB admin corrections** were saved as the lab's own edit when the browser
  also had a participant session.

### Security

- Report links sent by email used the legacy `/d/` route: no login, no expiry,
  and a guessable URL. They now use signed `/dl/` links that require a login
  and expire after 30 days.

### Added

- Audit-log entry listing each value an admin changes in a lab's TB response
  (original and new value), and a notice on the lab's response page when its
  response was modified by the PT provider.
- Container options for test and training instances: `EPT_MAIL_TRAP_DSN`
  (send all mail to a catcher), `EPT_INSECURE_HTTP=1` (log in over plain
  HTTP), and a `mailpit` service under the `mailtrap` compose profile.
- `DISTRIBUTION_VERSION` and this changelog.
- Test installation guide: `docs/fr/installation-test-conteneurs.md`.

### Known issues (not fixed in this release)

- TB documentation score stays at 0.00 even with complete documentation
  (scheme configuration or bug: to investigate).
- TB summary report: the Ct (Probe A) chart is empty when the shipment has no
  reference raw values.
- An admin correction still replaces the lab's stored values; the original
  values are kept only in the audit log.
- Confirmations and validation messages use browser pop-ups; *Evaluate > View*
  needs two clicks after the page loads; the *Email* button of the data
  manager list changes the login email; *All Schemes* shows *Shipped* for a
  finalized shipment.
- Default report texts (header, CDC contacts, XTPT programme text) must be
  replaced in *Configure > PDF Report Settings* and the scheme configuration.
- Not tested in this release: schemes other than TB molecular, multi-lab
  rounds, bulk import, PTCC, reminders and deadline extension, corrective
  actions, certificates (no templates are shipped), upgrades of an existing
  installation.
