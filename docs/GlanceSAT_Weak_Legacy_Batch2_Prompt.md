# GlanceSAT — Weak Legacy Sentence Rewrite Prompt (Batch 2)

Copy everything below the line into your LLM chat.

---

You are an expert SAT vocabulary curriculum editor. Write replacement example sentences for **GlanceSAT**, an SAT vocab app.

## Your task

Rewrite **only the flagged sentence slot(s)** listed for each of the **41 words** below. Each word needs **1 or 2 new sentences** (see list). Do **not** rewrite slots that are not listed.

**Total output: 47 sentences** (35 words × 1 + 6 words × 2).

## Strict rules (every sentence must pass all)

1. **Length:** 10–15 words (hard max 15). Count carefully.
2. **Tone:** Sophisticated high-school / SAT reading-passage voice. Concrete academic, civic, literary, or professional context.
3. **No weak first-person:** Do **not** use **I, me, my, mine, we, our, us, you, your** in personal/anecdotal ways.
   - ❌ *I will not acquiesce…* · *My grandmother has a penchant…* · *You should take your car…*
   - ✅ Narrative collective *we* is OK only when literary (*We waited indoors for the howling winds to abate*) — when in doubt, use third person.
4. **Target word:** The exact vocabulary word must appear (inflections OK: *surmised*, *truncated*, *upbraided*).
5. **Correct sense:** Match the definition given. Do not use a different meaning.
   - ❌ *Recalcitrant hardware* (hardware cannot be defiant — word describes stubborn people/animals)
   - ❌ *a remiss error* (awkward — use *would be remiss*, *was remiss in*, *remiss to*)
6. **Context clues:** Show meaning through situation, contrast, or consequence — not dictionary glosses.
   - ❌ *Mundane, quotidian tasks constitute the primary routine…* (synonym stacking)
   - ❌ *Seminal papers define the foundation of modern research…* (too abstract/generic)
7. **No filler intensifiers:** Avoid *incredibly, completely, massive, very, deeply, often, immense, extreme, simply, truly*.
8. **PG-13:** No gore, sexual content, or disturbing violence.
9. **No duplicates:** Each of the 47 sentences must be distinct in structure and scenario.

## Output format (follow exactly)

For each word, use this block. Words needing **2 sentences** → first sentence replaces the **first** listed slot, second sentence the **second** slot.

```
Word

First sentence.

Second sentence.   ← omit this line if only 1 sentence needed
```

Separate words with a blank line. Numbering optional.

## Quality bar (study these)

**Strong (aim for this):**
- *The prosecution faced an implacable opposing counsel who refused every proposed plea arrangement.*
- *Forensic analysts worked overnight to ascertain the fire's precise point of origin.*
- *Officious clerks interrupt important meetings with constant and unnecessary requests for validation.*

**Weak (do not write like this):**
- *Human beings show a propensity for seeking patterns within complex visual stimuli.* (textbook-generic)
- *Recalcitrant hardware often requires advanced troubleshooting…* (wrong sense)
- *Raucous celebrations erupted after the championship title win this evening.* (vague, no scene)
- *It was presumptuous of him to assume I would pay…* (first-person)

---

## Word list — 41 words, 47 sentences

For each word: **definition · part of speech · slots to replace · count**

### Needs 2 sentences (6 words)

| Word | POS | Definition | Replace |
|------|-----|------------|---------|
| **Officious** | adjective | Asserting authority in annoying ways | `quizSentence`, then `exampleSentence` |
| **Quaint** | adjective | Attractively unusual or old-fashioned | `quizSentence`, then `exampleSentence` |
| **Remiss** | adjective | Lacking in required care | `quizSentence`, then `alternateExampleSentence` |
| **Surmise** | verb | To guess without evidence | `quizSentence`, then `exampleSentence` |
| **Tacit** | adjective | Understood without being stated | `quizSentence`, then `alternateExampleSentence` |
| **Vex** | verb | To cause deep persistent annoyance | `quizSentence`, then `exampleSentence` |

### Needs 1 sentence (35 words)

