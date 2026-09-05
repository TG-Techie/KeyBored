<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# Bundled data

## `12dicts-3esl-lowercase.txt`

19,217 words. The `3esl` list from **12dicts version 6.0.2**, compiled by Alan Beale,
filtered to entries matching `[a-z]+` and sorted. 12dicts describes `3esl` as the core
American vocabulary common to three ESL dictionaries.

**Licence: public domain.** Alan Beale's own words, from `ReadMe.html` in the 12dicts
6.0.2 distribution, read directly rather than from a summary of it:

> The 12dicts lists were compiled by Alan Beale. I explicitly release them to the public
> domain, but request acknowledgment of their use. (Actually, the dependency of the
> 2of12inf list and the 2+2+3 lists on AGID prevents their release into the public
> domain. However, I do not impose any additional requirements on their use beyond those
> imposed by AGID and its sources, as described in agid.txt.)

`3esl` is not one of the AGID-dependent lists, so it is public domain outright. **This
file is the acknowledgment he requests**, and it is the reason the acknowledgment is a
file in the repository rather than a line in a commit message.

Downloaded 2026-09-05 from `http://downloads.sourceforge.net/wordlist/12dicts-6.0.2.zip`
(HTTP 200, 1,992,138 bytes).

### What was dropped, and why

2,660 of the 21,877 raw entries are not plain lowercase words and were filtered out:
1,453 multi-word phrases ("according to"), 613 hyphenated forms ("able-bodied"), 279
capitalised entries ("ABC", "Advent"), 89 with apostrophes ("Achilles' heel"), and the
rest carrying periods, colons or slashes ("abbr.", "A.D.").

None of them are typeable as a letter-only tap form, which is what the matcher consumes.
Contractions are handled instead by `EnglishLexicon.contractions`, where the tap form is
the apostrophe-free spelling and the insertion carries the apostrophe — a shape 3esl's
own apostrophe entries do not have.

### Why this list and not a bigger one

Under equal weighting, list size *is* the weighting: every extra obscure word is another
equal competitor for the same taps. SPEC.md section 5.4 adds frequency weighting later,
and until it does, a 19k core-vocabulary list predicts better than an 80k one.

When frequency weighting lands, 12dicts' `2+2+3frq` (33,260 words in usage-frequency
order, from the BYU corpus) is the obvious next candidate, because it carries the
ordering the weighting needs. **It is AGID-dependent and its terms are not established**:
`agid.txt` in the 6.0.2 distribution carries "Copyright 2000 by Kevin Atkinson" and a
pointer to `http://aspell.sourceforge.net/wl/`, and contains no grant of permission of
any kind. Establish AGID's actual licence before using it, rather than inferring one from
12dicts' sentence about it.
