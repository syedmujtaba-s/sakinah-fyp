# Regression Report

- Threshold: `SCORE_THRESHOLD = 0.35`
- Total cases: 101
- Dataset: 369 stories / 1110 chunks

## Phase A — retrieval-only

Pass rate: **80/100 (80.0%)**

### Phase A pass rate by emotion

| Emotion | Passed | Total | % |
|---|---:|---:|---:|
| anxious | 2 | 5 | 40% |
| embarrassed | 3 | 6 | 50% |
| stressed | 4 | 7 | 57% |
| confused | 3 | 5 | 60% |
| fearful | 3 | 5 | 60% |
| rejected | 3 | 5 | 60% |
| overwhelmed | 4 | 6 | 67% |
| lonely | 5 | 6 | 83% |
| lost | 5 | 6 | 83% |
| hopeless | 17 | 18 | 94% |
| happy | 7 | 7 | 100% |
| sad | 8 | 8 | 100% |
| angry | 5 | 5 | 100% |
| grateful | 5 | 5 | 100% |
| guilty | 6 | 6 | 100% |

### Top-1 score distribution (Phase A)

- min: 0.238
- p25: 0.372
- p50: 0.443
- p75: 0.506
- max: 0.718

### Phase A failures (20)

- **anxious_01_exam** (anxious) — score `0.376891553401947` → `The News of Badr Reaches Madinah: Joy and Celebration`
  - entry: _I have my final exam tomorrow and I have not slept in two days. My heart is racing and I keep thinking I am going to fail and disappoint my _
  - FAIL `min_top_score`: expected 0.4 got 0.376891553401947

- **anxious_02_interview** (anxious) — score `0.29989415407180786` → `The Hiatus Between the First and Second Revelation`
  - entry: _I have a big interview in the morning. I keep rehearsing answers and none feel good enough. What if they see through me? What if I freeze?_
  - FAIL `min_top_score`: expected 0.35 got 0.29989415407180786

- **anxious_05_children** (anxious) — score `0.32410427927970886` → `The Du'aa Al-Mustad'afeen: The Prophet's Prayer of the Oppressed`
  - entry: _My son is being bullied at school and I feel helpless. I lie awake at night worrying about him. I do not know how to protect him from the wo_
  - FAIL `min_top_score`: expected 0.35 got 0.32410427927970886

- **confused_02_career** (confused) — score `0.3232121765613556` → `Reconciliation with the Ansar After Hunayn`
  - entry: _I have two job offers. One pays more, the other aligns with my values. I keep flipping between them and losing sleep._
  - FAIL `min_top_score`: expected 0.35 got 0.3232121765613556

- **confused_05_direction** (confused) — score `0.32571732997894287` → `Reconciliation with the Ansar After Hunayn`
  - entry: _I do not know what to do with my life. Medicine? Business? My parents want one thing, my heart wants another, and I cannot tell which is rig_
  - FAIL `min_top_score`: expected 0.35 got 0.32571732997894287

- **lonely_05_married_lonely** (lonely) — score `0.3271121084690094` → `The Night Journey (Isra and Mi'raj)`
  - entry: _I am married but I feel completely alone. He is there but he is not there. I have never felt this lonely in my life._
  - FAIL `min_top_score`: expected 0.35 got 0.3271121084690094

- **stressed_01_deadline** (stressed) — score `0.3885071575641632` → `The Patience of Ayyub (Job)`
  - entry: _I have three major deliverables due this week and my team is short-staffed. I have not slept more than four hours in five days. I feel like _
  - FAIL `min_top_score`: expected 0.4 got 0.3885071575641632

- **stressed_02_debt** (stressed) — score `0.24475213885307312` → `The Patience of Ayyub (Job)`
  - entry: _The bills are piling up and I do not know how I will pay rent this month. I keep calculating numbers and they never add up. My chest is cons_
  - FAIL `min_top_score`: expected 0.35 got 0.24475213885307312

- **stressed_05_wedding** (stressed) — score `0.333929181098938` → `The Second Migration to Abyssinia`
  - entry: _Wedding planning is destroying me. Both families are fighting over every detail and I am in the middle trying to keep the peace. I cry every_
  - FAIL `min_top_score`: expected 0.35 got 0.333929181098938