| Word | POS | Definition | Replace |
|------|-----|------------|---------|
| **Paradigm** | noun | A typical example or pattern | `alternateExampleSentence` |
| **Paramount** | adjective | More important than anything else | `exampleSentence` |
| **Pellucid** | adjective | Translucently clear | `quizSentence` |
| **Penchant** | noun | A strong or habitual liking | `quizSentence` |
| **Perfunctory** | adjective | Carried out with minimum effort | `quizSentence` |
| **Pertinacious** | adjective | Holding firmly to an opinion | `exampleSentence` |
| **Pervasive** | adjective | Spreading widely throughout an area | `exampleSentence` |
| **Pragmatic** | adjective | Dealing with matters practically | `quizSentence` |
| **Presumptuous** | adjective | Failing to observe acceptable limits | `quizSentence` |
| **Procure** | verb | To carefully obtain or secure | `quizSentence` |
| **Propensity** | noun | A natural behavioral tendency | `quizSentence` |
| **Prudence** | noun | Cautious and careful management | `alternateExampleSentence` |
| **Quotidian** | adjective | Occurring every day; ordinary | `quizSentence` |
| **Rash** | adjective | Acting without careful consideration | `quizSentence` |
| **Raucous** | adjective | Disturbingly loud | `quizSentence` |
| **Recalcitrant** | adjective | Uncooperative, stubborn (people/animals) | `quizSentence` |
| **Recapitulate** | verb | To summarize and restate | `quizSentence` |
| **Relish** | verb | To enjoy greatly | `quizSentence` |
| **Renovate** | verb | To restore or repair | `quizSentence` |
| **Reputable** | adjective | Having a trusted reputation | `quizSentence` |
| **Ruse** | noun | A clever deceptive trick | `alternateExampleSentence` |
| **Satiate** | verb | To satisfy fully (appetite/desire) | `quizSentence` |
| **Seminal** | adjective | Strongly influencing later developments | `exampleSentence` |
| **Taciturn** | adjective | Saying little; reserved | `quizSentence` |
| **Tedious** | adjective | Too dull and long | `exampleSentence` |
| **Tranquil** | adjective | Free from disturbance | `quizSentence` |
| **Trepidation** | noun | Fear or anxiety about something future | `quizSentence` |
| **Truncate** | verb | To shorten by cutting | `quizSentence` |
| **Turgid** | adjective | Swollen; or pompous/overblown prose | `quizSentence` |
| **Ubiquitous** | adjective | Found everywhere | `exampleSentence` |
| **Umbrage** | noun | Offense or annoyance | `quizSentence` |
| **Unctuous** | adjective | Excessively flattering | `exampleSentence` |
| **Upbraid** | verb | To scold severely | `quizSentence` |
| **Vacillate** | verb | To waver between choices | `quizSentence` |
| **Zephyr** | noun | A soft gentle breeze | `alternateExampleSentence` |

---

## Sentences being replaced (for reference — do not reuse phrasing)

**Officious** [quiz]: *An officious security guard demanded to check my ID three times in ten minutes.*  
**Officious** [example]: *The officious clerk insisted on checking my identification three separate times today.*

**Quaint** [quiz]: *We stayed in a quaint little bed-and-breakfast covered in climbing ivy.*  
**Quaint** [example]: *We stayed in a quaint cottage located in a small rural village.*

**Remiss** [quiz]: *I would be remiss if I didn't thank my wonderful parents for their endless support.*  
**Remiss** [alternate]: *It was remiss of me to forget your birthday during this week.*

**Surmise** [quiz]: *From his wet umbrella, I could easily surmise that it was raining outside.*  
**Surmise** [example]: *I can only surmise that he was late because of the traffic.*

**Tacit** [quiz]: *My boss gave a tacit nod of approval when I suggested leaving the office early.*  
**Tacit** [alternate]: *He gave a tacit nod to show that he agreed with me.*

**Vex** [quiz]: *The difficult crossword puzzle continued to vex me for the entire morning.*  
**Vex** [example]: *The constant noise from the neighbor's house continues to vex me daily.*

