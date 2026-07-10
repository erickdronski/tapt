# Tapt, Design & Motion Strategy

The plan for making Tapt look and feel like a team of engineers and designers
spent months on it: expensive, heavy, smooth, alive. Design is not decoration
here; it is the retention mechanic. Every surface earns attention, rewards it
with motion, and connects to the next.

## Principles (the non-negotiables)
1. **One signature object: the pint.** The beer glass is the brand. It is the
   app icon, the hero, the loaders, the empty states. It must be identical in
   spirit everywhere (centered, foam dome, gold gradient, shine). Consistency
   is what reads as "expensive."
2. **Motion means life, not noise.** Everything enters (fade + rise), responds
   to touch (spring scale), and rewards action (haptics, splash, count-ups).
   Nothing is static; nothing is gratuitous. Respect reduced-motion.
3. **Depth, not flatness.** Layered gradients, double shadows (tight key + soft
   ambient), rim lights, subtle glows. Flat = cheap.
4. **Dopamine architecture.** Put the reward early and often: the pour animation
   on open, the vote that visibly moves the board, the BOW crown, the passport
   stamp, the level-up haptic. Short loops, quick payoffs.
5. **Honest beauty.** Real data, real photos, honest-empty states made gorgeous.
   Blank beats invented, and a beautiful empty state beats a fake full one.

## Palette & type (single source: docs/06 + Theme.swift)
Pour Gold #F2A900 · Malt Black #1A1206 · Foam #FBF6EC · Fresh Hop #3F8F5B ·
Copper #B4531F. Poppins/Inter on web, SF-rounded in app. Tabular figures for
all the numbers (ratings, ABV, counts).

## What shipped (this wave)
- **New app icon**: clean centered pint, centered foam dome, gold gradient,
  shine, bubbles, premium dark bg. Removed the tilt, the crammed "T", and the
  confusing green hop leaf. Opaque 1024 for App Store.
- **Landing hero glass**: replaced the flat rectangle with an SVG pint that
  matches the icon exactly (pour animation, rising bubbles, foam dome, glow,
  gentle float) so icon -> hero -> app are one object.
- **Scroll-reveal motion** on the landing (fade + rise, staggered in grids,
  IntersectionObserver, reduced-motion safe).
- **App motion system** (prior waves, live): BeerGlassView, TaptHeroPanel v2,
  shimmer skeletons, TaptPressStyle, haptics, collapsibles.

## Multi-wave design plan (forward)
### Wave 1, Consistency & the glass (mostly done)
- [x] Icon, landing hero glass, scroll-reveal.
- [ ] Make the in-app BeerGlassView foam a centered dome to match the icon
  exactly (currently irregular blobs).
- [ ] Favicon + OG image from the new icon.
- [ ] Portal/admin/menu/pitch pages inherit the reveal motion + glass accents.

### Wave 2, Signature moments (the dopamine beats)
- Pour-to-log animation: logging a beer fills a glass and stamps the passport
  in one satisfying sequence.
- Vote feedback: the board tile physically bumps and the number count-ups when
  a vote lands (partially there; make it a hero moment).
- BOW crown reveal: a weekly winner animation worth screenshotting.
- Level-up / badge unlock: confetti-light + haptic on passport milestones.

### Wave 3, Depth & texture pass
- Consistent double-shadow system across all cards.
- Subtle grain/paper texture on the Foam background (premium, tactile).
- Beer-page hero: the label photo or SRM glass with a parallax tilt.
- Custom iconography pass (replace generic SF Symbols on hero surfaces with
  brand glyphs where it counts).

### Wave 4, Delight & retention
- App-open micro-animation (the pour) that varies subtly so it never feels rote.
- Streak / return rewards designed as motion moments.
- Share cards: motion-designed export templates (already static; animate).
- Onboarding: a guided, cinematic first-run that teaches by doing.

## The rule of thumb
If a screen feels flat, add one layer of depth and one moment of motion. If it
feels busy, remove a color and calm the motion. Expensive is the balance of the
two, restrained depth, purposeful movement, one hero object.
