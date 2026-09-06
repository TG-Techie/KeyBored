<!-- Copyright 2026 Jonah Y-M (@TG-Techie) <jonah@tg-techie.com> -->
<!-- Licensed under the MIT License. See LICENSE at the repository root. -->
<!-- This file is permitted to be edited by AI models and agents. -->

# Bundled data

## `12dicts-2of12inf-lowercase.txt`

75,646 words. The `2of12inf` list from **12dicts version 6.0.2**, compiled by Alan Beale,
unioned with the `3esl` list this replaced, filtered to entries matching `[a-z]+` and
sorted.

`2of12inf` is the `2of12` core vocabulary **plus its inflections** — the plurals, the past
tenses and the `-ing` forms. That is the whole reason for it: the list it replaced had
`edit` but not `editing`, `cat` but not `cats`, `walk` but not `walked`.

Downloaded 2026-09-05 from `http://downloads.sourceforge.net/wordlist/12dicts-6.0.2.zip`
(HTTP 200, 1,992,138 bytes).

### Licence, which is not the same as the list it replaced

`3esl` was public domain outright. **`2of12inf` is not**, because it derives from Kevin
Atkinson's AGID, and AGID carries its own terms. They are permissive and they require an
acknowledgment, which is what this file is.

Alan Beale, from `ReadMe.html` in the 12dicts 6.0.2 distribution:

> The 12dicts lists were compiled by Alan Beale. I explicitly release them to the public
> domain, but request acknowledgment of their use. (Actually, the dependency of the
> 2of12inf list and the 2+2+3 lists on AGID prevents their release into the public
> domain. However, I do not impose any additional requirements on their use beyond those
> imposed by AGID and its sources, as described in agid.txt.)

Kevin Atkinson, from `agid.txt` in the same distribution, lines 105-118, read directly:

> Copyright 2000 by Kevin Atkinson
>
> Permission to use, copy, modify, distribute and sell this database, the associated
> scripts, the output created form the scripts and its documentation for any purpose is
> hereby granted without fee, provided that the above copyright notice appears in all
> copies and that both that copyright notice and this permission notice appear in
> supporting documentation. Kevin Atkinson makes no representations about the suitability
> of this array for any purpose. It is provided "as is" without express or implied
> warranty.

AGID's own sources carry two further notices, reproduced here because AGID's grant
requires the notices of what it is built from to travel with it. The Moby part-of-speech
database is public domain, in Grady Ward's words: "The Moby lexicon project is complete
and has been place into the public domain. Use, sell, rework, excerpt and use in any way
on any platform." And WordNet:

> WordNet 1.6 Copyright 1997 by Princeton University. All rights reserved.
>
> Permission to use, copy, modify and distribute this software and database and its
> documentation for any purpose and without fee or royalty is hereby granted, provided
> that you agree to comply with the following copyright notice and statements, including
> the disclaimer, and that the same appear on ALL copies of the software, database and
> documentation, including modifications that you make for internal use or for
> distribution.
>
> THIS SOFTWARE AND DATABASE IS PROVIDED "AS IS" AND PRINCETON UNIVERSITY MAKES NO
> REPRESENTATIONS OR WARRANTIES, EXPRESS OR IMPLIED. BY WAY OF EXAMPLE, BUT NOT
> LIMITATION, PRINCETON UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES OF MERCHANT-
> ABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF THE LICENSED SOFTWARE,
> DATABASE OR DOCUMENTATION WILL NOT INFRINGE ANY THIRD PARTY PATENTS, COPYRIGHTS,
> TRADEMARKS OR OTHER RIGHTS.
>
> The name of Princeton University or Princeton may not be used in advertising or
> publicity pertaining to distribution of the software and/or database.

An earlier version of this file said `agid.txt` "contains no grant of permission of any
kind" and told the next reader to establish AGID's licence before using it. That was
wrong, and it is recorded rather than quietly deleted: the grant is in the file, about
two thirds of the way down, under a heading of its own. The instruction was right and it
was followed — the file was read, and the grant is above.

### What was dropped, and why

**The 6,242 entries marked `%`.** 12dicts uses that suffix for plurals of uncountable
nouns — `abandonments`, `abasements`, `abeyances`. They are in the list to be complete
about a grammatical question, not because anybody types them, and every one of them is
another equal competitor for the same taps.

**The `!` marker was stripped and the word kept.** It marks a neologism from 12dicts'
`neol2016` list, which is a reason to keep a word rather than to drop it.

**Everything not `[a-z]+`.** The source list already excludes capitalised words, phrases,
abbreviations, contractions and hyphenated forms, so this filter removes almost nothing;
it is there because the matcher consumes letter-only tap forms and the guarantee should
be in code rather than in a claim about the file.

**Single-letter words were kept**, from the `3esl` side of the union. `2of12inf` excludes
them by its own criteria, and `a` and `i` are two of the commonest words in English.

Contractions are still handled by `EnglishLexicon.contractions`, where the tap form is
the apostrophe-free spelling and the insertion carries the apostrophe.

### Why the list grew fourfold, against the reasoning that kept it small

The version of this file written on 2026-09-05 argued for the small list, and the
argument was good: under equal weighting, list size *is* the weighting, so every extra
obscure word is another equal competitor for the same taps, and a 19k core-vocabulary
list predicts better than an 80k one until frequency weighting lands.

What that missed is which mistake each list makes. A word that is **absent** cannot be
offered, and worse, it cannot defend itself: the commit rule replaced what was typed
whenever a candidate came close enough, and a word not in the list has no entry of its own
to be close. Reported 2026-09-06, in his words: "It also make a bunch of poor corrections
like editinf to doting and/or often drooping an s to turn it into a wholehxdifferent
word", and separately, "there are some missing words". Both are this. `editing` was not in
the list, so `exciting` won it — reproduced on a simulator, in Safari's address field,
before the change.

So the trade is not "better ranking against worse ranking". It is "a word the user typed
survives" against "the bar's third bubble is sometimes an odd word". The second is a
disappointment and the first is corruption of text somebody wrote.

The change that makes the bigger list safe went in beside it: a literal that is itself in
the lexicon is never replaced, whatever the ranking says. With that rule, adding words can
only ever *reduce* the number of corrections applied to correctly typed words. SPEC.md
Appendix A.16.

Frequency weighting is still the real answer and is still unbuilt. When it lands, 12dicts'
`2+2+3frq` (33,260 words in BYU usage-frequency order) is the obvious candidate, and it is
AGID-dependent exactly as this list is, under the terms quoted above.
