# UI direction

Inspiration lives in [inspo/](inspo/). Take the mood from it, never copy a screen.

## Style

- Light mode only.
- Main colour: soft indigo/periwinkle, with lavender gradients for headers and the sign-in screens.
- Rounded cards with soft shadows. Pastel colour-block tiles (green, pink, blue, lavender) for visual variety.
- Badges on cards for counts, for example "5 Presentations · 3 Exercises".
- Chips to switch between lists.
- Floating pill-shaped tab bar.

## Screens

- **Sign in / sign up**: lavender gradient background. At sign-up, Teacher and Student are two large cards to tap.
- **Tab bar**: two tabs, Courses and Profile.
- **Courses (home)**: greeting header ("Good morning, <name>") with an initials avatar, then course cards. Each card has a pastel colour-block cover picked automatically per Course. Teachers see "+ New Course"; Students see "Join with code".
- **Course**: chips for Presentations and Exercises. Each file row shows a coloured file-type badge (PPT, PDF, DOCX, KEY), the title and the upload date. Teachers also see Roster and Join Code buttons.
- **Profile**: initials avatar (no photo upload), name, role, sign out.

## Left out on purpose

Prices, ratings, progress, chat, leaderboard, notifications, search, categories, deadlines, points and certificates. None are in the plan.

## Chosen variation: B

The owner picked variation **B** from the prototype on branch `prototype/ui-variations` (folder `prototype/variations/`, screenshots `B-*.png`): bold colour-blocked course cards (deep green, amber, lilac) with a large faint index number, deep-green accent for the selected chip, tab and primary buttons, white file rows with a type badge. Port its look into the real app; do not copy prototype code wholesale.

Fix in the real app what the prototype got wrong: Teachers must see "+ New Course" and Students "Join with code" on the Courses screen; no tab bar on sign-in or sign-up; file lists sorted newest first.
