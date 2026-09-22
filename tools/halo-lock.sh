#!/bin/bash
# **Un singur rig de capturi pe mașină, oricâți agenți ar lucra în paralel.**
#
# Victor, 2026-09-22: *"când își fac testele, cei doi agenți de calibrare să nu se
# calce între ei. Când își fac pozele, adică."* Și are dreptate de două ori: două
# rulări simultane își fură procesorul una alteia — deci fiecare măsoară un motor
# mai lent decât cel adevărat — și amândouă pun ferestre pe ecran, iar capturile
# sunt „doar de motor" doar în măsură în care nimeni nu se bagă peste.
#
# Nu e o grijă teoretică: în repo-ul ăsta o suită de teste a dat trei ore de
# măsurători contaminate fiindcă rulau două instanțe deodată, iar `wispr-loop.sh`
# a căpătat lacăt exact din motivul ăsta (`~/.walkie-talkie/wispr-loop.lock`).
#
#   source "$(dirname "$0")/halo-lock.sh"        # ia lacătul, îl dă drumul la ieșire
#
# `mkdir` fiindcă e atomic pe orice sistem de fișiere, spre deosebire de
# `test -f && touch`. Înăuntru scriem cine îl ține, ca să nu te uiți la un director
# gol când vrei să știi pe cine aștepți.

HALO_LOCK="${HALO_LOCK:-$HOME/.walkie-talkie/halo-shoot.lock}"
mkdir -p "$(dirname "$HALO_LOCK")"

halo_lock_holder() { cat "$HALO_LOCK/holder" 2>/dev/null || echo "necunoscut"; }

for _i in $(seq 1 900); do            # 30 de minute, apoi renunțăm zgomotos
  if mkdir "$HALO_LOCK" 2>/dev/null; then
    echo $$ > "$HALO_LOCK/pid"
    printf 'pid %s · %s · %s\n' "$$" "${HALO_LOCK_WHO:-$(basename "$0")}" "$(date '+%H:%M:%S')" > "$HALO_LOCK/holder"
    trap 'rm -rf "$HALO_LOCK"' EXIT INT TERM
    break
  fi
  # **Deținătorul mort se detectează după proces, nu după ceas.** Laptopul a
  # repornit pe 2026-09-22 la 08:13 în mijlocul unei capturi Magma și a lăsat
  # lacătul în urmă; la pornire toate pid-urile dinăuntru erau moarte, dar
  # regula de vechime de mai jos ar fi ținut rig-ul închis încă 20 de minute
  # degeaba. `kill -0` răspunde imediat, deci un lacăt orfan se ia pe loc.
  # (Cursa e inofensivă: dacă doi așteptători văd amândoi pid-ul mort, `mkdir`
  # e atomic și tot unul singur intră.)
  _h=$(cat "$HALO_LOCK/pid" 2>/dev/null)
  if [ -n "$_h" ] && ! kill -0 "$_h" 2>/dev/null; then
    echo "  (lacăt orfan — pid $_h nu mai există, îl iau: $(halo_lock_holder))" >&2
    rm -rf "$HALO_LOCK"
    continue
  fi
  # Un lacăt mai vechi de 20 de minute e al unei rulări care a murit fără să-și
  # lase pid-ul (o versiune mai veche a fișierului ăstuia), nu al uneia care
  # lucrează: cea mai lungă captură cinstită (7 efecte × 3 rute × 10 s) stă mult
  # sub el.
  if [ -n "$(find "$HALO_LOCK" -maxdepth 0 -mmin +20 2>/dev/null)" ]; then
    echo "  (lacăt vechi de peste 20 min, îl iau: $(halo_lock_holder))" >&2
    rm -rf "$HALO_LOCK"
    continue
  fi
  [ $((_i % 15)) -eq 1 ] && echo "  (aștept rig-ul de capturi — îl ține: $(halo_lock_holder))" >&2
  sleep 2
done

if [ ! -d "$HALO_LOCK" ]; then
  echo "nu am putut lua lacătul de capturi în 30 de minute: $(halo_lock_holder)" >&2
  exit 3
fi
