#!/usr/bin/env bash
# Lance tous les tests : simulation seule, puis partie réelle entre un serveur et deux clients.
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

echo "== Partie en réseau : un serveur, deux clients en pilote automatique =="
"$GODOT" --headless --path . -- --server --port="$PORT" --exit-after-kills=1 --quit-after=90 >"$LOGS/server.log" 2>&1 &
server_pid=$!
sleep 2
"$GODOT" --headless --path . -- --connect=127.0.0.1:"$PORT" --name=Alpha --autopilot --quit-after=80 >"$LOGS/alpha.log" 2>&1 &
alpha_pid=$!
"$GODOT" --headless --path . -- --connect=127.0.0.1:"$PORT" --name=Beta --autopilot --quit-after=80 >"$LOGS/beta.log" 2>&1 &
beta_pid=$!

wait "$alpha_pid"; alpha_code=$?
wait "$beta_pid"; beta_code=$?
wait "$server_pid"; server_code=$?

for name in server alpha beta; do
	echo "--- $name ---"
	cat "$LOGS/$name.log"
done

# Le serveur s'arrête dès la première élimination ; les clients voient alors la connexion
# se fermer et sortent avec le code 1, ce qui est attendu. Leur bon fonctionnement se
# vérifie dans les journaux : accueil par le serveur, états reçus, écart de prédiction.
[ "$server_code" -eq 0 ] || { echo "ÉCHEC : le serveur n'a enregistré aucune élimination (code $server_code)"; status=1; }
grep -q "kill killer=" "$LOGS/server.log" || { echo "ÉCHEC : aucune élimination dans le journal du serveur"; status=1; }
grep -q "join name=Alpha" "$LOGS/server.log" || { echo "ÉCHEC : Alpha n'a pas rejoint"; status=1; }
grep -q "join name=Beta" "$LOGS/server.log" || { echo "ÉCHEC : Beta n'a pas rejoint"; status=1; }
grep -q "joined hero_id=" "$LOGS/alpha.log" || { echo "ÉCHEC : Alpha n'a pas été accueilli"; status=1; }
grep -q "joined hero_id=" "$LOGS/beta.log" || { echo "ÉCHEC : Beta n'a pas été accueilli"; status=1; }
for name in alpha beta; do
	snapshots="$(sed -n 's/.*snapshots=\([0-9]*\).*/\1/p' "$LOGS/$name.log" | tail -1)"
	worst="$(sed -n 's/.*max_correction=\([0-9.]*\).*/\1/p' "$LOGS/$name.log" | tail -1)"
	[ "${snapshots:-0}" -ge 30 ] || { echo "ÉCHEC : $name a reçu trop peu d'états du serveur (${snapshots:-0})"; status=1; }
	# Sur la même machine, la prédiction du client ne doit presque jamais s'écarter du serveur.
	awk -v w="${worst:-99}" 'BEGIN { exit !(w < 1.5) }' || { echo "ÉCHEC : $name a subi une correction de ${worst:-?} unités"; status=1; }
done
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
