#!/bin/sh
# Hugin panorama stitching pipeline. Runs inside the panorama-hugin container.
#
# Reads:  /work/input/*.jpg|*.png  (source photos, sorted by filename)
# Writes: /work/output/panorama.jpg
# Logs:   /work/logs/{NN}_{step}.log  (per-step stdout+stderr) and
#         /work/logs/project.pto      (intermediate Hugin project file)
#
# Exits non-zero on the first failing step. The host (HuginPanoramaStitcher)
# inspects exit code + presence of /work/output/panorama.jpg to classify the
# outcome.

set -eu

log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

INPUT_DIR=/work/input
OUTPUT_DIR=/work/output
LOGS_DIR=/work/logs
PTO=$LOGS_DIR/project.pto

[ -d "$INPUT_DIR" ] || fail "missing $INPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"

# Source photos are presented in directory order. The host names them
# NNN_<filename> so `set -- input/*` is already in capture order.
set -- "$INPUT_DIR"/*
[ $# -ge 2 ] || fail "need at least 2 input images, got $#"

log "Stitching $# input image(s)"

run_step() {
  step_name=$1
  log_file=$LOGS_DIR/$step_name.log
  shift
  log "$step_name: $*"
  "$@" > "$log_file" 2>&1 || fail "$step_name failed (exit $?) — see $log_file"
}

run_step 01_pto_gen        pto_gen -o "$PTO" "$@"
run_step 02_cpfind         cpfind --multirow --celeste -o "$PTO" "$PTO"
run_step 03_cpclean        cpclean -o "$PTO" "$PTO"
run_step 04_autooptimiser  autooptimiser -a -m -l -s -o "$PTO" "$PTO"
run_step 05_pano_modify    pano_modify --canvas=AUTO --crop=AUTO --output-type=NORMAL -o "$PTO" "$PTO"
run_step 06_stitch         hugin_executor --stitching --prefix="$OUTPUT_DIR/panorama" "$PTO"

# hugin_executor produces panorama.tif by default for the NORMAL output type;
# convert to JPEG so the host has a predictable filename.
if [ -f "$OUTPUT_DIR/panorama.tif" ]; then
  log "Converting panorama.tif → panorama.jpg"
  convert "$OUTPUT_DIR/panorama.tif" -quality 88 "$OUTPUT_DIR/panorama.jpg" \
    > "$LOGS_DIR/07_convert.log" 2>&1 \
    || fail "convert tif→jpg failed — see $LOGS_DIR/07_convert.log"
fi

[ -f "$OUTPUT_DIR/panorama.jpg" ] || fail "no panorama.jpg produced"

log "Done — $OUTPUT_DIR/panorama.jpg"
