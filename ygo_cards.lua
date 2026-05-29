-- [ygo_cards] YGO80 module -- loaded via require() from ygo80.lua

-- ============================================================
-- CARD DATABASE
-- ============================================================
CARDS={
 -- ============================================================
 -- MONSTERS
 -- ============================================================

 -- Level 1
 kuriboh={
  name="Kuriboh", cat="monster", type="fiend", attr="dark", effect="kuriboh", atk=300, def=200, lvl=1, spr=256,  desc="If your opponent's monster attacks: You can discard this card; you take no battle damage from that battle."
 },

 -- Level 2
 man_eater_bug={
  name="Man-Eater Bug", cat="monster", type="insect", attr="earth", effect="maneater", atk=450, def=600, lvl=2, spr=258,  desc="FLIP: Target 1 monster on the field; destroy that target."
 },
 a_cat_of_ill_omen={
  name="A Cat of Ill Omen", cat="monster", type="beast", attr="dark", effect="catillomen", atk=500, def=300, lvl=2, spr=356,  desc="FLIP: Search your deck for 1 Trap Card and place it on top of your deck. If 'Necrovalley' is on the field, add it to your hand instead."
 },

 -- Level 2
 time_wizard={
  name="Time Wizard", cat="monster", type="spellcaster", attr="light", effect="timewizard", atk=500, def=400, lvl=2, spr=332,  desc="Once per turn: Toss a coin. On win, destroy all monsters your opponent controls. On loss, destroy all monsters you control and take damage equal to half their total ATK."
 },

 -- Level 3
 kaibaman={
  name="Kaibaman", cat="monster", type="warrior", attr="light", effect="kaibaman", atk=200, def=700, lvl=3, spr=366,  desc="You can Tribute this card; Special Summon 1 'Blue-Eyes White Dragon' from your hand."
 },
 sangan={
  name="Sangan", cat="monster", type="fiend", attr="dark", effect="sangan", atk=1000, def=600, lvl=3, spr=260,  desc="When destroyed, add a monster with 1500 or less ATK from your deck to your hand."
  },
 giant_soldier={
  name="Giant Soldier", cat="monster", type="rock", attr="earth", atk=1300, def=2000, lvl=3, spr=262,  desc="A towering stone giant with impenetrable armor and very high defense."
  },
 gravekeeper_curse={
  name="Gravekeeper's Curse", cat="monster", type="spellcaster", attr="dark", effect="gkcurse", atk=800, def=600, lvl=3, spr=354,  desc="Each time this card is Normal or Special Summoned, inflict 800 damage to your opponent."
  },
 baby_dragon={
  name="Baby Dragon", cat="monster", type="dragon", attr="wind", atk=1200, def=700, lvl=3, spr=388,  desc="A small dragon with much potential. One day it will grow into a fearsome beast."
 },

 -- Level 4
 seven_color_fish={
  name="7 Color Fish", cat="monster", type="fish", attr="water", atk=1800, def=800, lvl=4, spr=264,  desc="A vibrant and powerful fish that traverses all the world's oceans."
 },
 la_jinn={
  name="La Jinn", cat="monster", type="fiend", attr="dark", atk=1800, def=1000, lvl=4, spr=266,  desc="A mystical genie released from an ancient lamp. Commands fearsome power."
 },
 battle_ox={
  name="Battle Ox", cat="monster", type="beast-warrior", attr="earth", atk=1700, def=1000, lvl=4, spr=268,  desc="A savage warrior ox that charges through enemies with brutal force."
 },
 ufo_turtle={
  name="Ufo Turtle", cat="monster", type="machine", attr="fire", effect="ufoturtle", atk=1400, def=1200, lvl=4, spr=270,  desc="When destroyed in battle, special summons a FIRE monster from the deck."
 },
 alligators_sword={
  name="Alligator's Sword", cat="monster", type="beast-warrior", attr="earth", atk=1500, def=1200, lvl=4, spr=386,  desc="A fierce reptilian warrior that wields its blade with savage skill."
 },
 lord_of_d={
  name="Lord of D.", cat="monster", type="spellcaster", attr="dark", effect="lordofd", atk=1200, def=1100, lvl=4, spr=364,  desc="Neither player can target Dragon monsters on the field with card effects."
 },
 spear_dragon={
  name="Spear Dragon", cat="monster", type="dragon", attr="wind", effect="speardragon", atk=1900, def=0, lvl=4, spr=384,  desc="If this card attacks a Defense Position monster, inflict piercing battle damage. If this card attacks, it is changed to Defense Position at the end of the Damage Step."
 },
 rocket_warrior={
  name="Rocket Warrior", cat="monster", type="warrior", attr="light", effect="rocketwarrior", atk=1500, def=1300, lvl=4, spr=396,  desc="During your turn, this card cannot be destroyed by battle, also you take no damage from battles involving this card. If this card attacks a monster, after damage calculation: that target loses 500 ATK until the end of this turn."
 },
 aqua_madoor={
  name="Aqua Madoor", cat="monster", type="spellcaster", attr="water", atk=1200, def=2000, lvl=4, spr=288,  desc="A powerful water sorcerer who calls upon the deep sea for protection."
 },
 mystical_elf={
  name="Mystical Elf", cat="monster", type="spellcaster", attr="light", atk=800, def=2000, lvl=4, spr=290,  desc="A gentle elf shielded by a sacred barrier. Possesses extreme defense."
 },
 feral_imp={
  name="Feral Imp", cat="monster", type="fiend", attr="dark", atk=1300, def=1400, lvl=4, spr=298,  desc="A fiendish imp that lurks in the shadows, striking with vicious claws."
 },
 rogue_doll={
  name="Rogue Doll", cat="monster", type="spellcaster", attr="light", atk=1600, def=1000, lvl=4, spr=300,  desc="A possessed doll that moves on its own will, wielding powerful magic."
 },
 legion_fiend_jester={
  name="Legion the Fiend Jester", cat="monster", type="fiend", attr="dark", effect="legion", atk=1200, def=0, lvl=4, spr=320,  desc="Once per turn: Tribute Summon 1 Spellcaster in ATK pos, in addition to your Normal Summon. If sent from field to GY: add 1 Spellcaster Normal Monster from Deck or GY to hand."
 },
 the_stern_mystic={
  name="The Stern Mystic", cat="monster", type="spellcaster", attr="light", effect="sternmystic", atk=1500, def=1200, lvl=4, spr=324,  desc="FLIP: Both players reveal all face-down cards on the field. After this, return them to their original positions."
 },
 double_coston={
  name="Double Coston", cat="monster", type="zombie", attr="dark", effect="doublecoston", atk=1700, def=1650, lvl=4, spr=326,  desc="If used as a Tribute for the Tribute Summon of a DARK monster, this card is treated as 2 Tributes."
 },
 vorse_raider={
  name="Vorse Raider", cat="monster", type="beast-warrior", attr="dark", atk=1900, def=1200, lvl=4, spr=330,  desc="This wicked Beast-Warrior does every horrid thing imaginable, and loves it! His axe bears the marks of his countless victims."
 },
 gravekeeper_assailant={
  name="Gravekeeper's Assailant", cat="monster", type="spellcaster", attr="dark", effect="gkassailant", atk=1500, def=1500, lvl=4, spr=352,  desc="If 'Necrovalley' is on the field, when this card attacks: you can change the battle position of 1 monster your opponent controls."
 },
 gravekeeper_spy={
  name="Gravekeeper's Spy", cat="monster", type="spellcaster", attr="dark", effect="gkspy", atk=1200, def=2000, lvl=4, spr=334,  desc="FLIP: Special Summon 1 'Gravekeeper's' monster from your Deck."},

 -- Level 6
 summoned_skull={
  name="Summoned Skull", cat="monster", type="fiend", attr="dark", atk=2500, def=1200, lvl=6, spr=292,  desc="A powerful fiend that rules the darkness. One of the strongest monsters."
 },
 dark_magician_girl={
  name="Dark Magician Girl", cat="monster", type="spellcaster", attr="light", effect="dmgirl", atk=2000, def=1700, lvl=6, spr=302,  desc="Gains 300 ATK for each Dark Magician in either GY."
 },
  jinzo={
  name="Jinzo", cat="monster", type="machine", attr="dark", effect="jinzo", atk=2400, def=1500, lvl=6, spr=328,  desc="While this card is face-up on the field, Trap Cards cannot be activated."},
 gravekeeper_shaman={
  name="Gravekeeper's Shaman", cat="monster", type="spellcaster", attr="dark", effect="gkshaman", atk=1500, def=1500, lvl=6, spr=360,  desc="Gains 200 DEF for each GK in either GY. Negates GY monster effects (not GKs). While Necrovalley: opp can't activate Field Spells."
 },

 -- Level 7
 dark_magician={
  name="Dark Magician", cat="monster", type="spellcaster", attr="dark", atk=2500, def=2100, lvl=7, spr=294,  desc="The ultimate wizard in terms of both attack and defense. A legend."
 },
 red_eyes_b_dragon={
  name="Red Eyes B Dragon", cat="monster", type="dragon", attr="dark", atk=2400, def=2000, lvl=7, spr=296,  desc="A ferocious black dragon with a devastating black fire breath attack."
 },
 buster_blader={
  name="Buster Blader", cat="monster", type="warrior", attr="earth", effect="busterblader", atk=2600, def=2300, lvl=7, spr=322,  desc="Gains 500 ATK for each Dragon-type monster your opponent controls or has in their GY."},

 -- Level 8
 blue_eyes_w_dragon={
  name="Blue-Eyes W Dragon", cat="monster", type="dragon", attr="light", atk=3000, def=2500, lvl=8, spr=362,  desc="This legendary dragon is a powerful engine of destruction."
 },

  -- Level 10
 gravekeeper_oracle={
  name="Gravekeeper's Oracle", cat="monster", type="spellcaster", attr="dark", effect="gkoracle", atk=2000, def=1500, lvl=10, spr=358,  desc="Tribute 1 GK or 3 monsters to summon. On Tribute Summon: activate up to [GKs tributed] effects in sequence:\n * incr ATK by tributed levels x100\n * destroy opp set monsters\n * opp monsters -2000 ATK/DEF"
 },

 -- ============================================================
 -- SPELLS
 -- ============================================================

 -- Normal
 dark_hole={
  name="Dark Hole", cat="spell", subtype="normal", effect="darkhole", spr=448,  desc="Destroy all monsters on the field."
 },
 raigeki={
  name="Raigeki", cat="spell", subtype="normal", effect="raigeki", spr=450,  desc="Destroy all monsters your opponent controls."
 },
 fissure={
  name="Fissure", cat="spell", subtype="normal", effect="fissure", spr=452,  desc="Destroy your opponent's face-up monster with the lowest ATK."
 },
 ookazi={
  name="Ookazi", cat="spell", subtype="normal", effect="ookazi", spr=454,  desc="Inflict 800 points of damage to your opponent's Life Points."
 },
 thousand_knives={
  name="Thousand Knives", cat="spell", subtype="normal", effect="thousandknives", spr=484,  desc="If you control 'Dark Magician': Target 1 monster your opponent controls; destroy that target."
 },
 pot_of_greed={
  name="Pot of Greed", cat="spell", subtype="normal", effect="potofgreed", spr=488,  desc="Draw 2 cards."
 },
 monster_reborn={
  name="Monster Reborn", cat="spell", subtype="normal", effect="monsterreborn", spr=490,  desc="Target 1 monster in either GY; Special Summon it to your field in ATK position."
 },
 gravekeeper_stele={
  name="Gravekeeper's Stele", cat="spell", subtype="normal", effect="gkstele", spr=418,  desc="If you have at least 1 'Gravekeeper's' monster in your GY: Target 2 'Gravekeeper's' monsters in your GY; add them to your hand (1 at a time)."
 },
 flute_of_dragon={
  name="Flute of Dragon", cat="spell", subtype="normal", effect="fluteofdragon", spr=424,  desc="Special Summon up to 2 Dragon monsters from your hand. 'Lord of D.' must be on the field to activate and to resolve this effect."
 },
 stamping_destruction={
  name="Stamping Destruction", cat="spell", subtype="normal", effect="stampingdestruction", spr=426,  desc="If you control a Dragon: Target 1 Spell/Trap on the field; destroy it, and inflict 500 damage to its controller."
 },
 cost_down={
  name="Cost Down", cat="spell", subtype="normal", effect="costdown", spr=428,  desc="Discard 1 card; for the rest of this turn, the Levels of all monsters in your hand are reduced by 2 (even after they are Summoned)."
 },
 stray_lambs={
  name="Stray Lambs", cat="spell", subtype="normal", effect="straylambs", spr=390,  desc="Special Summon 2 'Lamb Tokens' (Beast/EARTH/Level 1/ATK 0/DEF 0) in Defense Position."
 },
 giant_trunade={
  name="Giant Trunade", cat="spell", subtype="normal", effect="gianttrunade", spr=394,  desc="Return all Spell and Trap Cards on the field to the hand."
 },

 -- Equip
 united_we_stand={
  name="United We Stand", cat="spell", subtype="equip", effect="unitedwestand", spr=462,  desc="The equipped monster gains 800 ATK/DEF for each face-up monster you control."},

 -- Quick-Play
 mystical_typhoon={
  name="Mystical Typhoon", cat="spell", subtype="quickplay", effect="mst", spr=480,  desc="Target 1 Spell/Trap on the field; destroy that target."},
 graceful_dice={
  name="Graceful Dice", cat="spell", subtype="quickplay", effect="gracefuldice", spr=420,  desc="Roll a six-sided die. All face-up monsters you control gain ATK and DEF equal to the result x100, until the end of the turn."},

 -- Continuous
 swords_of_revealing_light={
  name="Swords of Revealing Light", cat="spell", subtype="continuous", effect="swords", spr=486,  desc="Your opponent's monsters cannot declare an attack. Destroyed during your opponent's 3rd End Phase."},

 -- Field
 necrovalley={
  name="Necrovalley", cat="spell", subtype="field", effect="necrovalley", spr=416,  desc="All 'Gravekeeper's' monsters gain 500 ATK/DEF. Negate any card effect that moves a card from a Graveyard."},
 sogen={
  name="Sogen", cat="spell", subtype="field", effect="sogen", spr=398,  desc="All Warrior and Beast-Warrior monsters on the field gain 400 ATK/DEF."},

 -- ============================================================
 -- TRAPS
 -- ============================================================

 -- Normal
 mirror_force={
  name="Mirror Force", cat="trap", subtype="normal", effect="mirrorforce", spr=456,  desc="When an opponent's monster declares an attack, destroy all their attack position monsters."
 },
 trap_hole={
  name="Trap Hole", cat="trap", subtype="normal", effect="traphole", spr=458,  desc="When your opponent summons a monster with 1000 or more ATK, destroy it."},

 -- Continuous
 call_of_the_haunted={
  name="Call of Haunted", cat="trap", subtype="continuous", effect="callhaunted", spr=460,  desc="Target 1 monster in your GY; Special Summon it in ATK Pos. When this card leaves the field, destroy that monster. When that monster is destroyed, destroy this card."},
 gravity_bind={
  name="Gravity Bind", cat="trap", subtype="continuous", effect="gravitybind", spr=422,  desc="Monsters that are Level 4 or higher cannot declare an attack."},

 -- Counter
 magic_jammer={
  name="Magic Jammer", cat="trap", subtype="counter", effect="magicjammer", spr=482,  desc="When a Spell is activated: Discard 1 card; negate that activation, and destroy that card."},
 seven_tools={
  name="Seven Tools", cat="trap", subtype="counter", effect="seventools", spr=494,  desc="When a Trap is activated: Pay 1000 LP; negate the activation and destroy it."},
 negate_attack={
  name="Negate Attack", cat="trap", subtype="counter", effect="negateattack", spr=430,  desc="When an opponent's monster declares an attack: Target the attacking monster; negate the attack, then end the Battle Phase."},
 kunai_with_chain={
  name="Kunai with Chain", cat="trap", subtype="normal", effect="kunaichain", spr=392,  desc="When an opp monster declares an attack: pick one or both - change the attacker to DEF, OR equip to a face-up monster you control (gains 500 ATK)."},

}

