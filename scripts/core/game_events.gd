extends Node
## Gameplay event bus (autoload). Later systems (Witness/Shock, fines, heat loss)
## subscribe here instead of being called from physics code.

signal object_yeeted(body: Node3D)
signal object_despawned(body: Node3D)
signal npc_bonked(npc: Node3D, attacker: Node3D, power: int)
signal npc_knocked_out(npc: Node3D, ragdoll: Node3D, attacker: Node3D)
signal opening_toggled(opening: Node3D, is_open: bool)
signal player_left_train(player: Node3D)
signal player_reboarded(player: Node3D)
signal player_left_behind(player: Node3D)
