#!/usr/bin/env bash
# Lance tous les tests : règles du jeu, commandes tactiles, session locale, partie complète
# entre bots en accéléré, puis partie réelle en réseau à 3 contre 3 entre un serveur, ses
# bots et deux clients (l'un aux commandes directes, l'autre aux commandes tactiles).
# Usage : tests/run_all.sh        (variable GODOT pour choisir l'exécutable, "godot" par défaut)
set -u

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-24599}"
LOGS="$(mktemp -d)"
status=0

echo "== Import du projet =="
"$GODOT" --headless --path . --import >"$LOGS/import.log" 2>&1 || { cat "$LOGS/import.log"; exit 1; }

echo "== Tests de la simulation =="
if ! "$GODOT" --headless --path . -s tests/test_sim.gd 2>&1 | tee "$LOGS/sim.log"; then
	status=1
fi
if grep -Eq "SCRIPT ERROR|Parse Error|FAIL:" "$LOGS/sim.log"; then
	status=1
fi

echo "== Tests des commandes tactiles =="
if ! "$GODOT" --headless --path . -s tests/test_touch.gd 2>&1 | tee "$LOGS/touch.log"; then
	status=1
fi
if grep -Eq "SCRIPT ERROR|Parse Error|FAIL:" "$LOGS/touch.log"; then
	status=1
fi

echo "== Session locale : jouer, quitter, relancer =="
if ! "$GODOT" --headless --path . -s tests/test_session.gd 2>&1 | tee "$LOGS/session.log"; then
	status=1
fi
if grep -Eq "SCRIPT ERROR|Parse Error|FAIL:" "$LOGS/session.log" || ! grep -q "2 rounds, 0 failures" "$LOGS/session.log"; then
	echo "ÉCHEC : la session locale ne se relance pas correctement"
	status=1
fi

echo "== Partie complète entre bots, en accéléré =="
if ! "$GODOT" --headless --path . -s tests/test_match.gd 2>&1 | tee "$LOGS/match.log"; then
	status=1
fi
if grep -Eq "SCRIPT ERROR|Parse Error|FAIL:" "$LOGS/match.log"; then
	status=1
fi

echo "== Partie en réseau : un serveur complété par des bots, un client clavier-souris et un client tactile =="
"$GODOT" --headless --path . -- --server --port="$PORT" --fill --exit-after-events=1 --quit-after=250 >"$LOGS/server.log" 2>&1 &
server_pid=$!
sleep 2
"$GODOT" --headless --path . -- --connect=127.0.0.1:"$PORT" --name=Alpha --hero=scutum --autopilot --quit-after=240 >"$LOGS/alpha.log" 2>&1 &
alpha_pid=$!
"$GODOT" --headless --path . -- --connect=127.0.0.1:"$PORT" --name=Beta --hero=columba --touch --autopilot --quit-after=240 >"$LOGS/beta.log" 2>&1 &
beta_pid=$!

wait "$alpha_pid"; alpha_code=$?
wait "$beta_pid"; beta_code=$?
wait "$server_pid"; server_code=$?

for name in server alpha beta; do
	echo "--- $name ---"
	cat "$LOGS/$name.log"
done

# Le serveur s'arrête au premier événement de jeu (élimination, relique ou camp pris,
# temple détruit) ; les clients voient alors la connexion se fermer et sortent avec le
# code 1, ce qui est attendu. Leur bon fonctionnement se vérifie dans les journaux :
# accueil par le serveur, états reçus, sbires vus, écart de prédiction.
[ "$server_code" -eq 0 ] || { echo "ÉCHEC : le serveur n'a enregistré aucun événement de jeu (code $server_code)"; status=1; }
grep -Eq "kill killer=|relic captured|camp captured|structure destroyed" "$LOGS/server.log" || { echo "ÉCHEC : aucun événement de jeu dans le journal du serveur"; status=1; }
# Chaque joueur remplace un bot : il joue le héros demandé et la partie reste à six héros.
grep -q "join name=Alpha team=[01] hero=scutum heroes=6" "$LOGS/server.log" || { echo "ÉCHEC : Alpha n'a pas remplacé un bot avec son héros"; status=1; }
grep -q "join name=Beta team=[01] hero=columba heroes=6" "$LOGS/server.log" || { echo "ÉCHEC : Beta n'a pas remplacé un bot avec son héros"; status=1; }
alpha_team="$(sed -n 's/.*join name=Alpha team=\([01]\).*/\1/p' "$LOGS/server.log")"
beta_team="$(sed -n 's/.*join name=Beta team=\([01]\).*/\1/p' "$LOGS/server.log")"
[ "$alpha_team" != "$beta_team" ] || { echo "ÉCHEC : les deux joueurs sont dans la même équipe"; status=1; }
grep -q "joined hero_id=" "$LOGS/alpha.log" || { echo "ÉCHEC : Alpha n'a pas été accueilli"; status=1; }
grep -q "joined hero_id=" "$LOGS/beta.log" || { echo "ÉCHEC : Beta n'a pas été accueilli"; status=1; }
for name in alpha beta; do
	snapshots="$(sed -n 's/.*snapshots=\([0-9]*\).*/\1/p' "$LOGS/$name.log" | tail -1)"
	worst="$(sed -n 's/.*max_correction=\([0-9.]*\).*/\1/p' "$LOGS/$name.log" | tail -1)"
	seen="$(sed -n 's/.*max_units=\([0-9]*\).*/\1/p' "$LOGS/$name.log" | tail -1)"
	[ "${snapshots:-0}" -ge 30 ] || { echo "ÉCHEC : $name a reçu trop peu d'états du serveur (${snapshots:-0})"; status=1; }
	[ "${seen:-0}" -ge 8 ] || { echo "ÉCHEC : $name n'a pas vu les sbires (${seen:-0})"; status=1; }
	moves="$(sed -n 's/.*moves=\([0-9]*\).*/\1/p' "$LOGS/$name.log" | tail -1)"
	actions="$(sed -n 's/.*actions=\([0-9]*\).*/\1/p' "$LOGS/$name.log" | tail -1)"
	[ "${moves:-0}" -ge 30 ] || { echo "ÉCHEC : $name ne s'est presque pas déplacé (${moves:-0} pas)"; status=1; }
	[ "${actions:-0}" -ge 1 ] || { echo "ÉCHEC : $name n'a utilisé aucune capacité"; status=1; }
	# Sur la même machine, la prédiction du client ne doit presque jamais s'écarter du serveur.
	awk -v w="${worst:-99}" 'BEGIN { exit !(w < 1.5) }' || { echo "ÉCHEC : $name a subi une correction de ${worst:-?} unités"; status=1; }
done
# Jeu croisé : Beta joue par les commandes tactiles (doigts virtuels), Alpha par les commandes directes.
grep -q "touch controls enabled" "$LOGS/beta.log" || { echo "ÉCHEC : Beta ne joue pas en tactile"; status=1; }
if grep -q "touch controls enabled" "$LOGS/alpha.log"; then echo "ÉCHEC : Alpha ne devrait pas jouer en tactile"; status=1; fi
if grep -Eq "SCRIPT ERROR|Parse Error" "$LOGS"/*.log; then
	echo "ÉCHEC : erreur de script dans les journaux"
	status=1
fi
echo "codes de sortie : serveur=$server_code alpha=$alpha_code beta=$beta_code"

rm -rf "$LOGS"
if [ "$status" -eq 0 ]; then
	echo "TOUS LES TESTS PASSENT"
else
	echo "DES TESTS ÉCHOUENT"
fi
exit "$status"