**Paradigm** [alternate]: *She challenged the current paradigm regarding how we teach advanced software engineering.*

**Paramount** [example]: *It is of paramount importance that we finish the project by Friday.*

**Pellucid** [quiz]: *(already strong — may keep or lightly polish)*

**Penchant** [quiz]: *My grandmother has a well-known penchant for buying unnecessarily expensive shoes.*

**Perfunctory** [quiz]: *The bored cashier gave a perfunctory nod as she handed back my receipt.*

**Pertinacious** [example]: *The pertinacious salesman refused to leave until I bought his new product.*

**Pervasive** [example]: *The use of mobile phones is pervasive in our modern digital society.*

**Pragmatic** [quiz]: *We need a pragmatic solution to this budget crisis, not just unrealistic wishful thinking.*

**Presumptuous** [quiz]: *It was presumptuous of him to assume I would pay for his expensive dinner.*

**Procure** [quiz]: *I need to procure some rare spices before I can cook this authentic Indian dish.*

**Propensity** [quiz]: *My clumsy brother has a propensity for dropping his phone and cracking the screen.*

**Prudence** [alternate]: *Prudence dictates that we should wait for more data before investing money.*

**Quotidian** [quiz]: *Checking my email and making coffee are part of my quotidian morning routine.*

**Rash** [quiz]: *(already third-person — may keep or upgrade context)*

**Raucous** [quiz]: *A raucous party next door kept me awake until three in the morning.*

**Recalcitrant** [quiz]: *The recalcitrant horse refused to enter the trailer no matter how hard we pulled.* ← good sense; just drop I/we

**Recapitulate** [quiz]: *Let me briefly recapitulate the main points of the presentation before we conclude.*

**Relish** [quiz]: *I always relish the opportunity to sleep in late on a rainy Sunday morning.*

**Renovate** [quiz]: *We hired a contractor to entirely renovate our outdated 1970s kitchen.*

**Reputable** [quiz]: *You should always take your car to a reputable mechanic rather than a shady garage.*

**Ruse** [alternate]: *It was just a ruse to get me to reveal the secret.*

**Satiate** [quiz]: *A heavy bowl of oatmeal is usually enough to satiate my hunger until lunchtime.*

**Seminal** [example]: *(decent — upgrade to specific field/paper if possible)*

**Taciturn** [quiz]: *My grandfather is a taciturn man who prefers quiet whittling to making idle conversation.*

**Tedious** [example]: *The project was tedious and took much longer than we had planned.*

**Tranquil** [quiz]: *We spent a tranquil evening sipping wine on the porch and listening to the crickets.*

**Trepidation** [quiz]: *I opened the letter from the IRS with a profound sense of trepidation.*

**Truncate** [quiz]: *We had to truncate our beach vacation by two days because a hurricane was approaching.*

**Turgid** [quiz]: *(already strong)*

**Ubiquitous** [example]: *Digital screens have become ubiquitous in our modern and busy urban society.*

**Umbrage** [quiz]: *He took immediate umbrage at my suggestion that his painting looked like a child's drawing.*

**Unctuous** [example]: *The unctuous salesman tried to charm me into buying the expensive car.*

**Upbraid** [quiz]: *My mother will certainly upbraid me if I track muddy footprints across her clean floor.*

**Vacillate** [quiz]: *I continue to vacillate between ordering the steak or the salmon for dinner.*

**Zephyr** [alternate]: *We enjoyed the cool zephyr while sitting on the deck at night.*

---

## Final checklist before you submit

- [ ] Exactly **41 words**, **47 sentences**
- [ ] Every sentence **10–15 words**
- [ ] **No** casual I / my / you / your
- [ ] **Recalcitrant** = stubborn defiance (person, animal, faction) — not machines
- [ ] **Remiss** used as adjective (*was remiss to…*, *would be remiss*) — not *a remiss error*
- [ ] Varied settings: courts, labs, diplomacy, archives, medicine, journalism — not all generic office sentences
- [ ] Each sentence could plausibly appear in an SAT reading passage

Write all 41 words now.