-- Auto-generated from CARDS keys: monster < spell < trap, then by level, then by name.
CARD_ORDER={}
for k in pairs(CARDS) do CARD_ORDER[#CARD_ORDER+1]=k end
table.sort(CARD_ORDER,function(a,b)
 local ca,cb=CARDS[a],CARDS[b]
 if ca.cat~=cb.cat then return ca.cat<cb.cat end
 if (ca.lvl or 0)~=(cb.lvl or 0) then return (ca.lvl or 0)<(cb.lvl or 0) end
 return ca.name<cb.name
end)
CARD_NUM={}
for i,id in ipairs(CARD_ORDER) do CARD_NUM[id]=i end

-- ============================================================
-- DECKS
-- ============================================================

DECK1 = {
  -- Monsters
  "dark_magician", "dark_magician_girl", "summoned_skull", "feral_imp", "kuriboh", "sangan", "giant_soldier", "mystical_elf", "legion_fiend_jester", "rogue_doll", "double_coston", "man_eater_bug", "man_eater_bug",
  -- Spells
  "dark_hole", "ookazi", "ookazi", "fissure",
  -- Traps
  "mirror_force", "mirror_force", "trap_hole", "gravity_bind",
}

-- Opponents

DECK_YUGI = {
  -- Monsters
  "dark_magician_girl", "dark_magician", "summoned_skull", "feral_imp", "kuriboh", "sangan", "giant_soldier", "mystical_elf", "legion_fiend_jester", "rogue_doll", "double_coston", "man_eater_bug", "man_eater_bug",
  -- Spells
  "dark_hole", "ookazi", "ookazi",
  -- Traps
  "mirror_force", "mirror_force", "fissure", "trap_hole",
}

DECK_JOEY = {
  -- TEST DECK: Lord of D. protection. Packed with monster-targeting effects.
  -- Monsters
  "man_eater_bug", "man_eater_bug", "man_eater_bug", "man_eater_bug",
  "battle_ox", "la_jinn", "vorse_raider", "seven_color_fish", "ufo_turtle",
  -- Spells
  "fissure", "fissure", "fissure", "fissure", "ookazi", "ookazi",
  -- Traps
  "trap_hole", "trap_hole", "trap_hole", "mirror_force", "mirror_force",
}

DECK_KAIBA = {
  -- Monsters
  "summoned_skull", "summoned_skull", "red_eyes_b_dragon", "red_eyes_b_dragon", "battle_ox", "la_jinn", "vorse_raider",
  -- Spells
  "dark_hole", "raigeki", "fissure", "mystical_typhoon", "mystical_typhoon",
  -- Traps
  "trap_hole", "mirror_force", "mirror_force",
}

DECK_MARIK = {
  -- Monsters
  "gravekeeper_oracle", "gravekeeper_shaman", "gravekeeper_spy", "gravekeeper_spy",
  "gravekeeper_assailant", "gravekeeper_assailant", "gravekeeper_curse", "gravekeeper_curse",
  "a_cat_of_ill_omen", "a_cat_of_ill_omen",
  -- Spells
  "dark_hole", "raigeki", "ookazi", "necrovalley", "necrovalley", "gravekeeper_stele", "gravekeeper_stele",
  -- Traps
  "trap_hole", "mirror_force", "mirror_force",
}

-- Selectable opponents. spr = top-left tile of a 32x32 (4x4 tile) portrait.
OPPONENTS={
 {name="YUGI",  spr=384, deck=DECK_YUGI,  quotes={
  "I believe in the Heart of the Cards!",
  "Because I have friends who believe in me, I can fight!"}},
 {name="JOEY",  spr=388, deck=DECK_JOEY,  quotes={
  "I'm gonna take this loser to school!",
  "It's Wheeler time, baby!"}},
 {name="KAIBA", spr=392, deck=DECK_KAIBA, quotes={
  "You're a third-rate duelist with a fourth-rate deck!",
  "Why don't you go look for an opponent you can actually beat? Like an infant, or a monkey."}},
 {name="MARIK", spr=396, deck=DECK_MARIK, quotes={
  "The shadows hunger for your soul.",
  "Is that fear in your eyes? I like to see this side of you.",
  "Mercy is for the weak, like you, my friend."}},
}
OPP_SEL=1
