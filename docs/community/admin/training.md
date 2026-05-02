# VS14 admin training

How to start admin work and what to expect long-term. Three
sections: what tools you have, how to start, and what ongoing
admin life looks like.

## Tools you have

You'll need walk-throughs from the maintainer on each of these
in a live or test server — most aren't usable cold.

- **In-game admin menu** (F5). Spawn panel, admin-verb panel,
  ahelp client, observer mode, ban/kick/warn dialogs.
- **SS14.Admin web panel** (once deployed). Ban lookup, role
  history, hub ID search.
- **Watchdog admin API** at `/watchdog/`. For restarts and log
  inspection — don't poke unless you've been shown how.
- **Player appeals at `/appeals`**. How we thread appeals, what
  we say publicly vs privately, where the "decision" label lives.
- **Postgres `admin` table** (read-only to start). How admin
  permissions actually get set. The maintainer handles writes.

## How to start

- Tag-in with the maintainer on non-trivial tickets when you're
  new. "You write the response, the maintainer reads it before
  you send" is a fine starting mode.
- Skip permanent bans early on. Any ticket you feel needs a
  permaban goes to the maintainer.
- Keep a running log of tickets you handle for the first stretch.
  Helps calibration — you (or the maintainer) can spot drift.
- Ask questions constantly. There's no penalty for over-checking
  rule interpretations or wanting a second pair of eyes.

## Ongoing admin life

Admin work here is come-as-you-go. No shifts, no minimums, no
hour quotas — show up when you can.

- Keep an eye on the admin channels when you log on. Situational
  awareness on what's been happening is part of the job.
- Re-read [expectations.md](./expectations.md) and
  [sanctions.md](./sanctions.md) regularly. Both drift, and your
  calibration drifts with them.
- Speak up when you think a policy is wrong. This project is
  small enough that "this isn't working" from a single admin can
  actually change the rules — it's how the docs evolve.
