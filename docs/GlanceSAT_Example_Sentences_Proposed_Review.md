# Proposed example-sentence replacements (review)

**Status:** Applied to `Database.json` (approved).

**Scope:** 32 vocabulary rows from the weak/broken example audit (30 headwords + 2 extra sense rows for Advocate and Coup).

**Targets:** SAT-useful, trust-first tone; **10–16 words**; headword present; distinct from each row’s `quizSentence` where possible (widgets/carousel use `exampleSentence`; quizzes use `quizSentence`).

**Also proposed:** Truncated `definition` fix for **Fabricate** (§G / display-safety).

---

## How to review

- [x] Approved and applied to `Database.json` (36 field updates).

---

## Broken rows (6)

### Fabricate

| | |
|---|---|
| **Issue** | Example uses *façade*, not *fabricate*; definition truncated in DB |
| **Current example** | Despite my smiling façade, I am feeling melancholy. |
| **Current definition** | To make up, invent (When I arrived an hour late to. |
| **Quiz sentence** | The dishonest employee tried to fabricate an elaborate excuse for missing the big meeting. |
| **Proposed example** (12w) | The witness was caught trying to fabricate details about the robbery. |
| **Proposed definition** (≤60) | To make up or invent falsely |

### Incessant

| | |
|---|---|
| **Issue** | Typo: `incessantrain` |
| **Current example** | We wanted to go outside and play, but the incessantrain kept us indoors for two days. |
| **Quiz sentence** | The incessant dripping of the leaky faucet kept me awake all night. |
| **Proposed example** (13w) | The incessant noise from the construction site made it hard to concentrate. |

### Mendacious

| | |
|---|---|
| **Issue** | Typo: `mendaciouscontent` |
| **Current example** | The mendaciouscontent of the tabloid magazines is at least entertaining. |
| **Quiz sentence** | The mendacious car salesman lied about the vehicle's accident history. |
| **Proposed example** (12w) | Journalists exposed the mendacious claims in the politician's campaign ads. |

### Scrupulous

| | |
|---|---|
| **Issue** | Typo: `scrupulouscare` |
| **Current example** | With scrupulouscare, Sam cut a snowflake out of white paper. |
| **Quiz sentence** | The scrupulous accountant caught an error of merely three cents in the massive ledger. |
| **Proposed example** (13w) | A scrupulous editor checked every citation before the article went to press. |

### Exasperate

| | |
|---|---|
| **Issue** | Typo: `roomate` |
| **Current example** | George’s endless complaints exasperated his roomate. |
| **Quiz sentence** | The toddler's constant screaming began to seriously exasperate the exhausted babysitter. |
| **Proposed example** (12w) | His habit of interrupting every sentence began to exasperate the panel. |

### Amicable

| | |
|---|---|
| **Issue** | Headword missing (only *amicably*); awkward syntax |
| **Current example** | Claudia and Jimmy got divorced, but amicably and without hard feelings. |
| **Quiz sentence** | Despite the breakup, they managed to reach an amicable agreement. |
| **Proposed example** (12w) | The rival teams reached an amicable settlement after the disputed game. |

---

## Weak / below-standard examples (25)

### Abduct

| **Current** | The evildoers abducted the fairy princess from her happy home. |
| **Quiz** | The sci-fi movie featured aliens trying to abduct an unsuspecting farmer. |
| **Proposed** (13w) | Authorities feared the cartel would abduct the journalist before the trial. |

### Abhor

| **Current** | After repeatedly injuring himself, Oswald began to abhor playing soccer. |
| **Quiz** | Pacifists inherently abhor any form of physical violence. |
| **Proposed** (11w) | Many voters abhor policies that strip funding from public schools. |

### Abide

| **Current** | Though he did not agree with the decision, Chuck decided to abide by it. |
| **Quiz** | Everyone in the building must abide by the new fire regulations. |
| **Proposed** (12w) | Referees must abide by the league rules even under heavy pressure. |

### Abject

| **Current** | After losing all her money, falling into a puddle, and breaking her ankle, Eloise was abject. |
| **Quiz** | The abandoned puppy was found shivering in abject misery. |
| **Proposed** (12w) | Refugees lived in abject poverty after fleeing the devastated region. |

### Abjure

| **Current** | To prove his honesty, the President abjured the evil policies of his wicked predecessor. |
| **Quiz** | To gain citizenship, you must abjure allegiance to your former nation. |
| **Proposed** (12w) | The defendant agreed to abjure violence as a condition of release. |

### Abstain

| **Current** | When everyone demanded he wear the kilt, Angus abstained and refused. |
| **Quiz** | I will abstain from voting on this issue due to a conflict of interest. |
| **Proposed** (13w) | Several board members chose to abstain when the contract came to a vote. |

### Accessible

| **Current** | After a strong SAT score, Marlena realized an Ivy League school was accessible. |
| **Quiz** | The new ramp makes the library accessible to wheelchair users. |
| **Proposed** (12w) | Clear diagrams make the complex proof accessible to younger students. |

### Accolade

| **Current** | Everyone offered accolades to Sam after he won the Nobel Prize. |
| **Quiz** | Winning the Nobel Prize is the highest accolade a scientist can achieve. |
| **Proposed** (12w) | The film earned the highest accolade at the international festival. |

### Acrimony

| **Current** | Despite their vow of friendship, acrimony eventually overwhelmed Biff and Trevor. |
| **Quiz** | The bitter divorce was filled with endless acrimony and shouting. |
| **Proposed** (12w) | Years of acrimony finally destroyed the partnership between the founders. |

### Acute

| **Current** | Arnold could not walk because the pain in his foot was so acute. |
| **Quiz** | The patient complained of an acute pain in his lower back. |
| **Proposed** (12w) | The factory faces an acute shortage of skilled technicians this quarter. |

### Advocate

Primary sense in DB is **verb**; quiz sentence uses **noun** (acceptable split: example = verb, quiz = noun).

| Field | Current | Proposed |
|-------|---------|----------|
| **Top-level `exampleSentence`** | Arnold advocated turning left at the stop sign, though everyone else favored turning right. | Community leaders advocate for stricter safety standards near the highway. (11w) |
| **`senses[0]` (verb)** | Arnold advocated turning left at the stop sign, even though everyone else thought we should turn right. | Same as top-level proposed. |
| **`senses[1]` (noun)** | In addition to wanting to turn left at every stop sign, Arnold was also a great advocate of increasing national defense spending. | She became a fierce advocate for expanding access to mental health care. (13w) |
| **Quiz** | She works as an advocate for children with learning disabilities. | — |

### Alacrity

| **Current** | When his mother asked him to set the table, Chuck did so with alacrity. |
| **Quiz** | She accepted the exciting job offer with impressive alacrity. |
| **Proposed** (13w) | The volunteers responded with alacrity when the shelter asked for help. |

### Amenity

| **Current** | Bill Gates's house is stocked with amenities, so he rarely must do anything himself. |
| **Quiz** | A heated swimming pool is a lovely amenity at this resort. |
| **Proposed** (12w) | Free Wi-Fi has become a standard amenity in most business-class hotels. |

### Circumvent

| **Current** | Students circumvented the dress code by covering navel-baring jeans with long coats near administrators. |
| **Quiz** | Hackers found a clever way to circumvent the company's new firewall. |
| **Proposed** (13w) | Lobbyists tried to circumvent the new ethics law through a legal loophole. |

### Compensate

| **Current** | Reginald bought Sharona a dress to compensate her for the one he'd spilled ice cream on. |
| **Quiz** | The airline agreed to compensate the passengers for the delayed flight. |
| **Proposed** (12w) | The court ordered the company to compensate workers for unpaid overtime. |

### Condolence

| **Current** | Brian lamely offered his condolences on the loss of his sister’s roommate’s cat. |
| **Quiz** | I sent a heartfelt card to express my condolence for her loss. |
| **Proposed** (12w) | She wrote a brief note of condolence to the grieving family. |

### Consonant

| **Current** | The singers’ consonant voices were beautiful. *(musical homograph; mismatches SAT “in agreement” sense)* |
| **Quiz** | His charitable actions are entirely consonant with his deep religious beliefs. |
| **Proposed** (13w) | Her public actions are consonant with the principles she defends in speeches. |

### Coup

Primary sense in DB is **“brilliant, unexpected act”** (not overthrow); quiz uses **government overthrow**.

| Field | Current | Proposed |
|-------|---------|----------|
| **Top-level `exampleSentence`** | Alexander's coup was getting a date with Cynthia by letting her car hit him on purpose. | Pulling off the merger on such short notice was a remarkable coup for the firm. (14w) |
| **`senses[0]`** (feat / triumph) | Alexander pulled off an amazing coup when he got a date with Cynthia by purposely getting hit by her car. | Same as top-level proposed. |
| **`senses[1]`** (overthrow) | In their coup attempt, the army officers stormed the Parliament and took all the legislators hostage. | The sudden coup toppled the elected government within a single night. (12w) |
| **Quiz** | The military generals staged a sudden coup and overthrew the democratic government. | — |

### Culpable

| **Current** | He was culpable of the crime, and was sentenced to perform community service for 75 years. |
| **Quiz** | The investigation determined that the driver was culpable for the tragic accident. |
| **Proposed** (12w) | The audit found managers culpable for failing to report the fraud. |

### Extol

| **Current** | Violet extolled the virtues of a vegetarian diet to her meatloving brother. |
| **Quiz** | The nutritionist continues to extol the massive health benefits of eating dark leafy greens. |
| **Proposed** (12w) | Critics extol the novel for its precise prose and moral complexity. |

### Platitude

| **Current** | After rereading her paper, Helene realized her insights were mere platitudes. |
| **Quiz** | "Everything happens for a reason" is a tired platitude that rarely comforts a grieving person. |
| **Proposed** (12w) | His speech offered only platitudes instead of a concrete policy plan. |

### Portent

| **Current** | When a black cat crossed her path, my sister read it as a portent of failure. |
| **Quiz** | A black cat crossing your path is considered an unlucky portent in many cultures. |
| **Proposed** (12w) | The dark clouds were a portent of the severe storm that followed. |

*Note:* Example and quiz both avoid repeating the same black-cat image.

### Regurgitate

| **Current** | Feeling sick, Chuck regurgitated his dinner. |
| **Quiz** | The mother bird will chew the worms and regurgitate them for her hungry chicks. |
| **Proposed** (12w) | Students who only regurgitate facts often struggle on inference questions. |

### Reproach

| **Current** | Brian reproached the customer for failing to rewind the video he had rented. |
| **Quiz** | Her spotless professional record is completely beyond any reproach. |
| **Proposed** (14w) | She did not reproach him publicly, but her silence carried clear disapproval. |

*Note:* Quiz uses noun *reproach*; proposed example uses verb (matches primary definition “To scold, disapprove”).

### Trite

| **Current** | Keith fancied himself learned, but others found his observations trite and repetitive. |
| **Quiz** | The commencement speech was full of trite advice like "follow your dreams" and "reach for the stars." |
| **Proposed** (12w) | The review dismissed the film's plot as trite and entirely predictable. |

---

## Optional: trim 9 quiz sentences (17–18 words)

Not included in this pass (examples only). Say the word if you want proposed trims for: **Nadir, Ostensible, Ruminate, Temerity, Tenuous, Tortuous, Trite, Wistful, Zenith**.

---

## Summary

| Category | Count |
|----------|------:|
| Broken + weak headwords | 30 |
| Extra sense rows (Advocate ×1, Coup ×1) | 2 |
| Definition fix (Fabricate) | 1 |

**After you approve:** apply patches to `GlanceSAT/GlanceSAT/Database.json` only (no merge until then).
