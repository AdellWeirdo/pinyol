# The games' pages: comments, votes and numbers

Every game on the site has a page, `juegos/<id>/` (and `ca/juegos/<id>/`, `en/juegos/<id>/`), made by
`site/gamepage.py` when the site is built. It shows the game, its card and these numbers:

| Number | Where it comes from |
|---|---|
| Visits | GoatCounter: the people who opened the game's page, in the three languages |
| Plays | GoatCounter: the event `partida/<id>`, sent by the web player when a game from the site starts |
| Time played | GoatCounter: the events `tiempo/<id>/<m>`, sent when the play passes 1, 2, 3, 5, 10... minutes |
| Likes | giscus: the reactions on the game's GitHub Discussion, except 👎 and 😕 |
| Comments | giscus: the comments on the game's Discussion, with their replies |
| In the ranking | its place by likes, then comments, then plays |

`tools/stats.py` gathers them once a day (`.github/workflows/stats.yml`, 05:17 UTC, or by hand from the Actions tab)
into `stats.json`, published on the branch `stats`. The page reads it from there when it opens
(`site/src/games.js`), and so does the home page for its ranking and its cover of the week: the game most voted that
week, or else the one most commented, or else one at random that has not been the cover in the last 8 weeks.
While the Library holds only the site author's games, the cover is IL·LUSTRES (`PIN` in `tools/stats.py`); the
first game someone else sends ends that, from the next week on.

The comments and votes are [giscus](https://giscus.app): a Discussion per game in the category *Juegos*, titled with
the game's id, made by giscus the first time someone comments or reacts. Commenting and voting need a GitHub account.
Nothing from giscus.app loads until someone presses *Ver los comentarios y votar*.

## Setting it up (once)

1. **Discussions:** in the repository's *Settings → General → Features*, tick *Discussions*.
2. **The category:** in *Discussions*, the pencil next to *Categories* → *New category*: name `Juegos`, format
   *Announcement* (only giscus and the maintainers start Discussions in it; anyone can comment and react).
3. **giscus:** install the app at <https://github.com/apps/giscus>, for this repository only.
4. **Its id:** open <https://giscus.app>, fill in `ipaud/pinyol` and choose the category *Juegos*: the snippet it
   shows has `data-category-id="DIC_..."`. Put that value in `GISCUS["category_id"]` in `site/gamepage.py`, build and
   publish the site. Until then the pages say the comments are on their way.
5. **Visits, plays and time played (optional):** in GoatCounter, *Settings → API* → a new key with only *Read
   statistics*; in the repository, *Settings → Secrets and variables → Actions* → a secret `GOATCOUNTER_TOKEN` with
   it. Without it those three numbers stay empty and the rest works.

Then run the workflow *stats* once from the Actions tab, so the numbers do not wait for the next morning.

## Moderating

The comments live in the repository's Discussions: hide, edit or delete them there, lock a Discussion to close it, or
block a user from the repository's settings. GitHub's own rules and reporting apply to everything said there.
