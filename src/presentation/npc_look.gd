class_name NpcLook
extends RefCounted
## What a person looks like: the CharacterFigure palette for an NPC.
##
## Recognisable people carry an authored `look` in data/npcs.json. Everyone
## else is dressed from a small generated set, chosen from their id so the same
## person always looks the same, across sessions and saves, with nothing stored.

const SKINS: Array[String] = ["f0d0b8", "e8c4a0", "d9a882", "b98260", "8a5a3c"]
const HAIRS: Array[String] = ["1a1a1a", "3b2a20", "6b4a2e", "a0703a", "d0b070", "9a9a9a"]
const SHIRTS: Array[String] = ["3f6e8c", "6b8c3f", "8c3f4a", "c9a23a", "5a4a7a", "d0d0c8", "2f5f5a", "a0603a"]
const TROUSERS: Array[String] = ["2f3440", "2e4a6b", "4a3f30", "3a3a3a", "5a5a50"]
const SHOES: Array[String] = ["1f1d1c", "3b2a1e", "e0e0e0"]


static func palette_for(npc: Npc) -> Dictionary:
	var out := generated(npc.id)
	for key in npc.look:
		out[key] = Color(str(npc.look[key]))
	return out


## The palette an unauthored person gets. Each part takes different bits of
## the id's hash, so two people rarely share a whole outfit.
static func generated(npc_id: String) -> Dictionary:
	var h := npc_id.hash()
	return {
		"skin": Color(SKINS[posmod(h, SKINS.size())]),
		"hair": Color(HAIRS[posmod(h >> 4, HAIRS.size())]),
		"shirt": Color(SHIRTS[posmod(h >> 8, SHIRTS.size())]),
		"trousers": Color(TROUSERS[posmod(h >> 12, TROUSERS.size())]),
		"shoes": Color(SHOES[posmod(h >> 16, SHOES.size())]),
	}
