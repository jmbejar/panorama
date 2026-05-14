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

WORK_DIR=${WORKSPACE:-/work}
INPUT_DIR=$WORK_DIR/input
OUTPUT_DIR=$WORK_DIR/output
LOGS_DIR=$WORK_DIR/logs
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
# --multirow uses Hugin's heuristic to find control points between any
# pair of images that share visual features, including the first ↔ last
# pair that closes the loop on a 360° panorama. It can mis-match when
# input photos are near-duplicates (the user took two shots from the same
# angle by accident); in that case enblend later rejects the run with
# "excessive image overlap detected" and we surface a friendly message
# pointing the user at the duplicate to remove.
run_step 02_cpfind         cpfind --multirow --celeste -o "$PTO" "$PTO"
run_step 03_cpclean        cpclean -o "$PTO" "$PTO"
run_step 04_autooptimiser  autooptimiser -a -m -l -s -o "$PTO" "$PTO"
run_step 05_pano_modify    pano_modify --canvas=AUTO --crop=AUTO --output-type=NORMAL -o "$PTO" "$PTO"

# Steps 6a + 6b replace `hugin_executor --stitching`: that wrapper invokes
# nona + enblend with no way to pass custom enblend flags, and
# pano_modify's --blender-args doesn't reliably round-trip through the PTO.
# Running nona then enblend manually lets us pick a more tolerant seam
# generator (see below).
run_step 06a_nona          nona -m TIFF_m -z LZW -o "$OUTPUT_DIR/panorama" "$PTO"

# enblend's default seam generator (graph-cut) refuses to blend images with
# heavy overlap — "excessive image overlap detected; too high risk of
# defective seam line". Phone-based panorama captures routinely have
# 60-70% overlap, which trips graph-cut. The older NFT
# (nearest-feature-transform) generator is more permissive at the cost of
# slightly less optimal seams.
log "06b_enblend: blending tiles → $OUTPUT_DIR/panorama.tif"
enblend --primary-seam-generator=nearest-feature-transform \
        -o "$OUTPUT_DIR/panorama.tif" \
        "$OUTPUT_DIR"/panorama*.tif \
        > "$LOGS_DIR/06b_enblend.log" 2>&1 \
        || fail "06b_enblend failed (exit $?) — see $LOGS_DIR/06b_enblend.log"

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
