class_name SimConst
## Constantes partagées par la simulation, le serveur et le client.

## Version du protocole réseau : un client d'une autre version est refusé.
const PROTOCOL_VERSION := 1

## Nombre de pas de simulation par seconde (doit suivre physics_ticks_per_second).
const TICK_RATE := 30
const DT := 1.0 / TICK_RATE

const TEAM_DAWN := 0
const TEAM_DUSK := 1

## 3 contre 3.
const MAX_PLAYERS := 6

## Le bouton du créneau i d'un héros est le bit (1 << i).
const BTN_ATTACK := 1
const BTN_ABILITY_1 := 2
const BTN_ABILITY_2 := 4

const RESPAWN_TIME := 5.0