- **fearful_02_diagnosis** (fearful) — score `0.3044210970401764` → `The First Revelation in the Cave of Hira`
  - entry: _The doctor used the word cancer today. I do not remember anything after that. I am scared of dying but more scared of suffering first._
  - FAIL `min_top_score`: expected 0.35 got 0.3044210970401764

- **fearful_05_future** (fearful) — score `0.31531059741973877` → `The Second Migration to Abyssinia`
  - entry: _I graduated six months ago and I have no job. I am running out of savings. I am scared I will end up a failure and disappoint everyone._
  - FAIL `min_top_score`: expected 0.35 got 0.31531059741973877

- **hopeless_01_repeated_failure** (hopeless) — score `0.3528556823730469` → `The News of Badr Reaches Makkah: Grief and Forbidden Mourning`
  - entry: _Another rejection today. Number 47. I do not know why I keep trying. Nothing I do is working. I feel like giving up on life plans entirely._
  - FAIL `min_top_score`: expected 0.4 got 0.3528556823730469

- **overwhelmed_02_grief_waves** (overwhelmed) — score `0.3028958737850189` → `Difficulties of the Muhajireen in Madinah`
  - entry: _Some days I am fine. Other days everything at once hits me and I cannot breathe. I do not know how to handle these waves._
  - FAIL `min_top_score`: expected 0.35 got 0.3028958737850189

- **overwhelmed_05_responsibility** (overwhelmed) — score `0.32707586884498596` → `Difficulties of the Muhajireen in Madinah`
  - entry: _My team depends on me, my parents depend on me, my wife depends on me. I have no space to be weak. I am about to break._
  - FAIL `min_top_score`: expected 0.35 got 0.32707586884498596

- **rejected_01_proposal** (rejected) — score `0.29587429761886597` → `Reconciliation with the Ansar After Hunayn`
  - entry: _My marriage proposal was turned down for the third time. She said she liked me but her family wanted someone else. I feel worthless._
  - FAIL `min_top_score`: expected 0.4 got 0.29587429761886597

- **rejected_03_job** (rejected) — score `0.26297539472579956` → `Reconciliation with the Ansar After Hunayn`
  - entry: _The company I really wanted rejected me after three rounds. They hired someone with less experience. I am questioning my entire worth._
  - FAIL `min_top_score`: expected 0.35 got 0.26297539472579956

- **embarrassed_01_public_mistake** (embarrassed) — score `0.26789188385009766` → `Abu Sufyan's Failed Mission to Renew the Treaty in Madinah`
  - entry: _I gave a presentation to senior management and completely blanked on the main slide. They were silent for ten seconds. I want to disappear._
  - FAIL `min_top_score`: expected 0.3 got 0.26789188385009766

- **embarrassed_03_social** (embarrassed) — score `0.27516597509384155` → `The Slander Against Aisha (RA)`
  - entry: _At the iftar I said something really stupid in front of everyone. They all laughed awkwardly. I have been replaying it for three days._
  - FAIL `min_top_score`: expected 0.3 got 0.27516597509384155

- **embarrassed_05_failure_public** (embarrassed) — score `0.23830090463161469` → `The Battle of Uhud`
  - entry: _At the family gathering everyone asked about my job and I had to say I still have nothing. My cousin's pity was worse than the question._
  - FAIL `min_top_score`: expected 0.3 got 0.23830090463161469

- **lost_01_purpose** (lost) — score `0.34711194038391113` → `The Conversion of Umar ibn al-Khattab`
  - entry: _I have money, a family, a career. Every box ticked. And yet I feel empty. I do not know what my purpose is anymore. Is this all there is?_
  - FAIL `min_top_score`: expected 0.4 got 0.34711194038391113

## Phase B — full pipeline

Pass rate: **56/56 (100.0%)**

### Crisis detection

- True positives: **13/13** crisis phrases triggered `crisis=true`
- False-positive guards: **3/3** benign phrases correctly NOT flagged

### Latency

- median: 464 ms
- p95: 2413 ms
- max: 2884 ms
