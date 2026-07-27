#!/usr/bin/env bash
# Runs the expert-reply flow (accounts -> fetch -> reply), creating a venv
# under this directory the first time and reusing it afterwards.
#
# Usage:
#   ./run.sh                                       # full flow: accounts, fetch, reply
#   ./run.sh reply                                  # just the reply step (e.g. re-running after a break)
#   ./run.sh fetch reply                             # any subset of steps, in the order given
#   ./run.sh reply --from-xlsx path/to/filled_in.xlsx # post from a filled-in spreadsheet instead of the terminal prompt
#   ./run.sh export                                  # (re)write candidate_posts.xlsx from queue.json
#   ./run.sh sync-interests                           # pull the interest+tags catalog from the live API
#   ./run.sh app                                      # manage everything via a Streamlit web dashboard

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
DEFAULT_STEPS=(accounts fetch reply export)
VALID_STEPS=(accounts fetch reply export app sync-interests)

if [ ! -d "$VENV_DIR" ]; then
  echo "No venv found, creating one at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"
pip install -q -r "$SCRIPT_DIR/requirements.txt"

extra_args=()

if [ "$#" -eq 0 ]; then
  steps=("${DEFAULT_STEPS[@]}")
else
  # If every arg is a recognized step name, treat it as a chain of steps
  # with no extra flags. Otherwise the first arg is a single step and
  # everything after it is passed straight through to that step
  # (e.g. `reply --from-xlsx foo.xlsx`).
  all_valid=true
  for a in "$@"; do
    if [[ ! " ${VALID_STEPS[*]} " == *" $a "* ]]; then
      all_valid=false
      break
    fi
  done

  if $all_valid; then
    steps=("$@")
  else
    if [[ ! " ${VALID_STEPS[*]} " == *" $1 "* ]]; then
      echo "Unknown step: $1 (expected one of: ${VALID_STEPS[*]})" >&2
      exit 1
    fi
    steps=("$1")
    extra_args=("${@:2}")
  fi
fi

cd "$REPO_ROOT"

for step in "${steps[@]}"; do
  echo
  echo "== $step =="
  if [ "$step" = "app" ]; then
    if [ "${#extra_args[@]}" -gt 0 ]; then
      streamlit run "$SCRIPT_DIR/app.py" "${extra_args[@]}"
    else
      streamlit run "$SCRIPT_DIR/app.py"
    fi
  elif [ "${#extra_args[@]}" -gt 0 ]; then
    python -m scripts.expert_replies "$step" "${extra_args[@]}"
  else
    python -m scripts.expert_replies "$step"
  fi
done
