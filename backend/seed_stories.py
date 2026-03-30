"""
Seed script: Inserts 20 Seerah stories into MongoDB and builds the vector index.

Usage:
    python seed_stories.py

This covers all 15 supported emotions with at least 2 stories each.
"""

import time
from dotenv import load_dotenv

load_dotenv()

from database import stories_collection, story_index_collection

SEED_STORIES = [
    # --- 1. The Year of Sorrow ---
    {
        "title": "The Year of Sorrow (Aam ul-Huzn)",
        "period": "10th Year of Prophethood",
        "emotions": ["sad", "lonely", "hopeless", "lost"],
        "summary": "The Prophet (PBUH) lost his beloved wife Khadijah and his protective uncle Abu Talib within days of each other, leaving him deeply grieved and without his two greatest supporters.",
        "story": "In the tenth year of prophethood, the Prophet Muhammad (PBUH) endured the most painful period of his life. His beloved wife Khadijah (RA), who had been his first believer, his confidante, and his source of comfort for 25 years, passed away. She was the one who had wrapped him in a blanket when he trembled after the first revelation, the one who said 'Never! By Allah, Allah will never disgrace you.' Just days later, his uncle Abu Talib, who had shielded him from the persecution of the Quraysh for years, also died. The Prophet (PBUH) was left without his emotional anchor and his political protector simultaneously. The Quraysh, now emboldened, increased their persecution. The Prophet (PBUH) called this period the Year of Sorrow. Yet even in this darkness, he did not lose faith. He turned to Allah with even greater devotion, and soon after, Allah honored him with the miraculous Night Journey (Isra and Mi'raj), showing him that divine comfort comes when human comfort is taken away.",
        "lessons": [
            "Grief is a natural human experience that even the best of creation went through deeply",
            "Losing the people we love most does not mean Allah has abandoned us",
            "The darkest moments often precede the greatest divine gifts and openings"
        ],
        "practical_advice": [
            "Allow yourself to feel the grief without guilt — the Prophet (PBUH) openly mourned his losses",
            "Make sincere dua in sujood (prostration) pouring out your heart to Allah",
            "Remember that after every hardship comes ease, just as the Night Journey followed the Year of Sorrow"
        ]
    },

    # --- 2. The Cave of Thawr ---
    {
        "title": "The Cave of Thawr",
        "period": "13th Year of Prophethood (Hijrah)",
        "emotions": ["anxious", "fearful", "stressed"],
        "summary": "During the Hijrah migration, the Prophet (PBUH) and Abu Bakr hid in a cave while enemies searched for them just feet away, and the Prophet calmed his companion with complete trust in Allah.",
        "story": "When the Quraysh plotted to assassinate the Prophet Muhammad (PBUH), he and Abu Bakr (RA) secretly left Makkah at night, heading toward Madinah. To evade their pursuers, they took refuge in the Cave of Thawr on a mountain south of Makkah. The Quraysh sent trackers who followed their trail right to the mouth of the cave. Abu Bakr (RA), hearing the footsteps and voices of the enemy just outside, was terrified. He whispered to the Prophet (PBUH), 'If any of them looks down at their feet, they will see us!' But the Prophet (PBUH), with calm certainty, replied: 'What do you think of two people whose third companion is Allah? Do not grieve; indeed Allah is with us.' A spider had spun its web across the cave entrance, and a bird had built its nest there, making the trackers conclude no one had entered recently. They turned back. The Prophet (PBUH) and Abu Bakr remained in the cave for three days before safely continuing their journey to Madinah.",
        "lessons": [
            "Anxiety is a natural human response, even the greatest companions felt it",
            "True peace comes from trusting that Allah is always with you, even in the tightest spots",
            "When you have done your best (taken practical precautions), leave the rest to Allah"
        ],
        "practical_advice": [
            "When anxiety overwhelms you, pause and repeat: 'Hasbunallahu wa ni'mal wakil' (Allah is sufficient for us and He is the best disposer of affairs)",
            "Take practical steps to address your worry, then consciously release the outcome to Allah",
            "Find a quiet space, close your eyes, and take deep breaths while remembering that Allah is with you right now"
        ]
    },

    # --- 3. The Journey to Ta'if ---
    {
        "title": "The Journey to Ta'if",
        "period": "10th Year of Prophethood",
        "emotions": ["rejected", "sad", "hopeless"],
        "summary": "After losing his protectors in Makkah, the Prophet (PBUH) traveled to Ta'if seeking support, but the people mocked him, sent their children to stone him until he bled, yet he responded with a heartfelt prayer and refused to curse them.",
        "story": "After the deaths of Khadijah and Abu Talib, the Prophet Muhammad (PBUH) traveled to the nearby city of Ta'if, hoping its people would accept his message and offer him protection. Instead, the leaders of Ta'if rejected him harshly and mockingly. They then sent the street children and youth to chase him out of the city, pelting him with stones. The Prophet (PBUH) was struck so severely that his sandals filled with blood. Exhausted and wounded, he took shelter in a garden outside the city. There, bleeding and alone, he raised his hands and made one of the most beautiful and vulnerable duas ever recorded: 'O Allah, to You alone I complain of my weakness, my lack of resources, and my lowliness before the people. You are the Lord of the weak, and You are my Lord. To whom will You entrust me?' Allah then sent the Angel of the Mountains, offering to crush the people of Ta'if between two mountains. But the Prophet (PBUH) refused, saying: 'No, perhaps Allah will bring from their descendants people who will worship Him alone.' This was the height of mercy in the face of rejection.",
        "lessons": [
            "Rejection does not define your worth — the greatest human was rejected too",
            "Your response to rejection reveals your character — choose mercy over bitterness",
            "When the whole world turns against you, you still have Allah to turn to"
        ],
        "practical_advice": [
            "When you feel rejected, turn to Allah in a private conversation — pour out your heart like the Prophet did at Ta'if",
            "Do not let the rejection of people make you bitter; instead pray for those who hurt you",
            "Remember that rejection is often redirection — the Prophet was rejected at Ta'if but welcomed at Madinah"
        ]
    },

    # --- 4. The Bedouin in the Masjid ---
    {
        "title": "The Bedouin in the Masjid",
        "period": "Madinah Period",
        "emotions": ["angry", "stressed"],
        "summary": "When a Bedouin man urinated in the Prophet's mosque, the companions became furious, but the Prophet (PBUH) calmly stopped them and gently educated the man, teaching that gentleness achieves what anger cannot.",
        "story": "One day in the Prophet's Mosque in Madinah, a Bedouin man who was unfamiliar with mosque etiquette stood up and began urinating in a corner of the masjid. The companions were outraged and rushed toward him to stop him forcefully. The Prophet Muhammad (PBUH) immediately called out: 'Leave him alone! Do not interrupt him.' He waited until the man had finished, then calmly asked for a bucket of water to be poured over the spot. He then turned to the Bedouin gently and said: 'These mosques are not the place for urine or filth; they are for the remembrance of Allah and prayer.' The Bedouin, moved by this gentle treatment when he expected punishment, later said: 'May my mother and father be sacrificed for him. He did not scold me or insult me.' The companions learned a powerful lesson that day: that the Prophet's anger was always controlled, and that gentleness achieves what harshness never could.",
        "lessons": [
            "Anger is a natural reaction, but responding with wisdom is a choice and a skill",
            "Gentleness in correction is more effective than harsh punishment",
            "The Prophet (PBUH) controlled his anger even when he had every right to be upset"
        ],
        "practical_advice": [
            "When anger rises, pause before reacting — the Prophet advised: 'If you are angry, sit down. If still angry, lie down'",
            "Perform wudu (ablution) to cool the fire of anger — water extinguishes fire, both physical and emotional",
            "Before responding in anger, ask yourself: 'What would the Prophet do in this situation?'"
        ]
    },

    # --- 5. The Smile of the Prophet ---
    {
        "title": "The Smile of the Prophet (PBUH)",
        "period": "Throughout His Life",
        "emotions": ["happy", "grateful"],
        "summary": "Despite carrying the immense burden of prophethood, the Prophet (PBUH) was known as the most smiling person among his companions, teaching that joy and gratitude are acts of worship.",
        "story": "The companions consistently described Prophet Muhammad (PBUH) as the person who smiled the most among them. Abdullah ibn Harith (RA) said: 'I have never seen anyone who smiled more than the Messenger of Allah.' Despite the heavy responsibilities of leading a nation, dealing with enemies, and worrying about his ummah, the Prophet (PBUH) made it a point to spread joy through his warm smile. He said: 'Your smiling in the face of your brother is charity.' He would greet everyone with a beaming face, making each person feel as though they were the most important person in the room. Jarir ibn Abdullah (RA) said: 'The Prophet never refused to see me after I embraced Islam, and he never looked at me except with a smile.' This was not superficial cheerfulness — it was a deep spiritual practice. The Prophet found joy in gratitude to Allah, in the blessings of companionship, in the beauty of nature, and in simple everyday moments. He taught that expressing happiness and gratitude is itself an act of worship.",
        "lessons": [
            "Joy and smiling are forms of worship and charity in Islam",
            "True happiness comes from gratitude to Allah, not from having a perfect life",
            "Even under great stress, choosing to smile is a sunnah that heals you and those around you"
        ],
        "practical_advice": [
            "Start each morning by listing three things you are grateful for — this was the Prophet's practice of shukr",
            "Make it a habit to smile at others today — it is charity and it will lift your own mood",
            "When something good happens, say 'Alhamdulillah' out loud to anchor the feeling of gratitude"
        ]
    },

    # --- 6. The Night Journey (Isra and Mi'raj) ---
    {
        "title": "The Night Journey (Isra and Mi'raj)",
        "period": "11th Year of Prophethood",
        "emotions": ["lonely", "lost", "hopeless"],
        "summary": "At the lowest point in his life, after the Year of Sorrow and the rejection at Ta'if, Allah elevated the Prophet (PBUH) through the heavens in a single night, showing that divine closeness comes when worldly doors close.",
        "story": "After enduring the Year of Sorrow — losing Khadijah and Abu Talib — and the brutal rejection at Ta'if, the Prophet Muhammad (PBUH) was at the lowest point of his prophetic mission. He felt alone, unsupported, and surrounded by hostility. It was at this precise moment of deepest isolation that Allah chose to honor him with the most extraordinary journey in human history. In a single night, the Angel Jibril came to him and carried him from Makkah to Jerusalem (Isra), where he led all the previous prophets in prayer. Then he was ascended through the seven heavens (Mi'raj), meeting prophets at each level — Adam, Isa, Musa, Ibrahim — until he reached the Divine Presence itself. There, he was given the gift of the five daily prayers as a direct connection between the believer and Allah. The message was profound: when the world closes its doors, Allah opens the heavens. When people reject you, Allah draws you closer. The loneliest moment became the most intimate conversation between a servant and his Lord.",
        "lessons": [
            "Feeling lost and alone may actually be a sign that Allah is about to draw you closer",
            "When human support is removed, divine support intensifies",
            "The five daily prayers were given as a gift of connection — they are your personal Mi'raj"
        ],
        "practical_advice": [
            "In your lowest moments, pray two rak'ahs of night prayer (tahajjud) — the Prophet received his greatest gift in the night",
            "Remember that feeling lost often precedes finding your true direction",
            "Use your five daily prayers as moments of direct conversation with Allah — each prayer is your own Mi'raj"
        ]
    },

    # --- 7. Forgiveness at the Conquest of Makkah ---
    {
        "title": "Forgiveness at the Conquest of Makkah",
        "period": "8th Year After Hijrah",
        "emotions": ["angry", "guilty", "overwhelmed"],
        "summary": "When the Prophet (PBUH) conquered Makkah with 10,000 companions, he had every right to take revenge on those who had tortured and expelled him for 21 years, but instead he forgave them all.",
        "story": "In the 8th year after Hijrah, the Prophet Muhammad (PBUH) returned to Makkah at the head of 10,000 companions. This was the city that had persecuted him, starved his followers, tortured his companions, killed his family members, and driven him out. The people of Makkah, who had fought him for over two decades, were now completely at his mercy. They gathered before him, terrified of retribution. The Prophet (PBUH) stood before them and asked: 'O people of Quraysh, what do you think I will do with you?' They replied: 'You are a generous brother, the son of a generous brother.' The Prophet (PBUH) then said: 'Go, for you are free. No blame shall be on you today.' He forgave them all — Hind, who had mutilated his uncle Hamza's body; Wahshi, who had killed Hamza; Abu Sufyan, who had led armies against him. This was not weakness but the ultimate strength: the power to forgive when you have the power to punish. He entered the city not as a conqueror seeking revenge, but as a mercy to all of creation.",
        "lessons": [
            "True strength lies in the ability to forgive, not in the ability to punish",
            "Carrying anger and desire for revenge is a burden on your own soul",
            "Forgiveness does not mean what happened was okay — it means you choose freedom over bitterness"
        ],
        "practical_advice": [
            "If you are carrying guilt, know that Allah's forgiveness is greater than any sin — make sincere tawbah (repentance) and move forward",
            "If anger toward someone is consuming you, make dua for them — it will free your heart before it frees theirs",
            "Write down what is overwhelming you, then consciously choose to release one thing to Allah's control today"
        ]
    },

    # --- 8. The Treaty of Hudaybiyyah ---
    {
        "title": "The Treaty of Hudaybiyyah",
        "period": "6th Year After Hijrah",
        "emotions": ["confused", "overwhelmed"],
        "summary": "When the Prophet (PBUH) accepted seemingly unfair peace terms that frustrated many companions, it turned out to be one of the greatest strategic victories in Islamic history, teaching that what seems like a setback is often divine wisdom.",
        "story": "In the 6th year after Hijrah, the Prophet (PBUH) set out with 1,400 companions for Umrah in Makkah. The Quraysh blocked them at Hudaybiyyah and demanded humiliating terms for a peace treaty: the Muslims could not perform Umrah that year, they had to return; any Quraysh member who became Muslim had to be returned to Makkah, but any Muslim who left for Makkah would not be returned; and the treaty would last 10 years. The companions were shocked and upset. Umar (RA) was so frustrated he went to Abu Bakr asking: 'Are we not on the truth?' The Prophet (PBUH) himself was asked to erase 'Muhammad, Messenger of Allah' from the treaty document and write simply 'Muhammad ibn Abdullah,' and he agreed. The companions were confused and felt defeated. But the Prophet (PBUH) had seen what they could not. Within two years, the peace allowed Islam to spread freely, thousands embraced the faith, and the Muslims grew so strong that they eventually conquered Makkah peacefully. Allah called this treaty a 'Clear Victory' in the Quran, even though it felt like a loss at the time.",
        "lessons": [
            "What feels like confusion or defeat may actually be Allah's plan unfolding in ways you cannot yet see",
            "Sometimes you must accept short-term discomfort for long-term benefit",
            "Trust the process — Allah's timeline is different from yours"
        ],
        "practical_advice": [
            "When you are confused about a situation, pray Salat al-Istikhara (prayer for guidance) and trust the outcome",
            "Write down what is overwhelming you and separate what you can control from what you cannot",
            "Remember a past situation that seemed negative but turned out to be a blessing — this one might be the same"
        ]
    },

    # --- 9. The Slander of Aisha (RA) ---
    {
        "title": "The Slander Against Aisha (RA)",
        "period": "5th Year After Hijrah",
        "emotions": ["embarrassed", "sad", "lonely"],
        "summary": "When false rumors were spread about Aisha (RA), she endured weeks of public humiliation and isolation until Allah Himself revealed her innocence, showing that truth always prevails.",
        "story": "After a military expedition, Aisha (RA), the wife of the Prophet (PBUH), was accidentally left behind by the caravan and brought back by a companion named Safwan. Hypocrites in Madinah, led by Abdullah ibn Ubayy, seized on this to spread vicious rumors about her honor. The slander spread through the entire city. For a full month, Aisha (RA) endured the pain of public accusation. Even the Prophet (PBUH) seemed uncertain, which added to her anguish. She fell ill from the stress and withdrew to her parents' home, weeping constantly. She felt utterly alone — humiliated by the public, uncertain of her husband's support, and powerless to prove her innocence. All she could do was cry and turn to Allah. She said: 'By Allah, I know that you have heard this story so much that it has settled in your minds and you believe it. I cannot say anything except what the father of Yusuf said: Patience is beautiful, and Allah is the one sought for help.' Then Allah revealed verses from Surah An-Nur, declaring her complete innocence from above seven heavens. The truth came not from people, but from Allah Himself.",
        "lessons": [
            "Being falsely accused or embarrassed is a trial that even the purest souls face",
            "When people's words hurt you, remember that your ultimate judge is Allah, not people",
            "Truth always comes to light, even if the wait feels unbearable"
        ],
        "practical_advice": [
            "If you feel embarrassed or falsely judged, remember Aisha's words: 'Patience is beautiful, and Allah is the one sought for help'",
            "Do not exhaust yourself defending against every accusation — trust that Allah will make the truth clear",
            "Talk to someone you trust about what you are feeling — isolation deepens pain"
        ]
    },

    # --- 10. The Loss of Ibrahim ---
    {
        "title": "The Loss of His Son Ibrahim",
        "period": "10th Year After Hijrah",
        "emotions": ["sad", "guilty", "hopeless"],
        "summary": "When the Prophet's infant son Ibrahim died in his arms, he wept openly and taught that tears of grief are a mercy from Allah, not a sign of weakness.",
        "story": "Ibrahim, the infant son of the Prophet Muhammad (PBUH) and Maria (RA), fell seriously ill. The Prophet (PBUH) held his dying son in his arms, and tears began flowing from his eyes. His companion Abdur-Rahman ibn Awf said: 'Even you, O Messenger of Allah?' surprised to see the Prophet weeping. The Prophet (PBUH) responded with one of the most beautiful statements on grief: 'The eyes shed tears, the heart grieves, and we do not say anything except what pleases our Lord. O Ibrahim, indeed we are grieved by your departure.' On the same day, there happened to be a solar eclipse. People began saying it eclipsed because of Ibrahim's death. But the Prophet immediately corrected them: 'The sun and the moon are two signs among the signs of Allah. They do not eclipse for the death or birth of anyone.' Even in his deepest personal grief, he maintained truth and taught his community. He buried his son with his own hands, showing that grief and faith coexist beautifully.",
        "lessons": [
            "Crying and showing emotion is not weakness — the Prophet himself wept openly",
            "You can grieve deeply and still maintain your faith and trust in Allah",
            "Expressing sadness is healthy and even the strongest souls need to mourn"
        ],
        "practical_advice": [
            "If you are grieving, let yourself cry — tears are a mercy from Allah, as the Prophet taught",
            "Do not feel guilty for feeling sad — even the Prophet said 'the heart grieves' and that is okay",
            "Speak to Allah about your loss in your own words during sujood — He is the closest to you there"
        ]
    },

    # --- 11. The Boycott of Banu Hashim ---
    {
        "title": "The Boycott of Banu Hashim",
        "period": "7th-10th Year of Prophethood",
        "emotions": ["stressed", "lonely", "overwhelmed"],
        "summary": "For three years, the Prophet (PBUH) and his entire clan were confined to a valley with no food, trade, or marriage allowed with them, enduring starvation and isolation — yet they held firm together.",
        "story": "When the Quraysh could not stop the spread of Islam through persecution alone, they devised a cruel collective punishment. They wrote a pact: no one in Makkah would trade with, sell food to, or marry anyone from Banu Hashim (the Prophet's clan) until they handed Muhammad over. The pact was hung inside the Kaaba. For three full years, the entire clan — Muslim and non-Muslim alike — was confined to the valley of Abu Talib (Shi'b Abi Talib). They faced severe starvation. The sounds of children crying from hunger could be heard outside the valley. They ate leaves from trees and scraps of leather. Some kind-hearted Quraysh would secretly sneak food to them at night, risking their own safety. The companions later recalled this as one of the most difficult periods of their lives. Yet the Prophet (PBUH) remained steadfast, continuing to teach and comfort his followers. The Muslims supported each other, sharing whatever little they had. After three years, sympathetic Quraysh leaders worked to end the boycott, and when they went to remove the pact from the Kaaba, they found that termites had eaten away everything except the name of Allah.",
        "lessons": [
            "Overwhelming circumstances are temporary — even a three-year siege came to an end",
            "Community and togetherness are essential during times of hardship",
            "Allah works behind the scenes even when you cannot see any way out"
        ],
        "practical_advice": [
            "When feeling overwhelmed, focus on just getting through today — do not carry tomorrow's burden now",
            "Reach out to at least one person in your life — isolation makes stress worse, connection makes it bearable",
            "Remember that even the most suffocating situations have an expiry date — 'Indeed, with hardship comes ease'"
        ]
    },

    # --- 12. Abu Bakr's Steadfastness ---
    {
        "title": "Abu Bakr's Unwavering Faith",
        "period": "Throughout Prophethood",
        "emotions": ["anxious", "fearful", "confused"],
        "summary": "Abu Bakr (RA) was the first adult male to accept Islam without hesitation, and throughout every frightening and confusing moment — from the cave to the Prophet's death — his response was always trust in Allah.",
        "story": "Abu Bakr (RA) earned the title 'As-Siddiq' (the truthful) because of his immediate, unwavering acceptance of everything the Prophet (PBUH) conveyed. When the Prophet told him about the Night Journey — traveling from Makkah to Jerusalem and through the heavens in a single night — the disbelievers rushed to Abu Bakr, certain he would finally doubt. Instead, Abu Bakr simply said: 'If he said it, then he has spoken the truth.' When the Prophet (PBUH) died, the companions were in such shock and denial that Umar (RA) stood with his sword threatening anyone who said the Prophet was dead. It was Abu Bakr who stood firm. He entered, verified the Prophet had passed, then addressed the people: 'Whoever worshipped Muhammad, know that Muhammad has died. And whoever worshipped Allah, know that Allah is Ever-Living and does not die.' In every moment of fear, confusion, and anxiety throughout 23 years of prophethood, Abu Bakr's anchor was simple: trust in Allah and His Messenger. This trust did not eliminate his fear — in the cave he was terrified — but it gave him a foundation to stand on when the ground shook.",
        "lessons": [
            "Faith does not mean the absence of fear — it means trusting Allah despite the fear",
            "Having a clear anchor (your relationship with Allah) helps navigate confusion",
            "True courage is not fearlessness but continuing forward while afraid"
        ],
        "practical_advice": [
            "When fear or confusion overwhelms you, return to your anchor — pray two rak'ahs and ask Allah for clarity",
            "Strengthen your faith during calm times so it holds firm during storms",
            "Write down the facts of your situation separately from your fears — often the fear is larger than the reality"
        ]
    },

    # --- 13. Bilal's Perseverance ---
    {
        "title": "Bilal ibn Rabah's Perseverance Under Torture",
        "period": "Early Makkah Period",
        "emotions": ["stressed", "hopeless", "rejected"],
        "summary": "Bilal (RA), an enslaved African man, was tortured under the burning desert sun for accepting Islam — with a boulder on his chest — yet he only repeated 'Ahad, Ahad' (One, One), and went on to become the first muezzin of Islam.",
        "story": "Bilal ibn Rabah (RA) was an Abyssinian slave owned by Umayyah ibn Khalaf, one of the fiercest enemies of Islam. When Bilal accepted Islam, his master was enraged. He would drag Bilal out into the scorching desert heat at the hottest part of the day, lay him on the burning sand, and place a massive boulder on his chest. As Bilal struggled to breathe under the crushing weight, Umayyah would demand he renounce Islam and praise the idols. But Bilal, with whatever breath he could muster, would only repeat one word: 'Ahad... Ahad...' (The One... The One...). He was whipped, starved, and paraded through the streets. Other slaves who accepted Islam were similarly tortured — Yasir and Sumayyah (RA) were killed for their faith. Bilal had every reason to feel hopeless. He was a slave with no power, no family to protect him, rejected by society. Yet his inner conviction was unbreakable. Eventually, Abu Bakr (RA) purchased and freed him. And when Islam triumphed, it was Bilal's voice that was chosen to give the first ever call to prayer (Adhan) from atop the Kaaba — the same man who was tortured for his faith now called an entire nation to prayer.",
        "lessons": [
            "Your current circumstances do not define your future — Bilal went from tortured slave to honored muezzin",
            "Inner conviction can sustain you through external suffering that seems unbearable",
            "Those who reject and oppress you today may have no power over your tomorrow"
        ],
        "practical_advice": [
            "When you feel hopeless, remember Bilal under the boulder — if he could say 'Ahad,' you can hold on too",
            "Repeat a simple dhikr when stress feels crushing — 'La ilaha illa Allah' can be your anchor like 'Ahad' was Bilal's",
            "Rejection by people does not equal rejection by Allah — sometimes Allah elevates through difficulty"
        ]
    },

    # --- 14. Khadijah's Unwavering Support ---
    {
        "title": "Khadijah's Unwavering Support",
        "period": "Early Prophethood",
        "emotions": ["grateful", "happy", "lonely"],
        "summary": "When the Prophet (PBUH) came home trembling after the first revelation, terrified and confused, Khadijah (RA) wrapped him in a blanket and reassured him with words that changed history, showing the power of one person's belief in you.",
        "story": "When the Prophet Muhammad (PBUH) received the first revelation in the Cave of Hira, he was overwhelmed with fear. He came home to Khadijah (RA) trembling and said: 'Cover me! Cover me!' She wrapped him in a blanket and held him until the trembling stopped. Then she spoke words that became a cornerstone of Islamic history: 'Never! By Allah, Allah will never disgrace you. You keep good relations with your relatives, you help the poor, you serve your guests generously, you bear the hardships in the path of truthfulness, and you assist those afflicted by calamities.' Khadijah became the first person to accept Islam. She did not hesitate for a moment. For 25 years, she was his partner, his advisor, his comfort, and his greatest supporter. She spent her entire wealth in the cause of Islam. She stood by him when the whole world stood against him. The Prophet (PBUH) never forgot her. Even years after her death, he would send gifts to her friends and remember her fondly. When Aisha once asked about her, the Prophet said: 'Her love has been nurtured in my heart by Allah Himself.' Khadijah showed that one person's genuine love and belief can sustain you through anything.",
        "lessons": [
            "One person's unwavering support can make all the difference in your life — be grateful for those who believe in you",
            "True love is not just affection but standing by someone when the world turns against them",
            "The feeling of being truly understood and supported is one of Allah's greatest blessings"
        ],
        "practical_advice": [
            "Think of the people who have supported you and express gratitude to them today — a message, a call, a dua",
            "If you feel lonely, remember that the Prophet deeply missed Khadijah too — longing for loved ones is human",
            "Be a Khadijah to someone in your life — your words of encouragement could change their world"
        ]
    },

    # --- 15. The Battle of Uhud ---
    {
        "title": "The Battle of Uhud",
        "period": "3rd Year After Hijrah",
        "emotions": ["guilty", "embarrassed", "sad"],
        "summary": "When the Muslim archers disobeyed the Prophet's clear orders at Uhud and left their positions, it led to a devastating reversal that injured the Prophet and killed 70 companions, yet the Prophet did not blame them and sought collective healing.",
        "story": "At the Battle of Uhud, the Prophet (PBUH) stationed 50 archers on a hill with clear instructions: 'Do not leave this position, even if you see us collecting war booty.' Initially, the Muslims were winning decisively. But when some archers saw the enemy retreating, they disobeyed and left their posts to collect spoils. The enemy cavalry commander, Khalid ibn al-Walid, saw the gap and launched a devastating flanking attack. The tide turned completely. The Prophet (PBUH) was struck in the face, his tooth was broken, and blood poured down his cheeks. Seventy companions were martyred, including his beloved uncle Hamza (RA), whose body was mutilated. The surviving archers who had left their posts were consumed with guilt. The entire Muslim army was shaken with shame and grief. Yet the Prophet (PBUH) did not curse them or single anyone out for blame. When he wiped the blood from his face, he said: 'How can a people prosper who have injured their Prophet?' but then he prayed for their guidance. Allah later revealed: 'It was by mercy from Allah that you were lenient with them.' The Prophet chose mercy over blame, and the community healed together.",
        "lessons": [
            "Making mistakes, even serious ones, does not make you a bad person — what matters is how you respond",
            "Guilt is a sign of a living conscience, not a reason for permanent shame",
            "The Prophet's response to failure was mercy, not punishment — extend that mercy to yourself"
        ],
        "practical_advice": [
            "If guilt is weighing on you, make sincere tawbah (repentance) — say 'Astaghfirullah' and mean it, then let go",
            "Understand that everyone makes mistakes — even the companions at Uhud — and Allah's door of forgiveness is always open",
            "Learn from the mistake and move forward — dwelling in guilt without action is not what Islam teaches"
        ]
    },

    # --- 16. Reconciliation with the Ansar After Hunayn ---
    {
        "title": "Reconciliation with the Ansar After Hunayn",
        "period": "8th Year After Hijrah",
        "emotions": ["confused", "rejected", "angry"],
        "summary": "After the Battle of Hunayn, the Ansar felt hurt when the Prophet distributed war spoils primarily to new Quraysh converts, but his emotional speech moved them to tears and restored their bond.",
        "story": "After the Battle of Hunayn and the conquest of Makkah, the Prophet (PBUH) distributed a large portion of the war spoils to the newly converted Quraysh leaders — people who had fought Islam for 20 years. The Ansar (helpers of Madinah), who had sacrificed everything for Islam for years, received very little. They felt confused and hurt. Some young Ansar said: 'When things get difficult, we are called upon, but the spoils go to others.' When the Prophet (PBUH) heard about their feelings, he gathered them privately and delivered one of the most emotional speeches in Seerah history. He said: 'O Ansar! Did I not find you misguided and Allah guided you through me? Were you not divided and Allah united you through me? Were you not poor and Allah enriched you through me?' To each point, they replied: 'Allah and His Messenger have shown us the greater favor.' Then the Prophet said, with tears in his eyes: 'O Ansar, are you upset over some worldly goods by which I wished to win over a people who recently left disbelief? Are you not satisfied that while others take sheep and camels, you return home with the Messenger of Allah? By the One in whose hand is my soul, if all people went one way and the Ansar went another, I would choose the path of the Ansar.' The Ansar wept until their beards were soaked with tears.",
        "lessons": [
            "Feeling overlooked or underappreciated is natural, but there may be a bigger picture you are not seeing",
            "Honest communication about hurt feelings leads to resolution, not silent resentment",
            "Sometimes what seems like rejection is actually trust — the Prophet gave less to the Ansar because he trusted their faith was already firm"
        ],
        "practical_advice": [
            "If you feel confused or rejected, express your feelings to the person involved rather than bottling them up",
            "Ask yourself if there might be a reason or wisdom behind the situation that you have not considered",
            "Remember that your worth is not measured by material recognition — sometimes being trusted is the highest honor"
        ]
    },

    # --- 17. The Prophet's Gratitude in Hardship ---
    {
        "title": "The Prophet's Gratitude in Every Circumstance",
        "period": "Throughout His Life",
        "emotions": ["grateful", "happy"],
        "summary": "The Prophet (PBUH) practiced gratitude so deeply that he would pray until his feet swelled, and when asked why he pushed himself when already forgiven, he replied 'Should I not be a grateful servant?'",
        "story": "Aisha (RA) narrated that the Prophet Muhammad (PBUH) would stand in night prayer (Tahajjud) for so long that his feet would swell. When Aisha asked him: 'Why do you do this to yourself when Allah has forgiven all your past and future sins?' the Prophet replied: 'Afala akoonu abdan shakoora?' — 'Should I not then be a grateful servant?' This single phrase reveals the essence of his character. The Prophet's gratitude was not conditional on good times. He was grateful when he had food and when he was hungry. He was grateful when people supported him and when they rejected him. He tied a stone to his stomach during the digging of the Trench to suppress hunger pangs, yet he thanked Allah. He ate simple meals of dates and water, yet said Alhamdulillah with full contentment. He taught his companions: 'Look at those below you in worldly matters and above you in matters of faith, so you do not belittle Allah's blessings upon you.' The Prophet found reasons to be grateful in every single circumstance — and this gratitude was the source of his unshakeable inner peace.",
        "lessons": [
            "Gratitude is not about having everything — it is about recognizing what you have",
            "The practice of gratitude itself generates happiness, not the other way around",
            "Looking at those who have less than you in worldly matters helps cultivate thankfulness"
        ],
        "practical_advice": [
            "Before sleeping tonight, thank Allah for three specific blessings — even small ones like a warm bed or clean water",
            "When you catch yourself complaining, pause and reframe: what is one thing in this situation to be grateful for?",
            "Practice the Prophet's advice: look at those who have less than you, and your blessings will feel enormous"
        ]
    },

    # --- 18. The Conversion of Umar ibn al-Khattab ---
    {
        "title": "The Conversion of Umar ibn al-Khattab",
        "period": "6th Year of Prophethood",
        "emotions": ["confused", "lost", "angry"],
        "summary": "Umar (RA) set out with a sword to kill the Prophet but was transformed by hearing the Quran, showing that the most lost and angry person can find clarity and purpose in an instant.",
        "story": "Before Islam, Umar ibn al-Khattab was one of the fiercest enemies of the Muslims. He was a strong, intimidating man whom the early Muslims feared deeply. One day, Umar set out with his sword, determined to kill Prophet Muhammad (PBUH) and end Islam once and for all. On the way, someone told him: 'Why don't you take care of your own family first? Your sister Fatimah and her husband have become Muslim.' Furious, Umar stormed to his sister's house. When he arrived, he heard the recitation of Surah Taha from behind the door. He burst in and struck his sister, drawing blood. When he saw the blood on her face, something shifted in his heart. He felt ashamed. He said: 'Show me what you were reading.' She replied: 'You are impure; you cannot touch it.' Umar washed himself and began reading the verses. As he read, his heart, which moments ago was filled with murderous rage, began to melt. He said: 'How beautiful and noble these words are.' He immediately went to the Prophet (PBUH) and declared his Islam. The man who left his home to kill the Prophet arrived at the Prophet's door as a believer. The Muslims, who had been hiding their faith in fear, now prayed openly in the Kaaba for the first time. Umar went on to become the second Caliph and one of the greatest leaders in history.",
        "lessons": [
            "No matter how lost or angry you feel, transformation can happen in a single moment",
            "Anger often masks deeper confusion and a soul searching for truth",
            "The path that seems destructive might actually be leading you to your turning point"
        ],
        "practical_advice": [
            "If you feel lost or directionless, open the Quran and read — Umar's entire life changed from hearing a few verses",
            "Channel your anger into seeking truth rather than destruction",
            "Remember that it is never too late to change direction — Umar went from wanting to kill the Prophet to being one of Islam's greatest leaders"
        ]
    },

    # --- 19. The Farewell Sermon ---
    {
        "title": "The Farewell Sermon (Khutbat al-Wada)",
        "period": "10th Year After Hijrah",
        "emotions": ["overwhelmed", "grateful", "sad"],
        "summary": "In his final sermon before over 100,000 people, the Prophet (PBUH) summarized the core values of Islam — equality, justice, kindness — and asked 'Have I conveyed the message?' leaving a legacy of compassion.",
        "story": "In the 10th year after Hijrah, the Prophet Muhammad (PBUH) performed his final Hajj. Standing on the plain of Arafat before an estimated 114,000 companions, he delivered what would be his last major public address. He seemed to know it was farewell. His words carried the weight of 23 years of prophethood and a lifetime of struggle. He said: 'All mankind is from Adam and Eve. An Arab has no superiority over a non-Arab, nor does a non-Arab have any superiority over an Arab. A white person has no superiority over a black person, nor does a black person have any superiority over a white person — except by piety and good action.' He urged them to treat women well, to be just in their dealings, to abandon the feuds and interest-based transactions of the pre-Islamic era. He reminded them that they would meet Allah and be asked about their deeds. Then he paused and asked the crowd: 'Have I conveyed the message?' The crowd responded: 'Yes, you have!' He raised his finger to the sky and said: 'O Allah, bear witness.' Months later, the Prophet (PBUH) passed away. But his words that day became an eternal constitution of human dignity, echoing across 1,400 years to reach us today.",
        "lessons": [
            "Life is temporary — focus on leaving a legacy of kindness, not material accumulation",
            "Every human being has equal worth regardless of race, status, or background",
            "When you feel overwhelmed by life, zoom out and focus on what truly matters: your character and your relationship with Allah"
        ],
        "practical_advice": [
            "If you are feeling overwhelmed, ask yourself: in a year, what will actually matter from today's worries?",
            "Practice one act of kindness today that someone might remember you by",
            "Spend a few minutes in gratitude for the simple fact that you are alive and have the chance to do good"
        ]
    },

    # --- 20. The Prophet's Patience with His Neighbor ---
    {
        "title": "The Prophet's Patience with His Abusive Neighbor",
        "period": "Madinah Period",
        "emotions": ["angry", "stressed", "embarrassed"],
        "summary": "A neighbor would regularly throw garbage on the Prophet's doorstep, but instead of retaliating, the Prophet (PBUH) visited the neighbor when they fell ill, winning them over through kindness.",
        "story": "There lived a neighbor near the Prophet Muhammad (PBUH) in Madinah who would regularly throw garbage and waste on his doorstep. Every day, the Prophet (PBUH) would find trash at his door, and every day, he would quietly clean it up without complaint or retaliation. He never cursed the neighbor, never confronted them angrily, and never asked the companions to intervene. He simply endured it with patience and grace. One day, the Prophet (PBUH) noticed that no garbage had been thrown. Concerned, he inquired about the neighbor and learned they had fallen ill. Instead of feeling relieved or vindicated, the Prophet (PBUH) went to visit the sick neighbor. The neighbor was shocked and moved — they had expected anger and revenge, but instead received compassion and concern. This act of extraordinary kindness transformed the neighbor's heart. The story illustrates the Prophet's core teaching that the best response to bad treatment is good treatment. He said: 'The best among you are those who are best to their neighbors.' He endured the daily embarrassment and stress of being disrespected at his own door, yet chose patience over confrontation, and kindness over revenge.",
        "lessons": [
            "Responding to negativity with kindness is more powerful than any confrontation",
            "Patience with difficult people is one of the highest forms of strength",
            "Your character is defined by how you treat those who treat you badly"
        ],
        "practical_advice": [
            "If someone is causing you stress, try responding with unexpected kindness — it may transform the relationship",
            "When embarrassed or disrespected, remember that your dignity comes from Allah, not from people's opinions",
            "Practice patience as a daily muscle: when annoyed, take three deep breaths before responding"
        ]
    },
]


def seed():
    """Insert seed stories into MongoDB and build the vector index."""
    existing = stories_collection.count_documents({})
    if existing > 0:
        confirm = input(f"Database already has {existing} stories. Clear and re-seed? (y/n): ")
        if confirm.lower() != 'y':
            print("Aborted.")
            return
        stories_collection.delete_many({})
        story_index_collection.delete_many({})
        print("Cleared existing stories and index.")

    # Add timestamps
    for story in SEED_STORIES:
        story["created_at"] = time.time()

    stories_collection.insert_many(SEED_STORIES)
    print(f"Inserted {len(SEED_STORIES)} Seerah stories.")

    # Build vector index
    print("Building vector index (this may take a minute on first run as the model downloads)...")
    from rag import sync_new_stories
    sync_new_stories()

    print(f"Total indexed: {story_index_collection.count_documents({})}")
    print("\nDone! Remember to create the Vector Search index in MongoDB Atlas UI:")
    print("  Index name: story_vector_index")
    print("  Collection: story_index")
    print("  Fields: embedding (vector, 384 dims, cosine) + emotions (filter)")


if __name__ == "__main__":
    seed()
