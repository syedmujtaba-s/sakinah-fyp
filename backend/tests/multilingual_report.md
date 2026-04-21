# Phase C — Multilingual Retrieval Quality Report

- Total groups: **18**

## Score delta vs English (English score minus variant score)

Positive delta = English retrieves higher-scoring story than the variant.
Large positive delta = meaningful degradation for that language.

| Language | Groups | Avg delta | Max delta | Min delta | Same top story as EN |
|---|---:|---:|---:|---:|---|
| Roman Urdu | 16 | -0.034 | +0.178 | -0.175 | 3/16 |
| Urdu (native) | 2 | -0.010 | -0.003 | -0.018 | 2/2 |
| Hindi (Roman) | 2 | -0.022 | +0.024 | -0.068 | 1/2 |

## Recommendation

- Roman Urdu: avg delta **-0.034**, emotion-match rate **100%**, same-story rate 3/16 (19%, note: low same-story rate does NOT mean low quality — different-but-equally-relevant stories are normal) → **ACCEPTABLE** — Roman Urdu scores are within noise of English and emotion-match rate is high. Current embedder handles it.

## Per-group detail

### `sad_parent_death` — emotion: `sad`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.423 | The Loss of His Son Ibrahim | Y |
| Roman Urdu | 0.418 | The Prophet's Grief and Divine Consolation After Raj'i and Bir Ma'una | Y |
| Urdu (native) | 0.441 | The Loss of His Son Ibrahim | Y |

Delta vs EN: Roman Urdu: +0.005, Urdu (native): -0.018

### `anxious_exam` — emotion: `anxious`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.373 | The News of Badr Reaches Madinah: Joy and Celebration | Y |
| Roman Urdu | 0.484 | The News of Badr Reaches Madinah: Joy and Celebration | Y |
| Urdu (native) | 0.375 | The News of Badr Reaches Madinah: Joy and Celebration | Y |

Delta vs EN: Roman Urdu: -0.111, Urdu (native): -0.003

### `anxious_interview` — emotion: `anxious`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.300 | The Hiatus Between the First and Second Revelation | Y |
| Roman Urdu | 0.379 | The News of Badr Reaches Madinah: Joy and Celebration | Y |

Delta vs EN: Roman Urdu: -0.079

### `stressed_debt` — emotion: `stressed`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.245 | The Patience of Ayyub (Job) | Y |
| Roman Urdu | 0.402 | The Warning from Mount Safa | Y |

Delta vs EN: Roman Urdu: -0.157

### `stressed_caregiving` — emotion: `stressed`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.427 | The Patience of Ayyub (Job) | Y |
| Roman Urdu | 0.437 | The Warning from Mount Safa | Y |

Delta vs EN: Roman Urdu: -0.010

### `grateful_recovery` — emotion: `grateful`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.570 | The Prophet's Gratitude in Every Circumstance | Y |
| Roman Urdu | 0.544 | The Smile of the Prophet (PBUH) | Y |

Delta vs EN: Roman Urdu: +0.026

### `grateful_job` — emotion: `grateful`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.649 | Banu Mazhaj Accept Islam | Y |
| Roman Urdu | 0.567 | The Smile of the Prophet (PBUH) | Y |

Delta vs EN: Roman Urdu: +0.082

### `lonely_abroad` — emotion: `lonely`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.582 | The Night Journey (Isra and Mi'raj) | Y |
| Roman Urdu | 0.404 | The Night Journey (Isra and Mi'raj) | Y |

Delta vs EN: Roman Urdu: +0.178

### `lonely_home_far` — emotion: `lonely`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.424 | Difficulties of the Muhajireen in Madinah | Y |
| Roman Urdu | 0.382 | The Du'aa Al-Mustad'afeen: The Prophet's Prayer of the Oppressed | Y |

Delta vs EN: Roman Urdu: +0.041

### `guilty_past` — emotion: `guilty`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.706 | Ka'b bin Malik and the Three Who Stayed Behind | Y |
| Roman Urdu | 0.564 | The Loss of His Son Ibrahim | Y |

Delta vs EN: Roman Urdu: +0.143

### `hopeless_failure` — emotion: `hopeless`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.353 | The News of Badr Reaches Makkah: Grief and Forbidden Mourning | Y |
| Roman Urdu | 0.461 | The Journey to Ta'if | Y |

Delta vs EN: Roman Urdu: -0.108

### `fearful_future` — emotion: `fearful`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.315 | The Second Migration to Abyssinia | Y |
| Roman Urdu | 0.465 | Abu Dhar Ghifari Embraces Islam and Boldly Announces It at the Ka'bah | Y |

Delta vs EN: Roman Urdu: -0.150

### `overwhelmed_juggling` — emotion: `overwhelmed`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.428 | Difficulties of the Muhajireen in Madinah | Y |
| Roman Urdu | 0.421 | Bilal Calls the Adhan from the Roof of the Ka'bah | Y |

Delta vs EN: Roman Urdu: +0.007

### `codeswitch_mixed` — emotion: `stressed`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.417 | The Patience of Ayyub (Job) | Y |
| Roman Urdu | 0.507 | The Patience of Ayyub (Job) | Y |

Delta vs EN: Roman Urdu: -0.090

### `short_urdu_stressed` — emotion: `stressed`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.351 | The Patience of Ayyub (Job) | Y |
| Roman Urdu | 0.495 | The Warning from Mount Safa | Y |

Delta vs EN: Roman Urdu: -0.144

### `typo_urdu_anxious` — emotion: `anxious`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.329 | The News of Badr Reaches Madinah: Joy and Celebration | Y |
| Roman Urdu | 0.504 | Abu Dhar Ghifari Embraces Islam and Boldly Announces It at the Ka'bah | Y |

Delta vs EN: Roman Urdu: -0.175

### `hindi_sad` — emotion: `sad`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.507 | The Loss of His Son Ibrahim | Y |
| Hindi (Roman) | 0.483 | The Loss of His Son Ibrahim | Y |

Delta vs EN: Hindi (Roman): +0.024

### `hindi_grateful` — emotion: `grateful`

| Language | Top score | Top story | Emotion match |
|---|---:|---|:---:|
| English | 0.535 | The Prophet's Gratitude in Every Circumstance | Y |
| Hindi (Roman) | 0.603 | The Smile of the Prophet (PBUH) | Y |

Delta vs EN: Hindi (Roman): -0.068
